from datetime import datetime, timezone
from sqlalchemy import Column, Integer, String, BigInteger, Float, Boolean, DateTime, ForeignKey, Text, Enum
from sqlalchemy.orm import relationship
from app.db.session import Base
import enum

def utcnow():
    return datetime.now(timezone.utc)

class JobStatus(str, enum.Enum):
    PENDING = "PENDING"
    RUNNING = "RUNNING"
    COMPLETED = "COMPLETED"
    FAILED = "FAILED"
    PAUSED = "PAUSED"
    CANCELLED = "CANCELLED"

class JobType(str, enum.Enum):
    SINGLE_MEDIA = "SINGLE_MEDIA"
    BATCH_CHANNEL = "BATCH_CHANNEL"
    FORUM_TOPICS = "FORUM_TOPICS"
    OSINT_RECON = "OSINT_RECON"

class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    email = Column(String(255), unique=True, index=True, nullable=False)
    hashed_password = Column(String(255), nullable=False)
    is_active = Column(Boolean, default=True)
    is_superuser = Column(Boolean, default=False)
    created_at = Column(DateTime(timezone=True), default=utcnow)

    # Relaciones
    telegram_session = relationship("TelegramSession", back_populates="user", uselist=False, cascade="all, delete-orphan")
    drive_connection = relationship("DriveConnection", back_populates="user", uselist=False, cascade="all, delete-orphan")
    jobs = relationship("Job", back_populates="user", cascade="all, delete-orphan")
    files = relationship("File", back_populates="user", cascade="all, delete-orphan")

class TelegramSession(Base):
    __tablename__ = "telegram_sessions"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), unique=True, nullable=False)
    phone = Column(String(50), nullable=True)
    # Almacenamiento cifrado con Fernet/AES (StringSession)
    encrypted_session_string = Column(Text, nullable=True)
    status = Column(String(50), default="DISCONNECTED") # DISCONNECTED, PENDING_CODE, PENDING_PASSWORD, CONNECTED
    phone_code_hash = Column(String(255), nullable=True) # Para completar el flujo de login
    created_at = Column(DateTime(timezone=True), default=utcnow)
    updated_at = Column(DateTime(timezone=True), default=utcnow, onupdate=utcnow)

    user = relationship("User", back_populates="telegram_session")

class DriveConnection(Base):
    __tablename__ = "drive_connections"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), unique=True, nullable=False)
    # Token OAuth cifrado con Fernet/AES
    encrypted_token_json = Column(Text, nullable=True)
    folder_id = Column(String(255), nullable=True)
    folder_name = Column(String(255), default="Telegram Media Hub")
    status = Column(String(50), default="DISCONNECTED") # DISCONNECTED, CONNECTED
    created_at = Column(DateTime(timezone=True), default=utcnow)
    updated_at = Column(DateTime(timezone=True), default=utcnow, onupdate=utcnow)

    user = relationship("User", back_populates="drive_connection")

class Job(Base):
    __tablename__ = "jobs"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    job_type = Column(String(50), default=JobType.SINGLE_MEDIA)
    target_url = Column(String(500), nullable=False)
    destination = Column(String(50), default="DIRECT_DOWNLOAD") # GDRIVE o DIRECT_DOWNLOAD
    params_json = Column(Text, nullable=True) # Almacena topics seleccionados, concurrencia, etc.
    
    status = Column(String(50), default=JobStatus.PENDING, index=True)
    progress_percent = Column(Float, default=0.0)
    speed_mbs = Column(Float, default=0.0)
    eta_seconds = Column(Integer, default=0)
    
    total_files = Column(Integer, default=0)
    processed_files = Column(Integer, default=0)
    current_file_name = Column(String(500), nullable=True)
    
    error_message = Column(Text, nullable=True)
    created_at = Column(DateTime(timezone=True), default=utcnow)
    updated_at = Column(DateTime(timezone=True), default=utcnow, onupdate=utcnow)

    user = relationship("User", back_populates="jobs")
    job_files = relationship("JobFile", back_populates="job", cascade="all, delete-orphan")

class File(Base):
    __tablename__ = "files"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    sha256 = Column(String(64), index=True, nullable=False) # Huella criptografica para deduplicacion
    filename = Column(String(500), nullable=False)
    file_size_bytes = Column(BigInteger, default=0)
    mime_type = Column(String(100), nullable=True)
    telegram_ref = Column(String(500), nullable=True)
    drive_file_id = Column(String(255), nullable=True)
    drive_web_link = Column(Text, nullable=True)
    local_path = Column(String(500), nullable=True) # Ruta en disco para streaming y descarga directa
    created_at = Column(DateTime(timezone=True), default=utcnow)

    user = relationship("User", back_populates="files")
    job_files = relationship("JobFile", back_populates="file")

class JobFile(Base):
    __tablename__ = "job_files"

    id = Column(Integer, primary_key=True, index=True)
    job_id = Column(Integer, ForeignKey("jobs.id", ondelete="CASCADE"), nullable=False, index=True)
    file_id = Column(Integer, ForeignKey("files.id", ondelete="CASCADE"), nullable=True, index=True)
    status = Column(String(50), default="PENDING") # PENDING, DOWNLOADING, HASHED, UPLOADING, COMPLETED, FAILED, DEDUP_SKIPPED
    error_message = Column(Text, nullable=True)
    created_at = Column(DateTime(timezone=True), default=utcnow)

    job = relationship("Job", back_populates="job_files")
    file = relationship("File", back_populates="job_files")
