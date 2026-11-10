@echo off
title TELEGRAM MEDIA HUB 360 - ACCESO PUBLICO EN INTERNET (@lukgtz)
color 0A
chcp 65001 > nul
cls

echo =========================================================================
echo   TELEGRAM MEDIA HUB v3.0 - ACCESO GLOBAL EN INTERNET 24/7
echo   Creador: @lukgtz (Luciano Gutierrez)
echo =========================================================================
echo.

cd /d "%~dp0"

echo [1/3] Limpiando procesos previos...
taskkill /F /IM cloudflared.exe >nul 2>&1
taskkill /F /IM uvicorn.exe >nul 2>&1
timeout /t 1 > nul

if exist "tunnel.log" del "tunnel.log" >nul 2>&1

echo [2/3] Iniciando Servidor Backend FastAPI Turbo...
powershell -NoProfile -Command "Start-Process -FilePath 'python' -ArgumentList '-m uvicorn app.main:app --host 0.0.0.0 --port 8000' -WorkingDirectory '%~dp0backend' -WindowStyle Hidden"
timeout /t 3 > nul

echo [3/3] Conectando Tunel Seguro HTTPS con Cloudflare para tu celular...
powershell -NoProfile -Command "Start-Process -FilePath '%~dp0cloudflared.exe' -ArgumentList 'tunnel --no-autoupdate --logfile \"%~dp0tunnel.log\" --url http://127.0.0.1:8000' -WindowStyle Hidden"

echo Esperando asignacion de enlace seguro...
timeout /t 6 > nul

set "TUNNEL_URL="
for /f "delims=" %%i in ('python -c "import re; f=open(r'%~dp0tunnel.log', 'r', encoding='utf-8', errors='ignore').read(); m=re.findall(r'https://[a-zA-Z0-9-]+\.trycloudflare\.com', f); print(m[-1] if m else '')"') do (
    set "TUNNEL_URL=%%i"
)

cls
echo =========================================================================
echo   TELEGRAM MEDIA HUB v3.0 - ¡LISTO Y FUNCIONANDO!
echo   Creador: @lukgtz (Luciano Gutierrez)
echo =========================================================================
echo.
if defined TUNNEL_URL (
    echo   👉 TU ENLACE PARA ABRIR EN EL CELULAR:
    echo.
    echo      %TUNNEL_URL%
    echo.
    echo   (Abriendo el enlace en tu navegador automáticamente...)
    start "" "%TUNNEL_URL%"
) else (
    echo   👉 ENLACE EN TU COMPUTADORA:
    echo      http://localhost:8000
    start "" "http://localhost:8000"
)
echo =========================================================================
echo.
echo   * Los servidores estan corriendo en segundo plano sin molestar.
echo   * Presiona cualquier tecla para APAGAR el bot cuando termines.
echo.
pause > nul

echo.
echo Apagando bot y cerrando tunel...
taskkill /F /IM cloudflared.exe >nul 2>&1
taskkill /F /IM uvicorn.exe >nul 2>&1
echo Listo.
timeout /t 2 > nul
