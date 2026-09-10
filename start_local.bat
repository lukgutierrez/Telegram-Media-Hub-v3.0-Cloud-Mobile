@echo off
title TELEGRAM MEDIA HUB v3.0 - SERVER (@lukgtz)
color 0A
chcp 65001 > nul
cls
echo ========================================================
echo   TELEGRAM MEDIA HUB v3.0 - FASTAPI + WEB INTERFACE
echo   Creado por: @lukgtz (Luciano Gutierrez - Salta, Arg)
echo ========================================================
echo.
echo [1/3] Verificando dependencias...
cd backend
if not exist venv (
    echo Creando entorno virtual...
    python -m venv venv
)
call .\venv\Scripts\activate.bat
pip install -r requirements.txt
echo.
echo [2/3] Iniciando servidor FastAPI con WebSockets...
echo [3/3] Abre en tu navegador: http://localhost:8000
echo.
python -m uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
pause
