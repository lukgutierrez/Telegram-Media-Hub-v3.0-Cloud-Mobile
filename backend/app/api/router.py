from fastapi import APIRouter
from app.api.endpoints import auth, telegram, drive, jobs, osint

api_router = APIRouter()

api_router.include_router(auth.router, prefix="/auth", tags=["Autenticación"])
api_router.include_router(telegram.router, prefix="/telegram", tags=["Telegram"])
api_router.include_router(drive.router, prefix="/drive", tags=["Google Drive"])
api_router.include_router(jobs.router, prefix="/jobs", tags=["Tareas y Descargas"])
api_router.include_router(osint.router, prefix="/osint", tags=["Inteligencia OSINT"])
