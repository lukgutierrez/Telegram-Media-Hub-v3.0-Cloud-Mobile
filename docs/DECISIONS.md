# 📜 Registro de Decisiones de Arquitectura (ADR)

> **Proyecto:** Telegram Media Hub v3.0 & OSINT Matrix  
> **Reglas:** Nunca se borra una entrada; si cambia, se marca como "Reemplazada por ADR-00Y". Nunca se mezcla con TODOs.

---

## ADR-001 — Desacoplamiento de Sesiones SQLite en Memoria (`MemorySession`)
**Fecha:** 2026-09-08  
**Estado:** Vigente  
**Decisión:** Utilizar `StringSession` y `MemorySession` de Telethon para las operaciones asíncronas en Streamlit y FastAPI, cargando la sesión cifrada desde la base de datos solo al inicializar.  
**Motivo:** Telethon por defecto bloquea el archivo `.session` en disco mediante SQLite. Al ejecutar múltiples hilos o peticiones concurrentes, SQLite lanzaba `sqlite3.OperationalError: database is locked`.  
**Alternativas descartadas:** Compartir un único archivo `.session` en disco entre FastAPI y workers (generaba corrupción y bloqueos constantes).

---

## ADR-002 — Bucle de Eventos Asíncrono en Hilo Dedicado
**Fecha:** 2026-09-08  
**Estado:** Vigente  
**Decisión:** En entornos con ciclo de vida dinámico (Streamlit GUI), ejecutar un loop singleton de `asyncio` dentro de un `threading.Thread(daemon=True)` y despachar corrutinas con `asyncio.run_coroutine_threadsafe()`.  
**Motivo:** Streamlit destruye y crea loops de asyncio en cada re-renderizado, provocando `RuntimeError: Event loop is closed`.  
**Alternativas descartadas:** Crear `asyncio.run()` en cada botón de la UI (congelaba la interfaz y desconectaba los sockets de Telegram).

---

## ADR-003 — Deduplicación Doble-Capa (Identificador + Hash SHA-256)
**Fecha:** 2026-09-09  
**Estado:** Vigente  
**Decisión:** Implementar dos capas de deduplicación: Capa 1 por nombre determinista en disco `YYYYMMDD_HHMMSS_{msg_id}_{filename}` (O(1)), y Capa 2 criptográfica mediante hash SHA-256 en bloques de 64KB registrado en base de datos.  
**Motivo:** Evitar descargar archivos que ya existen o que fueron subidos con distintos nombres en diferentes canales, reduciendo el consumo de ancho de banda y almacenamiento en más de un 40%.  
**Alternativas descartadas:** Comparar únicamente por nombre de archivo (vulnerable a nombres genéricos como `video.mp4` o `photo.jpg`).

---

## ADR-004 — Sincronización Google Drive Híbrida (Desktop Sync + API v3)
**Fecha:** 2026-09-09  
**Estado:** Vigente  
**Decisión:** En entornos locales con escritorio se utiliza el daemon nativo `Google Drive para Escritorio` copiando por bloques de 8MB a la unidad virtual `G:\Mi unidad`. En servidores headless (Oracle VPS) se utiliza el cliente oficial Google Drive API v3 con subidas reanudables (`MediaFileUpload`) en chunks de 64MB/128MB.  
**Motivo:** Minimizar el uso de memoria RAM a cero en subidas de más de 20GB en el entorno local, manteniendo soporte completo sin interfaz gráfica en el VPS en la nube.  
**Alternativas descartadas:** Cargar archivos enteros en memoria RAM antes de enviarlos a la API (provocaba Out Of Memory en archivos grandes).

---

## ADR-005 — Despliegue en Oracle Cloud Always Free con Cloudflare Tunnel
**Fecha:** 2026-09-10  
**Estado:** Vigente  
**Decisión:** Alojar la plataforma en una instancia Ubuntu 24.04 dentro del plan Always Free de Oracle Cloud en la región de Santiago de Chile, exponiendo el servicio mediante Cloudflare Zero Trust Tunnel (`cloudflared`).  
**Motivo:** Proporciona conectividad HTTPS/WSS segura sin necesidad de abrir puertos en el firewall de Oracle ni pagar por certificados SSL o IPs públicas dedicadas.  
**Alternativas descartadas:** Nginx con Certbot y apertura de puertos manual (más complejo y expone la IP directa del servidor a ataques DDoS).

---

## ADR-006 — Vinculación Rápida Web-Móvil mediante QR y PIN
**Fecha:** 2026-09-10  
**Estado:** Vigente  
**Decisión:** Implementar un sistema de tokens temporales de un solo uso vinculados al ID de usuario, permitiendo a la app de Flutter iniciar sesión automáticamente al escanear un Código QR o ingresar un PIN de 6 caracteres (ej: `TMH-9172`).  
**Motivo:** Evitar la fricción de escribir correos y contraseñas complejas en pantallas táctiles de celulares y asegurar que la app móvil comparta exactamente la misma sesión de Telegram.  
**Alternativas descartadas:** Envío manual de tokens JWT por mensaje de texto.

---

## ADR-007 — Consultas de Intent en AndroidManifest (`<queries>`) para Descarga Directa
**Fecha:** 2026-09-10  
**Estado:** Vigente  
**Decisión:** Incluir declaraciones de `<queries>` para esquemas `https` y `http` en `AndroidManifest.xml`, y utilizar lanzador con captura de excepciones (`try/catch`) con fallback a `LaunchMode.platformDefault`.  
**Motivo:** Android 11+ (API level 30+) oculta las aplicaciones del sistema a las apps de Flutter a menos que estén declaradas en `<queries>`, lo que causaba que `canLaunchUrl()` devolviera `false` y bloqueara la descarga de archivos y ZIPs al celular.  
**Alternativas descartadas:** Incrustar un navegador web dentro de la app (InAppWebView), ya que no permite gestionar las descargas directamente con el gestor nativo de Android.
