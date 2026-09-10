#!/bin/bash
# ==============================================================================
# TELEGRAM MEDIA HUB 360° - SCRIPT DE DESPLIEGUE AUTOMÁTICO EN ORACLE CLOUD VPS
# Autor: @lukgtz (Luciano Gutierrez - Salta, Argentina)
# ==============================================================================

set -e

echo "========================================================"
echo "  INICIANDO DESPLIEGUE DE TELEGRAM MEDIA HUB 360°"
echo "  Servidor: Ubuntu / Debian en Oracle Cloud VPS"
echo "========================================================"
echo ""

# 1. Actualizar repositorios
echo "[1/5] Actualizando paquetes del sistema..."
sudo apt-get update && sudo apt-get upgrade -y
sudo apt-get install -y curl wget git ufw apt-transport-https ca-certificates gnupg lsb-release

# 2. Instalar Docker si no está instalado
if ! command -v docker &> /dev/null; then
    echo "[2/5] Instalando Docker Engine oficial..."
    curl -fsSL https://get.docker.com | sh
    sudo usermod -aG docker $USER
fi

# 3. Configurar Firewall (Abrir puertos 80, 443, 8000)
echo "[3/5] Configurando Firewall UFW e IPTables..."
sudo ufw allow 22/tcp || true
sudo ufw allow 80/tcp || true
sudo ufw allow 443/tcp || true
sudo ufw allow 8000/tcp || true
sudo ufw --force enable || true

# En Oracle Cloud, liberar iptables para permitir trafico externo
sudo iptables -I INPUT 6 -m state --state NEW -p tcp --dport 80 -j ACCEPT || true
sudo iptables -I INPUT 6 -m state --state NEW -p tcp --dport 443 -j ACCEPT || true
sudo iptables -I INPUT 6 -m state --state NEW -p tcp --dport 8000 -j ACCEPT || true

# 4. Crear tarea programada para limpiar archivos temporales de mas de 24h
echo "[4/5] Configurando cron para limpieza automatica de almacenamiento..."
CRON_JOB="0 3 * * * find $(pwd)/downloads $(pwd)/temp_storage -type f -mtime +1 -delete"
(crontab -l 2>/dev/null | grep -v "temp_storage" ; echo "$CRON_JOB") | crontab -

# 5. Iniciar Contenedores con Docker Compose
echo "[5/5] Compilando e iniciando Telegram Media Hub 360°..."
docker compose down || true
docker compose up -d --build

echo ""
echo "========================================================"
echo "  ¡DESPLIEGUE COMPLETADO CON ÉXITO EN TU VPS!"
echo "  Accede desde tu navegador en: http://TU_IP_PUBLICA:8000"
echo "========================================================"
