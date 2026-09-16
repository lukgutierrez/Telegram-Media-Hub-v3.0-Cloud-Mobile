import os
import time
import json
import asyncio
from typing import Optional, Dict, Any, List
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.future import select
from app.db.session import AsyncSessionLocal
from app.db.models import Job, JobStatus, JobType, TelegramSession, DriveConnection, File, JobFile
from app.services.telegram_service import (
    get_user_telegram_client,
    parse_telegram_link,
    parse_multiple_telegram_links,
    get_message_media_type,
    fetch_all_forum_topics,
    resolve_entity_safe,
    sanitize_filename,
    fast_download_media
)
from app.services.drive_service import (
    get_drive_service,
    create_or_get_folder,
    upload_file_to_drive
)
from app.services.dedup_service import calculate_sha256, check_duplicate_file, register_processed_file
from app.workers.progress import manager
from app.core.config import settings

# Diccionario de control de señales de tareas en memoria
job_control_signals: Dict[int, str] = {}

def set_job_signal(job_id: int, signal: str):
    """Establece la señal de control para un Job: RUNNING, PAUSED, CANCELLED."""
    job_control_signals[job_id] = signal

def get_job_signal(job_id: int) -> str:
    return job_control_signals.get(job_id, "RUNNING")

def matches_media_filter(msg, m_filter: str) -> bool:
    if not msg or not getattr(msg, 'media', None):
        return False
    if not m_filter or m_filter == "ALL":
        return True
    m_type = get_message_media_type(msg)
    if m_filter == "PHOTO":
        return m_type == "PHOTO"
    if m_filter == "VIDEO":
        return m_type == "VIDEO"
    if m_filter == "DOCUMENT":
        return m_type in ["DOCUMENT", "AUDIO"]
    return True

async def execute_download_job(job_id: int):
    """Pipeline completo de procesamiento asíncrono con Topics, Multi-Link Batch, Deduplicación y Descargas Directas."""
    job_control_signals[job_id] = "RUNNING"
    
    async with AsyncSessionLocal() as db:
        stmt = select(Job).where(Job.id == job_id)
        res = await db.execute(stmt)
        job = res.scalars().first()
        if not job:
            return

        user_id = job.user_id
        
        # 1. Obtener sesion de Telegram
        stmt_tg = select(TelegramSession).where(TelegramSession.user_id == user_id)
        res_tg = await db.execute(stmt_tg)
        tg_sess = res_tg.scalars().first()
        
        if not tg_sess or not tg_sess.encrypted_session_string or tg_sess.status != "CONNECTED":
            job.status = JobStatus.FAILED
            job.error_message = "Tu cuenta de Telegram no está conectada. Inicia sesión en el Asistente de Conexión."
            await db.commit()
            await manager.broadcast_user_job_progress(user_id, {"job_id": job.id, "status": job.status, "error": job.error_message})
            return

        # 2. Parsear parámetros opcionales del Job
        params = {}
        if job.params_json:
            try:
                params = json.loads(job.params_json)
            except Exception:
                params = {}

        selected_topic_ids = params.get("selected_topic_ids") or params.get("topic_ids")
        concurrency = max(1, min(20, params.get("concurrency", 10)))
        invert_order = bool(params.get("invert_order", False))
        limit_messages = params.get("limit_messages")
        media_filter = params.get("media_filter") or params.get("filter_media") or "ALL"

        # 3. Obtener conexion de Google Drive si el destino es Drive
        drive_service = None
        drive_root_folder_id = None
        if job.destination == "GDRIVE":
            stmt_dr = select(DriveConnection).where(DriveConnection.user_id == user_id)
            res_dr = await db.execute(stmt_dr)
            dr_conn = res_dr.scalars().first()
            if not dr_conn or not dr_conn.encrypted_token_json or dr_conn.status != "CONNECTED":
                job.status = JobStatus.FAILED
                job.error_message = "Google Drive no está conectado. Conecta tu cuenta o selecciona Descarga Directa."
                await db.commit()
                await manager.broadcast_user_job_progress(user_id, {"job_id": job.id, "status": job.status, "error": job.error_message})
                return
            try:
                drive_service = get_drive_service(dr_conn.encrypted_token_json)
                drive_root_folder_id = create_or_get_folder(drive_service, dr_conn.folder_name or "Telegram Media Hub")
            except Exception as e:
                job.status = JobStatus.FAILED
                job.error_message = f"Error al conectar con Google Drive: {e}"
                await db.commit()
                await manager.broadcast_user_job_progress(user_id, {"job_id": job.id, "status": job.status, "error": job.error_message})
                return

        # 4. Iniciar Telegram Client
        job.status = JobStatus.RUNNING
        job.progress_percent = 2.0
        await db.commit()
        await manager.broadcast_user_job_progress(user_id, {"job_id": job.id, "status": job.status, "progress": 2.0})

        client = get_user_telegram_client(tg_sess.encrypted_session_string)
        try:
            await client.connect()
            if not await client.is_user_authorized():
                job.status = JobStatus.FAILED
                job.error_message = "La sesión de Telegram ha expirado. Por favor vuelve a conectar tu cuenta."
                await db.commit()
                await manager.broadcast_user_job_progress(user_id, {"job_id": job.id, "status": job.status, "error": job.error_message})
                return

            items_to_download: List[Tuple[Any, str]] = [] # (msg, subfolder_or_topic_name)
            search_items = params.get("search_items")

            # Directorio de almacenamiento persistente para Descargas Directas
            job_storage_dir = os.path.join(settings.STORAGE_DIR, f"user_{user_id}", f"job_{job_id}")
            if job.destination == "DIRECT_DOWNLOAD":
                os.makedirs(job_storage_dir, exist_ok=True)

            target_drive_folder = drive_root_folder_id

            # CASO A: Ítems seleccionados desde Buscador Global 360°
            if search_items and len(search_items) > 0:
                chat_title = sanitize_filename(job.target_url or "Busqueda_Telegram")
                if drive_service and drive_root_folder_id:
                    target_drive_folder = create_or_get_folder(drive_service, chat_title, parent_id=drive_root_folder_id)

                for it in search_items:
                    cid = it.get("chat_id")
                    mid = it.get("msg_id")
                    c_title = sanitize_filename(it.get("chat_title") or str(cid))
                    try:
                        m = await client.get_messages(cid, ids=mid)
                        if m and m.media:
                            items_to_download.append((m, c_title))
                    except Exception:
                        pass

            else:
                parsed_links = parse_multiple_telegram_links(job.target_url or "")
                is_multi_link = len(parsed_links) > 1 or job.job_type in [JobType.BATCH_LINKS, "BATCH_LINKS", "BATCH_LINKS_MULTIPLE"]

                # CASO B: Múltiples enlaces ingresados (10, 20, 50+ links)
                if is_multi_link and len(parsed_links) > 0:
                    # Agrupar links por canal/grupo para optimizar consultas
                    groups_by_ref: Dict[str, List[Any]] = {}
                    for p in parsed_links:
                        groups_by_ref.setdefault(p.channel_ref, []).append(p)

                    for channel_ref, p_list in groups_by_ref.items():
                        entity = await resolve_entity_safe(client, channel_ref)
                        if not entity:
                            continue

                        chat_title = getattr(entity, 'title', getattr(entity, 'first_name', str(channel_ref)))
                        group_folder = sanitize_filename(chat_title)

                        # B.1 Mensajes individuales con ID específico
                        specific_msg_ids = [p.msg_id for p in p_list if p.msg_id is not None]
                        if specific_msg_ids:
                            for chunk_start in range(0, len(specific_msg_ids), 100):
                                chunk_ids = specific_msg_ids[chunk_start:chunk_start + 100]
                                try:
                                    msgs = await client.get_messages(entity, ids=chunk_ids)
                                    if not isinstance(msgs, list):
                                        msgs = [msgs] if msgs else []
                                    for m in msgs:
                                        if m and m.media and matches_media_filter(m, media_filter):
                                            items_to_download.append((m, group_folder))
                                except Exception:
                                    pass

                        # B.2 Enlaces de topics sin msg_id específico
                        topic_links = [p.topic_id for p in p_list if p.topic_id is not None and p.msg_id is None]
                        for top_id in topic_links:
                            async for m in client.iter_messages(entity, reply_to=top_id, limit=limit_messages or 200, reverse=invert_order):
                                if matches_media_filter(m, media_filter):
                                    items_to_download.append((m, f"{group_folder}_Topic_{top_id}"))

                        # B.3 Enlaces de canal general sin msg_id ni topic_id
                        has_bare_channel = any(p.msg_id is None and p.topic_id is None for p in p_list)
                        if has_bare_channel:
                            async for m in client.iter_messages(entity, limit=limit_messages or 50, reverse=invert_order):
                                if matches_media_filter(m, media_filter):
                                    items_to_download.append((m, group_folder))

                # CASO C: Enlace individual o Canal completo / Foro
                else:
                    parsed = parsed_links[0] if parsed_links else parse_telegram_link(job.target_url)
                    entity = await resolve_entity_safe(client, parsed.channel_ref)

                    if not entity:
                        job.status = JobStatus.FAILED
                        job.error_message = f"No se pudo acceder al canal, grupo o foro '{parsed.channel_ref}'."
                        await db.commit()
                        await manager.broadcast_user_job_progress(user_id, {"job_id": job.id, "status": job.status, "error": job.error_message})
                        return

                    chat_title = getattr(entity, 'title', getattr(entity, 'first_name', 'Telegram_Media'))
                    chat_folder_name = sanitize_filename(chat_title)

                    if drive_service and drive_root_folder_id:
                        target_drive_folder = create_or_get_folder(drive_service, chat_folder_name, parent_id=drive_root_folder_id)

                    is_forum = bool(getattr(entity, 'forum', False))

                    # C.1 Si es un Foro (Topics) o se solicitó modo FORUM_TOPICS
                    if job.job_type == JobType.FORUM_TOPICS or (is_forum and not parsed.msg_id and not parsed.topic_id and job.job_type != JobType.SINGLE_MEDIA):
                        all_topics = await fetch_all_forum_topics(client, entity, max_topics=500)
                        
                        target_topics = all_topics
                        if selected_topic_ids and len(selected_topic_ids) > 0:
                            target_topics = [t for t in all_topics if t.id in selected_topic_ids]

                        # Iterar cada topic del foro
                        for topic in target_topics:
                            t_title = sanitize_filename(getattr(topic, 'title', f"Topic_{topic.id}"))
                            async for m in client.iter_messages(entity, reply_to=topic.id, limit=limit_messages, reverse=invert_order):
                                if matches_media_filter(m, media_filter):
                                    items_to_download.append((m, t_title))

                        # Incluir mensajes del hilo principal / General si no estaban en topics
                        async for m in client.iter_messages(entity, limit=min(limit_messages or 100, 100), reverse=invert_order):
                            if matches_media_filter(m, media_filter):
                                if not any(x[0].id == m.id for x in items_to_download):
                                    items_to_download.append((m, "General"))

                    # C.2 Batch tradicional de canal no-foro
                    elif (job.job_type == JobType.BATCH_CHANNEL or job.job_type == "BATCH_CHANNEL") and not is_forum:
                        lim = limit_messages if (limit_messages and limit_messages > 0) else 500
                        async for m in client.iter_messages(entity, limit=lim, reverse=invert_order):
                            if matches_media_filter(m, media_filter):
                                items_to_download.append((m, ""))

                    # C.3 Enlace individual de mensaje o topic único
                    else:
                        if parsed.msg_id:
                            msg = await client.get_messages(entity, ids=parsed.msg_id)
                            if msg and matches_media_filter(msg, media_filter):
                                items_to_download.append((msg, ""))
                        elif parsed.topic_id:
                            async for m in client.iter_messages(entity, reply_to=parsed.topic_id, limit=limit_messages or 200, reverse=invert_order):
                                if matches_media_filter(m, media_filter):
                                    items_to_download.append((m, ""))
                        else:
                            lim = limit_messages if (limit_messages and limit_messages > 0) else 500
                            async for m in client.iter_messages(entity, limit=lim, reverse=invert_order):
                                if matches_media_filter(m, media_filter):
                                    items_to_download.append((m, ""))

            if not items_to_download:
                job.status = JobStatus.FAILED
                job.error_message = "No se encontraron archivos multimedia para procesar con los filtros seleccionados."
                await db.commit()
                await manager.broadcast_user_job_progress(user_id, {"job_id": job.id, "status": job.status, "error": job.error_message})
                return

            total_files_count = len(items_to_download)
            job.total_files = total_files_count
            job.processed_files = 0
            await db.commit()

            # Procesar descargas en paralelo con Semáforo de concurrencia
            sem = asyncio.Semaphore(concurrency)
            db_lock = asyncio.Lock()
            processed_count = 0
            track_speed = {"bytes_total": 0, "start_time": time.time()}

            async def process_single_item(idx, msg, topic_name):
                nonlocal processed_count
                
                # Chequear pausa o cancelación
                while job_control_signals.get(job_id) == "PAUSED":
                    await asyncio.sleep(0.5)
                if job_control_signals.get(job_id) == "CANCELLED":
                    return

                async with sem:
                    if job_control_signals.get(job_id) == "CANCELLED":
                        return

                    raw_filename = f"media_{msg.id}"
                    if getattr(msg, "file", None) and getattr(msg.file, "name", None):
                        raw_filename = msg.file.name
                    elif msg.photo:
                        raw_filename = f"photo_{msg.id}.jpg"
                    elif msg.video:
                        raw_filename = f"video_{msg.id}.mp4"

                    prefix = f"{topic_name}_" if topic_name else ""
                    clean_name = sanitize_filename(f"{prefix}{msg.date.strftime('%Y%m%d_%H%M%S')}_{msg.id}_{raw_filename}")

                    if job.destination == "DIRECT_DOWNLOAD":
                        target_file_path = os.path.join(job_storage_dir, clean_name)
                    else:
                        target_file_path = os.path.join(settings.TEMP_DIR, f"{job.id}_{clean_name}")

                    # Descargar archivo multimedia con Turbo Fast Download
                    last_broadcast_time = time.time()
                    def in_flight_progress(cur, tot):
                        nonlocal last_broadcast_time
                        now = time.time()
                        if (now - last_broadcast_time > 0.4) or cur == tot:
                            last_broadcast_time = now
                            dt_live = now - track_speed["start_time"]
                            bytes_live = track_speed["bytes_total"] + cur
                            speed_live = (bytes_live / (1024 * 1024)) / dt_live if dt_live > 0 else 0.0
                            
                            # Porcentaje total ponderado
                            if total_files_count == 1:
                                live_pct = round((cur / tot) * 100, 1) if tot > 0 else 50.0
                            else:
                                live_pct = round(((processed_count + (cur / tot if tot > 0 else 0)) / total_files_count) * 100, 1)

                            asyncio.create_task(manager.broadcast_user_job_progress(user_id, {
                                "job_id": job.id,
                                "status": "RUNNING",
                                "progress": live_pct,
                                "speed_mbs": round(speed_live, 2),
                                "eta_seconds": int(((tot - cur) / (speed_live * 1024 * 1024))) if speed_live > 0 and tot > cur else 0,
                                "current_file": clean_name,
                                "processed_files": processed_count,
                                "total_files": total_files_count
                            }))

                    try:
                        await fast_download_media(client, msg, out_path=target_file_path, progress_callback=in_flight_progress, workers=6)
                    except Exception as dl_err:
                        print(f"Error descargando msg {msg.id}: {dl_err}")
                        try:
                            await client.download_media(msg, file=target_file_path, progress_callback=in_flight_progress)
                        except Exception as dl_err2:
                            print(f"Error fallback msg {msg.id}: {dl_err2}")
                            return

                    if os.path.exists(target_file_path):
                        fsize = os.path.getsize(target_file_path)
                        f_hash = calculate_sha256(target_file_path)
                        
                        async with AsyncSessionLocal() as local_db:
                            existing_file = await check_duplicate_file(local_db, user_id, f_hash)
                            if existing_file:
                                if job.destination == "DIRECT_DOWNLOAD" and (not existing_file.local_path or not os.path.exists(existing_file.local_path)):
                                    existing_file.local_path = target_file_path
                                    await local_db.commit()

                                job_file = JobFile(
                                    job_id=job.id,
                                    file_id=existing_file.id,
                                    status="DEDUP_SKIPPED"
                                )
                                local_db.add(job_file)
                                await local_db.commit()
                                if job.destination == "GDRIVE":
                                    try: os.remove(target_file_path)
                                    except Exception: pass
                            else:
                                drive_id, web_link = None, None
                                if drive_service and target_drive_folder:
                                    drive_id, web_link, up_err = upload_file_to_drive(
                                        drive_service,
                                        target_file_path,
                                        folder_id=target_drive_folder
                                    )
                                    try: os.remove(target_file_path)
                                    except Exception: pass

                                new_file = await register_processed_file(
                                    db=local_db,
                                    user_id=user_id,
                                    sha256=f_hash,
                                    filename=clean_name,
                                    file_size_bytes=fsize,
                                    mime_type=getattr(msg.file, "mime_type", None) if getattr(msg, "file", None) else None,
                                    telegram_ref=f"{parsed.channel_ref}/{msg.id}",
                                    drive_file_id=drive_id,
                                    drive_web_link=web_link,
                                    local_path=target_file_path if job.destination == "DIRECT_DOWNLOAD" else None
                                )
                                job_file = JobFile(
                                    job_id=job.id,
                                    file_id=new_file.id,
                                    status="COMPLETED"
                                )
                                local_db.add(job_file)
                                await local_db.commit()

                        async with db_lock:
                            processed_count += 1
                            track_speed["bytes_total"] += fsize
                            dt = time.time() - track_speed["start_time"]
                            speed_mbs = (track_speed["bytes_total"] / (1024 * 1024)) / dt if dt > 0 else 0.0
                            pct = round((processed_count / total_files_count) * 100, 1)

                            rem_files = total_files_count - processed_count
                            avg_size = (track_speed["bytes_total"] / processed_count) if processed_count > 0 else 0
                            rem_bytes = rem_files * avg_size
                            eta_sec = int(rem_bytes / (speed_mbs * 1024 * 1024)) if speed_mbs > 0 else 0

                            await manager.broadcast_user_job_progress(user_id, {
                                "job_id": job.id,
                                "status": "RUNNING",
                                "progress": pct,
                                "speed_mbs": round(speed_mbs, 2),
                                "eta_seconds": eta_sec,
                                "current_file": clean_name,
                                "processed_files": processed_count,
                                "total_files": total_files_count
                            })

            await asyncio.gather(*[process_single_item(i, m, t) for i, (m, t) in enumerate(items_to_download, start=1)])

            job.status = JobStatus.COMPLETED
            job.progress_percent = 100.0
            job.current_file_name = None
            job.speed_mbs = 0.0
            job.eta_seconds = 0
            job.processed_files = total_files_count
            await db.commit()

            await manager.broadcast_user_job_progress(user_id, {
                "job_id": job.id,
                "status": "COMPLETED",
                "progress": 100.0,
                "processed_files": total_files_count,
                "total_files": total_files_count,
                "speed_mbs": 0.0,
                "eta_seconds": 0
            })

        except Exception as e:
            job.status = JobStatus.FAILED
            job.error_message = str(e)
            await db.commit()
            await manager.broadcast_user_job_progress(user_id, {"job_id": job.id, "status": "FAILED", "error": str(e)})
        finally:
            if job_id in job_control_signals:
                del job_control_signals[job_id]
            await client.disconnect()

