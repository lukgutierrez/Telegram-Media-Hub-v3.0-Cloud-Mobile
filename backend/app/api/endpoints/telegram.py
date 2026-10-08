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
    phone_clean = payload.phone.strip()
    ok, msg, code_hash = await send_telegram_login_code(phone_clean)
    if not ok:
        raise HTTPException(status_code=400, detail=msg)
    
    # Buscar si ya existe una sesion para este numero o una pendiente de login
    stmt = select(TelegramSession).where(
        TelegramSession.user_id == user.id,
        TelegramSession.phone == phone_clean
    )
    res = await db.execute(stmt)
    tg = res.scalars().first()
    
    if not tg:
        # Buscar alguna sesion desconectada o crear nueva
        tg = TelegramSession(user_id=user.id, phone=phone_clean)
        db.add(tg)
        
    tg.phone = phone_clean
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
    phone_clean = payload.phone.strip()
    stmt = select(TelegramSession).where(
        TelegramSession.user_id == user.id,
        TelegramSession.phone == phone_clean
    )
    res = await db.execute(stmt)
    tg = res.scalars().first()
    
    # Fallback a cualquier sesión pendiente de este usuario
    if not tg or not tg.phone_code_hash:
        stmt_fallback = select(TelegramSession).where(
            TelegramSession.user_id == user.id,
            TelegramSession.status.in_(["PENDING_CODE", "PENDING_PASSWORD"])
        )
        res_fb = await db.execute(stmt_fallback)
        tg = res_fb.scalars().first()

    if not tg or not tg.phone_code_hash:
        raise HTTPException(status_code=400, detail="Debes solicitar un código primero.")

    ok, msg, encrypted_sess, user_info = await complete_telegram_login(
        phone=tg.phone or phone_clean,
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

    # Desactivar otras cuentas y marcar esta como activa
    all_stmt = select(TelegramSession).where(TelegramSession.user_id == user.id)
    all_res = await db.execute(all_stmt)
    for other in all_res.scalars().all():
        other.is_active = False

    tg.encrypted_session_string = encrypted_sess
    tg.status = "CONNECTED"
    tg.phone_code_hash = None
    tg.is_active = True
    if user_info:
        tg.first_name = user_info.get("first_name")
        tg.username = user_info.get("username")
        tg.telegram_id = str(user_info.get("id")) if user_info.get("id") else None
        tg.account_name = user_info.get("first_name") or user_info.get("username") or tg.phone

    await db.commit()

    return {"status": "CONNECTED", "message": "¡Cuenta de Telegram vinculada con éxito!", "user_info": user_info}

@router.get("/status")
async def get_telegram_status(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    stmt = select(TelegramSession).where(TelegramSession.user_id == user.id).order_by(TelegramSession.is_active.desc(), TelegramSession.id.desc())
    res = await db.execute(stmt)
    sessions = res.scalars().all()
    active_tg = sessions[0] if sessions else None

    accounts_list = [
        {
            "id": s.id,
            "phone": s.phone,
            "account_name": s.account_name or s.first_name or s.username or s.phone or f"Cuenta {s.id}",
            "first_name": s.first_name,
            "username": s.username,
            "telegram_id": s.telegram_id,
            "is_active": bool(s.is_active),
            "status": s.status
        }
        for s in sessions if s.status == "CONNECTED"
    ]

    return {
        "connected": bool(active_tg and active_tg.status == "CONNECTED"),
        "phone": active_tg.phone if active_tg else None,
        "status": active_tg.status if active_tg else "DISCONNECTED",
        "account_id": active_tg.id if active_tg else None,
        "account_name": (active_tg.account_name or active_tg.first_name or active_tg.username or active_tg.phone) if active_tg else None,
        "accounts": accounts_list,
        "accounts_count": len(accounts_list)
    }

@router.get("/accounts")
async def list_accounts(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    stmt = select(TelegramSession).where(TelegramSession.user_id == user.id).order_by(TelegramSession.id.asc())
    res = await db.execute(stmt)
    sessions = res.scalars().all()
    return [
        {
            "id": s.id,
            "phone": s.phone,
            "account_name": s.account_name or s.first_name or s.username or s.phone or f"Cuenta {s.id}",
            "first_name": s.first_name,
            "username": s.username,
            "telegram_id": s.telegram_id,
            "is_active": bool(s.is_active),
            "status": s.status
        }
        for s in sessions if s.status == "CONNECTED"
    ]

@router.post("/accounts/switch/{account_id}")
async def switch_account(
    account_id: int,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    stmt = select(TelegramSession).where(TelegramSession.user_id == user.id)
    res = await db.execute(stmt)
    sessions = res.scalars().all()
    
    target = None
    for s in sessions:
        if s.id == account_id:
            target = s
            s.is_active = True
        else:
            s.is_active = False

    if not target:
        raise HTTPException(status_code=404, detail="Cuenta de Telegram no encontrada.")

    await db.commit()
    return {
        "message": f"Cuenta activa cambiada a {target.account_name or target.phone}",
        "active_account": {
            "id": target.id,
            "phone": target.phone,
            "account_name": target.account_name or target.first_name or target.username or target.phone
        }
    }

@router.delete("/accounts/{account_id}")
async def delete_account(
    account_id: int,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    stmt = select(TelegramSession).where(TelegramSession.user_id == user.id, TelegramSession.id == account_id)
    res = await db.execute(stmt)
    target = res.scalars().first()
    if not target:
        raise HTTPException(status_code=404, detail="Cuenta no encontrada.")

    was_active = target.is_active
    await db.delete(target)
    await db.commit()

    # Si era la cuenta activa, activar la primera restante conectada
    if was_active:
        remain_stmt = select(TelegramSession).where(TelegramSession.user_id == user.id, TelegramSession.status == "CONNECTED").order_by(TelegramSession.id.desc())
        rem_res = await db.execute(remain_stmt)
        next_active = rem_res.scalars().first()
        if next_active:
            next_active.is_active = True
            await db.commit()

    return {"message": "Cuenta de Telegram eliminada con éxito."}

@router.delete("/disconnect")
async def disconnect_telegram(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    stmt = select(TelegramSession).where(TelegramSession.user_id == user.id, TelegramSession.is_active == True)
    res = await db.execute(stmt)
    tg = res.scalars().first()
    if tg:
        tg.status = "DISCONNECTED"
        tg.encrypted_session_string = None
        tg.is_active = False
        await db.commit()
    return {"message": "Cuenta activa desconectada exitosamente."}
