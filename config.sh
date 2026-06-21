#!/bin/bash
#=============================================================
# config.sh — Configuración compartida para todos los scripts
# Source este archivo al inicio de cada script:
#   source "$(dirname "$0")/config.sh"
#=============================================================

# ── Telegram ─────────────────────────────────────────────────
TELEGRAM_TOKEN="8289233106:AAFkzZnnrwHytGOLmV_MQKz02MW4QJUjeL4"
TELEGRAM_CHAT="-1004407895363"
TELEGRAM_URL="https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage"

# ── Directorio de logs ────────────────────────────────────────
LOG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/logs"
mkdir -p "$LOG_DIR"

# ── IP local (para mensajes informativos) ─────────────────────
IP_LOCAL=$(hostname -I 2>/dev/null | awk '{print $1}')

#──────────────────────────────────────────────────────────────
# enviar_alerta MSG
#   Envía un mensaje al bot de Telegram.
#──────────────────────────────────────────────────────────────
enviar_alerta() {
    local msg="$1"
    curl -s -X POST "$TELEGRAM_URL" \
        -d chat_id="$TELEGRAM_CHAT" \
        -d parse_mode="Markdown" \
        -d text="$msg" > /dev/null
}

#──────────────────────────────────────────────────────────────
# registrar_log ARCHIVO MENSAJE
#   Escribe una línea con timestamp en el archivo de log dado.
#──────────────────────────────────────────────────────────────
registrar_log() {
    local archivo="$1"
    local mensaje="$2"
    printf '[%s] %s\n' "$(date '+%F %T')" "$mensaje" >> "$archivo"
}
