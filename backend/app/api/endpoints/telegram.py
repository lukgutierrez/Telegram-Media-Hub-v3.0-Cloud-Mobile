from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.future import select
from pydantic import BaseModel
from typing import Optional, Dict, Any
from app.db.session import get_db
from app.db.models import User, TelegramSession
from app.api.endpoints.auth import get_current_user
from app.services.telegram_service import send_telegram_login_code, complete_telegram_login

router = APIRouter()

class SendCodeSchema(BaseModel):
    phone: str

class VerifyCodeSchema(BaseModel):
    phone: str
    code: str
    password: Optional[str] = None

@router.post("/send-code")
async def send_code(
    payload: SendCodeSchema,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    ok, msg, code_hash = await send_telegram_login_code(payload.phone.strip())
    if not ok:
        raise HTTPException(status_code=400, detail=msg)
    
    stmt = select(TelegramSession).where(TelegramSession.user_id == user.id)
    res = await db.execute(stmt)
    tg = res.scalars().first()
    if not tg:
        tg = TelegramSession(user_id=user.id)
        db.add(tg)
        
    tg.phone = payload.phone.strip()
    tg.phone_code_hash = code_hash
    tg.status = "PENDING_CODE"
    await db.commit()

    return {"status": "PENDING_CODE", "message": "Código de seguridad enviado a tu Telegram o SMS."}

@router.post("/verify-code")
async def verify_code(
    payload: VerifyCodeSchema,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    stmt = select(TelegramSession).where(TelegramSession.user_id == user.id)
    res = await db.execute(stmt)
    tg = res.scalars().first()
    if not tg or not tg.phone_code_hash:
        raise HTTPException(status_code=400, detail="Debes solicitar un código primero.")

    ok, msg, encrypted_sess, user_info = await complete_telegram_login(
        phone=payload.phone.strip(),
        code=payload.code.strip(),
        phone_code_hash=tg.phone_code_hash,
        two_factor_password=payload.password
    )

    if not ok:
        if msg == "2FA_REQUIRED":
            tg.status = "PENDING_PASSWORD"
            await db.commit()
            return {"status": "PENDING_PASSWORD", "message": "Tu cuenta tiene verificación en dos pasos (2FA). Ingresa tu contraseña."}
        raise HTTPException(status_code=400, detail=msg)

    tg.encrypted_session_string = encrypted_sess
    tg.status = "CONNECTED"
    tg.phone_code_hash = None
    await db.commit()

    return {"status": "CONNECTED", "message": "¡Cuenta de Telegram vinculada con éxito!", "user_info": user_info}

@router.get("/status")
async def get_telegram_status(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    stmt = select(TelegramSession).where(TelegramSession.user_id == user.id)
    res = await db.execute(stmt)
    tg = res.scalars().first()
    return {
        "connected": bool(tg and tg.status == "CONNECTED"),
        "phone": tg.phone if tg else None,
        "status": tg.status if tg else "DISCONNECTED"
    }

@router.delete("/disconnect")
async def disconnect_telegram(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    stmt = select(TelegramSession).where(TelegramSession.user_id == user.id)
    res = await db.execute(stmt)
    tg = res.scalars().first()
    if tg:
        tg.encrypted_session_string = None
        tg.status = "DISCONNECTED"
        tg.phone_code_hash = None
        await db.commit()
    return {"message": "Telegram desconectado exitosamente."}
