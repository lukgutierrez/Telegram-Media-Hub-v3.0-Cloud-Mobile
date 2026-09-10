import os
from fastapi import FastAPI, WebSocket, WebSocketDisconnect, Depends
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse
from contextlib import asynccontextmanager

from app.core.config import settings
from app.api.router import api_router
from app.db.session import async_engine, Base
import app.db.models
from app.workers.progress import manager

from sqlalchemy import text

@asynccontextmanager
async def lifespan(app: FastAPI):
    # Inicializar tablas al arrancar
    async with async_engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
        # Migraciones ligeras si la DB SQLite ya existía
        try:
            await conn.execute(text("ALTER TABLE files ADD COLUMN local_path VARCHAR(500);"))
        except Exception:
            pass
        try:
            await conn.execute(text("ALTER TABLE jobs ADD COLUMN params_json TEXT;"))
        except Exception:
            pass
    yield

app = FastAPI(
    title=settings.PROJECT_NAME,
    openapi_url=f"{settings.API_V1_STR}/openapi.json",
    lifespan=lifespan
)

# CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Router de API REST
app.include_router(api_router, prefix=settings.API_V1_STR)

# Endpoint WebSocket para progreso en tiempo real
@app.websocket("/ws/progress/{user_id}")
async def websocket_progress_endpoint(websocket: WebSocket, user_id: int):
    await manager.connect(user_id, websocket)
    try:
        while True:
            # Mantener conexion viva
            data = await websocket.receive_text()
    except WebSocketDisconnect:
        manager.disconnect(user_id, websocket)
    except Exception:
        manager.disconnect(user_id, websocket)

# Servir Frontend
possible_frontend_dirs = [
    os.path.join(os.path.dirname(os.path.dirname(__file__)), "frontend"),
    os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(__file__))), "frontend"),
    "/app/frontend",
    os.path.join(os.getcwd(), "frontend"),
]
frontend_dir = None
for fd in possible_frontend_dirs:
    if os.path.exists(fd) and os.path.exists(os.path.join(fd, "index.html")):
        frontend_dir = fd
        break

if frontend_dir:
    app.mount("/static", StaticFiles(directory=frontend_dir), name="static")

    @app.get("/")
    async def serve_index():
        return FileResponse(os.path.join(frontend_dir, "index.html"))

# Endpoint para descargar el APK de la App Movil Android
@app.get("/download-apk")
@app.get("/download/app")
async def download_apk():
    # Buscar en raíz o carpeta v3
    possible_paths = [
        os.path.join(os.path.dirname(os.path.dirname(__file__)), "TelegramMediaHub_v3.apk"),
        os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(__file__))), "TelegramMediaHub_v3.apk"),
        os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(__file__)))), "TelegramMediaHub_v3.apk"),
        os.path.join(os.getcwd(), "TelegramMediaHub_v3.apk"),
        "/app/TelegramMediaHub_v3.apk",
        "/home/ubuntu/app/TelegramMediaHub_v3.apk"
    ]
    for p in possible_paths:
        if os.path.exists(p):
            return FileResponse(p, media_type="application/vnd.android.package-archive", filename="TelegramMediaHub_v3.apk")
    return {"error": "APK no encontrado en el servidor"}

@app.get("/health")
async def health_check():
    return {"status": "healthy", "service": settings.PROJECT_NAME}

