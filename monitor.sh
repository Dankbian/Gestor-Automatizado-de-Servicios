#!/bin/bash

# Verificar si se proporcionó un argumento (la ruta a evaluar)
if [ -z "$1" ]; then
    echo "Uso: $0 <ruta_al_recurso>"
    exit 1
fi

RECURSO="$1"

# --- NIVEL 1: Existencia ---
if [ -e "$RECURSO" ]; then
    
    # --- NIVEL 2: Tipo de Objeto ---
    if [ -d "$RECURSO" ]; then
        echo "Ruta válida: Es un directorio de sistema"
    else
        if [ -f "$RECURSO" ]; then
            
            # --- NIVEL 3: Integridad ---
            if [ -s "$RECURSO" ]; then
                
                # Contar las líneas del archivo
                LINEAS=$(wc -l < "$RECURSO")
                
                if [ "$LINEAS" -gt 100 ]; then
                    echo "Aviso: El archivo tiene contenido y excede las 100 líneas (Total: $LINEAS)."
                else
                    echo "El archivo tiene contenido y está dentro del rango normal ($LINEAS líneas)."
                fi
                
                # --- NIVEL 4: Seguridad ---
                if [ -x "$RECURSO" ]; then
                    echo "Estado: Binario/Script listo para ejecución"
                fi
                
            else
                echo "Alerta: El archivo de servicio no tiene datos"
            fi
            
        fi
    fi

else
    echo "Error: La ruta proporcionada no existe en el sistema."
    exit 1
fi
