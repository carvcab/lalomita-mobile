@echo off
title Servidor de Variedades La Lomita
echo ==============================================
echo 🚀 Iniciando Servidor de Variedades La Lomita
echo ==============================================
echo.
echo Usando uv para iniciar el servidor python...
uv run --with pywebview server.py
if %errorlevel% neq 0 (
    echo.
    echo ❌ Hubo un error al iniciar el servidor.
    pause
)
