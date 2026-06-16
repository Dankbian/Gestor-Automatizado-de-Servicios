#!/bin/bash
# respaldo.sh — Respaldo comprimido de directorios
#
# Uso:
#   ./respaldo.sh <dir_origen> [dir_origen2 ...] <dir_destino>
#   ./respaldo.sh <dir_origen> <dir_destino> HH:MM   → programa en cron
#
# Ejemplos:
#   ./respaldo.sh /home/jorge /var/www /tmp/respaldos
#   ./respaldo.sh /home/jorge /tmp/respaldos 02:30

source "$(dirname "$0")/config.sh"

LOG="$LOG_DIR/respaldo.log"

# Ayuda
ayuda() {
    echo "Uso:"
    echo "  $0 <origen> [origen2 ...] <destino>"
    echo "  $0 <origen> <destino> HH:MM   → además programa cron"
    echo ""
    echo "Ejemplos:"
    echo "  $0 /home/jorge /tmp/respaldos"
    echo "  $0 /etc /home/jorge /tmp/respaldos 03:00"
    exit 0
}

# Validar argumentos
#   Separa: orígenes, destino y hora_cron (opcional)
parsear_argumentos() {
    [[ $# -lt 2 ]] && { echo " Se requieren al menos un origen y un destino."; ayuda; }

    HORA_CRON=""
    # Si el último arg tiene formato HH:MM es la hora de cron
    ultimo="${!#}"
    if [[ "$ultimo" =~ ^([01]?[0-9]|2[0-3]):([0-5][0-9])$ ]]; then
        HORA_CRON="$ultimo"
        set -- "${@:1:$(($#-1))}"   # quita el último arg
    fi

    # Ahora el último arg es el destino
    DESTINO="${!#}"
    ORIGENES=("${@:1:$(($#-1))}")

    [[ ${#ORIGENES[@]} -eq 0 ]] && { echo " Debes especificar al menos un directorio origen."; ayuda; }

    # Validaciones
    for src in "${ORIGENES[@]}"; do
        [[ ! -e "$src" ]] && { echo " El origen '$src' no existe."; exit 1; }
    done

    [[ ! -d "$DESTINO" ]] && {
        mkdir -p "$DESTINO" || { echo " No se pudo crear el directorio destino '$DESTINO'."; exit 1; }
    }
}

# Crear respaldo

hacer_respaldo() {
    local fecha
    fecha=$(date '+%Y-%m-%d_%H-%M-%S')

    # Nombre del archivo: respaldo_<dirs>_<fecha>.tar.gz
    local nombres=""
    for src in "${ORIGENES[@]}"; do
        nombres+="$(basename "$src")-"
    done
    nombres="${nombres%-}"   # quita guión final

    ARCHIVO_RESPALDO="$DESTINO/respaldo_${nombres}_${fecha}.tar.gz"

    echo " Creando respaldo..."
    echo " Orígenes : ${ORIGENES[*]}"
    echo " Destino  : $ARCHIVO_RESPALDO"

    tar -czf "$ARCHIVO_RESPALDO" "${ORIGENES[@]}" 2>/dev/null
    TAR_EXIT=$?

    if [[ $TAR_EXIT -ne 0 ]]; then
        echo " ⚠️  tar terminó con advertencias (puede ser normal si algunos archivos cambiaron)."
    fi
}

# Verificar y notificar
verificar_y_notificar() {
    if [[ ! -f "$ARCHIVO_RESPALDO" ]]; then
        local msg="[ x ] ERROR: no se generó el archivo de respaldo."
        echo "$msg"
        enviar_alerta "$msg"
        registrar_log "$LOG" "ERROR: no se creó $ARCHIVO_RESPALDO"
        exit 2
    fi

    local tam
    tam=$(stat -c%s "$ARCHIVO_RESPALDO" 2>/dev/null || stat -f%z "$ARCHIVO_RESPALDO" 2>/dev/null)

    if [[ -z "$tam" || "$tam" -eq 0 ]]; then
        local msg="[ x ] ERROR: el archivo de respaldo está vacío: \`$ARCHIVO_RESPALDO\`"
        echo "$msg"
        enviar_alerta "$msg"
        registrar_log "$LOG" "ERROR: archivo vacío $ARCHIVO_RESPALDO"
        exit 2
    fi

    # Convertir tamaño a formato legible
    local tam_legible
    if [[ $tam -ge 1073741824 ]]; then
        tam_legible="$(echo "scale=2; $tam/1073741824" | bc) GB"
    elif [[ $tam -ge 1048576 ]]; then
        tam_legible="$(echo "scale=2; $tam/1048576" | bc) MB"
    elif [[ $tam -ge 1024 ]]; then
        tam_legible="$(echo "scale=2; $tam/1024" | bc) KB"
    else
        tam_legible="${tam} B"
    fi

    local fecha_legible
    fecha_legible=$(date '+%d/%m/%Y %H:%M:%S')

    echo " ✅ Respaldo creado exitosamente."
    echo "    Archivo : $ARCHIVO_RESPALDO"
    echo "    Tamaño  : $tam_legible"
    echo "    Fecha   : $fecha_legible"

    local msg="✅ *Respaldo creado*
📁 Archivo: \`$(basename "$ARCHIVO_RESPALDO")\`
📦 Tamaño: $tam_legible
📂 Ruta: \`$DESTINO\`
🕐 Fecha: $fecha_legible
🖥️ Host: \`$(hostname)\`"

    enviar_alerta "$msg"
    registrar_log "$LOG" "✅ Respaldo: $ARCHIVO_RESPALDO | Tamaño: $tam_legible | Orígenes: ${ORIGENES[*]}"
}

# Programar en cron (usuario sin root)
programar_cron() {
    [[ -z "$HORA_CRON" ]] && return

    local min="${HORA_CRON#*:}"
    local hora="${HORA_CRON%:*}"
    local script_abs
    script_abs="$(realpath "$0")"

    # Construir los argumentos de la línea cron
    local args_cron=""
    for src in "${ORIGENES[@]}"; do
        args_cron+="\"$(realpath "$src")\" "
    done
    args_cron+="\"$(realpath "$DESTINO")\""

    local entrada_cron="$min $hora * * * /bin/bash \"$script_abs\" $args_cron"

    # Evitar duplicados
    if crontab -l 2>/dev/null | grep -qF "$script_abs"; then
        echo " ⚠️  Ya existe una tarea cron para este script."
        echo " Para editarla: crontab -e"
        return
    fi

    (crontab -l 2>/dev/null; echo "$entrada_cron") | crontab -
    echo " ✅ Tarea programada en cron: todos los días a las $HORA_CRON"
    echo "    Línea añadida: $entrada_cron"
    enviar_alerta "⏰ *Respaldo programado* todos los días a las *$HORA_CRON* en \`$(hostname)\`"
    registrar_log "$LOG" "⏰ Cron programado: $HORA_CRON | Script: $script_abs"
}

# Main
main() {
    [[ "$1" == "-h" || "$1" == "--help" ]] && ayuda
    parsear_argumentos "$@"
    hacer_respaldo
    verificar_y_notificar
    programar_cron
}

main "$@"
