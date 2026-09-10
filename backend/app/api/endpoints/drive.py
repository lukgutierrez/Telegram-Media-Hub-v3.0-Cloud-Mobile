from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.future import select
from pydantic import BaseModel
from typing import Optional
from app.db.session import get_db
from app.db.models import User, DriveConnection
from app.api.endpoints.auth import get_current_user
from app.services.drive_service import get_drive_auth_url, exchange_drive_code

router = APIRouter()

class CallbackSchema(BaseModel):
    code: str

@router.get("/auth-url")
async def get_auth_url(user: User = Depends(get_current_user)):
    url, err = get_drive_auth_url(user.id)
    if err:
        raise HTTPException(status_code=400, detail=err)
    return {"auth_url": url}

@router.post("/callback")
async def drive_callback(
    payload: CallbackSchema,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    ok, encrypted_token, err = exchange_drive_code(payload.code.strip())
    if not ok:
        raise HTTPException(status_code=400, detail=f"Error al canjear código de Google Drive: {err}")

    stmt = select(DriveConnection).where(DriveConnection.user_id == user.id)
    res = await db.execute(stmt)
    dr = res.scalars().first()
    if not dr:
        dr = DriveConnection(user_id=user.id)
        db.add(dr)

    dr.encrypted_token_json = encrypted_token
    dr.status = "CONNECTED"
    dr.folder_name = "Telegram Media Hub"
    await db.commit()

    return {"status": "CONNECTED", "message": "¡Google Drive conectado exitosamente!"}

@router.get("/status")
async def get_drive_status(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    stmt = select(DriveConnection).where(DriveConnection.user_id == user.id)
    res = await db.execute(stmt)
    dr = res.scalars().first()
    return {
        "connected": bool(dr and dr.status == "CONNECTED"),
        "folder_name": dr.folder_name if dr else "Telegram Media Hub",
        "status": dr.status if dr else "DISCONNECTED"
    }

@router.delete("/disconnect")
async def disconnect_drive(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    stmt = select(DriveConnection).where(DriveConnection.user_id == user.id)
    res = await db.execute(stmt)
    dr = res.scalars().first()
    if dr:
        dr.encrypted_token_json = None
        dr.status = "DISCONNECTED"
        await db.commit()
    return {"message": "Google Drive desconectado exitosamente."}
