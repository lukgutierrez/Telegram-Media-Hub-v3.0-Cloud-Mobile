import os
import json
import time
from typing import Optional, Tuple, Dict, Any
from google.oauth2.credentials import Credentials
from google_auth_oauthlib.flow import Flow
from google.auth.transport.requests import Request
from googleapiclient.discovery import build
from googleapiclient.http import MediaFileUpload
from app.core.config import settings
from app.core.crypto import encrypt_secret, decrypt_secret

SCOPES = [
    'https://www.googleapis.com/auth/drive.file',
    'https://www.googleapis.com/auth/drive'
]

def get_drive_auth_url(user_id: int) -> Tuple[Optional[str], Optional[str]]:
    """Genera la URL de consentimiento OAuth 2.0 para que el usuario conecte su Google Drive."""
    if not settings.GOOGLE_CLIENT_ID or not settings.GOOGLE_CLIENT_SECRET:
        # Modo simulación o sin credenciales cloud configuradas
        return None, "GOOGLE_CLIENT_ID y GOOGLE_CLIENT_SECRET no están configurados en el servidor."

    client_config = {
        "web": {
            "client_id": settings.GOOGLE_CLIENT_ID,
            "client_secret": settings.GOOGLE_CLIENT_SECRET,
            "auth_uri": "https://accounts.google.com/o/oauth2/auth",
            "token_uri": "https://oauth2.googleapis.com/token",
            "redirect_uris": [settings.GOOGLE_REDIRECT_URI]
        }
    }

    try:
        flow = Flow.from_client_config(
            client_config,
            scopes=SCOPES,
            redirect_uri=settings.GOOGLE_REDIRECT_URI
        )
        auth_url, _ = flow.authorization_url(
            prompt='consent',
            access_type='offline',
            state=str(user_id)
        )
        return auth_url, None
    except Exception as e:
        return None, str(e)


def exchange_drive_code(code: str) -> Tuple[bool, Optional[str], Optional[str]]:
    """Canjea el código de autorización de Google por tokens de acceso/refresh y los cifra."""
    client_config = {
        "web": {
            "client_id": settings.GOOGLE_CLIENT_ID,
            "client_secret": settings.GOOGLE_CLIENT_SECRET,
            "auth_uri": "https://accounts.google.com/o/oauth2/auth",
            "token_uri": "https://oauth2.googleapis.com/token",
            "redirect_uris": [settings.GOOGLE_REDIRECT_URI]
        }
    }

    try:
        flow = Flow.from_client_config(
            client_config,
            scopes=SCOPES,
            redirect_uri=settings.GOOGLE_REDIRECT_URI
        )
        flow.fetch_token(code=code)
        creds = flow.credentials
        encrypted_token = encrypt_secret(creds.to_json())
        return True, encrypted_token, None
    except Exception as e:
        return False, None, str(e)


def get_drive_service(encrypted_token_json: str):
    """Retorna una instancia autenticada de Google Drive API v3."""
    raw_json = decrypt_secret(encrypted_token_json)
    token_data = json.loads(raw_json)
    
    creds = Credentials.from_authorized_user_info(token_data, SCOPES)
    if not creds.valid:
        if creds.expired and creds.refresh_token:
            creds.refresh(Request())
            
    return build('drive', 'v3', credentials=creds)


def create_or_get_folder(service, folder_name: str, parent_id: Optional[str] = None) -> Optional[str]:
    """Crea una carpeta en Google Drive o retorna su ID si ya existe."""
    query = f"mimeType='application/vnd.google-apps.folder' and name='{folder_name}' and trashed=false"
    if parent_id:
        query += f" and '{parent_id}' in parents"

    try:
        results = service.files().list(q=query, spaces='drive', fields='files(id, name)').execute()
        files = results.get('files', [])
        if files:
            return files[0]['id']

        file_metadata = {
            'name': folder_name,
            'mimeType': 'application/vnd.google-apps.folder'
        }
        if parent_id:
            file_metadata['parents'] = [parent_id]

        folder = service.files().create(body=file_metadata, fields='id').execute()
        return folder.get('id')
    except Exception:
        return None


def upload_file_to_drive(
    service,
    file_path: str,
    folder_id: Optional[str] = None,
    progress_callback = None
) -> Tuple[Optional[str], Optional[str], Optional[str]]:
    """Sube un archivo por bloques a Google Drive (64MB/128MB Chunks) reportando progreso."""
    if not os.path.exists(file_path):
        return None, None, "El archivo local no existe."

    filename = os.path.basename(file_path)
    file_size = os.path.getsize(file_path)

    metadata = {'name': filename}
    if folder_id:
        metadata['parents'] = [folder_id]

    chunk_size = 64 * 1024 * 1024
    if file_size > 1 * 1024 * 1024 * 1024:
        chunk_size = 128 * 1024 * 1024

    media = MediaFileUpload(
        file_path,
        mimetype='application/octet-stream',
        chunksize=chunk_size,
        resumable=True
    )

    try:
        request = service.files().create(body=metadata, media_body=media, fields='id, name, webViewLink')
        response = None
        
        t_start = time.time()
        t_last = t_start
        bytes_last = 0
        smooth_speed = 0.0

        while response is None:
            status, response = request.next_chunk()
            if status:
                current_bytes = status.progress()
                t_now = time.time()
                dt = t_now - t_last
                if dt > 0.3:
                    d_bytes = current_bytes - bytes_last
                    inst_speed = (d_bytes / (1024 * 1024)) / dt if dt > 0 else 0
                    smooth_speed = 0.7 * smooth_speed + 0.3 * inst_speed if smooth_speed > 0 else inst_speed
                    t_last = t_now
                    bytes_last = current_bytes

                if progress_callback:
                    try:
                        progress_callback(filename, current_bytes, file_size, smooth_speed)
                    except Exception:
                        pass

        drive_id = response.get('id')
        web_link = response.get('webViewLink', f"https://drive.google.com/file/d/{drive_id}/view")
        return drive_id, web_link, None

    except Exception as e:
        return None, None, str(e)
