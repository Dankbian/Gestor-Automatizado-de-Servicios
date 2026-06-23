#!/bin/bash
#=============================================================
# monitoreo.sh — Monitoreo de CPU y disco
#
# Uso:
#   ./monitoreo.sh <host> [umbral_cpu] [umbral_disco]
#
# Ejemplos:
#   ./monitoreo.sh localhost
#   ./monitoreo.sh localhost 85 90
#   ./monitoreo.sh valero@192.168.1.105 70 80
#=============================================================

source "$(dirname "$0")/config.sh"

LOG="$LOG_DIR/monitoreo.log"

#──────────────────────────────────────────────────────────────
# Ayuda
#──────────────────────────────────────────────────────────────
ayuda() {
    echo "Uso: $0 <host> [umbral_cpu] [umbral_disco]"
    echo ""
    echo "  host          → localhost, 127.0.0.1 o usuario@IP"
    echo "  umbral_cpu    → porcentaje (default: 70)"
    echo "  umbral_disco  → porcentaje (default: 70)"
    echo ""
    echo "Ejemplos:"
    echo "  $0 localhost"
    echo "  $0 localhost 85 90"
    echo "  $0 jorge@192.168.1.50"
    exit 0
}

#──────────────────────────────────────────────────────────────
# Validar argumentos
#──────────────────────────────────────────────────────────────
validar_argumentos() {
    [[ -z "$1" ]] && { echo " Se requiere al menos el host."; ayuda; }

    HOST="$1"
    UMBRAL_CPU="${2:-70}"
    UMBRAL_DISCO="${3:-70}"

    if ! [[ "$UMBRAL_CPU" =~ ^[1-9][0-9]*$ ]] || [[ "$UMBRAL_CPU" -gt 100 ]]; then
        echo " Umbral CPU inválido: '$UMBRAL_CPU'. Debe ser un número entre 1 y 100."
        exit 1
    fi
    if ! [[ "$UMBRAL_DISCO" =~ ^[1-9][0-9]*$ ]] || [[ "$UMBRAL_DISCO" -gt 100 ]]; then
        echo " Umbral disco inválido: '$UMBRAL_DISCO'. Debe ser un número entre 1 y 100."
        exit 1
    fi

    # Validar formato de host
    if [[ "$HOST" != "localhost" && "$HOST" != "127.0.0.1" ]]; then
        if ! [[ "$HOST" =~ ^[a-zA-Z0-9._-]+@[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo " Formato de host inválido. Usa: localhost o usuario@IP"
            exit 1
        fi
    fi
}

#──────────────────────────────────────────────────────────────
# Obtener métricas localmente
#──────────────────────────────────────────────────────────────
obtener_cpu_local() {
    # Lee /proc/stat dos veces con 0.5s de diferencia para medir delta real
    local cpu1 cpu2
    cpu1=$(grep '^cpu ' /proc/stat)
    sleep 0.5
    cpu2=$(grep '^cpu ' /proc/stat)

    local idle1 total1 idle2 total2
    idle1=$(echo "$cpu1" | awk '{print $5}')
    total1=$(echo "$cpu1" | awk '{s=0; for(i=2;i<=NF;i++) s+=$i; print s}')
    idle2=$(echo "$cpu2" | awk '{print $5}')
    total2=$(echo "$cpu2" | awk '{s=0; for(i=2;i<=NF;i++) s+=$i; print s}')

    local delta_idle=$(( idle2 - idle1 ))
    local delta_total=$(( total2 - total1 ))

    if [[ "$delta_total" -eq 0 ]]; then
        echo "0"
    else
        echo $(( 100 * (delta_total - delta_idle) / delta_total ))
    fi
}

obtener_disco_local() {
    # Devuelve el uso del sistema de archivos raíz en %
    df / | awk 'NR==2 {gsub(/%/,"",$5); print $5}'
}

#──────────────────────────────────────────────────────────────
# Obtener métricas remotamente
#──────────────────────────────────────────────────────────────
obtener_metricas_remoto() {
    local host_ip="${HOST##*@}"

    echo " Verificando conectividad con $host_ip..."
    if ! ping -c1 -W2 "$host_ip" &>/dev/null; then
        echo " ❌ No se puede contactar con $host_ip"
        enviar_alerta "❌ *monitoreo.sh*: host \`$host_ip\` no responde"
        registrar_log "$LOG" "ERROR: host $host_ip no responde"
        exit 2
    fi

    read -r CPU_USO DISCO_USO < <(ssh -o ConnectTimeout=10 "$HOST" '
        cpu1=$(grep "^cpu " /proc/stat)
        sleep 0.5
        cpu2=$(grep "^cpu " /proc/stat)
        idle1=$(echo "$cpu1" | awk "{print \$5}")
        total1=$(echo "$cpu1" | awk "{s=0; for(i=2;i<=NF;i++) s+=\$i; print s}")
        idle2=$(echo "$cpu2" | awk "{print \$5}")
        total2=$(echo "$cpu2" | awk "{s=0; for(i=2;i<=NF;i++) s+=\$i; print s}")
        dt=$(( total2 - total1 ))
        di=$(( idle2 - idle1 ))
        [[ $dt -eq 0 ]] && cpu_pct=0 || cpu_pct=$(( 100 * (dt - di) / dt ))
        disco=$(df / | awk "NR==2 {gsub(/%/,\"\",\$5); print \$5}")
        echo "$cpu_pct $disco"
    ' 2>/dev/null)

    if [[ -z "$CPU_USO" || -z "$DISCO_USO" ]]; then
        echo " ❌ No se pudieron obtener métricas de $HOST"
        enviar_alerta "❌ *monitoreo.sh*: no se obtuvieron métricas de \`$HOST\`"
        registrar_log "$LOG" "ERROR: no se obtuvieron métricas de $HOST"
        exit 2
    fi
}

#──────────────────────────────────────────────────────────────
# Evaluar y registrar
#──────────────────────────────────────────────────────────────
evaluar_y_notificar() {
    local timestamp
    timestamp=$(date '+%F %T')
    local nombre_host="${HOST##*@}"
    [[ "$HOST" == "localhost" || "$HOST" == "127.0.0.1" ]] && nombre_host="localhost"

    echo "──────────────────────────────────────"
    echo " Host    : $nombre_host"
    echo " CPU     : ${CPU_USO}%  (umbral: ${UMBRAL_CPU}%)"
    echo " Disco   : ${DISCO_USO}%  (umbral: ${UMBRAL_DISCO}%)"
    echo " Hora    : $timestamp"
    echo "──────────────────────────────────────"

    # Siempre registrar en log
    registrar_log "$LOG" "HOST=$nombre_host | CPU=${CPU_USO}% (umbral ${UMBRAL_CPU}%) | DISCO=${DISCO_USO}% (umbral ${UMBRAL_DISCO}%)"

    local alerta=0

    # Evaluar CPU
    if [[ "$CPU_USO" -gt "$UMBRAL_CPU" ]]; then
        alerta=1
        echo " ⚠️  ALERTA: CPU en ${CPU_USO}% — supera el umbral de ${UMBRAL_CPU}%"
        enviar_alerta "⚠️ *ALERTA CPU* en \`$nombre_host\`
📊 Uso actual: *${CPU_USO}%*
🔴 Umbral configurado: ${UMBRAL_CPU}%
🕐 $timestamp"
        registrar_log "$LOG" "ALERTA: CPU ${CPU_USO}% supera umbral ${UMBRAL_CPU}% en $nombre_host"
    else
        echo " ✅ CPU dentro del umbral."
    fi

    # Evaluar disco
    if [[ "$DISCO_USO" -gt "$UMBRAL_DISCO" ]]; then
        alerta=1
        echo " ⚠️  ALERTA: Disco en ${DISCO_USO}% — supera el umbral de ${UMBRAL_DISCO}%"
        enviar_alerta "⚠️ *ALERTA DISCO* en \`$nombre_host\`
💾 Uso actual: *${DISCO_USO}%*
🔴 Umbral configurado: ${UMBRAL_DISCO}%
🕐 $timestamp"
        registrar_log "$LOG" "ALERTA: DISCO ${DISCO_USO}% supera umbral ${UMBRAL_DISCO}% en $nombre_host"
    else
        echo " ✅ Disco dentro del umbral."
    fi

    [[ $alerta -eq 0 ]] && echo " ✅ Todo dentro de los umbrales. Sin alertas."
}

#──────────────────────────────────────────────────────────────
# Main
#──────────────────────────────────────────────────────────────
main() {
    [[ "$1" == "-h" || "$1" == "--help" ]] && ayuda
    validar_argumentos "$@"

    if [[ "$HOST" == "localhost" || "$HOST" == "127.0.0.1" ]]; then
        CPU_USO=$(obtener_cpu_local)
        DISCO_USO=$(obtener_disco_local)
    else
        obtener_metricas_remoto
    fi

    evaluar_y_notificar
}

main "$@"
