#!/bin/bash
#=============================================================
# remoto.sh — Distribución y ejecución remota de scripts
#
# Uso:
#   ./remoto.sh <script_a_ejecutar.sh> [usuario_default]
#
# Lee los hosts de hosts.txt (formato: usuario@IP por línea)
#
# Ejemplo:
#   ./remoto.sh monitoreo.sh localhost 70 80
#   ./remoto.sh inventario.sh
#=============================================================

source "$(dirname "$0")/config.sh"

LOG="$LOG_DIR/remoto.log"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOSTS_FILE="$SCRIPT_DIR/hosts.txt"
REPORTES_DIR="$SCRIPT_DIR/reportes"

#──────────────────────────────────────────────────────────────
# Ayuda
#──────────────────────────────────────────────────────────────
ayuda() {
    echo "Uso: $0 <script.sh> [args_del_script...]"
    echo ""
    echo "  script.sh      → script local a copiar y ejecutar en cada host"
    echo "  args_del_script → argumentos que se pasan al script remoto"
    echo ""
    echo "Los hosts se leen de hosts.txt (formato: usuario@IP)"
    echo ""
    echo "Ejemplos:"
    echo "  $0 inventario.sh"
    echo "  $0 monitoreo.sh localhost 80 85"
    exit 0
}

#──────────────────────────────────────────────────────────────
# Validaciones iniciales
#──────────────────────────────────────────────────────────────
validar() {
    SCRIPT_LOCAL="$1"
    shift
    ARGS_REMOTOS=("$@")

    [[ -z "$SCRIPT_LOCAL" ]] && { echo " Debes especificar el script a ejecutar."; ayuda; }
    [[ ! -f "$SCRIPT_LOCAL" ]] && { echo " No se encontró el script: '$SCRIPT_LOCAL'"; exit 1; }
    [[ ! -f "$HOSTS_FILE"  ]] && { echo " No se encontró hosts.txt en $SCRIPT_DIR"; exit 1; }

    mapfile -t HOSTS < <(grep -v '^#' "$HOSTS_FILE" | grep -v '^[[:space:]]*$')

    if [[ ${#HOSTS[@]} -eq 0 ]]; then
        echo " hosts.txt está vacío o solo tiene comentarios."
        exit 1
    fi

    mkdir -p "$REPORTES_DIR"
}

#──────────────────────────────────────────────────────────────
# Probar conectividad
#──────────────────────────────────────────────────────────────
probar_ping() {
    local host_ip="${1##*@}"
    ping -c1 -W2 "$host_ip" &>/dev/null
}

#──────────────────────────────────────────────────────────────
# Copiar script al host remoto
#──────────────────────────────────────────────────────────────
copiar_script() {
    local destino="$1"
    local script_remoto="$2"
    scp -o ConnectTimeout=10 -q "$SCRIPT_LOCAL" "$destino:$script_remoto" 2>/dev/null
}

#──────────────────────────────────────────────────────────────
# Ejecutar script en host remoto y capturar salida
#──────────────────────────────────────────────────────────────
ejecutar_remoto() {
    local destino="$1"
    local script_remoto="$2"
    local args="${ARGS_REMOTOS[*]}"
    ssh -o ConnectTimeout=10 "$destino" "bash $script_remoto $args; rm -f $script_remoto" 2>&1
}

#──────────────────────────────────────────────────────────────
# Generar reporte individual
#──────────────────────────────────────────────────────────────
guardar_reporte() {
    local host_ip="$1"
    local salida="$2"
    local timestamp
    timestamp=$(date '+%Y%m%d_%H%M%S')

    local archivo_reporte="$REPORTES_DIR/reporte_${host_ip//@/_}_${timestamp}.log"

    {
        echo "=============================================="
        echo " REPORTE DE EJECUCIÓN REMOTA"
        echo "=============================================="
        echo " Host     : $host_ip"
        echo " Script   : $(basename "$SCRIPT_LOCAL")"
        echo " Args     : ${ARGS_REMOTOS[*]:-ninguno}"
        echo " Timestamp: $(date '+%F %T')"
        echo "──────────────────────────────────────────────"
        echo "$salida"
        echo "=============================================="
    } > "$archivo_reporte"

    echo "$archivo_reporte"
}

#──────────────────────────────────────────────────────────────
# Notificar resultado en Telegram
#──────────────────────────────────────────────────────────────
notificar_telegram() {
    local host_ip="$1"
    local estado="$2"   # OK o ERROR
    local resumen="$3"

    local icono="✅"
    [[ "$estado" == "ERROR" ]] && icono="❌"

    # Truncar resumen a 800 chars para no exceder límite de Telegram
    local resumen_corto="${resumen:0:800}"
    [[ ${#resumen} -gt 800 ]] && resumen_corto+="..."

    enviar_alerta "$icono *Ejecución remota* en \`$host_ip\`
📜 Script: \`$(basename "$SCRIPT_LOCAL")\`
📋 Estado: *$estado*
\`\`\`
$resumen_corto
\`\`\`"
}

#──────────────────────────────────────────────────────────────
# Procesar un host
#──────────────────────────────────────────────────────────────
procesar_host() {
    local host="$1"
    local host_ip="${host##*@}"

    echo ""
    echo "══════════════════════════════════════"
    echo " Host: $host"
    echo "══════════════════════════════════════"

    # 1. Ping
    echo " Verificando conectividad..."
    if ! probar_ping "$host"; then
        echo " ❌ $host no responde al ping. Saltando."
        registrar_log "$LOG" "ERROR: $host no responde | Script: $(basename "$SCRIPT_LOCAL")"
        notificar_telegram "$host" "ERROR" "Host no responde al ping"
        HOSTS_FALLIDOS+=("$host")
        return
    fi
    echo " ✅ Conectividad OK"

    # 2. Copiar script
    local script_remoto="/tmp/$(basename "$SCRIPT_LOCAL")_$$"
    echo " Copiando script..."
    if ! copiar_script "$host" "$script_remoto"; then
        echo " ❌ Error al copiar el script a $host"
        registrar_log "$LOG" "ERROR: fallo scp a $host | Script: $(basename "$SCRIPT_LOCAL")"
        notificar_telegram "$host" "ERROR" "Fallo al copiar script con scp"
        HOSTS_FALLIDOS+=("$host")
        return
    fi
    echo " ✅ Script copiado"

    # 3. Ejecutar
    echo " Ejecutando script en $host..."
    local salida
    salida=$(ejecutar_remoto "$host" "$script_remoto")
    local exit_code=$?

    echo "$salida"

    # 4. Guardar reporte
    local ruta_reporte
    ruta_reporte=$(guardar_reporte "$host_ip" "$salida")
    echo " 📄 Reporte guardado: $ruta_reporte"

    # 5. Log y Telegram
    if [[ $exit_code -eq 0 ]]; then
        registrar_log "$LOG" "OK: $host | Script: $(basename "$SCRIPT_LOCAL") | Reporte: $ruta_reporte"
        notificar_telegram "$host" "OK" "$salida"
        HOSTS_OK+=("$host")
    else
        registrar_log "$LOG" "ERROR (exit $exit_code): $host | Script: $(basename "$SCRIPT_LOCAL") | Reporte: $ruta_reporte"
        notificar_telegram "$host" "ERROR" "Exit code $exit_code\n$salida"
        HOSTS_FALLIDOS+=("$host")
    fi
}

#──────────────────────────────────────────────────────────────
# Main
#──────────────────────────────────────────────────────────────
main() {
    [[ "$1" == "-h" || "$1" == "--help" ]] && ayuda
    validar "$@"

    HOSTS_OK=()
    HOSTS_FALLIDOS=()

    echo " Script   : $(basename "$SCRIPT_LOCAL")"
    echo " Args     : ${ARGS_REMOTOS[*]:-ninguno}"
    echo " Hosts    : ${#HOSTS[@]}"
    echo " Reportes : $REPORTES_DIR"
    echo "──────────────────────────────────────"

    for host in "${HOSTS[@]}"; do
        procesar_host "$host"
    done

    echo ""
    echo "══════════════════════════════════════"
    echo " RESUMEN FINAL"
    echo "══════════════════════════════════════"
    echo " Total    : ${#HOSTS[@]} host(s)"
    echo " ✅ OK    : ${#HOSTS_OK[@]} — ${HOSTS_OK[*]:-ninguno}"
    echo " ❌ Falló : ${#HOSTS_FALLIDOS[@]} — ${HOSTS_FALLIDOS[*]:-ninguno}"
    echo " Log      : $LOG"

    registrar_log "$LOG" "RESUMEN: ${#HOSTS[@]} hosts | OK: ${#HOSTS_OK[@]} | Falló: ${#HOSTS_FALLIDOS[@]} | Script: $(basename "$SCRIPT_LOCAL")"
}

main "$@"
