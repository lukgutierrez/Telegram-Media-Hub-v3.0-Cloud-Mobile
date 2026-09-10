# 📋 01 — Requerimientos del Sistema

> **Proyecto:** Telegram Media Hub v3.0 & OSINT Matrix  
> **Versión:** 3.0.0  
> **Última Actualización:** 2026-09-10

---

## 🎯 1. Requerimientos Funcionales

- **RF-01: Búsqueda Global 360° en Telegram:**
  - Búsqueda directa por palabras clave en todos los canales, grupos, supergrupos y diálogos del usuario.
  - Filtros por tipo de archivo: Todos, Videos (`.mp4`, `.mkv`), Fotos (`.jpg`, `.png`), Documentos (`.pdf`, `.zip`, etc.).
  - Detección automática y despaquetado de álbumes multimedia (packs de fotos/videos agrupados con el mismo `grouped_id`).
  - Descarga directa individual al vuelo o empaquetado masivo en ZIP.

- **RF-02: Motor Turbo Downloader Concurrente:**
  - Descarga masiva con semáforos de concurrencia configurable (1 a 20 hilos).
  - Soporte para enlaces públicos (`t.me/...`), privados (`t.me/c/...`), IDs numéricos (`-100...`) y nombres de usuario (`@...`).
  - Pausa, reanudación y cancelación interactiva de descargas en curso.

- **RF-03: Extractor y Pre-Analizador de Temas / Foros (Topics):**
  - Enumeración completa de temas en supergrupos tipo Foro (`GetForumTopicsRequest`).
  - Pre-análisis con cálculo de cantidad de archivos, peso estimado y conteo por tema.
  - Selección interactiva mediante casillas de verificación (checkboxes) para descarga granular.

- **RF-04: Módulo de Inteligencia OSINT & Reconocimiento:**
  - Inspección técnica de canales y usuarios (`/info`): ID, título, estado de verificación, banderas de scam/fake/restringido.
  - Estadísticas de actividad: mensajes totales, desglose de multimedia, conteo de fotos, videos y documentos.
  - Análisis de horarios pico de publicación y búsqueda de palabras clave dentro de un canal.

- **RF-05: Motor Criptográfico de Deduplicación SHA-256:**
  - Cálculo de hash SHA-256 en bloques de 64KB para cada archivo procesado.
  - Detección instantánea de archivos repetidos para evitar consumo redundante de ancho de banda.
  - Registro de estadísticas de MB ahorrados y archivos únicos procesados.

- **RF-06: Sincronización en la Nube con Google Drive:**
  - Integración híbrida: Subida de alta velocidad vía Google Drive Desktop Daemon (bloques de 8MB) o cliente oficial Google Drive API v3 (flujo OAuth2).
  - Creación automática de estructura de carpetas por canal y por tema.

- **RF-07: Telemetría en Tiempo Real por WebSockets:**
  - Transmisión continua de velocidad instantánea (MB/s), porcentaje de progreso (%), tiempo estimado restante (ETA) y archivo actual.
  - Notificaciones en vivo sincronizadas entre el servidor, la Web y la App Móvil.

- **RF-08: Autenticación, Seguridad y Vinculación Rápida Web-Móvil:**
  - Registro e inicio de sesión con JWT y contraseñas hasheadas con Bcrypt.
  - Vinculación táctica de celular en 1 clic mediante Código QR y PIN de 6 caracteres.
  - Recuperación y reseteo de contraseñas.

---

## ⚡ 2. Requerimientos No Funcionales

- **RNF-01: Rendimiento & Eficiencia:**
  - Búsqueda global en Telegram con tiempo de respuesta inferior a 2 segundos.
  - Compatibilidad estricta con los límites Always Free de Oracle Cloud (RAM < 1GB por contenedor, CPU optimizada).
- **RNF-02: Seguridad & Cifrado:**
  - Cifrado simétrico AES-256 para todas las cadenas de sesión (`session_string`) y tokens de Google Drive en base de datos.
  - Protocolo HTTPS y WSS obligatorio mediante túnel seguro de Cloudflare Zero Trust.
- **RNF-03: Estabilidad & Concurrencia:**
  - Aislamiento de sesiones Telethon en memoria (`MemorySession`) para evitar bloqueos SQLite.
  - Loop de asyncio en hilo dedicado desacoplado del ciclo de vida de Streamlit / FastAPI.
- **RNF-04: Usabilidad & UI:**
  - Interfaz gráfica táctica Cyberpunk OLED (`#050811`, `#00F0FF`, `#00FF41`) con respuesta ágil en móviles y escritorio.
  - Paridad funcional 100% entre la aplicación Web y la aplicación móvil Android Flutter.

---

## 🚫 3. Explícitamente Fuera de Alcance (Out of Scope)

- **Edición o borrado masivo de mensajes** en canales o grupos ajenos.
- **Envío automatizado de spam**, mensajes promocionales o creación masiva de cuentas falsas.
- **Bypass forzado de canales con derechos de autor restringidos a nivel servidor de Telegram** (si Telegram bloquea a nivel de servidor la transferencia de bytes por DMCA o restricción geográfica).
- **Soporte para plataformas no-Telegram** (WhatsApp, Discord, etc. no forman parte de este sistema).
