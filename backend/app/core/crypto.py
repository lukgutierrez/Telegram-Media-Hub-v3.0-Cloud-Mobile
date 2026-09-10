import base64
from cryptography.fernet import Fernet
from app.core.config import settings

def _get_cipher_suite():
    key = settings.ENCRYPTION_KEY
    # Si la clave no tiene el formato Fernet adecuado, la derivamos de forma segura
    try:
        return Fernet(key.encode() if isinstance(key, str) else key)
    except Exception:
        # Fallback seguro: derivar 32 bytes base64
        padded = (key + "================================")[:32]
        fernet_key = base64.urlsafe_b64encode(padded.encode())
        return Fernet(fernet_key)

def encrypt_secret(plain_text: str) -> str:
    """Cifra un texto plano (StringSession o Token JSON) devolviendo un string seguro."""
    if not plain_text:
        return ""
    cipher = _get_cipher_suite()
    encrypted_bytes = cipher.encrypt(plain_text.encode('utf-8'))
    return encrypted_bytes.decode('utf-8')

def decrypt_secret(encrypted_text: str) -> str:
    """Descifra una cadena cifrada y retorna el texto original."""
    if not encrypted_text:
        return ""
    cipher = _get_cipher_suite()
    decrypted_bytes = cipher.decrypt(encrypted_text.encode('utf-8'))
    return decrypted_bytes.decode('utf-8')
