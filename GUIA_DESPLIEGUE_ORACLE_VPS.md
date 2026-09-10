# ☁️ Guía Paso a Paso: Despliegue en Oracle Cloud Free Tier (VPS 24/7 Gratis)

> **TELEGRAM MEDIA HUB 360°**  
> **Creado por:** `@lukgtz` (Luciano Gutiérrez - Salta, Argentina)  
> **Servidor:** Ubuntu Linux en Oracle Cloud (4 vCPUs, 24 GB RAM, 200 GB SSD) - **100% Gratis de por vida**

---

## 🧭 Paso 1: Crear tu Cuenta Gratuita en Oracle Cloud
1. Entra en el sitio oficial: 👉 **[https://www.oracle.com/cloud/free/](https://www.oracle.com/cloud/free/)**
2. Haz clic en el botón **"Start for free" (Empieza gratis)**.
3. Completa tu país (Argentina), nombre y correo.
4. Selecciona tu *Home Region* (por ejemplo: `Chile (Santiago)`, `Brazil (Sao Paulo)` o `US East (Ashburn)`).
5. Te pedirá validar con una tarjeta de débito/crédito (te cobran ~$1 USD temporal para validar que eres humano y te lo devuelven al instante; **nunca te cobrarán nada** porque usarás solo el plan *Always Free*).

---

## 🖥️ Paso 2: Crear tu Servidor Virtual (Instancia VPS)
1. En el panel principal de Oracle Cloud, ve al menú:  
   **Compute** > **Instances** > **Create instance** (Crear instancia).
2. **Nombre:** `telegram-media-hub`
3. **Image and shape (Imagen y Forma):**
   - **Image:** Cambia a **Ubuntu 22.04 LTS** o **Ubuntu 24.04 LTS**.
   - **Shape:** Selecciona **Ampere (ARM)** -> `VM.Standard.A1.Flex`.
   - Asigna **2 a 4 OCPUs** y **12 a 24 GB de RAM** *(Always Free Eligible)*.
4. **Primary VNIC / Red:** Deja la configuración por defecto y marca **"Assign a public IPv4 address"** (Asignar IP pública).
5. **Add SSH keys (Claves SSH):**
   - Selecciona **"Generate SSH key pair"** y descarga el archivo de clave privada (`.key` / `.pem`).
6. Haz clic en **Create** (Crear). En 1 o 2 minutos tu servidor estará en estado **RUNNING (Verde)** y te mostrará su **IP Pública**.

---

## 🔓 Paso 3: Abrir Puertos en la Red de Oracle (Security Lists)
1. En los detalles de tu instancia, haz clic en tu **Subnet** (Subred).
2. Haz clic en **Default Security List for...**.
3. Haz clic en **Add Ingress Rules** (Agregar regla de entrada):
   - **Source CIDR:** `0.0.0.0/0`
   - **IP Protocol:** `TCP`
   - **Destination Port Range:** `80, 443, 8000`
   - **Description:** `Telegram Media Hub Web & API`
4. Haz clic en **Add Ingress Rules**.

---

## 🚀 Paso 4: Conectar al Servidor y Desplegar en 1 Minuto

1. Abre tu terminal (PowerShell, CMD o PuTTY en Windows) y conéctate por SSH:
   ```bash
   ssh -i ruta_a_tu_clave.pem ubuntu@TU_IP_PUBLICA
   ```
2. Clona o sube la carpeta del proyecto a tu VPS:
   ```bash
   git clone https://github.com/TU_USUARIO/BOT-Telegram-OSINT-Matrix-Turbo-Downloader-v2.0.git hub
   cd hub/telegram_media_hub_v3
   ```
3. Dale permisos de ejecución y corre el instalador automático:
   ```bash
   chmod +x deploy_oracle_vps.sh
   ./deploy_oracle_vps.sh
   ```

---

## 🎉 ¡Listo! Tu plataforma estará 100% online
* **Web Pública:** `http://TU_IP_PUBLICA:8000`
* **App Móvil Android:** En la app ingresas `http://TU_IP_PUBLICA:8000/api/v1`
* **Descarga del APK:** `http://TU_IP_PUBLICA:8000/download-apk`

Tu servidor trabajará las 24 horas del día sin consumir recursos de tu computadora.
