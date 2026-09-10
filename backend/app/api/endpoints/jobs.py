import os
import json
import time
import zipfile
import mimetypes
import asyncio
from typing import List, Optional, Dict, Any
from fastapi import APIRouter, Depends, HTTPException, status, BackgroundTasks, Query, Header
from fastapi.responses import FileResponse
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.future import select
from pydantic import BaseModel
from app.db.session import get_db
from app.db.models import User, Job, JobFile, File, JobStatus
from app.api.endpoints.auth import get_current_user, get_user_from_token_str
from app.workers.tasks import execute_download_job, set_job_signal
from app.services.dedup_service import get_dedup_statistics
from app.services.telegram_service import sanitize_filename
from app.workers.progress import manager
from app.core.config import settings

router = APIRouter()

class CreateJobSchema(BaseModel):
    target_url: str
    destination: str = "DIRECT_DOWNLOAD" # GDRIVE o DIRECT_DOWNLOAD
    job_type: str = "SINGLE_MEDIA" # SINGLE_MEDIA, BATCH_CHANNEL, FORUM_TOPICS
    selected_topic_ids: Optional[List[int]] = None
    concurrency: int = 10
    invert_order: bool = False
    limit_messages: Optional[int] = None
    media_filter: str = "ALL" # ALL, PHOTO, VIDEO, DOCUMENT

class JobActionSchema(BaseModel):
    action: str # PAUSE, RESUME, CANCEL

class JobResponseSchema(BaseModel):
    id: int
    user_id: int
    target_url: str
    destination: str
    job_type: str
    status: str
    progress_percent: float
    speed_mbs: float
    eta_seconds: int
    total_files: int
    processed_files: int
    current_file_name: Optional[str] = None
    error_message: Optional[str] = None

@router.post("/", response_model=JobResponseSchema)
async def create_job(
    payload: CreateJobSchema,
    background_tasks: BackgroundTasks,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    if not payload.target_url.strip():
        raise HTTPException(status_code=400, detail="Debes ingresar un enlace o ID de Telegram válido.")

    params_dict = {
        "selected_topic_ids": payload.selected_topic_ids,
        "concurrency": payload.concurrency,
        "invert_order": payload.invert_order,
        "limit_messages": payload.limit_messages,
        "media_filter": payload.media_filter
    }

    job = Job(
        user_id=user.id,
        target_url=payload.target_url.strip(),
        destination=payload.destination,
        job_type=payload.job_type,
        params_json=json.dumps(params_dict),
        status=JobStatus.PENDING,
        progress_percent=0.0
    )
    db.add(job)
    await db.commit()
    await db.refresh(job)

    # Lanzar tarea asíncrona de fondo
    background_tasks.add_task(execute_download_job, job.id)

    return {
        "id": job.id,
        "user_id": job.user_id,
        "target_url": job.target_url,
        "destination": job.destination,
        "job_type": job.job_type,
        "status": job.status,
        "progress_percent": job.progress_percent,
        "speed_mbs": job.speed_mbs,
        "eta_seconds": job.eta_seconds,
        "total_files": job.total_files,
        "processed_files": job.processed_files,
        "current_file_name": job.current_file_name,
        "error_message": job.error_message
    }

@router.get("/", response_model=List[JobResponseSchema])
async def list_jobs(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    stmt = select(Job).where(Job.user_id == user.id).order_by(Job.id.desc()).limit(50)
    res = await db.execute(stmt)
    jobs = res.scalars().all()
    return [
        {
            "id": j.id,
            "user_id": j.user_id,
            "target_url": j.target_url,
            "destination": j.destination,
            "job_type": j.job_type,
            "status": j.status,
            "progress_percent": j.progress_percent,
            "speed_mbs": j.speed_mbs,
            "eta_seconds": j.eta_seconds,
            "total_files": j.total_files,
            "processed_files": j.processed_files,
            "current_file_name": j.current_file_name,
            "error_message": j.error_message
        }
        for j in jobs
    ]

@router.get("/stats/dedup")
async def get_dedup_stats_endpoint(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Retorna las estadísticas del motor de deduplicación SHA-256."""
    stats = await get_dedup_statistics(db, user.id)
    return stats

@router.get("/search/files")
async def search_downloaded_files(
    q: Optional[str] = Query("", description="Término de búsqueda"),
    media_filter: Optional[str] = Query("ALL", description="Filtro de tipo"),
    token: Optional[str] = Query(None),
    authorization: Optional[str] = Header(None),
    db: AsyncSession = Depends(get_db)
):
    """Busca archivos descargados por nombre, topic o referencia."""
    user = None
    if token:
        user = await get_user_from_token_str(token, db)
    elif authorization and authorization.startswith("Bearer "):
        token_str = authorization.split("Bearer ")[1]
        user = await get_user_from_token_str(token_str, db)

    if not user:
        raise HTTPException(status_code=401, detail="Token no válido o no proporcionado.")

    stmt = select(File).order_by(File.id.desc())
    if q and q.strip():
        stmt = stmt.where(File.filename.ilike(f"%{q.strip()}%") | File.telegram_ref.ilike(f"%{q.strip()}%"))
    
    res = await db.execute(stmt)
    files = res.scalars().all()
    
    results = []
    for f in files:
        ext = os.path.splitext(f.filename)[1].lower()
        is_video = ext in [".mp4", ".mkv", ".mov", ".avi", ".webm"] or (f.mime_type and f.mime_type.startswith("video/"))
        is_photo = ext in [".jpg", ".jpeg", ".png", ".webp"] or (f.mime_type and f.mime_type.startswith("image/"))
        is_doc = not is_video and not is_photo
        
        if media_filter == "VIDEO" and not is_video:
            continue
        if media_filter == "PHOTO" and not is_photo:
            continue
        if media_filter == "DOCUMENT" and not is_doc:
            continue
            
        has_local = bool(f.local_path and os.path.exists(f.local_path))
        
        topic_name = "General"
        base_name = f.filename
        if "_" in base_name:
            cand = base_name.split("_", 1)[0]
            if len(cand) > 1 and not cand.isdigit() and len(cand) < 50:
                topic_name = cand
                
        results.append({
            "id": f.id,
            "filename": f.filename,
            "topic": topic_name,
            "size_mb": round(f.file_size_bytes / (1024 * 1024), 2),
            "sha256": f.sha256,
            "drive_link": f.drive_web_link,
            "has_local_download": has_local,
            "download_url": f"/api/v1/jobs/download-file/{f.id}" if has_local else None,
            "type": "Video 🎥" if is_video else ("Foto 📷" if is_photo else "Documento 📄")
        })
    return results

@router.get("/search/download-zip")
async def download_search_zip_get(
    q: Optional[str] = Query("", description="Término de búsqueda"),
    media_filter: Optional[str] = Query("ALL", description="Filtro"),
    token: Optional[str] = Query(None),
    authorization: Optional[str] = Header(None),
    db: AsyncSession = Depends(get_db)
):
    """Descarga en ZIP todos los archivos coincidentes con una búsqueda."""
    user = None
    if token:
        user = await get_user_from_token_str(token, db)
    elif authorization and authorization.startswith("Bearer "):
        token_str = authorization.split("Bearer ")[1]
        user = await get_user_from_token_str(token_str, db)

    if not user:
        raise HTTPException(status_code=401, detail="Token no válido o no proporcionado.")

    stmt = select(File)
    if q and q.strip():
        stmt = stmt.where(File.filename.ilike(f"%{q.strip()}%") | File.telegram_ref.ilike(f"%{q.strip()}%"))
        
    res = await db.execute(stmt)
    files = res.scalars().all()
    
    valid_files = []
    for f in files:
        if not f.local_path or not os.path.exists(f.local_path):
            continue
        ext = os.path.splitext(f.filename)[1].lower()
        is_video = ext in [".mp4", ".mkv", ".mov", ".avi", ".webm"] or (f.mime_type and f.mime_type.startswith("video/"))
        is_photo = ext in [".jpg", ".jpeg", ".png", ".webp"] or (f.mime_type and f.mime_type.startswith("image/"))
        is_doc = not is_video and not is_photo
        
        if media_filter == "VIDEO" and not is_video:
            continue
        if media_filter == "PHOTO" and not is_photo:
            continue
        if media_filter == "DOCUMENT" and not is_doc:
            continue
        valid_files.append(f)

    if not valid_files:
        raise HTTPException(status_code=404, detail="No se encontraron archivos descargados para empaquetar.")

    clean_q = sanitize_filename(q.strip() or "Todos")
    zip_filename = f"Telegram_Search_{clean_q}_{int(time.time())}.zip"
    temp_zip_path = os.path.join(settings.TEMP_DIR, zip_filename)

    with zipfile.ZipFile(temp_zip_path, 'w', zipfile.ZIP_STORED) as zip_file:
        for f in valid_files:
            base_name = os.path.basename(f.local_path)
            if "_" in base_name:
                parts = base_name.split("_", 1)
                topic_candidate = sanitize_filename(parts[0])
                if len(topic_candidate) > 1 and not topic_candidate.isdigit() and len(topic_candidate) < 50:
                    arcname = f"{topic_candidate}/{parts[1]}"
                else:
                    ext = os.path.splitext(base_name)[1].lower()
                    if ext in [".jpg", ".jpeg", ".png", ".webp"]:
                        arcname = f"Fotos/{base_name}"
                    elif ext in [".mp4", ".mkv", ".mov", ".avi", ".webm"]:
                        arcname = f"Videos/{base_name}"
                    else:
                        arcname = f"Documentos/{base_name}"
            else:
                arcname = base_name
            zip_file.write(f.local_path, arcname=arcname)

    return FileResponse(
        path=temp_zip_path,
        filename=zip_filename,
        media_type="application/zip",
        headers={
            "Content-Disposition": f'attachment; filename="{zip_filename}"'
        }
    )

@router.get("/{job_id}", response_model=JobResponseSchema)
async def get_job(
    job_id: int,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    stmt = select(Job).where(Job.id == job_id, Job.user_id == user.id)
    res = await db.execute(stmt)
    j = res.scalars().first()
    if not j:
        raise HTTPException(status_code=404, detail="Tarea no encontrada.")
    return {
        "id": j.id,
        "user_id": j.user_id,
        "target_url": j.target_url,
        "destination": j.destination,
        "job_type": j.job_type,
        "status": j.status,
        "progress_percent": j.progress_percent,
        "speed_mbs": j.speed_mbs,
        "eta_seconds": j.eta_seconds,
        "total_files": j.total_files,
        "processed_files": j.processed_files,
        "current_file_name": j.current_file_name,
        "error_message": j.error_message
    }

@router.post("/{job_id}/action")
async def control_job_action(
    job_id: int,
    payload: JobActionSchema,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Pausar, reanudar o cancelar una tarea activa."""
    stmt = select(Job).where(Job.id == job_id, Job.user_id == user.id)
    res = await db.execute(stmt)
    j = res.scalars().first()
    if not j:
        raise HTTPException(status_code=404, detail="Tarea no encontrada.")

    action = payload.action.upper()
    if action == "PAUSE":
        set_job_signal(job_id, "PAUSED")
        j.status = JobStatus.PAUSED
    elif action == "RESUME":
        set_job_signal(job_id, "RUNNING")
        j.status = JobStatus.RUNNING
    elif action == "CANCEL":
        set_job_signal(job_id, "CANCELLED")
        j.status = JobStatus.CANCELLED
    else:
        raise HTTPException(status_code=400, detail="Acción no soportada. Usa PAUSE, RESUME o CANCEL.")

    await db.commit()
    await manager.broadcast_user_job_progress(user.id, {
        "job_id": j.id,
        "status": j.status
    })
    return {"status": "ok", "job_id": j.id, "job_status": j.status}

@router.get("/{job_id}/files")
async def get_job_files(
    job_id: int,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    stmt = select(JobFile, File).join(File, JobFile.file_id == File.id).where(JobFile.job_id == job_id)
    res = await db.execute(stmt)
    results = []
    for jf, f in res.all():
        has_local = bool(f.local_path and os.path.exists(f.local_path))
        results.append({
            "id": f.id,
            "filename": f.filename,
            "size_mb": round(f.file_size_bytes / (1024 * 1024), 2),
            "sha256": f.sha256,
            "drive_link": f.drive_web_link,
            "has_local_download": has_local,
            "download_url": f"/api/v1/jobs/download-file/{f.id}" if has_local else None,
            "status": jf.status
        })
    return results

@router.get("/download-file/{file_id}")
async def download_file_direct(
    file_id: int,
    token: Optional[str] = Query(None),
    authorization: Optional[str] = Header(None),
    db: AsyncSession = Depends(get_db)
):
    """Transmite el archivo directamente al navegador del usuario (Celular / PC)."""
    user = None
    if token:
        user = await get_user_from_token_str(token, db)
    elif authorization and authorization.startswith("Bearer "):
        token_str = authorization.split("Bearer ")[1]
        user = await get_user_from_token_str(token_str, db)

    if not user:
        raise HTTPException(status_code=401, detail="Token no válido o no proporcionado.")

    stmt = select(File).where(File.id == file_id)
    res = await db.execute(stmt)
    f = res.scalars().first()
    if not f or not f.local_path or not os.path.exists(f.local_path):
        raise HTTPException(status_code=404, detail="El archivo no está disponible en almacenamiento local.")

    mime_type, _ = mimetypes.guess_type(f.filename)
    clean_filename = f.filename.split("/")[-1].split("\\")[-1]

    return FileResponse(
        path=f.local_path,
        filename=clean_filename,
        media_type=mime_type or f.mime_type or "application/octet-stream",
        headers={
            "Content-Disposition": f'attachment; filename="{clean_filename}"'
        }
    )

@router.get("/{job_id}/download-zip")
async def download_job_zip(
    job_id: int,
    token: Optional[str] = Query(None),
    authorization: Optional[str] = Header(None),
    db: AsyncSession = Depends(get_db)
):
    """Genera y transmite un archivo ZIP con todos los archivos de la tarea organizados en carpetas (Topics / Tipos)."""
    user = None
    if token:
        user = await get_user_from_token_str(token, db)
    elif authorization and authorization.startswith("Bearer "):
        token_str = authorization.split("Bearer ")[1]
        user = await get_user_from_token_str(token_str, db)

    if not user:
        raise HTTPException(status_code=401, detail="Token no válido o no proporcionado.")

    stmt_job = select(Job).where(Job.id == job_id)
    res_job = await db.execute(stmt_job)
    job = res_job.scalars().first()
    if not job:
        raise HTTPException(status_code=404, detail="Tarea no encontrada.")

    stmt = select(JobFile, File).join(File, JobFile.file_id == File.id).where(JobFile.job_id == job_id)
    res = await db.execute(stmt)
    files = res.all()

    valid_files = [f for jf, f in files if f.local_path and os.path.exists(f.local_path)]
    if not valid_files:
        raise HTTPException(status_code=404, detail="No hay archivos físicos descargados disponibles en esta tarea para comprimir.")

    # Generar archivo ZIP organizado
    clean_job_target = sanitize_filename(job.target_url.replace("https://t.me/", "").replace("/", "_"))
    zip_filename = f"Telegram_Job_{job_id}_{clean_job_target}.zip"
    temp_zip_path = os.path.join(settings.TEMP_DIR, f"job_{job_id}_{int(time.time())}.zip")

    with zipfile.ZipFile(temp_zip_path, 'w', zipfile.ZIP_STORED) as zip_file:
        for f in valid_files:
            base_name = os.path.basename(f.local_path)
            
            # Organizar estructura de carpetas
            if "_" in base_name:
                parts = base_name.split("_", 1)
                # Si la primera parte parece un topic
                topic_candidate = sanitize_filename(parts[0])
                if len(topic_candidate) > 1 and not topic_candidate.isdigit() and len(topic_candidate) < 50:
                    topic_folder = topic_candidate
                    file_inside = parts[1]
                    arcname = f"{topic_folder}/{file_inside}"
                else:
                    ext = os.path.splitext(base_name)[1].lower()
                    if ext in [".jpg", ".jpeg", ".png", ".webp"]:
                        arcname = f"Fotos/{base_name}"
                    elif ext in [".mp4", ".mkv", ".mov", ".avi", ".webm"]:
                        arcname = f"Videos/{base_name}"
                    elif ext in [".mp3", ".ogg", ".wav", ".m4a"]:
                        arcname = f"Audio/{base_name}"
                    else:
                        arcname = f"Documentos/{base_name}"
            else:
                ext = os.path.splitext(base_name)[1].lower()
                if ext in [".jpg", ".jpeg", ".png", ".webp"]:
                    arcname = f"Fotos/{base_name}"
                elif ext in [".mp4", ".mkv", ".mov", ".avi", ".webm"]:
                    arcname = f"Videos/{base_name}"
                else:
                    arcname = f"Documentos/{base_name}"

            zip_file.write(f.local_path, arcname=arcname)

    return FileResponse(
        path=temp_zip_path,
        filename=zip_filename,
        media_type="application/zip",
        headers={
            "Content-Disposition": f'attachment; filename="{zip_filename}"'
        }
    )


