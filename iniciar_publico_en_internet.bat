@echo off
title TELEGRAM MEDIA HUB 360 - ACCESO PUBLICO EN INTERNET (@lukgtz)
color 0A
chcp 65001 > nul
cls

echo =========================================================================
echo   TELEGRAM MEDIA HUB v3.0 - ACCESO GLOBAL EN INTERNET 24/7
echo   Creador: @lukgtz (Luciano Gutierrez - Salta, Argentina)
echo =========================================================================
echo.
echo [1/3] Iniciando Servidor Backend FastAPI Turbo...
start /B python -m uvicorn app.main:app --host 0.0.0.0 --port 8000
timeout /t 3 > nul

echo.
echo [2/3] Generando Tunel Seguro HTTPS con Cloudflare...
echo.
echo =========================================================================
echo   ABRIENDO TUNEL PUBLICO EN INTERNET...
echo   (Puedes abrir este enlace en cualquier celular, PC o provincia)
echo =========================================================================
echo.
..\cloudflared.exe tunnel --url http://127.0.0.1:8000
pause
