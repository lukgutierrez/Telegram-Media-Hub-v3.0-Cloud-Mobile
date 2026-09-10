import os
import json
import mimetypes
from fastapi import APIRouter, Depends, HTTPException, status, BackgroundTasks, Query, Header
from fastapi.responses import FileResponse
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.future import select
from pydantic import BaseModel
from typing import Optional, List, Dict, Any
from app.db.session import get_db
from app.db.models import User, TelegramSession, Job, JobType, JobStatus
from app.api.endpoints.auth import get_current_user, get_user_from_token_str
from app.workers.tasks import execute_download_job
from app.core.config import settings
from app.services.telegram_service import (
    get_user_telegram_client,
    parse_telegram_link,
    resolve_entity_safe,
    list_user_dialogs,
    pre_analyze_topics_service,
    osint_stats_channel,
    osint_search_keywords,
    osint_recent_messages,
    search_global_telegram_messages,
    fast_download_media,
    sanitize_filename
)

router = APIRouter()

class OsintInspectSchema(BaseModel):
    target: str

class PreAnalyzeTopicsSchema(BaseModel):
    target: str
    topics_ids: Optional[List[int]] = None
    concurrency: int = 10

class KeywordSearchSchema(BaseModel):
    target: str
    keyword: str
    limit: int = 50

class RecentMessagesSchema(BaseModel):
    target: str
    limit: int = 15

@router.get("/my-chats")
async def get_my_chats(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Lista todos los grupos, canales, supergrupos y foros donde está el usuario con IDs negativos (-100...)."""
    stmt = select(TelegramSession).where(TelegramSession.user_id == user.id)
    res = await db.execute(stmt)
    tg = res.scalars().first()
    if not tg or not tg.encrypted_session_string or tg.status != "CONNECTED":
        raise HTTPException(status_code=400, detail="Conecta tu cuenta de Telegram para listar tus chats.")

    client = get_user_telegram_client(tg.encrypted_session_string)
    await client.connect()
    try:
        chats = await list_user_dialogs(client)
        return chats
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Error obteniendo chats: {e}")
    finally:
        await client.disconnect()

@router.post("/inspect")
async def inspect_target(
    payload: OsintInspectSchema,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Inspección técnica detallada de una entidad (/info)."""
    stmt = select(TelegramSession).where(TelegramSession.user_id == user.id)
    res = await db.execute(stmt)
    tg = res.scalars().first()
    if not tg or not tg.encrypted_session_string or tg.status != "CONNECTED":
        raise HTTPException(status_code=400, detail="Conecta tu cuenta de Telegram para realizar consultas OSINT.")

    client = get_user_telegram_client(tg.encrypted_session_string)
    await client.connect()
    try:
        entity = await resolve_entity_safe(client, payload.target.strip())
        if not entity:
            raise HTTPException(status_code=404, detail="No se encontró la entidad en Telegram.")

        from telethon.tl.types import User as TgUser, Channel as TgChannel, Chat as TgChat
        
        info: Dict[str, Any] = {
            "id": entity.id,
            "id_formatted": f"-100{entity.id}" if getattr(entity, "id", 0) > 0 and not isinstance(entity, TgUser) else str(entity.id),
            "title": getattr(entity, "title", getattr(entity, "first_name", "Sin Nombre")),
            "username": getattr(entity, "username", None),
            "verified": getattr(entity, "verified", False),
            "scam": getattr(entity, "scam", False),
            "fake": getattr(entity, "fake", False),
            "restricted": getattr(entity, "restricted", False)
        }

        if isinstance(entity, TgUser):
            info["type"] = "USUARIO"
            info["phone"] = getattr(entity, "phone", None)
            info["bot"] = getattr(entity, "bot", False)
        elif isinstance(entity, TgChannel):
            info["type"] = "CANAL BROADCAST" if getattr(entity, "broadcast", False) else ("FORO" if getattr(entity, "forum", False) else "SUPERGRUPO")
            info["forum"] = getattr(entity, "forum", False)
            info["participants_count"] = getattr(entity, "participants_count", None)
        else:
            info["type"] = "GRUPO BÁSICO"

        return info

    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))
    finally:
        await client.disconnect()

@router.post("/topics")
async def get_forum_topics(
    payload: OsintInspectSchema,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Lista los topics de un foro."""
    stmt = select(TelegramSession).where(TelegramSession.user_id == user.id)
    res = await db.execute(stmt)
    tg = res.scalars().first()
    if not tg or not tg.encrypted_session_string or tg.status != "CONNECTED":
        raise HTTPException(status_code=400, detail="Conecta tu cuenta de Telegram.")

    client = get_user_telegram_client(tg.encrypted_session_string)
    await client.connect()
    try:
        from telethon.tl.functions.messages import GetForumTopicsRequest
        entity = await resolve_entity_safe(client, payload.target.strip())
        if not entity:
            raise HTTPException(status_code=404, detail="No se encontró el foro en Telegram.")
        
        res = await client(GetForumTopicsRequest(
            peer=entity, offset_date=None, offset_id=0, offset_topic=0, limit=300
        ))
        
        topics_list = []
        for t in res.topics:
            topics_list.append({
                "id": t.id,
                "title": t.title,
                "closed": getattr(t, "closed", False),
                "pinned": getattr(t, "pinned", False)
            })
        return topics_list
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Error obteniendo topics: {e}")
    finally:
        await client.disconnect()

@router.post("/pre-analyze-topics")
async def pre_analyze_topics(
    payload: PreAnalyzeTopicsSchema,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Pre-análisis detallado de todos los topics (fotos, videos, docs, MB, ETA)."""
    stmt = select(TelegramSession).where(TelegramSession.user_id == user.id)
    res = await db.execute(stmt)
    tg = res.scalars().first()
    if not tg or not tg.encrypted_session_string or tg.status != "CONNECTED":
        raise HTTPException(status_code=400, detail="Conecta tu cuenta de Telegram.")

    client = get_user_telegram_client(tg.encrypted_session_string)
    await client.connect()
    try:
        entity = await resolve_entity_safe(client, payload.target.strip())
        if not entity:
            raise HTTPException(status_code=404, detail="No se encontró el grupo o foro.")
        
        result = await pre_analyze_topics_service(
            client=client,
            entity=entity,
            topics_ids=payload.topics_ids,
            concurrency=payload.concurrency
        )
        return result
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Error en pre-análisis: {e}")
    finally:
        await client.disconnect()

@router.post("/stats")
async def get_channel_stats(
    payload: OsintInspectSchema,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Estadísticas avanzadas, horas pico, días activos y desglose multimedia (/stats)."""
    stmt = select(TelegramSession).where(TelegramSession.user_id == user.id)
    res = await db.execute(stmt)
    tg = res.scalars().first()
    if not tg or not tg.encrypted_session_string or tg.status != "CONNECTED":
        raise HTTPException(status_code=400, detail="Conecta tu cuenta de Telegram.")

    client = get_user_telegram_client(tg.encrypted_session_string)
    await client.connect()
    try:
        entity = await resolve_entity_safe(client, payload.target.strip())
        if not entity:
            raise HTTPException(status_code=404, detail="No se encontró el canal o grupo.")
        
        stats = await osint_stats_channel(client, entity)
        return stats
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Error obteniendo estadísticas: {e}")
    finally:
        await client.disconnect()

@router.post("/search-keywords")
async def search_keywords(
    payload: KeywordSearchSchema,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Buscador de mensajes por palabra clave en un canal o grupo."""
    stmt = select(TelegramSession).where(TelegramSession.user_id == user.id)
    res = await db.execute(stmt)
    tg = res.scalars().first()
    if not tg or not tg.encrypted_session_string or tg.status != "CONNECTED":
        raise HTTPException(status_code=400, detail="Conecta tu cuenta de Telegram.")

    client = get_user_telegram_client(tg.encrypted_session_string)
    await client.connect()
    try:
        entity = await resolve_entity_safe(client, payload.target.strip())
        if not entity:
            raise HTTPException(status_code=404, detail="No se encontró el canal o grupo.")
        
        results = await osint_search_keywords(client, entity, payload.keyword, limit=payload.limit)
        return results
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Error en búsqueda por palabra clave: {e}")
    finally:
        await client.disconnect()

@router.post("/recent")
async def get_recent_messages(
    payload: RecentMessagesSchema,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Obtiene los mensajes más recientes (/recent)."""
    stmt = select(TelegramSession).where(TelegramSession.user_id == user.id)
    res = await db.execute(stmt)
    tg = res.scalars().first()
    if not tg or not tg.encrypted_session_string or tg.status != "CONNECTED":
        raise HTTPException(status_code=400, detail="Conecta tu cuenta de Telegram.")

    client = get_user_telegram_client(tg.encrypted_session_string)
    await client.connect()
    try:
        entity = await resolve_entity_safe(client, payload.target.strip())
        if not entity:
            raise HTTPException(status_code=404, detail="No se encontró el canal o grupo.")
        
        msgs = await osint_recent_messages(client, entity, limit=payload.limit)
        return msgs
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Error obteniendo mensajes recientes: {e}")
    finally:
        await client.disconnect()


class GlobalTelegramSearchSchema(BaseModel):
    query: str
    media_filter: str = "ALL" # ALL, MEDIA_ONLY, VIDEO, PHOTO, DOCUMENT
    limit: int = 80

class DownloadSearchBatchSchema(BaseModel):
    query: str
    selected_items: List[Dict[str, Any]] # [{"chat_id": ..., "msg_id": ..., "chat_title": ...}]
    destination: str = "DIRECT_DOWNLOAD"
    concurrency: int = 10

@router.post("/telegram-global-search")
async def telegram_global_search_endpoint(
    payload: GlobalTelegramSearchSchema,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Busca en vivo en todos los chats, canales y grupos de Telegram del usuario."""
    stmt = select(TelegramSession).where(TelegramSession.user_id == user.id)
    res = await db.execute(stmt)
    tg = res.scalars().first()
    if not tg or not tg.encrypted_session_string or tg.status != "CONNECTED":
        raise HTTPException(status_code=400, detail="Conecta tu cuenta de Telegram para buscar en vivo.")

    if not payload.query or not payload.query.strip():
        raise HTTPException(status_code=400, detail="Ingresa un término de búsqueda.")

    client = get_user_telegram_client(tg.encrypted_session_string)
    await client.connect()
    try:
        data = await search_global_telegram_messages(
            client=client,
            query=payload.query.strip(),
            media_filter=payload.media_filter,
            limit=payload.limit
        )
        return data
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Error en búsqueda global de Telegram: {e}")
    finally:
        await client.disconnect()

@router.post("/download-search-batch")
async def download_search_batch_endpoint(
    payload: DownloadSearchBatchSchema,
    background_tasks: BackgroundTasks,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Crea una tarea de descarga en lote para los resultados de búsqueda global."""
    if not payload.selected_items or len(payload.selected_items) == 0:
        raise HTTPException(status_code=400, detail="No se seleccionó ningún archivo para descargar.")

    clean_target = f"Busqueda_{payload.query.strip() or 'Global'}"
    params_dict = {
        "search_items": payload.selected_items,
        "concurrency": payload.concurrency,
        "media_filter": "ALL"
    }

    job = Job(
        user_id=user.id,
        target_url=clean_target,
        destination=payload.destination,
        job_type=JobType.BATCH_CHANNEL,
        params_json=json.dumps(params_dict),
        status=JobStatus.PENDING,
        progress_percent=0.0
    )
    db.add(job)
    await db.commit()
    await db.refresh(job)

    # Lanzar tarea de descarga de fondo
    background_tasks.add_task(execute_download_job, job.id)

    return {
        "job_id": job.id,
        "status": "PENDING",
        "total_items": len(payload.selected_items),
        "target": clean_target
    }

@router.get("/download-single-media")
async def download_single_telegram_media(
    chat_id: int = Query(...),
    msg_id: int = Query(...),
    token: Optional[str] = Query(None),
    authorization: Optional[str] = Header(None),
    db: AsyncSession = Depends(get_db)
):
    """Descarga al vuelo un archivo multimedia individual directamente desde Telegram."""
    user = None
    if token:
        user = await get_user_from_token_str(token, db)
    elif authorization and authorization.startswith("Bearer "):
        token_str = authorization.split("Bearer ")[1]
        user = await get_user_from_token_str(token_str, db)

    if not user:
        raise HTTPException(status_code=401, detail="Token no válido.")

    stmt = select(TelegramSession).where(TelegramSession.user_id == user.id)
    res = await db.execute(stmt)
    tg = res.scalars().first()
    if not tg or not tg.encrypted_session_string or tg.status != "CONNECTED":
        raise HTTPException(status_code=400, detail="Telegram no conectado.")

    client = get_user_telegram_client(tg.encrypted_session_string)
    await client.connect()
    try:
        msg = await client.get_messages(chat_id, ids=msg_id)
        if not msg or not msg.media:
            raise HTTPException(status_code=404, detail="El mensaje no contiene multimedia descargable.")

        ext = ".bin"
        if getattr(msg, "file", None) and getattr(msg.file, "ext", None):
            ext = msg.file.ext
        elif msg.photo:
            ext = ".jpg"
        elif msg.video:
            ext = ".mp4"

        raw_filename = f"media_{chat_id}_{msg_id}{ext}"
        if getattr(msg, "file", None) and getattr(msg.file, "name", None):
            raw_filename = msg.file.name

        clean_filename = sanitize_filename(raw_filename)
        temp_path = os.path.join(settings.TEMP_DIR, f"direct_{clean_filename}")

        # Descargar a temp con fast_download_media
        await fast_download_media(client, msg, temp_path)

        mime_type, _ = mimetypes.guess_type(clean_filename)
        return FileResponse(
            path=temp_path,
            filename=clean_filename,
            media_type=mime_type or "application/octet-stream",
            headers={"Content-Disposition": f'attachment; filename="{clean_filename}"'}
        )
    finally:
        await client.disconnect()


