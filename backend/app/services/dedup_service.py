import hashlib
import os
from typing import Optional, Tuple
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.future import select
from app.db.models import File

def calculate_sha256(file_path: str, chunk_size: int = 64 * 1024) -> str:
    """Calcula el hash SHA-256 de un archivo en bloques de 64KB sin saturar memoria."""
    sha256_hash = hashlib.sha256()
    with open(file_path, "rb") as f:
        for byte_block in iter(lambda: f.read(chunk_size), b""):
            sha256_hash.update(byte_block)
    return sha256_hash.hexdigest()

async def check_duplicate_file(
    db: AsyncSession,
    user_id: int,
    sha256: str
) -> Optional[File]:
    """Verifica si el usuario ya ha procesado y subido este mismo archivo previamente."""
    stmt = select(File).where(File.user_id == user_id, File.sha256 == sha256)
    result = await db.execute(stmt)
    return result.scalars().first()

async def register_processed_file(
    db: AsyncSession,
    user_id: int,
    sha256: str,
    filename: str,
    file_size_bytes: int,
    mime_type: Optional[str] = None,
    telegram_ref: Optional[str] = None,
    drive_file_id: Optional[str] = None,
    drive_web_link: Optional[str] = None,
    local_path: Optional[str] = None
) -> File:
    """Registra un archivo único en el catálogo."""
    db_file = File(
        user_id=user_id,
        sha256=sha256,
        filename=filename,
        file_size_bytes=file_size_bytes,
        mime_type=mime_type,
        telegram_ref=telegram_ref,
        drive_file_id=drive_file_id,
        drive_web_link=drive_web_link,
        local_path=local_path
    )
    db.add(db_file)
    await db.commit()
    await db.refresh(db_file)
    return db_file

async def get_dedup_statistics(db: AsyncSession, user_id: int) -> dict:
    """Calcula el ahorro de almacenamiento por deduplicación SHA-256."""
    from sqlalchemy import func
    from app.db.models import JobFile
    
    # Archivos únicos
    stmt_unique = select(func.count(File.id), func.coalesce(func.sum(File.file_size_bytes), 0)).where(File.user_id == user_id)
    res_unique = await db.execute(stmt_unique)
    unique_count, unique_bytes = res_unique.first()
    
    # Archivos duplicados omitidos
    stmt_skipped = select(func.count(JobFile.id)).join(File, JobFile.file_id == File.id).where(
        File.user_id == user_id,
        JobFile.status == "DEDUP_SKIPPED"
    )
    res_skipped = await db.execute(stmt_skipped)
    skipped_count = res_skipped.scalar() or 0

    # Estimación de bytes ahorrados
    stmt_saved = select(func.coalesce(func.sum(File.file_size_bytes), 0)).join(JobFile, JobFile.file_id == File.id).where(
        File.user_id == user_id,
        JobFile.status == "DEDUP_SKIPPED"
    )
    res_saved = await db.execute(stmt_saved)
    saved_bytes = res_saved.scalar() or 0
    
    total_processed = unique_count + skipped_count
    dedup_ratio = round((skipped_count / total_processed * 100), 1) if total_processed > 0 else 0.0

    return {
        "unique_files": unique_count,
        "unique_mb": round(unique_bytes / (1024 * 1024), 2),
        "skipped_files": skipped_count,
        "saved_mb": round(saved_bytes / (1024 * 1024), 2),
        "total_processed": total_processed,
        "dedup_ratio_pct": dedup_ratio
    }
