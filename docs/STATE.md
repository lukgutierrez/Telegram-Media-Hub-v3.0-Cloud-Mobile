# 📊 Estado del Proyecto — Telegram Media Hub v3.0

> **Última actualización:** 2026-09-10T12:00:00-03:00  
> **Versión Actual:** 3.0.0 Release  
> **Responsable:** Luciano Gutiérrez (`@lukgtz`)

---

## 🚀 Qué se hizo en la última sesión
- **Búsqueda Global 360° Optimizada:** Indexación directa en Telegram para búsquedas instantáneas (< 1.5s) con despaquetado de álbumes multimedia.
- **Módulo OSINT Interactivo en Móvil:** Implementado modal táctico deslizable (`BottomSheet`) con desglose en vivo de fotos/videos/docs y explorador de Topics de foros con checkboxes interactivos.
- **Corrección Integral de Descargas Móviles (Android):**
  - Solucionado el bloqueo de `url_launcher` en Android 11+ agregando `<queries>` para esquemas `https`/`http` en `AndroidManifest.xml`.
  - Corregido el enrutamiento de endpoints de descarga directa y ZIP con el prefijo `/api/v1/jobs/.../download-zip`.
  - Agregado `didUpdateWidget` y auto-refresco en `JobsScreen` para sincronizar las tareas y archivos en vivo.
- **Despliegue en Servidor de Producción:**
  - Contenedores Docker `tmh_api`, `tmh_postgres` y `tmh_redis` corriendo de forma estable en Oracle VPS (Santiago).
  - Túnel Cloudflare Zero Trust operativo en `https://pdas-stats-orbit-forbes.trycloudflare.com`.
  - Compilado y publicado el APK Release de Android v3.0 listo para su descarga pública.

---

## ⏳ Qué quedó a medias (WIP)
- *Ninguna tarea bloqueada en este momento. Sistema en estado operativo estable.*

---

## 🎯 Qué sigue (Próximos pasos recomendados)
- Implementar notificaciones Push locales en Android cuando una descarga en segundo plano termine.
- Añadir reproductor de video / visor de fotos integrado en la aplicación móvil antes de descargar.
- Incorporar selector de rango de fechas para filtros avanzados en OSINT.

---

## 🚧 Bloqueos o dudas abiertas
- *Ninguno actualmente.*

---

## ✅ Verificación rápida
- [x] ¿Todos los servicios levantados y saludables en Oracle VPS? (Verificado con `/health`)
- [x] ¿App móvil compilada en Release y descargable? (Verificado en `/download-apk`)
- [x] ¿Búsqueda global y despaquetado de álbumes funcionando? (Probado con éxito)
- [x] ¿Descarga de paquetes ZIP en Android funcionando? (Verificado con código 200)
- [x] ¿Decisiones de arquitectura registradas en `docs/DECISIONS.md`? (ADR-001 a ADR-007)
