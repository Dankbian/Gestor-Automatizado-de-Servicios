#!/bin/bash
#=============================================================
# servicios.sh — Revisión y reinicio automático de servicios
#
# Uso:
#   ./servicios.sh [localhost | usuario@IP]
#
# Lee la lista de servicios de config.txt bajo la sección [servicios]
#=============================================================

source "$(dirname "$0")/config.sh"

LOG="$LOG_DIR/servicios.log"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config.txt"

#──────────────────────────────────────────────────────────────
# Ayuda
#──────────────────────────────────────────────────────────────
ayuda() {
    echo "Uso: $0 [localhost | usuario@IP]"
    echo ""
    echo "  Sin argumento o 'localhost' → revisa servicios en este equipo"
    echo "  usuario@IP                  → revisa servicios en host remoto"
    echo ""
    echo "La lista de servicios se lee de config.txt bajo [servicios]"
    exit 0
}

#──────────────────────────────────────────────────────────────
# Leer sección [servicios] de config.txt
#──────────────────────────────────────────────────────────────
cargar_servicios() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo " ❌ No se encontró config.txt en $SCRIPT_DIR"
        echo "    Crea el archivo con una sección [servicios]:"
        echo "    [servicios]"
        echo "    ssh"
        echo "    cron"
        exit 1
    fi

    mapfile -t SERVICIOS < <(
        awk '/^\[servicios\]/{found=1; next} /^\[/{found=0} found && /^[^#[:space:]]/{print $1}' "$CONFIG_FILE"
    )

    if [[ ${#SERVICIOS[@]} -eq 0 ]]; then
        echo " ❌ No se encontraron servicios en la sección [servicios] de config.txt"
        exit 1
    fi

    echo " Servicios a revisar: ${SERVICIOS[*]}"
    echo "──────────────────────────────────────"
}

#──────────────────────────────────────────────────────────────
# Revisar y reiniciar servicios — lógica local
#──────────────────────────────────────────────────────────────
revisar_servicios_local() {
    local host_display="${1:-localhost}"

    for svc in "${SERVICIOS[@]}"; do
        [[ -z "$svc" || "$svc" =~ ^# ]] && continue

        # Verificar si el servicio existe
        if ! systemctl list-unit-files --type=service 2>/dev/null | grep -q "^${svc}\.service"; then
            echo " ➖ $svc: no está instalado en $host_display"
            registrar_log "$LOG" "NO_INSTALADO: $svc en $host_display"
            continue
        fi

        local estado
        estado=$(systemctl is-active "$svc" 2>/dev/null)

        if [[ "$estado" == "active" ]]; then
            echo " ✅ $svc: activo en $host_display"
            registrar_log "$LOG" "OK: $svc activo en $host_display"

        elif [[ "$estado" == "inactive" || "$estado" == "failed" ]]; then
            echo " ⚠️  $svc: $estado en $host_display — intentando reiniciar..."
            registrar_log "$LOG" "CAÍDO ($estado): $svc en $host_display — intentando reiniciar"
            enviar_alerta "⚠️ *Servicio caído*: \`$svc\` está *$estado* en \`$host_display\`
🔄 Intentando reiniciar..."

            if sudo systemctl start "$svc" 2>/dev/null; then
                sleep 2
                local estado_nuevo
                estado_nuevo=$(systemctl is-active "$svc" 2>/dev/null)
                if [[ "$estado_nuevo" == "active" ]]; then
                    echo " ✅ $svc: reiniciado correctamente en $host_display"
                    registrar_log "$LOG" "REINICIADO: $svc OK en $host_display"
                    enviar_alerta "✅ *Servicio recuperado*: \`$svc\` está ahora *activo* en \`$host_display\`"
                else
                    echo " ❌ $svc: sigue caído después del reinicio ($estado_nuevo)"
                    registrar_log "$LOG" "FALLO_REINICIO: $svc sigue $estado_nuevo en $host_display"
                    enviar_alerta "❌ *Fallo al reiniciar*: \`$svc\` sigue *$estado_nuevo* en \`$host_display\`"
                fi
            else
                echo " ❌ $svc: error al ejecutar systemctl start"
                registrar_log "$LOG" "FALLO_REINICIO: systemctl start $svc falló en $host_display"
                enviar_alerta "❌ *Error al reiniciar* \`$svc\` en \`$host_display\` (sin permisos o error de config)"
            fi

        else
            echo " ❓ $svc: estado desconocido '$estado' en $host_display"
            registrar_log "$LOG" "DESCONOCIDO: $svc estado='$estado' en $host_display"
        fi
    done
}

#──────────────────────────────────────────────────────────────
# Modo remoto
#──────────────────────────────────────────────────────────────
revisar_servicios_remoto() {
    local destino="$1"
    local host_ip="${destino##*@}"

    echo " Verificando conectividad con $host_ip..."
    if ! ping -c1 -W2 "$host_ip" &>/dev/null; then
        echo " ❌ No se puede contactar con $host_ip"
        enviar_alerta "❌ *servicios.sh*: host \`$host_ip\` no responde"
        registrar_log "$LOG" "ERROR: host $host_ip no responde"
        exit 2
    fi

    local svcs_str="${SERVICIOS[*]}"

    ssh -o ConnectTimeout=10 "$destino" bash <<EOF
HOST_D="$host_ip"
TOKEN="$TELEGRAM_TOKEN"
CHAT="$TELEGRAM_CHAT"
TURL="https://api.telegram.org/bot\${TOKEN}/sendMessage"

enviar() { curl -s -X POST "\$TURL" -d chat_id="\$CHAT" -d parse_mode="Markdown" -d text="\$1" > /dev/null; }
log_r()  { printf '[%s] %s\n' "\$(date '+%F %T')" "\$1" >> "/tmp/servicios_remote.log"; }

for svc in $svcs_str; do
    [[ -z "\$svc" ]] && continue

    if ! systemctl list-unit-files --type=service 2>/dev/null | grep -q "^\${svc}\.service"; then
        echo " ➖ \$svc: no instalado en \$HOST_D"
        log_r "NO_INSTALADO: \$svc en \$HOST_D"
        continue
    fi

    estado=\$(systemctl is-active "\$svc" 2>/dev/null)

    if [[ "\$estado" == "active" ]]; then
        echo " ✅ \$svc: activo en \$HOST_D"
        log_r "OK: \$svc activo en \$HOST_D"

    elif [[ "\$estado" == "inactive" || "\$estado" == "failed" ]]; then
        echo " ⚠️  \$svc: \$estado en \$HOST_D — reiniciando..."
        log_r "CAÍDO (\$estado): \$svc en \$HOST_D"
        enviar "⚠️ *Servicio caído*: \\\`\$svc\\\` está *\$estado* en \\\`\$HOST_D\\\`"

        if sudo systemctl start "\$svc" 2>/dev/null; then
            sleep 2
            en=\$(systemctl is-active "\$svc" 2>/dev/null)
            if [[ "\$en" == "active" ]]; then
                echo " ✅ \$svc: reiniciado OK en \$HOST_D"
                log_r "REINICIADO: \$svc OK en \$HOST_D"
                enviar "✅ *Recuperado*: \\\`\$svc\\\` activo en \\\`\$HOST_D\\\`"
            else
                echo " ❌ \$svc: sigue caído (\$en) en \$HOST_D"
                log_r "FALLO_REINICIO: \$svc sigue \$en en \$HOST_D"
                enviar "❌ *Fallo reinicio*: \\\`\$svc\\\` sigue *\$en* en \\\`\$HOST_D\\\`"
            fi
        else
            echo " ❌ \$svc: error al reiniciar en \$HOST_D"
            log_r "FALLO_REINICIO: systemctl start \$svc falló en \$HOST_D"
            enviar "❌ *Error reinicio* \\\`\$svc\\\` en \\\`\$HOST_D\\\`"
        fi
    else
        echo " ❓ \$svc: estado '\$estado' en \$HOST_D"
        log_r "DESCONOCIDO: \$svc='\$estado' en \$HOST_D"
    fi
done
EOF

    # Traer el log remoto y fusionarlo con el local
    scp -q "$destino:/tmp/servicios_remote.log" "/tmp/servicios_remote_$$.log" 2>/dev/null && {
        cat "/tmp/servicios_remote_$$.log" >> "$LOG"
        rm -f "/tmp/servicios_remote_$$.log"
    }
}

#──────────────────────────────────────────────────────────────
# Main
#──────────────────────────────────────────────────────────────
main() {
    [[ "$1" == "-h" || "$1" == "--help" ]] && ayuda

    local destino="${1:-localhost}"
    cargar_servicios

    if [[ "$destino" == "localhost" || "$destino" == "127.0.0.1" ]]; then
        revisar_servicios_local "$(hostname)"
    else
        if ! [[ "$destino" =~ ^[a-zA-Z0-9._-]+@[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo " Formato inválido. Usa: localhost o usuario@IP"
            exit 1
        fi
        revisar_servicios_remoto "$destino"
    fi

    echo "──────────────────────────────────────"
    echo " Revisión completada. Log: $LOG"
}

main "$@"
