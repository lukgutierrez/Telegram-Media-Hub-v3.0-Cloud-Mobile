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

cd /d "%~dp0backend"

echo [1/3] Iniciando Servidor Backend FastAPI Turbo...
taskkill /F /IM uvicorn.exe >nul 2>&1
taskkill /F /IM cloudflared.exe >nul 2>&1
timeout /t 1 > nul

start "" /B python -m uvicorn app.main:app --host 0.0.0.0 --port 8000
timeout /t 3 > nul

cd /d "%~dp0"

echo.
echo [2/3] Generando Tunel Seguro HTTPS con Cloudflare...
echo.

if exist "tunnel.log" del "tunnel.log" >nul 2>&1

start "" /B "%~dp0cloudflared.exe" tunnel --edge-ip-version 4 --url http://127.0.0.1:8000 > "tunnel.log" 2>&1

echo Conectando con los servidores seguros de Cloudflare...
timeout /t 6 > nul

set "TUNNEL_URL="
for /f "tokens=*" %%a in ('powershell -NoProfile -Command "Get-Content '%~dp0tunnel.log' | Select-String -Pattern 'https://[a-zA-Z0-9-]+\.trycloudflare\.com' | ForEach-Object { $_.Matches.Value } | Select-Object -Last 1"') do (
    set "TUNNEL_URL=%%a"
)

cls
echo =========================================================================
echo   TELEGRAM MEDIA HUB v3.0 - LISTO Y ONLINE
echo   Creador: @lukgtz (Luciano Gutierrez)
echo =========================================================================
echo.
echo =========================================================================
if defined TUNNEL_URL (
    echo   TU ENLACE PARA EL CELULAR O CUALQUIER NAVEGADOR ES:
    echo.
    echo   ^>^>^> %TUNNEL_URL% ^<^<^<
    echo.
    echo   (Abriendo el enlace en tu navegador...)
    start "" "%TUNNEL_URL%"
) else (
    echo   TU ENLACE LOCAL:
    echo   ^>^>^> http://localhost:8000 ^<^<^<
    echo   (O en tu WiFi: http://192.168.25.63:8000)
    start "" "http://localhost:8000"
)
echo =========================================================================
echo.
echo   * Para cerrar el servidor cuando termines, simplemente presiona cualquier tecla.
echo.
pause > nul

taskkill /F /IM uvicorn.exe >nul 2>&1
taskkill /F /IM cloudflared.exe >nul 2>&1
