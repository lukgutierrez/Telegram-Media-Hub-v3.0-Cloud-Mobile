import os
from pydantic_settings import BaseSettings
from typing import Optional

class Settings(BaseSettings):
    PROJECT_NAME: str = "Telegram Media Hub v3.0"
    API_V1_STR: str = "/api/v1"
    
    # Seguridad y JWT
    SECRET_KEY: str = os.getenv("SECRET_KEY", "tmh_super_secret_jwt_key_development_2026_@lukgtz")
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 60 * 24 * 365  # 365 días (Sesión Permanente)
    
    # Criptografía Fernet (32 bytes base64 url-safe)
    ENCRYPTION_KEY: str = os.getenv("ENCRYPTION_KEY", "kZ_3eP9sN0fQ7uL1jX8wV2bM5rT4yU6iO3pA7dE1gH0=")
    
    # Base de Datos (PostgreSQL por defecto, SQLite para dev local)
    DATABASE_URL: str = os.getenv("DATABASE_URL", "sqlite:///./tmh_dev.db")
    ASYNC_DATABASE_URL: str = os.getenv("ASYNC_DATABASE_URL", "sqlite+aiosqlite:///./tmh_dev.db")
    
    # Redis Broker y Pub/Sub
    REDIS_URL: str = os.getenv("REDIS_URL", "redis://localhost:6379/0")
    
    # Telegram API Core
    TELEGRAM_API_ID: int = int(os.getenv("TELEGRAM_API_ID", "37975206"))
    TELEGRAM_API_HASH: str = os.getenv("TELEGRAM_API_HASH", "05c1d0668fb608e464154f3030b055af")
    
    # Google Drive OAuth 2.0
    GOOGLE_CLIENT_ID: Optional[str] = os.getenv("GOOGLE_CLIENT_ID", "")
    GOOGLE_CLIENT_SECRET: Optional[str] = os.getenv("GOOGLE_CLIENT_SECRET", "")
    GOOGLE_REDIRECT_URI: str = os.getenv("GOOGLE_REDIRECT_URI", "http://localhost:8000/api/v1/drive/callback")
    
    # Almacenamiento Temporal Efímero y Descargas Directas
    TEMP_DIR: str = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(__file__))), "temp_storage")
    STORAGE_DIR: str = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(__file__))), "downloads_storage")
    
    # Límites y Concurrencia
    MAX_CONCURRENT_DOWNLOADS_PER_USER: int = 5
    CHUNK_SIZE_BYTES: int = 8 * 1024 * 1024  # 8 MB

    class Config:
        case_sensitive = True
        env_file = ".env"

settings = Settings()
os.makedirs(settings.TEMP_DIR, exist_ok=True)
os.makedirs(settings.STORAGE_DIR, exist_ok=True)
