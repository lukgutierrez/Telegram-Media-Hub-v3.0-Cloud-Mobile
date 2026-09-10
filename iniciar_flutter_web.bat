@echo off
title TELEGRAM MEDIA HUB 360° - FLUTTER CLIENT (@lukgtz)
color 0B
chcp 65001 > nul
cls
echo ========================================================
echo   TELEGRAM MEDIA HUB 360° - FLUTTER MULTIPLATAFORMA
echo   Creador: @lukgtz (Luciano Gutierrez - Salta, Arg)
echo ========================================================
echo.
echo [1/2] Iniciando cliente Flutter en el Navegador...
echo.
cd flutter_app
flutter run -d edge --web-port=8080
pause
