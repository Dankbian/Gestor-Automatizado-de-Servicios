#!/bin/bash
#
# usuarios.sh — Gestión de usuarios del sistema
#
# Uso:
#   ./usuarios.sh              → modo local
#   Se ejecuta dentro de la máquina host 
#
#   ./usuarios.sh usuario@IP   → modo remoto vía SSH
#   Se conecta a un host remoto vía SSH y se ejecuta el script 

source "$(dirname "$0")/config.sh"

LOG="$LOG_DIR/usuarios.log"
IP=$(hostname -I 2>/dev/null | awk '{print $1}')

#
# --- Funciones 
#
esperar_tecla() { echo; read -rp "Presiona ENTER para continuar..."; }

validar_nombre() {
    # Nombres POSIX válidos: [a-z_][a-z0-9._-]{0,30}, no termina en '-'
    [[ "$1" =~ ^[a-z_][a-z0-9._-]{0,30}$ && "$1" != *- ]]
}

# --- Funciones para la administración de los usuarios
crear_usuario() {
    read -rp " Nombre del nuevo usuario (o escribe '6' para volver al menú): " usuario
    [[ "$usuario" == "6" ]] && return

    if ! validar_nombre "$usuario"; then
        echo " Nombre inválido. Use minúsculas, empiece con letra/guión_bajo y no termine en '-'."
        registrar_log "$LOG" "ERROR: nombre inválido '$usuario' (por $(whoami) en $IP)"
        esperar_tecla; return
    fi

    if id "$usuario" &>/dev/null; then
        echo " El usuario '$usuario' ya existe."
        enviar_alerta "[ x ] El usuario \`$usuario\` ya existe en \`$IP\` (por $(whoami))"
        registrar_log "$LOG" "ERROR: usuario '$usuario' ya existe (por $(whoami) en $IP)"
        esperar_tecla; return
    fi

    sudo useradd -m -s /bin/bash "$usuario" 2>/dev/null
    if [[ $? -ne 0 ]]; then
        echo " Error al crear el usuario."
        enviar_alerta "[ x ] Error al crear usuario \`$usuario\` en \`$IP\` (por $(whoami))"
        registrar_log "$LOG" "ERROR: fallo al crear usuario '$usuario' (por $(whoami) en $IP)"
        esperar_tecla; return
    fi

    echo " Contraseña para '$usuario':"
    if ! sudo passwd "$usuario"; then
        sudo userdel -r "$usuario" 2>/dev/null
        echo " Error en contraseña. El usuario ha sido eliminado."
        registrar_log "$LOG" "ERROR: fallo en la contraseña, usuario '$usuario' eliminado (por $(whoami) en $IP)"
        esperar_tecla; return
    fi

    echo "[ ✔ ] Usuario '$usuario' creado con directorio /home/$usuario."
    enviar_alerta "[ ✔ ] Usuario \`$usuario\` creado con /home/$usuario en \`$IP\` (por $(whoami))"
    registrar_log "$LOG" "[ ✔ ] Usuario '$usuario' creado (por $(whoami) en $IP)"
    esperar_tecla
}

eliminar_usuario() {
    read -rp " Nombre del usuario a eliminar (o escribe '6' para volver al menú): " usuario
    [[ "$usuario" == "6" ]] && return

    if ! id "$usuario" &>/dev/null; then
        echo " El usuario '$usuario' no existe."
        enviar_alerta "[ x ] El usuario \`$usuario\` no existe en \`$IP\` (por $(whoami))"
        registrar_log "$LOG" "ERROR: usuario '$usuario' no existe (por $(whoami) en $IP)"
        esperar_tecla; return
    fi

    read -rp " ¿Confirmas eliminar '$usuario' y su directorio home? [s/N]: " confirm
    [[ ! "$confirm" =~ ^[sS]$ ]] && { echo " Operación cancelada."; esperar_tecla; return; }

    if sudo userdel -r "$usuario" 2>/dev/null; then
        echo "[ ✔ ] Usuario '$usuario' eliminado del sistema."
        enviar_alerta "🗑️ Usuario \`$usuario\` eliminado en \`$IP\` (por $(whoami))"
        registrar_log "$LOG" "🗑️ Usuario '$usuario' eliminado (por $(whoami) en $IP)"
    else
        echo " Error al eliminar el usuario."
        enviar_alerta "[ ✔ ] Error al eliminar \`$usuario\` en \`$IP\` (por $(whoami))"
        registrar_log "$LOG" "ERROR: fallo al eliminar usuario '$usuario' (por $(whoami) en $IP)"
    fi
    esperar_tecla
}

modificar_usuario() {
    read -rp " Nombre actual del usuario (o escribe '6' para volver al menú): " viejo
    [[ "$viejo" == "6" ]] && return

    if ! id "$viejo" &>/dev/null; then
        echo " El usuario '$viejo' no existe."
        enviar_alerta "[ x ] El usuario \`$viejo\` no existe en \`$IP\` (por $(whoami))"
        registrar_log "$LOG" "ERROR: usuario '$viejo' no existe para modificar (por $(whoami) en $IP)"
        esperar_tecla; return
    fi

    read -rp " Nuevo nombre de usuario: " nuevo
    if ! validar_nombre "$nuevo"; then
        echo " Nombre inválido."
        esperar_tecla; return
    fi

    if id "$nuevo" &>/dev/null; then
        echo " El usuario '$nuevo' ya existe."
        enviar_alerta "[ x ] \`$nuevo\` ya existe, no se puede renombrar \`$viejo\` en \`$IP\`"
        registrar_log "$LOG" "ERROR: renombrar '$viejo' → '$nuevo' fallido, ya existe (por $(whoami) en $IP)"
        esperar_tecla; return
    fi

    sudo usermod -l "$nuevo" -d "/home/$nuevo" -m "$viejo" 2>/dev/null
    if getent group "$viejo" &>/dev/null; then
        sudo groupmod -n "$nuevo" "$viejo" 2>/dev/null
    fi

    if id "$nuevo" &>/dev/null; then
        echo "[ ✔ ] Usuario '$viejo' renombrado a '$nuevo' (home: /home/$nuevo)."
        enviar_alerta "Usuario \`$viejo\` → \`$nuevo\` en \`$IP\` (por $(whoami))"
        registrar_log "$LOG" "Usuario '$viejo' renombrado a '$nuevo' (por $(whoami) en $IP)"
    else
        echo " Error al modificar el usuario."
        enviar_alerta "[ x ] Error al modificar \`$viejo\` en \`$IP\` (por $(whoami))"
        registrar_log "$LOG" "ERROR: fallo al renombrar '$viejo' → '$nuevo' (por $(whoami) en $IP)"
    fi
    esperar_tecla
}

#
# Menú interactivo 
#

menu() {
    while true; do
        clear
        echo "╔══════════════════════════════════════════╗"
        echo "║      GESTIÓN DE USUARIOS DEL SISTEMA     ║"
        echo "╚══════════════════════════════════════════╝"
        echo " Host: $(hostname) | IP: $IP | Usuario: $(whoami)"
        echo "──────────────────────────────────────────"
        echo "  1) Crear usuario"
        echo "  2) Eliminar usuario"
        echo "  3) Modificar usuario (renombrar)"
        echo "  4) Salir"
        echo "──────────────────────────────────────────"
        read -rp " Elige una opción [1-4]: " op
        case "$op" in
            1) crear_usuario ;;
            2) eliminar_usuario ;;
            3) modificar_usuario ;;
            4) echo " Saliendo..."; exit 0 ;;
            *) echo " Opción inválida."; esperar_tecla ;;
        esac
    done
}

# Modo remoto: reenvía el script al host y lo ejecuta con SSH
modo_remoto() {
    local destino="$1"
    local host_ip="${destino##*@}"

    echo " Conectando a $destino..."
    ping -c1 -W2 "$host_ip" &>/dev/null || {
        echo " No se puede contactar con $host_ip"
        exit 1
    }

    local script_remoto="/tmp/usuarios_remote_$$.sh"
    scp -q "$0" "$destino:$script_remoto" || { echo " Error al copiar el script."; exit 1; }

    # Copia también config.sh para que source funcione
    scp -q "$(dirname "$0")/config.sh" "$destino:/tmp/config_remote_$$.sh" 2>/dev/null || true
    ssh -t "$destino" "chmod +x $script_remoto; bash $script_remoto; rm -f $script_remoto /tmp/config_remote_$$.sh"
}

# Main
main() {
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        echo "Uso: $0 [usuario@IP]"
        echo "  Sin argumento → modo local"
        echo "  Con usuario@IP → modo remoto vía SSH"
        exit 0
    fi

    if [[ -n "$1" && "$1" != "localhost" && "$1" != "127.0.0.1" ]]; then
        if [[ "$1" =~ ^[a-zA-Z0-9._-]+@[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            modo_remoto "$1"
        else
            echo " Formato inválido. Usa usuario@IP o deja vacío para local."
            exit 1
        fi
    else
        menu
    fi
}

main "$@"
