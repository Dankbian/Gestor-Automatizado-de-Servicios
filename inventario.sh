#!/bin/bash
#=============================================================
# inventario.sh — Inventario de hardware y sistema operativo
#
# Uso:
#   ./inventario.sh
#   ./inventario.sh --cron     → silencioso, apto para cron
#
# Guarda el reporte en /var/log/inventario_FECHA.txt
# (si no tiene permisos en /var/log usa $LOG_DIR)
#=============================================================

source "$(dirname "$0")/config.sh"

LOG="$LOG_DIR/inventario.log"
FECHA=$(date '+%Y-%m-%d_%H-%M-%S')
FECHA_LEGIBLE=$(date '+%d/%m/%Y %H:%M:%S')

# Destino del reporte
if [[ -w /var/log ]]; then
    REPORTE="/var/log/inventario_${FECHA}.txt"
else
    REPORTE="$LOG_DIR/inventario_${FECHA}.txt"
fi

MODO_CRON=0
[[ "$1" == "--cron" ]] && MODO_CRON=1

#──────────────────────────────────────────────────────────────
# Helpers
#──────────────────────────────────────────────────────────────
seccion() {
    echo ""
    echo "══════════════════════════════════════════════"
    echo "  $1"
    echo "══════════════════════════════════════════════"
}

linea() { echo "  $1"; }

ayuda() {
    echo "Uso: $0 [--cron]"
    echo ""
    echo "  Sin argumento → modo interactivo con salida en pantalla"
    echo "  --cron        → modo silencioso (solo log y Telegram)"
    echo ""
    echo "Reporte guardado en: /var/log/inventario_FECHA.txt"
    echo "  (o en logs/ si no hay permisos en /var/log)"
    exit 0
}

[[ "$1" == "-h" || "$1" == "--help" ]] && ayuda

#──────────────────────────────────────────────────────────────
# Recopilar datos del sistema
#──────────────────────────────────────────────────────────────
recopilar_datos() {
    # ── Identificación ────────────────────────────────────────
    HOSTNAME=$(hostname -f 2>/dev/null || hostname)
    IP_ADDR=$(hostname -I 2>/dev/null | tr ' ' '\n' | grep -v '^$' | head -5 | tr '\n' ' ')

    # ── Sistema operativo ─────────────────────────────────────
    if [[ -f /etc/os-release ]]; then
        OS_NOMBRE=$(. /etc/os-release && echo "$PRETTY_NAME")
    else
        OS_NOMBRE=$(uname -s)
    fi
    KERNEL=$(uname -r)
    ARQUITECTURA=$(uname -m)
    UPTIME=$(uptime -p 2>/dev/null || uptime)

    # ── CPU ───────────────────────────────────────────────────
    CPU_MODELO=$(grep 'model name' /proc/cpuinfo 2>/dev/null | head -1 | cut -d: -f2 | sed 's/^ *//')
    [[ -z "$CPU_MODELO" ]] && CPU_MODELO=$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo "No disponible")
    CPU_NUCLEOS_FISICOS=$(grep '^cpu cores' /proc/cpuinfo 2>/dev/null | sort -u | awk '{print $NF}' | head -1)
    CPU_NUCLEOS_LOGICOS=$(nproc 2>/dev/null || grep -c '^processor' /proc/cpuinfo 2>/dev/null || echo "?")
    [[ -z "$CPU_NUCLEOS_FISICOS" ]] && CPU_NUCLEOS_FISICOS="$CPU_NUCLEOS_LOGICOS"
    CPU_SOCKETS=$(grep '^physical id' /proc/cpuinfo 2>/dev/null | sort -u | wc -l)
    [[ "$CPU_SOCKETS" -eq 0 ]] && CPU_SOCKETS=1

    # Uso actual de CPU
    CPU_USO=$(top -bn1 2>/dev/null | grep '%Cpu' | awk '{print 100 - $8}' | head -1)
    [[ -z "$CPU_USO" ]] && CPU_USO="N/A"

    # ── RAM ───────────────────────────────────────────────────
    if [[ -f /proc/meminfo ]]; then
        RAM_TOTAL_KB=$(grep '^MemTotal' /proc/meminfo | awk '{print $2}')
        RAM_LIBRE_KB=$(grep '^MemAvailable' /proc/meminfo | awk '{print $2}')
        RAM_USADA_KB=$(( RAM_TOTAL_KB - RAM_LIBRE_KB ))

        ram_kb_a_legible() {
            local kb=$1
            if [[ $kb -ge 1048576 ]]; then
                echo "$(echo "scale=2; $kb/1048576" | bc) GB"
            else
                echo "$(echo "scale=0; $kb/1024" | bc) MB"
            fi
        }

        RAM_TOTAL=$(ram_kb_a_legible "$RAM_TOTAL_KB")
        RAM_LIBRE=$(ram_kb_a_legible "$RAM_LIBRE_KB")
        RAM_USADA=$(ram_kb_a_legible "$RAM_USADA_KB")
        RAM_USO_PCT=$(echo "scale=1; $RAM_USADA_KB * 100 / $RAM_TOTAL_KB" | bc)
    else
        RAM_TOTAL="N/A"; RAM_LIBRE="N/A"; RAM_USADA="N/A"; RAM_USO_PCT="N/A"
    fi

    # ── Disco ─────────────────────────────────────────────────
    DISCO_INFO=$(df -h --output=target,fstype,size,used,avail,pcent 2>/dev/null || \
                 df -h 2>/dev/null | awk 'NR>1 {printf "%-20s %-10s %8s %8s %8s %5s\n",$6,$1,$2,$3,$4,$5}')

    # ── Red ───────────────────────────────────────────────────
    INTERFACES=$(ip -brief addr show 2>/dev/null || ifconfig 2>/dev/null | grep -E '^[a-z]' | awk '{print $1}')

    # ── Paquetes instalados ───────────────────────────────────
    if command -v dpkg &>/dev/null; then
        PAQUETES=$(dpkg -l 2>/dev/null | grep -c '^ii')
        GESTOR_PKG="dpkg/apt"
    elif command -v rpm &>/dev/null; then
        PAQUETES=$(rpm -qa 2>/dev/null | wc -l)
        GESTOR_PKG="rpm/yum"
    else
        PAQUETES="N/A"
        GESTOR_PKG="desconocido"
    fi

    # ── Usuarios del sistema ──────────────────────────────────
    USUARIOS_SISTEMA=$(getent passwd 2>/dev/null | awk -F: '$3>=1000 && $3<65534 {print $1}' | tr '\n' ' ')
    [[ -z "$USUARIOS_SISTEMA" ]] && USUARIOS_SISTEMA="N/A"

    # ── Servicios activos ─────────────────────────────────────
    if command -v systemctl &>/dev/null; then
        SERVICIOS_ACTIVOS=$(systemctl list-units --type=service --state=active --no-legend 2>/dev/null | wc -l)
        SERVICIOS_FALLIDOS=$(systemctl list-units --type=service --state=failed --no-legend 2>/dev/null | wc -l)
    else
        SERVICIOS_ACTIVOS="N/A"
        SERVICIOS_FALLIDOS="N/A"
    fi
}

#──────────────────────────────────────────────────────────────
# Generar reporte en texto plano
#──────────────────────────────────────────────────────────────
generar_reporte() {
    {
        echo "============================================================"
        echo "  INVENTARIO DEL SISTEMA — $FECHA_LEGIBLE"
        echo "  Generado por: $(whoami)"
        echo "============================================================"

        echo ""
        echo "── IDENTIFICACIÓN ──────────────────────────────────────────"
        echo "  Hostname     : $HOSTNAME"
        echo "  IP(s)        : $IP_ADDR"
        echo "  Fecha/Hora   : $FECHA_LEGIBLE"
        echo "  Uptime       : $UPTIME"

        echo ""
        echo "── SISTEMA OPERATIVO ───────────────────────────────────────"
        echo "  OS           : $OS_NOMBRE"
        echo "  Kernel       : $KERNEL"
        echo "  Arquitectura : $ARQUITECTURA"

        echo ""
        echo "── CPU ─────────────────────────────────────────────────────"
        echo "  Modelo       : $CPU_MODELO"
        echo "  Sockets      : $CPU_SOCKETS"
        echo "  Núcleos físicos: $CPU_NUCLEOS_FISICOS"
        echo "  Núcleos lógicos: $CPU_NUCLEOS_LOGICOS"
        echo "  Uso actual   : ${CPU_USO}%"

        echo ""
        echo "── MEMORIA RAM ─────────────────────────────────────────────"
        echo "  Total        : $RAM_TOTAL"
        echo "  En uso       : $RAM_USADA (${RAM_USO_PCT}%)"
        echo "  Disponible   : $RAM_LIBRE"

        echo ""
        echo "── DISCO — USO POR PARTICIÓN ───────────────────────────────"
        echo "  Punto montaje       Tipo       Total    Usado    Libre   Uso%"
        echo "  $DISCO_INFO" | head -20

        echo ""
        echo "── RED ─────────────────────────────────────────────────────"
        echo "$INTERFACES" | sed 's/^/  /'

        echo ""
        echo "── SOFTWARE ────────────────────────────────────────────────"
        echo "  Gestor pkg   : $GESTOR_PKG"
        echo "  Paquetes inst: $PAQUETES"

        echo ""
        echo "── USUARIOS DEL SISTEMA (UID >= 1000) ──────────────────────"
        echo "  $USUARIOS_SISTEMA"

        echo ""
        echo "── SERVICIOS ───────────────────────────────────────────────"
        echo "  Activos      : $SERVICIOS_ACTIVOS"
        echo "  Fallidos     : $SERVICIOS_FALLIDOS"

        echo ""
        echo "============================================================"
        echo "  FIN DEL REPORTE"
        echo "============================================================"
    } > "$REPORTE"
}

#──────────────────────────────────────────────────────────────
# Mostrar reporte en pantalla (modo interactivo)
#──────────────────────────────────────────────────────────────
mostrar_en_pantalla() {
    cat "$REPORTE"
}

#──────────────────────────────────────────────────────────────
# Enviar resumen a Telegram
#──────────────────────────────────────────────────────────────
notificar_telegram() {
    local msg="🖥️ *Inventario del sistema*
🏷️ Host: \`$HOSTNAME\`
📅 Fecha: $FECHA_LEGIBLE

💻 *CPU*: $CPU_MODELO
🔢 Núcleos: $CPU_NUCLEOS_LOGICOS lógicos | Uso: ${CPU_USO}%

🧠 *RAM*: Total $RAM_TOTAL | Usado $RAM_USADA (${RAM_USO_PCT}%) | Libre $RAM_LIBRE

💾 *Disco raíz*:
\`$(df -h / | awk 'NR==2 {printf "Total: %s | Usado: %s (%s) | Libre: %s", $2,$3,$5,$4}')\`

🐧 *OS*: $OS_NOMBRE
⚙️ Kernel: $KERNEL
📦 Paquetes: $PAQUETES ($GESTOR_PKG)
🔧 Servicios activos: $SERVICIOS_ACTIVOS | Fallidos: $SERVICIOS_FALLIDOS

📄 Reporte: \`$REPORTE\`"

    enviar_alerta "$msg"
}

#──────────────────────────────────────────────────────────────
# Main
#──────────────────────────────────────────────────────────────
main() {
    [[ "$1" == "-h" || "$1" == "--help" ]] && ayuda

    recopilar_datos
    generar_reporte

    if [[ $MODO_CRON -eq 0 ]]; then
        mostrar_en_pantalla
    fi

    notificar_telegram
    registrar_log "$LOG" "Inventario generado: $REPORTE | OS: $OS_NOMBRE | CPU: $CPU_NUCLEOS_LOGICOS núcleos ${CPU_USO}% | RAM: $RAM_TOTAL (${RAM_USO_PCT}% uso)"

    echo ""
    echo " ✅ Inventario guardado en: $REPORTE"
    echo " ✅ Notificación enviada a Telegram."
    echo " ✅ Log: $LOG"
}

main "$@"
