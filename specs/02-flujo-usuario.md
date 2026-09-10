# 🧭 02 — Flujo de Usuario (User Journey)

> **Proyecto:** Telegram Media Hub v3.0 & OSINT Matrix  
> **Versión:** 3.0.0

---

## 🌊 Flujo Integral Paso a Paso

```mermaid
sequenceDiagram
    autonumber
    actor User as 👤 Operador
    participant App as 📱 App Móvil / 🌐 Web GUI
    participant API as ⚡ FastAPI Backend
    participant TG as ✈️ Telegram MTProto
    participant DB as 🗄️ PostgreSQL / Cache
    participant Drive as ☁️ Google Drive

    %% 1. Autenticación
    User->>App: 1. Inicia sesión (Credenciales o QR/PIN)
    App->>API: POST /api/v1/auth/login o /quick-login
    API->>DB: Valida usuario y emite JWT Token
    API-->>App: Retorna access_token + Perfil

    %% 2. Conexión de Telegram
    opt Conexión inicial de Telegram
        User->>App: Ingresa número de teléfono
        App->>API: POST /api/v1/telegram/login/send-code
        API->>TG: Solicita código de acceso MTProto
        TG-->>User: Envía código por Telegram oficial
        User->>App: Ingresa código + contraseña 2FA
        App->>API: POST /api/v1/telegram/login/complete
        API->>DB: Guarda StringSession cifrada con AES-256
    end

    %% 3. Búsqueda y Selección
    alt Búsqueda 360°
        User->>App: Busca término (ej: "goroso") + Filtro (Videos)
        App->>API: GET /api/v1/osint/search-global?q=goroso
        API->>TG: Búsqueda rápida indexada + despaquetado de álbumes
        API-->>App: Retorna lista de archivos y metadatos
        User->>App: Selecciona archivos con checkboxes
    else Turbo Descarga por Canal / Foro
        User->>App: Ingresa URL / ID (-100...) o selecciona de OSINT
        App->>API: POST /api/v1/osint/inspect o pre-analyze-topics
        API-->>App: Retorna desglose de fotos/videos/docs o lista de Topics
        User->>App: Elige concurrencia y destino (ZIP o Drive)
    end

    %% 4. Creación y Ejecución de Tarea
    User->>App: Presiona "⚡ INICIAR TURBO DESCARGA"
    App->>API: POST /api/v1/jobs/
    API->>DB: Registra Job (PENDING)
    API-->>App: Retorna job_id y redirige a pestaña "Tareas"

    %% 5. Monitoreo en Tiempo Real
    loop Telemetría en Vivo
        API->>TG: Descarga de chunks de medios concurrentes
        API->>DB: Deduplica con SHA-256 en memoria
        API-->>App: Broadcast WebSocket: {speed_mbs, progress_percent, eta_seconds}
        App-->>User: Actualiza barra de progreso, MB/s y archivos en vivo
    end

    %% 6. Entrega de Archivos
    alt Destino: Descarga Directa
        API->>API: Empaqueta en ZIP organizado por Topics/Tipos
        User->>App: Presiona "Descargar Todo en ZIP 📦" o archivo individual
        App->>API: GET /api/v1/jobs/{id}/download-zip?token=...
        API-->>User: Descarga automática en carpeta "Descargas" del celular/PC
    else Destino: Google Drive
        API->>Drive: Sube en chunks de 8MB vía Desktop Sync o API v3
        Drive-->>User: Archivos disponibles en la nube de Google Drive
    end
```

---

## 📱 Descripción de Pantallas Principales

1. **Pantalla de Autenticación & Conexión:**
   - Permite login clásico (Email/Contraseña), registro de nuevas cuentas, o escaneo de Código QR / PIN táctico generado en la Web.
   - Asistente de vinculación de cuenta de Telegram (Teléfono -> Código -> 2FA Password).

2. **Pestaña 1 — 🔍 BÚSQUEDA 360°:**
   - Barra de búsqueda global con selector de filtros (Todos, Videos, Fotos, Documentos).
   - Tarjetas interactivas con nombre, tamaño en MB, chat de origen, tipo de archivo y badge de procedencia (Directo, Álbum, Topic).
   - Botón de descarga individual directa al teléfono o descarga masiva seleccionada en ZIP.

3. **Pestaña 2 — ⚡ TURBO DESCARGAS:**
   - Entrada para URLs públicas, privadas (`t.me/c/...`), IDs numéricos (`-100...`) o nombres de usuario.
   - Selector de concurrencia deslizante (1 a 20 hilos simultáneos).
   - Selector de destino (Descarga Directa en Servidor/ZIP o Google Drive).
   - Botón de pre-análisis de temas de foro con checkboxes interactivos.

4. **Pestaña 3 — ⏱️ TAREAS & TELEMETRÍA EN VIVO:**
   - Tarjeta de telemetría en tiempo real: Velocidad en MB/s, porcentaje de progreso, ETA en minutos, conteo de deduplicación SHA-256.
   - Botones de control operativo: **Pausar**, **Reanudar**, **Cancelar** y **Descargar Todo en ZIP 📦**.
   - Lista interactiva de archivos procesados con estado, hash SHA-256 y botón de descarga individual.

5. **Pestaña 4 — 🕵️ OSINT RECON MATRIX:**
   - Lista automática de canales, grupos y foros del usuario con sus IDs formateados (`-100...`).
   - Botones rápidos de 1-tap para copiar ID y enlaces al portapapeles.
   - Botón **"Inspeccionar"** que despliega el panel táctico inferior con conteo de fotos/videos/docs, desglose de topics y botón de descarga directa.

6. **Pestaña 5 — ⚙️ AJUSTES & CONEXIONES:**
   - Estado de conexión con Telegram (Conectado / Desconectado).
   - Estado de vinculación con Google Drive.
   - Métricas globales de ahorro de almacenamiento por deduplicación SHA-256.
   - Generador de Código QR y PIN para vincular la App Móvil.
