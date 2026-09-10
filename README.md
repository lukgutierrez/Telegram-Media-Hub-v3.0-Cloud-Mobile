<div align="center">

# ⚡ TELEGRAM MEDIA HUB v3.0 (Cloud & Mobile Edition)
### 🚀 Plataforma Distribuida de Extracción Masiva de Multimedia, Inteligencia OSINT 360°, App Móvil Flutter & Sincronización en la Nube

[![FastAPI](https://img.shields.io/badge/FastAPI-005571?style=for-the-badge&logo=fastapi)](https://fastapi.tiangolo.com)
[![Python](https://img.shields.io/badge/Python-3.11+-3776AB?style=for-the-badge&logo=python&logoColor=white)](https://python.org)
[![Flutter](https://img.shields.io/badge/Flutter-Android_%26_Web-02569B?style=for-the-badge&logo=flutter&logoColor=white)](https://flutter.dev)
[![Telethon](https://img.shields.io/badge/Telethon-MTProto_Engine-2CA5E0?style=for-the-badge&logo=telegram)](https://docs.telethon.dev)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-16_Alpine-316192?style=for-the-badge&logo=postgresql&logoColor=white)](https://www.postgresql.org)
[![Redis](https://img.shields.io/badge/Redis-7.0_Cache-DC382D?style=for-the-badge&logo=redis&logoColor=white)](https://redis.io)
[![Docker](https://img.shields.io/badge/Docker-Compose_Stack-2496ED?style=for-the-badge&logo=docker&logoColor=white)](https://www.docker.com)
[![Cloudflare](https://img.shields.io/badge/Cloudflare-Zero_Trust_Tunnels-F38020?style=for-the-badge&logo=cloudflare&logoColor=white)](https://cloudflare.com)

**Creador & Arquitecto:** [Luciano Gutiérrez (`@lukgtz`)](https://github.com/lukgtz) • *Salta, Argentina*  
**Licencia:** MIT Open Source • **Estado:** Producción / Estable v3.0

---

</div>

## 🧭 1. Visión General del Sistema

**Telegram Media Hub v3.0** es una solución de ingeniería de software distribuida y reactiva diseñada para la **adquisición masiva y concurrente de multimedia, análisis de inteligencia en fuentes abiertas (OSINT) y empaquetado forense** de canales, supergrupos y foros de Telegram.

El sistema está diseñado bajo una arquitectura de microservicios contenerizados que opera de forma autónoma **24/7 en servidores Cloud (Oracle VPS Always Free)** y se controla de forma remota a través de una **App Móvil Nativa Android (Flutter)** y una **Consola Web Cyberpunk OLED** interconectadas mediante **WebSockets bidireccionales en tiempo real**.

---

## ✨ 2. Capacidades y Módulos Principales

### ⚡ Motor Turbo Downloader Concurrente
- **Descargas Multi-hilo por Chunks:** Descarga concurrente controlada por semáforos asíncronos (`asyncio.Semaphore`), evitando saturación de red y bloqueos por `FloodWaitError`.
- **Soporte Universal de Enlaces:** Parsea enlaces públicos (`t.me/...`), privados (`t.me/c/...`), IDs numéricos negativos (`-100...`) y nombres de usuario (`@...`).
- **Empaquetado Dinámico en ZIP:** Generación y compresión de archivos ZIP al vuelo organizados por carpetas según Topics o tipo de medio.

### 🔍 Motor de Inteligencia OSINT & Búsqueda 360°
- **Búsqueda Global en Milisegundos:** Búsqueda indexada en todos los diálogos y mensajes de Telegram con respuesta `< 1.5s`.
- **Despaquetado Automático de Álbumes:** Detección de `grouped_id` para extraer álbumes multimedia completos asociados a un mensaje.
- **Inspección Técnica (/info):** Identificación forense de entidades (ID numérico, banderas de scam/fake/restringido, conteo de miembros y tipos de medios).
- **Explorador de Foros / Topics:** Enumeración de sub-hilos mediante `GetForumTopicsRequest` con pre-análisis de peso y selección por casillas de verificación (`checkboxes`).

### 🔐 Motor Criptográfico de Deduplicación SHA-256
- **Cálculo por Bloques (64KB):** Genera firmas criptográficas SHA-256 sin cargar archivos enteros en memoria RAM.
- **Ahorro de Ancho de Banda y Espacio:** Si un archivo ya existe en la base de datos o en disco, se omite inmediatamente, registrando las métricas de megabytes ahorrados.

### 📱 Aplicación Móvil Nativa (Flutter Android)
- **Vinculación Táctica Web-Móvil (QR & PIN):** Inicio de sesión en 1 segundo mediante escaneo de Código QR o PIN de 6 dígitos generado en el panel web.
- **Telemetría en Vivo:** Medición de velocidad en tiempo real (MB/s), ETA estimado, porcentaje de progreso y lista de archivos descargados.
- **Descargas Directas:** Integración con intents de Android 11+ para guardar archivos individuales o paquetes ZIP directamente en la carpeta `Descargas/` del teléfono.

---

## 🏗️ 3. Diagrama de Arquitectura Técnica

```mermaid
graph TD
    subgraph "Clientes / Frontend"
        MobileApp["📱 Flutter Android App (Release APK)"]
        WebGUI["🌐 Modern Cyber Web UI (Tailwind + JS)"]
    end

    subgraph "Perímetro de Red & Seguridad"
        CFTunnel["☁️ Cloudflare Zero Trust Tunnel (WSS / HTTPS)"]
    end

    subgraph "Docker Stack (Oracle VPS - Ubuntu 24.04)"
        FastAPIServer["⚡ FastAPI REST & WebSocket Server (tmh_api:8000)"]
        AsyncWorkers["🔄 Async Background Workers (Telethon MTProto)"]
        PostgresDB["🗄️ PostgreSQL 16 (tmh_postgres:5432)"]
        RedisCache["⚡ Redis 7 (tmh_redis:6379)"]
        DiskStorage["📁 Persistent Storage (/app/downloads_storage)"]
    end

    subgraph "Servicios Cloud Externos"
        TelegramCloud["✈️ Telegram Cloud MTProto Servers"]
        GoogleDrive["☁️ Google Drive API v3 (OAuth2)"]
    end

    MobileApp -->|WSS / HTTPS| CFTunnel
    WebGUI -->|WSS / HTTPS| CFTunnel
    CFTunnel --> FastAPIServer

    FastAPIServer --> PostgresDB
    FastAPIServer --> RedisCache
    FastAPIServer --> AsyncWorkers

    AsyncWorkers --> TelegramCloud
    AsyncWorkers --> GoogleDrive
    AsyncWorkers --> DiskStorage
    AsyncWorkers --> PostgresDB
```

---

## 🔑 4. Credenciales y Prerrequisitos Necesarios

Para operar el sistema completo en local o en servidor, se requieren las siguientes credenciales:

### 1. Credenciales de la API de Telegram (Obligatorio)
1. Inicia sesión con tu número en [https://my.telegram.org](https://my.telegram.org).
2. Ve a la sección **API development tools**.
3. Crea una aplicación (ej: `TelegramMediaHub`) y obtén:
   - `TELEGRAM_API_ID` (ej: `12345678`)
   - `TELEGRAM_API_HASH` (ej: `abcdef0123456789abcdef0123456789`)

### 2. Claves de Seguridad y Cifrado (Obligatorio)
- `SECRET_KEY`: Cadena aleatoria de 32+ caracteres para firmar los tokens JWT.
- `CRYPTO_SECRET_KEY`: Llave de 32 bytes (AES-256) para cifrar las cadenas de sesión de Telegram en base de datos.

### 3. Credenciales de Google Drive (Opcional - para subidas a la nube)
1. En [Google Cloud Console](https://console.cloud.google.com), habilita la **Google Drive API v3**.
2. Crea credenciales de **ID de cliente OAuth 2.0** (Tipo: Aplicación Web).
3. Añade la URI de redirección: `https://tu-dominio.com/api/v1/drive/callback`.
4. Obtén `GDRIVE_CLIENT_ID` y `GDRIVE_CLIENT_SECRET`.

---

## ⚙️ 5. Configuración de Variables de Entorno (`.env`)

Crea un archivo `.env` en la raíz del proyecto basándote en la siguiente plantilla técnica:

```ini
# =================================================================
# TELEGRAM MEDIA HUB v3.0 — CONFIGURACIÓN DE ENTORNO
# =================================================================

# --- PROYECTO & ENTORNO ---
PROJECT_NAME="Telegram Media Hub v3.0"
ENVIRONMENT="production"
PORT=8000

# --- BASE DE DATOS (PostgreSQL 16) ---
POSTGRES_USER=tmh_user
POSTGRES_PASSWORD=tu_password_super_seguro_postgres_2026
POSTGRES_DB=tmh_db
DATABASE_URL=postgresql+asyncpg://tmh_user:tu_password_super_seguro_postgres_2026@tmh_postgres:5432/tmh_db

# --- CACHE & TELEMETRÍA (Redis 7) ---
REDIS_URL=redis://tmh_redis:6379/0

# --- TELEGRAM API CREDENTIALS (my.telegram.org) ---
TELEGRAM_API_ID=12345678
TELEGRAM_API_HASH=abcdef0123456789abcdef0123456789

# --- SEGURIDAD & JWT ---
SECRET_KEY=tu_clave_secreta_jwt_para_firmar_tokens_2026
ALGORITHM=HS256
ACCESS_TOKEN_EXPIRE_MINUTES=43200 # 30 días de persistencia

# --- CIFRADO DE SESIONES (AES-256) ---
CRYPTO_SECRET_KEY=clave_de_32_caracteres_aes_256!!

# --- GOOGLE DRIVE OAUTH2 (Opcional) ---
GDRIVE_CLIENT_ID=
GDRIVE_CLIENT_SECRET=
GDRIVE_REDIRECT_URI=https://tu-dominio.com/api/v1/drive/callback

# --- ALMACENAMIENTO ---
STORAGE_DIR=/app/downloads_storage
TEMP_DIR=/app/temp_storage
MAX_CONCURRENT_DOWNLOADS=15
```

---

## 🚀 6. Guía de Instalación y Puesta en Marcha

### Opción A: Despliegue en Servidor Cloud con Docker Compose (Recomendado)

1. **Clonar el Repositorio:**
   ```bash
   git clone https://github.com/lukgtz/Telegram-Media-Hub-v3.0-Cloud-Mobile.git
   cd Telegram-Media-Hub-v3.0-Cloud-Mobile
   ```

2. **Crear el archivo `.env`:**
   ```bash
   cp .env.example .env
   nano .env # Completar las credenciales
   ```

3. **Construir y Levantar los Contenedores:**
   ```bash
   docker compose up -d --build
   ```

4. **Verificar el Estado del Sistema:**
   ```bash
   docker compose ps
   curl http://localhost:8000/health
   # Respuesta: {"status":"healthy","service":"Telegram Media Hub v3.0"}
   ```

---

### Opción B: Exposición Pública Segura con Cloudflare Tunnel

Para acceder desde tu celular o desde cualquier parte del mundo con HTTPS gratuito y sin abrir puertos en tu router/VPS:

```bash
# Instalar cloudflared
curl -L --output cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
sudo dpkg -i cloudflared.deb

# Iniciar túnel efímero rápido
cloudflared tunnel --url http://localhost:8000
```
*Copia la URL generada (ej: `https://xxxx.trycloudflare.com`) y utilízala en tu navegador o configúrala en la app móvil.*

---

## 📱 7. Compilación y Configuración de la App Móvil (Flutter)

### Prerrequisitos
- Flutter SDK 3.22+ y Dart 3.4+
- Android Studio / Android SDK (API 34)

### Compilar el APK Release para Android

1. **Entrar a la carpeta de la App:**
   ```bash
   cd flutter_app
   ```

2. **Descargar Dependencias:**
   ```bash
   flutter pub get
   ```

3. **Compilar el APK Optimizado:**
   ```bash
   flutter build apk --release
   ```

4. **Ubicación del Archivo Compilado:**
   ```text
   flutter_app/build/app/outputs/flutter-apk/app-release.apk
   ```

> **Descarga Directa del APK:** El backend expone automáticamente el endpoint `GET /download-apk` para que los usuarios puedan descargar el instalador directamente desde su navegador.

---

## 📡 8. Resumen de Endpoints Principales de la API

| Método | Endpoint | Descripción |
| :--- | :--- | :--- |
| `POST` | `/api/v1/auth/login` | Autenticación con email/password (Retorna JWT). |
| `POST` | `/api/v1/auth/quick-login` | Autenticación táctica mediante PIN de 6 caracteres. |
| `POST` | `/api/v1/telegram/login/send-code` | Solicita código de inicio de sesión MTProto. |
| `POST` | `/api/v1/telegram/login/complete` | Valida código MTProto y contraseña 2FA. |
| `POST` | `/api/v1/jobs/` | Crea una nueva tarea de descarga concurrente. |
| `GET` | `/api/v1/jobs/{id}/download-zip` | Descarga el archivo ZIP compilado de una tarea. |
| `GET` | `/api/v1/osint/search-global` | Búsqueda global 360° indexada con filtros. |
| `POST` | `/api/v1/osint/inspect` | Inspección técnica forense de un canal o grupo. |
| `POST` | `/api/v1/osint/pre-analyze-topics` | Enumeración y conteo de medios por Topics. |
| `WS` | `/ws/progress/{user_id}` | Socket de telemetría en tiempo real (MB/s, ETA, %). |

---

## 🛡️ 9. Modelo de Seguridad y Buenas Prácticas

1. **Aislamiento de Sesiones MTProto:** Cada usuario posee su propia sesión encriptada con AES-256 en la base de datos PostgreSQL, sin archivos `.session` compartidos ni bloqueos de concurrencia.
2. **Protección contra Inyecciones y Fugas:** Nombres de archivos sanitizados con expresiones regulares para evitar ataques de *Directory Traversal* (`../`).
3. **Control de Flujo de Telegram:** Semáforos asíncronos ajustables (1 a 20 hilos) con backoff exponencial automático ante eventos `FloodWaitError`.
4. **Almacenamiento Efímero Seguro:** Los paquetes `.zip` temporales se generan bajo demanda y se limpian automáticamente tras su transmisión.

---

## 📚 10. Índice de Documentación Técnica Formal

Para consultar la arquitectura interna y registros técnicos completos:

* 📄 **[`agent.md`](agent.md):** Rol del agente de IA, stack técnico y reglas inmutables de desarrollo.
* 📄 **[`specs/01-requerimientos.md`](specs/01-requerimientos.md):** Especificación de requerimientos funcionales y límites de alcance.
* 📄 **[`specs/02-flujo-usuario.md`](specs/02-flujo-usuario.md):** Diagramas de secuencia y recorrido del usuario.
* 📄 **[`specs/03-arquitectura.md`](specs/03-arquitectura.md):** Topología de servicios Docker y capas de almacenamiento.
* 📄 **[`specs/04-modelo-datos.md`](specs/04-modelo-datos.md):** Diagrama ERD y contratos de datos JSON.
* 📄 **[`docs/DECISIONS.md`](docs/DECISIONS.md):** Registro de Decisiones de Arquitectura (ADR-001 a ADR-007).
* 📄 **[`docs/STATE.md`](docs/STATE.md):** Estado operativo actual y verificación de hitos.

---

## 👨‍💻 Autor & Créditos

**Luciano Gutiérrez (`@lukgtz`)**  
📍 *Salta, Argentina*  
GitHub: [@lukgtz](https://github.com/lukgtz)

---

<div align="center">
  <sub>Telegram Media Hub v3.0 • Desarrollado para gestión forense de multimedia, auditorías de seguridad y análisis OSINT.</sub>
</div>
