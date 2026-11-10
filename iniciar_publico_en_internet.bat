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

echo [1/3] Iniciando Servidor Backend FastAPI Turbo en segundo plano...
taskkill /F /IM uvicorn.exe >nul 2>&1
taskkill /F /IM cloudflared.exe >nul 2>&1

start "" /B python -m uvicorn app.main:app --host 0.0.0.0 --port 8000
timeout /t 3 > nul

cd /d "%~dp0"

echo.
echo [2/3] Generando Tunel Seguro HTTPS con Cloudflare...
echo.
echo =========================================================================
echo   ABRIENDO TUNEL PUBLICO EN INTERNET...
echo   (Puedes abrir este enlace en cualquier celular, PC o tablet)
echo =========================================================================
echo.

if exist "%~dp0cloudflared.exe" (
    "%~dp0cloudflared.exe" tunnel --url http://127.0.0.1:8000
) else if exist "%~dp0..\cloudflared.exe" (
    "%~dp0..\cloudflared.exe" tunnel --url http://127.0.0.1:8000
) else (
    cloudflared tunnel --url http://127.0.0.1:8000
)

pause
