from datetime import timedelta
from typing import Any, Optional
from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import OAuth2PasswordRequestForm
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.future import select
from pydantic import BaseModel, EmailStr
from app.db.session import get_db
from app.db.models import User, TelegramSession, DriveConnection
from app.core.security import get_password_hash, verify_password, create_access_token, decode_access_token, oauth2_scheme
from app.core.config import settings

router = APIRouter()

class UserRegisterSchema(BaseModel):
    email: EmailStr
    password: str

class TokenSchema(BaseModel):
    access_token: str
    token_type: str = "bearer"

class UserResponseSchema(BaseModel):
    id: int
    email: str
    is_active: bool
    telegram_connected: bool
    drive_connected: bool

async def get_user_from_token_str(token_str: str, db: AsyncSession) -> Optional[User]:
    """Valida un token JWT en string y devuelve el usuario si es válido."""
    user_id = decode_access_token(token_str)
    if not user_id:
        return None
    stmt = select(User).where(User.id == user_id)
    res = await db.execute(stmt)
    user = res.scalars().first()
    if not user or not user.is_active:
        return None
    return user

async def get_current_user(
    db: AsyncSession = Depends(get_db),
    token: str = Depends(oauth2_scheme)
) -> User:
    user = await get_user_from_token_str(token, db)
    if not user:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token inválido o expirado",
            headers={"WWW-Authenticate": "Bearer"}
        )
    return user

@router.post("/register", response_model=TokenSchema)
async def register(user_in: UserRegisterSchema, db: AsyncSession = Depends(get_db)):
    stmt = select(User).where(User.email == user_in.email)
    res = await db.execute(stmt)
    if res.scalars().first():
        raise HTTPException(status_code=400, detail="El correo ya está registrado.")
    
    user = User(
        email=user_in.email,
        hashed_password=get_password_hash(user_in.password)
    )
    db.add(user)
    await db.commit()
    await db.refresh(user)

    # Crear entradas de conexion por defecto
    tg = TelegramSession(user_id=user.id, status="DISCONNECTED")
    dr = DriveConnection(user_id=user.id, status="DISCONNECTED")
    db.add_all([tg, dr])
    await db.commit()

    token = create_access_token(user.id)
    return {"access_token": token, "token_type": "bearer"}

@router.post("/login", response_model=TokenSchema)
async def login(form_data: OAuth2PasswordRequestForm = Depends(), db: AsyncSession = Depends(get_db)):
    stmt = select(User).where(User.email == form_data.username)
    res = await db.execute(stmt)
    user = res.scalars().first()
    if not user or not verify_password(form_data.password, user.hashed_password):
        raise HTTPException(status_code=400, detail="Correo o contraseña incorrectos.")
    
    token = create_access_token(user.id)
    return {"access_token": token, "token_type": "bearer"}

@router.get("/me", response_model=UserResponseSchema)
async def get_me(user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    stmt_tg = select(TelegramSession).where(TelegramSession.user_id == user.id)
    res_tg = await db.execute(stmt_tg)
    tg = res_tg.scalars().first()
    
    stmt_dr = select(DriveConnection).where(DriveConnection.user_id == user.id)
    res_dr = await db.execute(stmt_dr)
    dr = res_dr.scalars().first()

    return {
        "id": user.id,
        "email": user.email,
        "is_active": user.is_active,
        "telegram_connected": bool(tg and tg.status == "CONNECTED"),
        "drive_connected": bool(dr and dr.status == "CONNECTED")
    }

class ForgotPasswordSchema(BaseModel):
    email: EmailStr

class ResetPasswordSchema(BaseModel):
    email: EmailStr
    new_password: str
    reset_code: Optional[str] = None

@router.post("/forgot-password")
async def forgot_password(data: ForgotPasswordSchema, db: AsyncSession = Depends(get_db)):
    stmt = select(User).where(User.email == data.email)
    res = await db.execute(stmt)
    user = res.scalars().first()
    if not user:
        raise HTTPException(status_code=404, detail="Correo no encontrado.")
    reset_token = create_access_token(user.id, expires_delta=timedelta(minutes=30))
    return {
        "message": "Solicitud de recuperación procesada.",
        "reset_token": reset_token,
        "email": user.email
    }

@router.post("/reset-password")
async def reset_password(data: ResetPasswordSchema, db: AsyncSession = Depends(get_db)):
    stmt = select(User).where(User.email == data.email)
    res = await db.execute(stmt)
    user = res.scalars().first()
    if not user:
        raise HTTPException(status_code=404, detail="Usuario no encontrado.")
    
    if len(data.new_password) < 6:
        raise HTTPException(status_code=400, detail="La contraseña debe tener al menos 6 caracteres.")
    
    user.hashed_password = get_password_hash(data.new_password)
    await db.commit()
import secrets
import json
from datetime import datetime, timezone

# Almacén de códigos de sincronización rápida temporales
_quick_sync_codes: dict[str, dict] = {}

def _clean_expired_sync_codes():
    now = datetime.now(timezone.utc)
    expired = [k for k, v in _quick_sync_codes.items() if v["expires_at"] < now]
    for k in expired:
        _quick_sync_codes.pop(k, None)

class QuickLoginSchema(BaseModel):
    code: str

@router.post("/quick-code/generate")
async def generate_quick_code(user: User = Depends(get_current_user)):
    """Genera un código PIN táctico y payload QR de 5 minutos para vincular la app móvil."""
    _clean_expired_sync_codes()
    pin_num = secrets.randbelow(9000) + 1000
    code = f"TMH-{pin_num}"
    norm_code = code.replace("-", "").upper()
    
    expires_at = datetime.now(timezone.utc) + timedelta(minutes=5)
    _quick_sync_codes[norm_code] = {
        "user_id": user.id,
        "email": user.email,
        "expires_at": expires_at
    }
    
    qr_payload = json.dumps({
        "app": "TelegramMediaHub",
        "code": code,
        "email": user.email,
        "server": "https://pdas-stats-orbit-forbes.trycloudflare.com/api/v1"
    })
    
    return {
        "code": code,
        "qr_payload": qr_payload,
        "expires_in_seconds": 300,
        "email": user.email
    }

@router.post("/quick-login", response_model=TokenSchema)
async def quick_login(data: QuickLoginSchema, db: AsyncSession = Depends(get_db)):
    """Valida el PIN o código escaneado por la app móvil y autentica al instante."""
    _clean_expired_sync_codes()
    raw_code = data.code.strip()
    
    # Si viene en formato JSON por escaneo de QR directo
    if raw_code.startswith("{") and "code" in raw_code:
        try:
            parsed = json.loads(raw_code)
            raw_code = parsed.get("code", raw_code)
        except Exception:
            pass
            
    norm_code = raw_code.replace("-", "").replace(" ", "").upper()
    
    item = _quick_sync_codes.pop(norm_code, None)
    if not item:
        raise HTTPException(
            status_code=400,
            detail="Código de vinculación inválido o expirado. Genera uno nuevo en la web."
        )
        
    if item["expires_at"] < datetime.now(timezone.utc):
        raise HTTPException(
            status_code=400,
            detail="El código ha expirado. Por favor genera un nuevo código en la web."
        )
        
    user_id = item["user_id"]
    stmt = select(User).where(User.id == user_id)
    res = await db.execute(stmt)
    user = res.scalars().first()
    if not user or not user.is_active:
        raise HTTPException(status_code=404, detail="Usuario no encontrado o inactivo.")
        
    token = create_access_token(user.id)
    return {"access_token": token, "token_type": "bearer"}

