#!/bin/bash
#=============================================================
# red.sh — Diagnóstico de red: conectividad y puertos
#
# Uso:
#   ./red.sh
#
# Lee hosts y puertos de config.txt bajo la sección [red]
# Formato:
#   [red]
#   192.168.1.1:22,80,443    → host con puertos críticos
#   192.168.1.50             → solo ping
#   google.com:443           → hostname con puerto
#=============================================================

source "$(dirname "$0")/config.sh"

LOG="$LOG_DIR/red.log"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config.txt"

# Timeout para nc y ping (segundos)
TIMEOUT_PING=2
TIMEOUT_PORT=3

#──────────────────────────────────────────────────────────────
# Ayuda
#──────────────────────────────────────────────────────────────
ayuda() {
    echo "Uso: $0 [-h]"
    echo ""
    echo "Lee hosts y puertos desde config.txt sección [red]:"
    echo ""
    echo "  [red]"
    echo "  192.168.1.1:22,80,443"
    echo "  192.168.1.50"
    echo "  google.com:443"
    echo ""
    echo "Clasificación de resultados:"
    echo "  ✅ ACCESIBLE       → ping OK y todos los puertos abiertos"
    echo "  ⚠️  PARCIAL         → ping OK pero algún puerto cerrado"
    echo "  ❌ SIN RESPUESTA   → ping fallido"
    exit 0
}

#──────────────────────────────────────────────────────────────
# Cargar hosts desde config.txt sección [red]
#──────────────────────────────────────────────────────────────
cargar_hosts_red() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo " ❌ No se encontró config.txt en $SCRIPT_DIR"
        exit 1
    fi

    mapfile -t ENTRADAS_RED < <(
        awk '/^\[red\]/{found=1; next} /^\[/{found=0} found && /^[^#[:space:]]/{print $1}' "$CONFIG_FILE"
    )

    if [[ ${#ENTRADAS_RED[@]} -eq 0 ]]; then
        echo " ❌ No se encontraron hosts en la sección [red] de config.txt"
        exit 1
    fi

    echo " Hosts a revisar: ${#ENTRADAS_RED[@]}"
}

#──────────────────────────────────────────────────────────────
# Verificar ping
#──────────────────────────────────────────────────────────────
verificar_ping() {
    local host="$1"
    ping -c1 -W"$TIMEOUT_PING" "$host" &>/dev/null
}

#──────────────────────────────────────────────────────────────
# Verificar puerto con nc (fallback a /dev/tcp)
#──────────────────────────────────────────────────────────────
verificar_puerto() {
    local host="$1"
    local puerto="$2"

    # Intentar con nc primero
    if command -v nc &>/dev/null; then
        nc -z -w "$TIMEOUT_PORT" "$host" "$puerto" &>/dev/null
        return $?
    fi

    # Fallback a /dev/tcp
    (
        exec 3<>/dev/tcp/"$host"/"$puerto" 2>/dev/null
        exit_code=$?
        exec 3>&-
        exit $exit_code
    ) 2>/dev/null
}

#──────────────────────────────────────────────────────────────
# Procesar una entrada host[:puerto1,puerto2,...]
#──────────────────────────────────────────────────────────────
procesar_entrada() {
    local entrada="$1"
    local timestamp
    timestamp=$(date '+%F %T')

    # Separar host y puertos
    local host="${entrada%%:*}"
    local puertos_str=""
    [[ "$entrada" == *:* ]] && puertos_str="${entrada#*:}"

    local puertos=()
    if [[ -n "$puertos_str" ]]; then
        IFS=',' read -ra puertos <<< "$puertos_str"
    fi

    echo ""
    echo "── Host: $host ──────────────────────────"

    # 1. Ping
    local ping_ok=0
    if verificar_ping "$host"; then
        ping_ok=1
        echo " ✅ Ping: responde"
    else
        echo " ❌ Ping: sin respuesta"
        registrar_log "$LOG" "[$timestamp] SIN_RESPUESTA | Host: $host | Ping: FAIL"
        enviar_alerta "❌ *Host sin respuesta*: \`$host\`
🕐 $timestamp
🔴 Sin respuesta al ping"
        HOSTS_SIN_RESPUESTA+=("$host")
        return
    fi

    # 2. Puertos
    local puertos_ok=()
    local puertos_cerrados=()

    for puerto in "${puertos[@]}"; do
        [[ -z "$puerto" ]] && continue
        if verificar_puerto "$host" "$puerto"; then
            puertos_ok+=("$puerto")
            echo " ✅ Puerto $puerto: abierto"
        else
            puertos_cerrados+=("$puerto")
            echo " ❌ Puerto $puerto: cerrado / no responde"
        fi
    done

    # 3. Clasificar y registrar
    if [[ ${#puertos_cerrados[@]} -eq 0 ]]; then
        # Accesible
        local detalle="Ping OK"
        [[ ${#puertos_ok[@]} -gt 0 ]] && detalle+=" | Puertos abiertos: ${puertos_ok[*]}"
        echo " 🟢 Clasificación: ACCESIBLE"
        registrar_log "$LOG" "[$timestamp] ACCESIBLE | Host: $host | $detalle"
        HOSTS_ACCESIBLES+=("$host")

    else
        # Parcialmente accesible
        echo " 🟡 Clasificación: PARCIALMENTE ACCESIBLE"
        local detalle="Ping OK | Abiertos: ${puertos_ok[*]:-ninguno} | Cerrados: ${puertos_cerrados[*]}"
        registrar_log "$LOG" "[$timestamp] PARCIAL | Host: $host | $detalle"

        local msg_puertos="Puertos cerrados: ${puertos_cerrados[*]}"
        [[ ${#puertos_ok[@]} -gt 0 ]] && msg_puertos+="\nPuertos abiertos: ${puertos_ok[*]}"
        enviar_alerta "⚠️ *Host parcialmente accesible*: \`$host\`
🕐 $timestamp
🔴 $msg_puertos"
        HOSTS_PARCIALES+=("$host")
    fi
}

#──────────────────────────────────────────────────────────────
# Resumen final
#──────────────────────────────────────────────────────────────
mostrar_resumen() {
    local timestamp
    timestamp=$(date '+%F %T')

    echo ""
    echo "══════════════════════════════════════"
    echo " RESUMEN DE RED — $timestamp"
    echo "══════════════════════════════════════"
    echo " 🟢 Accesibles   (${#HOSTS_ACCESIBLES[@]}): ${HOSTS_ACCESIBLES[*]:-ninguno}"
    echo " 🟡 Parciales    (${#HOSTS_PARCIALES[@]}): ${HOSTS_PARCIALES[*]:-ninguno}"
    echo " 🔴 Sin respuesta(${#HOSTS_SIN_RESPUESTA[@]}): ${HOSTS_SIN_RESPUESTA[*]:-ninguno}"
    echo " Log: $LOG"

    registrar_log "$LOG" "[$timestamp] RESUMEN: Accesibles=${#HOSTS_ACCESIBLES[@]} Parciales=${#HOSTS_PARCIALES[@]} SinRespuesta=${#HOSTS_SIN_RESPUESTA[@]}"

    # Notificar resumen si hay problemas
    local total_problemas=$(( ${#HOSTS_PARCIALES[@]} + ${#HOSTS_SIN_RESPUESTA[@]} ))
    if [[ $total_problemas -gt 0 ]]; then
        local msg="📊 *Resumen de red* — $timestamp
🟢 Accesibles: ${#HOSTS_ACCESIBLES[@]}
🟡 Parciales: ${#HOSTS_PARCIALES[@]} — ${HOSTS_PARCIALES[*]:-}
🔴 Sin respuesta: ${#HOSTS_SIN_RESPUESTA[@]} — ${HOSTS_SIN_RESPUESTA[*]:-}"
        enviar_alerta "$msg"
    fi
}

#──────────────────────────────────────────────────────────────
# Main
#──────────────────────────────────────────────────────────────
main() {
    [[ "$1" == "-h" || "$1" == "--help" ]] && ayuda

    HOSTS_ACCESIBLES=()
    HOSTS_PARCIALES=()
    HOSTS_SIN_RESPUESTA=()

    cargar_hosts_red

    registrar_log "$LOG" "──── INICIO REVISIÓN RED $(date '+%F %T') ────"

    for entrada in "${ENTRADAS_RED[@]}"; do
        [[ -z "$entrada" || "$entrada" =~ ^# ]] && continue
        procesar_entrada "$entrada"
    done

    mostrar_resumen
}

main "$@"
