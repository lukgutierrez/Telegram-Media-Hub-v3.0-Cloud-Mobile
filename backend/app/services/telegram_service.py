import os
import re
import math
import asyncio
from datetime import datetime
from collections import Counter
from typing import Optional, Dict, Any, Tuple, List
from telethon import TelegramClient, utils
from telethon.sessions import StringSession
from telethon.tl.types import (
    User, Channel, Chat,
    MessageMediaPhoto, MessageMediaDocument,
    DocumentAttributeVideo, DocumentAttributeAudio
)
from telethon.tl.functions.messages import GetForumTopicsRequest
from telethon.tl.functions.upload import GetFileRequest
from telethon.errors import (
    SessionPasswordNeededError,
    PhoneCodeInvalidError,
    PhoneCodeExpiredError,
    FloodWaitError
)
from app.core.config import settings
from app.core.crypto import encrypt_secret, decrypt_secret

_pending_login_clients: Dict[str, TelegramClient] = {}

class ParsedTelegramLink:
    def __init__(self, link_type: str, channel_ref: str, msg_id: Optional[int] = None, topic_id: Optional[int] = None):
        self.link_type = link_type
        self.channel_ref = channel_ref
        self.msg_id = msg_id
        self.topic_id = topic_id

def parse_telegram_link(target: str) -> ParsedTelegramLink:
    target = target.strip()
    m_priv_topic = re.search(r"t\.me/c/(\d+)/(\d+)/(\d+)", target)
    if m_priv_topic:
        return ParsedTelegramLink("PRIVATE_TOPIC", m_priv_topic.group(1), msg_id=int(m_priv_topic.group(3)), topic_id=int(m_priv_topic.group(2)))
        
    m_priv = re.search(r"t\.me/c/(\d+)/(\d+)", target)
    if m_priv:
        return ParsedTelegramLink("PRIVATE", m_priv.group(1), msg_id=int(m_priv.group(2)))
        
    m_pub_topic = re.search(r"t\.me/([a-zA-Z0-9_]+)/(\d+)/(\d+)", target)
    if m_pub_topic:
        return ParsedTelegramLink("PUBLIC_TOPIC", m_pub_topic.group(1), msg_id=int(m_pub_topic.group(3)), topic_id=int(m_pub_topic.group(2)))
        
    m_pub = re.search(r"t\.me/([a-zA-Z0-9_]+)/(\d+)", target)
    if m_pub:
        return ParsedTelegramLink("PUBLIC", m_pub.group(1), msg_id=int(m_pub.group(2)))
        
    m_inv = re.search(r"t\.me/(?:\+|joinchat/)([a-zA-Z0-9_-]+)", target)
    if m_inv:
        return ParsedTelegramLink("INVITE", m_inv.group(1))
        
    if target.lstrip("-").isdigit():
        return ParsedTelegramLink("NUMERIC_ID", target)
        
    clean_username = target.lstrip("@").split("/")[0]
    return ParsedTelegramLink("USERNAME", clean_username)


async def send_telegram_login_code(phone: str) -> Tuple[bool, str, Optional[str]]:
    try:
        client = TelegramClient(StringSession(), settings.TELEGRAM_API_ID, settings.TELEGRAM_API_HASH)
        await client.connect()
        sent_code = await client.send_code_request(phone)
        _pending_login_clients[phone] = client
        return True, "Código enviado exitosamente.", sent_code.phone_code_hash
    except FloodWaitError as e:
        return False, f"Telegram requiere esperar {e.seconds} segundos por seguridad.", None
    except Exception as e:
        return False, str(e), None


async def complete_telegram_login(
    phone: str,
    code: str,
    phone_code_hash: str,
    two_factor_password: Optional[str] = None
) -> Tuple[bool, str, Optional[str], Optional[Dict[str, Any]]]:
    client = _pending_login_clients.get(phone)
    if not client:
        client = TelegramClient(StringSession(), settings.TELEGRAM_API_ID, settings.TELEGRAM_API_HASH)
        await client.connect()

    try:
        try:
            user = await client.sign_in(phone, code, phone_code_hash=phone_code_hash)
        except SessionPasswordNeededError:
            if not two_factor_password:
                return False, "2FA_REQUIRED", None, None
            user = await client.sign_in(password=two_factor_password)

        session_str = client.session.save()
        encrypted_session = encrypt_secret(session_str)
        
        user_info = {
            "telegram_id": user.id,
            "first_name": user.first_name,
            "username": user.username,
            "phone": user.phone
        }
        
        if phone in _pending_login_clients:
            del _pending_login_clients[phone]
            
        return True, "Login exitoso", encrypted_session, user_info

    except (PhoneCodeInvalidError, PhoneCodeExpiredError):
        return False, "El código ingresado es incorrecto o ha expirado.", None, None
    except Exception as e:
        return False, str(e), None, None


def get_user_telegram_client(encrypted_session_string: str) -> TelegramClient:
    session_str = decrypt_secret(encrypted_session_string)
    return TelegramClient(StringSession(session_str), settings.TELEGRAM_API_ID, settings.TELEGRAM_API_HASH)


def sanitize_filename(filename: str) -> str:
    return re.sub(r'[\\/*?:"<>|]', "", filename)


async def resolve_entity_safe(client: TelegramClient, target: str):
    parsed = parse_telegram_link(target)
    ref = parsed.channel_ref
    
    if ref.lstrip("-").isdigit():
        clean_digits = ref.lstrip("-")
        if clean_digits.startswith("100"):
            clean_digits = clean_digits[3:]
        
        candidate_ids = [
            int(f"-100{clean_digits}"),
            int(clean_digits),
            int(f"-{clean_digits}"),
            int(ref)
        ]
        for cid in candidate_ids:
            try:
                return await client.get_entity(cid)
            except Exception:
                pass

    try:
        return await client.get_entity(ref)
    except Exception:
        pass

    try:
        async for d in client.iter_dialogs(limit=150):
            d_id = str(d.entity.id).lstrip("-")
            if d_id.startswith("100"):
                d_id = d_id[3:]
            target_clean = ref.lstrip("-")
            if target_clean.startswith("100"):
                target_clean = target_clean[3:]
            
            if target_clean == d_id or ref == str(d.entity.id) or ref == getattr(d.entity, 'username', None):
                return d.entity
    except Exception:
        pass

    return None


async def list_user_dialogs(client: TelegramClient) -> List[Dict[str, Any]]:
    chats = []
    async for dialog in client.iter_dialogs():
        entity = dialog.entity
        title = dialog.name or "Sin nombre"
        chat_id = entity.id
        
        if isinstance(entity, (Channel, Chat)):
            chat_id_fmt = f"-100{chat_id}" if chat_id > 0 else str(chat_id)
        else:
            chat_id_fmt = str(chat_id)

        tipo = "Usuario"
        if isinstance(entity, Channel):
            if getattr(entity, "forum", False):
                tipo = "Foro (Topics)"
            elif getattr(entity, "megagroup", False):
                tipo = "Supergrupo"
            else:
                tipo = "Canal Broadcast"
        elif isinstance(entity, Chat):
            tipo = "Grupo Básico"

        username = f"@{entity.username}" if getattr(entity, "username", None) else "Privado"
        miembros_cnt = getattr(entity, "participants_count", None)

        chats.append({
            "title": title,
            "id": chat_id_fmt,
            "type": tipo,
            "username": username,
            "members": miembros_cnt if miembros_cnt is not None else "N/A",
            "is_forum": bool(isinstance(entity, Channel) and getattr(entity, "forum", False))
        })
    return chats


async def fast_download_media(client: TelegramClient, message, out_path: str, progress_callback=None, workers: int = 6):
    """Descarga de ultra alta velocidad mediante chunks paralelos (512KB) y soporte para cryptg."""
    if not message.media:
        return None

    try:
        loc = utils.get_input_location(message)
        if isinstance(loc, tuple):
            media_dc_id, input_loc = loc
        else:
            media_dc_id, input_loc = client.session.dc_id, loc
    except Exception:
        return await client.download_media(message, file=out_path, progress_callback=progress_callback)

    file_size = getattr(message.file, "size", 0) or 0
    if not file_size or file_size < 512 * 1024:
        return await client.download_media(message, file=out_path, progress_callback=progress_callback)

    part_size = 512 * 1024 # 512 KB
    parts_count = math.ceil(file_size / part_size)

    # Pre-asignar archivo en disco
    try:
        with open(out_path, "wb") as f:
            f.seek(file_size - 1)
            f.write(b"\0")
    except Exception:
        return await client.download_media(message, file=out_path, progress_callback=progress_callback)

    downloaded_bytes = 0
    lock = asyncio.Lock()
    queue = asyncio.Queue()
    for i in range(parts_count):
        queue.put_nowait(i)

    is_same_dc = (media_dc_id == client.session.dc_id)

    async def worker():
        nonlocal downloaded_bytes
        borrowed = False
        if is_same_dc:
            sender = client._sender
        else:
            try:
                sender = await client._borrow_exported_sender(media_dc_id)
                borrowed = True
            except Exception:
                sender = client._sender

        try:
            with open(out_path, "r+b") as f:
                while True:
                    try:
                        part_idx = queue.get_nowait()
                    except asyncio.QueueEmpty:
                        break

                    offset = part_idx * part_size
                    # En la API de Telegram, limit DEBE ser múltiplo de 4KB (512KB) incluso en el último chunk
                    req = GetFileRequest(location=input_loc, offset=offset, limit=part_size)
                    
                    try:
                        if is_same_dc or not borrowed:
                            res = await client(req)
                        else:
                            res = await sender.send(req)
                    except Exception:
                        res = await client(req)

                    f.seek(offset)
                    f.write(res.bytes)

                    async with lock:
                        downloaded_bytes += len(res.bytes)
                        if progress_callback:
                            try:
                                progress_callback(min(downloaded_bytes, file_size), file_size)
                            except Exception:
                                pass
                    queue.task_done()
        finally:
            if borrowed:
                try:
                    await client._return_exported_sender(sender)
                except Exception:
                    pass

    num_workers = min(workers, parts_count)
    tasks = [asyncio.create_task(worker()) for _ in range(num_workers)]
    await asyncio.gather(*tasks)
    return out_path


async def pre_analyze_topics_service(client: TelegramClient, entity, topics_ids: Optional[List[int]] = None, concurrency: int = 10) -> Dict[str, Any]:
    """Carga instantánea de la estructura de Topics de un foro (0.3s) con metadatos."""
    all_topics = []
    try:
        res = await client(GetForumTopicsRequest(
            peer=entity, offset_date=None, offset_id=0, offset_topic=0, limit=300
        ))
        all_topics = list(res.topics)
    except Exception:
        all_topics = []

    # Fallback si no es un foro o no tiene topics
    if not all_topics:
        photos, videos, others, bytes_t = 0, 0, 0, 0
        try:
            async for msg in client.iter_messages(entity, limit=50):
                if not msg.media:
                    continue
                sz = getattr(msg.file, "size", 0) or 0
                bytes_t += sz
                if msg.photo: photos += 1
                elif msg.video: videos += 1
                else: others += 1
        except Exception:
            pass
        
        speed_est = max(8.0, concurrency * 1.5)
        total_mb = bytes_t / (1024 * 1024)
        eta_sec = int(total_mb / speed_est) if speed_est > 0 else 0
        m_est, s_est = divmod(eta_sec, 60)
        
        return {
            "topics": [{
                "id": 1,
                "title": getattr(entity, 'title', 'Canal Principal'),
                "photos": photos,
                "videos": videos,
                "other": others,
                "total_files": photos + videos + others,
                "size_mb": round(total_mb, 2)
            }],
            "summary": {
                "total_topics": 1,
                "total_photos": photos,
                "total_videos": videos,
                "total_other": others,
                "total_files": photos + videos + others,
                "total_mb": round(total_mb, 2),
                "eta_formatted": f"{m_est:02d}:{s_est:02d} min (@ {speed_est:.1f} MB/s)"
            }
        }

    target_topics = all_topics
    if topics_ids:
        target_topics = [t for t in all_topics if t.id in topics_ids]

    clean_details = []
    for t in target_topics:
        topic_id = t.id
        topic_title = getattr(t, 'title', f"Tema {topic_id}")
        unread = getattr(t, 'unread_count', 0) or 0
        
        clean_details.append({
            "id": topic_id,
            "title": topic_title,
            "photos": "Auto",
            "videos": "Auto",
            "other": "Auto",
            "total_files": unread if unread > 0 else "Disponible",
            "size_mb": "Alta Vel."
        })

    speed_est = max(8.0, concurrency * 1.5)

    return {
        "topics": clean_details,
        "summary": {
            "total_topics": len(clean_details),
            "total_photos": "Detectando...",
            "total_videos": "Detectando...",
            "total_other": "-",
            "total_files": len(clean_details),
            "total_mb": "En Vivo",
            "eta_formatted": f"Turbo ⚡ (@ {speed_est:.1f} MB/s)"
        }
    }


async def osint_stats_channel(client: TelegramClient, channel) -> Dict[str, Any]:
    counter_tipos = Counter()
    counter_usuarios = Counter()
    counter_dias = Counter()
    counter_horas = Counter()
    total_msg = 0
    total_con_media = 0

    async for message in client.iter_messages(channel, limit=100):
        total_msg += 1
        if message.media:
            total_con_media += 1
            if isinstance(message.media, MessageMediaPhoto):
                counter_tipos["Fotos"] += 1
            elif isinstance(message.media, MessageMediaDocument):
                doc = message.media.document
                if doc:
                    has_vid = any(isinstance(a, DocumentAttributeVideo) for a in doc.attributes)
                    has_aud = any(isinstance(a, DocumentAttributeAudio) for a in doc.attributes)
                    if has_vid:
                        counter_tipos["Videos"] += 1
                    elif has_aud:
                        counter_tipos["Audio"] += 1
                    else:
                        counter_tipos["Documentos"] += 1

        if message.sender_id:
            try:
                user = await client.get_entity(message.sender_id)
                u_name = user.first_name or f"User_{user.id}"
                counter_usuarios[u_name] += 1
            except Exception:
                counter_usuarios[f"ID_{message.sender_id}"] += 1

        if message.date:
            counter_dias[message.date.strftime("%A")] += 1
            counter_horas[message.date.hour] += 1

    hora_pico = counter_horas.most_common(1)[0] if counter_horas else (0, 0)
    dia_pico = counter_dias.most_common(1)[0] if counter_dias else ("N/A", 0)

    return {
        "total_messages_analyzed": total_msg,
        "media_messages": total_con_media,
        "media_ratio": round((total_con_media / total_msg * 100), 1) if total_msg > 0 else 0,
        "media_types": dict(counter_tipos),
        "top_active_users": dict(counter_usuarios.most_common(5)),
        "peak_hour": f"{hora_pico[0]}:00 ({hora_pico[1]} mensajes)",
        "most_active_day": f"{dia_pico[0]} ({dia_pico[1]} mensajes)"
    }


async def osint_search_keywords(client: TelegramClient, channel, keyword: str, limit: int = 50) -> List[Dict[str, Any]]:
    results = []
    async for msg in client.iter_messages(channel, search=keyword, limit=limit):
        sender = await msg.get_sender()
        autor = f"{sender.first_name or ''} {sender.last_name or ''}".strip() if sender else "Desconocido"
        if sender and getattr(sender, "username", None):
            autor += f" (@{sender.username})"
            
        results.append({
            "msg_id": msg.id,
            "date": msg.date.strftime("%Y-%m-%d %H:%M") if msg.date else "N/A",
            "author": autor,
            "text": msg.text or "[Archivo Multimedia]"
        })
    return results


async def osint_recent_messages(client: TelegramClient, channel, limit: int = 15) -> List[Dict[str, Any]]:
    msgs = []
    async for msg in client.iter_messages(channel, limit=limit):
        m_type = "Texto"
        if msg.photo:
            m_type = "Foto 📷"
        elif msg.video:
            m_type = "Video 🎥"
        elif msg.media:
            m_type = "Documento 📄"

        msgs.append({
            "id": msg.id,
            "date": msg.date.strftime("%d/%m %H:%M") if msg.date else "N/A",
            "type": m_type,
            "text": (msg.text or "")[:120]
        })
    return msgs


async def search_global_telegram_messages(
    client: TelegramClient,
    query: str,
    media_filter: str = "ALL", # ALL, MEDIA_ONLY, VIDEO, PHOTO, DOCUMENT
    limit: int = 150
) -> Dict[str, Any]:
    found_map = {} # (chat_id, msg_id) -> dict
    chat_cache = {}
    q_clean = query.strip()
    q_words = [w.upper() for w in q_clean.split() if len(w) > 1]

    # --- 1. BÚSQUEDA GLOBAL DE MENSAJES DIRECTA (ULTRA RÁPIDA) ---
    try:
        async for msg in client.iter_messages(None, search=query, limit=limit):
            cid = msg.chat_id
            if cid not in chat_cache:
                try:
                    chat = await msg.get_chat()
                    chat_cache[cid] = getattr(chat, 'title', getattr(chat, 'first_name', str(cid)))
                except Exception:
                    chat_cache[cid] = str(cid)
            cname = chat_cache[cid]

            key = (cid, msg.id)
            if key not in found_map:
                is_video = bool(msg.video or (getattr(msg, 'file', None) and getattr(msg.file, 'mime_type', '').startswith('video/')))
                is_photo = bool(msg.photo or (getattr(msg, 'file', None) and getattr(msg.file, 'mime_type', '').startswith('image/')))
                is_doc = bool(msg.media and not is_video and not is_photo)

                fn = msg.file.name if getattr(msg, 'file', None) and msg.file.name else (f"video_{msg.id}.mp4" if is_video else (f"photo_{msg.id}.jpg" if is_photo else f"msg_{msg.id}"))
                sz = round(msg.file.size / (1024*1024), 2) if getattr(msg, 'file', None) and msg.file.size else 0
                sz_bytes = msg.file.size if getattr(msg, 'file', None) and msg.file.size else 0

                s_name = "Usuario"
                try:
                    if msg.sender:
                        s_name = getattr(msg.sender, 'first_name', '') or getattr(msg.sender, 'title', 'Usuario')
                except Exception:
                    pass

                found_map[key] = {
                    "msg_id": msg.id,
                    "chat_id": cid,
                    "chat_title": cname,
                    "sender_name": s_name,
                    "date": msg.date.strftime("%Y-%m-%d %H:%M") if msg.date else "N/A",
                    "text": (msg.text or "[Archivo Multimedia]").replace("\n", " ")[:80],
                    "has_media": bool(msg.media),
                    "media_type": "VIDEO" if is_video else ("PHOTO" if is_photo else ("DOCUMENT" if is_doc else "TEXT")),
                    "filename": fn,
                    "size_mb": sz,
                    "size_bytes": sz_bytes,
                    "origin": "DIRECT_MATCH"
                }

            # Si es parte de un álbum (pack de fotos/videos), extraer los demás archivos del álbum
            if msg.grouped_id:
                try:
                    async for album_msg in client.iter_messages(cid, min_id=max(1, msg.id - 8), max_id=msg.id + 8):
                        if album_msg.grouped_id == msg.grouped_id:
                            a_key = (cid, album_msg.id)
                            if a_key not in found_map:
                                a_is_video = bool(album_msg.video or (getattr(album_msg, 'file', None) and getattr(album_msg.file, 'mime_type', '').startswith('video/')))
                                a_is_photo = bool(album_msg.photo or (getattr(album_msg, 'file', None) and getattr(album_msg.file, 'mime_type', '').startswith('image/')))
                                a_is_doc = bool(album_msg.media and not a_is_video and not a_is_photo)

                                a_fn = album_msg.file.name if getattr(album_msg, 'file', None) and album_msg.file.name else (f"video_{album_msg.id}.mp4" if a_is_video else (f"photo_{album_msg.id}.jpg" if a_is_photo else f"msg_{album_msg.id}"))
                                a_sz = round(album_msg.file.size / (1024*1024), 2) if getattr(album_msg, 'file', None) and album_msg.file.size else 0
                                a_sz_bytes = album_msg.file.size if getattr(album_msg, 'file', None) and album_msg.file.size else 0

                                found_map[a_key] = {
                                    "msg_id": album_msg.id,
                                    "chat_id": cid,
                                    "chat_title": cname,
                                    "sender_name": "Álbum Multimedia",
                                    "date": album_msg.date.strftime("%Y-%m-%d %H:%M") if album_msg.date else "N/A",
                                    "text": f"[Álbum: {query}] {album_msg.text or ''}".replace("\n", " ")[:80],
                                    "has_media": bool(album_msg.media),
                                    "media_type": "VIDEO" if a_is_video else ("PHOTO" if a_is_photo else ("DOCUMENT" if a_is_doc else "TEXT")),
                                    "filename": a_fn,
                                    "size_mb": a_sz,
                                    "size_bytes": a_sz_bytes,
                                    "origin": "ALBUM_PACK"
                                }
                except Exception:
                    pass
    except Exception:
        pass

    # --- 2. RASTREO COMPLEMENTARIO EN TÍTULOS DE FOROS DE TOPICS ---
    try:
        dialogs = await client.get_dialogs(limit=30)
        forum_dialogs = [d for d in dialogs if d.is_channel and getattr(d.entity, 'forum', False)]

        for dialog in forum_dialogs[:5]:
            try:
                res_topics = await client(GetForumTopicsRequest(
                    peer=dialog.entity, offset_date=None, offset_id=0, offset_topic=0, limit=50
                ))
                if res_topics and res_topics.topics:
                    for t in res_topics.topics:
                        t_title = t.title or ""
                        t_title_upper = t_title.upper()
                        is_match = q_clean.upper() in t_title_upper or any(w in t_title_upper for w in q_words)
                        if is_match:
                            try:
                                async for tm in client.iter_messages(dialog.entity, reply_to=t.id, limit=30):
                                    key = (dialog.id, tm.id)
                                    if key not in found_map:
                                        is_video = bool(tm.video or (getattr(tm, 'file', None) and getattr(tm.file, 'mime_type', '').startswith('video/')))
                                        is_photo = bool(tm.photo or (getattr(tm, 'file', None) and getattr(tm.file, 'mime_type', '').startswith('image/')))
                                        is_doc = bool(tm.media and not is_video and not is_photo)

                                        fn = tm.file.name if getattr(tm, 'file', None) and tm.file.name else (f"video_{tm.id}.mp4" if is_video else (f"photo_{tm.id}.jpg" if is_photo else f"doc_{tm.id}"))
                                        sz = round(tm.file.size / (1024*1024), 2) if getattr(tm, 'file', None) and tm.file.size else 0
                                        sz_bytes = tm.file.size if getattr(tm, 'file', None) and tm.file.size else 0

                                        found_map[key] = {
                                            "msg_id": tm.id,
                                            "chat_id": dialog.id,
                                            "chat_title": f"{dialog.name} / {t_title}",
                                            "sender_name": "Topic Post",
                                            "date": tm.date.strftime("%Y-%m-%d %H:%M") if tm.date else "N/A",
                                            "text": (tm.text or f"📁 Topic: {t_title}").replace("\n", " ")[:80],
                                            "has_media": bool(tm.media),
                                            "media_type": "VIDEO" if is_video else ("PHOTO" if is_photo else ("DOCUMENT" if is_doc else "TEXT")),
                                            "filename": fn,
                                            "size_mb": sz,
                                            "size_bytes": sz_bytes,
                                            "origin": "FORUM_TOPIC"
                                        }
                            except Exception:
                                pass
            except Exception:
                pass
    except Exception:
        pass


    # --- 2. BÚSQUEDA GLOBAL DE MENSAJES + EXPANSIÓN CONTEXTUAL Y DE ÁLBUMES ---
    try:
        async for msg in client.iter_messages(None, search=query, limit=limit):
            cid = msg.chat_id
            if cid not in chat_cache:
                try:
                    chat = await msg.get_chat()
                    chat_cache[cid] = getattr(chat, 'title', getattr(chat, 'first_name', str(cid)))
                except Exception:
                    chat_cache[cid] = str(cid)
            cname = chat_cache[cid]

            key = (cid, msg.id)
            if key not in found_map:
                is_video = bool(msg.video or (getattr(msg, 'file', None) and getattr(msg.file, 'mime_type', '').startswith('video/')))
                is_photo = bool(msg.photo or (getattr(msg, 'file', None) and getattr(msg.file, 'mime_type', '').startswith('image/')))
                is_doc = bool(msg.media and not is_video and not is_photo)

                fn = msg.file.name if getattr(msg, 'file', None) and msg.file.name else (f"video_{msg.id}.mp4" if is_video else (f"photo_{msg.id}.jpg" if is_photo else f"msg_{msg.id}"))
                sz = round(msg.file.size / (1024*1024), 2) if getattr(msg, 'file', None) and msg.file.size else 0
                sz_bytes = msg.file.size if getattr(msg, 'file', None) and msg.file.size else 0

                s_name = "Usuario"
                try:
                    if msg.sender:
                        s_name = getattr(msg.sender, 'first_name', '') or getattr(msg.sender, 'title', 'Usuario')
                except Exception:
                    pass

                found_map[key] = {
                    "msg_id": msg.id,
                    "chat_id": cid,
                    "chat_title": cname,
                    "sender_name": s_name,
                    "date": msg.date.strftime("%Y-%m-%d %H:%M") if msg.date else "N/A",
                    "text": (msg.text or "[Archivo Multimedia]").replace("\n", " ")[:80],
                    "has_media": bool(msg.media),
                    "media_type": "VIDEO" if is_video else ("PHOTO" if is_photo else ("DOCUMENT" if is_doc else "TEXT")),
                    "filename": fn,
                    "size_mb": sz,
                    "size_bytes": sz_bytes,
                    "origin": "DIRECT_MATCH"
                }

            # Si es parte de un álbum (pack de fotos/videos), extraer los demás archivos del álbum
            if msg.grouped_id:
                try:
                    async for album_msg in client.iter_messages(cid, min_id=max(1, msg.id - 10), max_id=msg.id + 10):
                        if album_msg.grouped_id == msg.grouped_id:
                            a_key = (cid, album_msg.id)
                            if a_key not in found_map:
                                a_is_video = bool(album_msg.video or (getattr(album_msg, 'file', None) and getattr(album_msg.file, 'mime_type', '').startswith('video/')))
                                a_is_photo = bool(album_msg.photo or (getattr(album_msg, 'file', None) and getattr(album_msg.file, 'mime_type', '').startswith('image/')))
                                a_is_doc = bool(album_msg.media and not a_is_video and not a_is_photo)

                                a_fn = album_msg.file.name if getattr(album_msg, 'file', None) and album_msg.file.name else (f"video_{album_msg.id}.mp4" if a_is_video else (f"photo_{album_msg.id}.jpg" if a_is_photo else f"msg_{album_msg.id}"))
                                a_sz = round(album_msg.file.size / (1024*1024), 2) if getattr(album_msg, 'file', None) and album_msg.file.size else 0
                                a_sz_bytes = album_msg.file.size if getattr(album_msg, 'file', None) and album_msg.file.size else 0

                                found_map[a_key] = {
                                    "msg_id": album_msg.id,
                                    "chat_id": cid,
                                    "chat_title": cname,
                                    "sender_name": "Álbum Multimedia",
                                    "date": album_msg.date.strftime("%Y-%m-%d %H:%M") if album_msg.date else "N/A",
                                    "text": f"[Álbum: {query}] {album_msg.text or ''}".replace("\n", " ")[:80],
                                    "has_media": bool(album_msg.media),
                                    "media_type": "VIDEO" if a_is_video else ("PHOTO" if a_is_photo else ("DOCUMENT" if a_is_doc else "TEXT")),
                                    "filename": a_fn,
                                    "size_mb": a_sz,
                                    "size_bytes": a_sz_bytes,
                                    "origin": "ALBUM_PACK"
                                }
                except Exception:
                    pass

            # Captura de contexto adyacente (si es mensaje de texto que nombra la persona, revisar +- 6 mensajes contiguos)
            if not msg.media and msg.text:
                try:
                    async for contig_msg in client.iter_messages(cid, min_id=max(1, msg.id - 6), max_id=msg.id + 6):
                        if contig_msg.media:
                            c_key = (cid, contig_msg.id)
                            if c_key not in found_map:
                                c_is_video = bool(contig_msg.video or (getattr(contig_msg, 'file', None) and getattr(contig_msg.file, 'mime_type', '').startswith('video/')))
                                c_is_photo = bool(contig_msg.photo or (getattr(contig_msg, 'file', None) and getattr(contig_msg.file, 'mime_type', '').startswith('image/')))
                                c_is_doc = bool(contig_msg.media and not c_is_video and not c_is_photo)
                                c_fn = contig_msg.file.name if getattr(contig_msg, 'file', None) and contig_msg.file.name else (f"video_{contig_msg.id}.mp4" if c_is_video else (f"photo_{contig_msg.id}.jpg" if c_is_photo else f"msg_{contig_msg.id}"))
                                c_sz = round(contig_msg.file.size / (1024*1024), 2) if getattr(contig_msg, 'file', None) and contig_msg.file.size else 0
                                c_sz_bytes = contig_msg.file.size if getattr(contig_msg, 'file', None) and contig_msg.file.size else 0

                                found_map[c_key] = {
                                    "msg_id": contig_msg.id,
                                    "chat_id": cid,
                                    "chat_title": cname,
                                    "sender_name": "Contenido Adyacente",
                                    "date": contig_msg.date.strftime("%Y-%m-%d %H:%M") if contig_msg.date else "N/A",
                                    "text": f"[Mención de: {msg.text[:30]}] {contig_msg.text or ''}".replace("\n", " ")[:80],
                                    "has_media": True,
                                    "media_type": "VIDEO" if c_is_video else ("PHOTO" if c_is_photo else "DOCUMENT"),
                                    "filename": c_fn,
                                    "size_mb": c_sz,
                                    "size_bytes": c_sz_bytes,
                                    "origin": "CONTEXT_ADJACENT"
                                }
                except Exception:
                    pass
    except Exception:
        pass

    # 3. FILTRADO Y ESTADÍSTICAS
    filtered_results = []
    total_videos = 0
    total_photos = 0
    total_docs = 0
    total_bytes = 0

    for r in found_map.values():
        is_video = r["media_type"] == "VIDEO"
        is_photo = r["media_type"] == "PHOTO"
        is_doc = r["media_type"] == "DOCUMENT"
        has_media = r["has_media"]

        if media_filter == "MEDIA_ONLY" and not has_media:
            continue
        if media_filter == "VIDEO" and not is_video:
            continue
        if media_filter == "PHOTO" and not is_photo:
            continue
        if media_filter == "DOCUMENT" and not is_doc:
            continue

        if is_video:
            total_videos += 1
        elif is_photo:
            total_photos += 1
        elif is_doc:
            total_docs += 1
        total_bytes += r["size_bytes"]

        filtered_results.append(r)

    # Ordenar: primero los que tienen multimedia, luego por fecha descendente
    filtered_results.sort(key=lambda x: (1 if x["has_media"] else 0, x["date"]), reverse=True)

    return {
        "query": query,
        "media_filter": media_filter,
        "total_results": len(filtered_results),
        "summary": {
            "total_matches": len(filtered_results),
            "videos_count": total_videos,
            "photos_count": total_photos,
            "docs_count": total_docs,
            "total_mb": round(total_bytes / (1024 * 1024), 2)
        },
        "results": filtered_results
    }

