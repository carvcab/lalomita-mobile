#!/bin/bash
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$DIR"

echo "=============================================="
echo "🚀 Iniciando Servidor SQL de Variedades La Lomita"
echo "=============================================="

# Launch python server in background
python3 server.py &
SERVER_PID=$!

# Wait a second for server to initialize
sleep 1.5

# Try opening in browser
if command -v xdg-open > /dev/null; then
    xdg-open "http://localhost:5000"
elif command -v google-chrome > /dev/null; then
    google-chrome "http://localhost:5000"
elif command -v firefox > /dev/null; then
    firefox "http://localhost:5000"
else
    echo "Servidor activo en: http://localhost:5000"
    echo "Por favor abre esa dirección en tu navegador."
fi

# Wait for server process
wait $SERVER_PID
