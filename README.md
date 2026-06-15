# Gestor-Automatizado-de-Servicios
Gestor Automatizado de Servicios con Notificación por Telegram

---

## Estructura del proyecto

```

Gestor-Automaatizado-de-Servucios/
├── config.sh ← TOKEN, CHAT_ID, enviar_alerta(), registrar_log()
├── usuarios.sh ← gestión de cuentas del sistema
├── respaldo.sh ← compresión y programación de respaldos
├── monitoreo.sh ← CPU y disco con umbrales configurables
├── servicios.sh ← revisión y reinicio de servicios
├── remoto.sh ← distribución y ejecución remota de scripts
├── red.sh ← diagnóstico de conectividad y puertos
├── inventario.sh ← recopilación de hardware y OS
├── config.txt ← servicios (para servicios.sh) y hosts+puertos (para red.sh)
├── hosts.txt ← usuario@IP por línea (para remoto.sh)
└── logs/
├── usuarios.log · respaldo.log · monitoreo.log · servicios.log
└── remoto.log · red.log · inventario.log
```


---

## Configuración inicial

### 1. Editar config.sh
Actualiza el token y chat ID de Telegram:
```bash
TELEGRAM_TOKEN="tu_token_aqui"
TELEGRAM_CHAT="tu_chat_id_aqui"
```

### 2. Dar permisos de ejecución
```bash
chmod +x *.sh
```

### 3. Editar config.txt
Agrega tus servicios y hosts de red en las secciones correspondientes.

### 4. Editar hosts.txt
Agrega los hosts remotos en formato `usuario@IP`.

---

## Scripts

### usuarios.sh — 12 pts
Gestión interactiva de usuarios del sistema.

```bash
./usuarios.sh                  # modo local
./usuarios.sh user@192.168.1.67  # modo remoto
```

- Menú: crear, eliminar, modificar (renombrar)
- Valida existencia antes de actuar
- Notifica por Telegram cada acción
- Log: `logs/usuarios.log`

---

### respaldo.sh — 12 pts
Compresión de directorios con tar y programación en cron.

```bash
./respaldo.sh /home/user /tmp/respaldos            # respaldo inmediato
./respaldo.sh /etc /home /tmp/respaldos             # múltiples orígenes
./respaldo.sh /home/user /tmp/respaldos 02:30      # respaldo + cron diario 2:30am
```

- Verifica que el archivo exista y tenga tamaño > 0
- Notifica ruta, tamaño y fecha a Telegram
- Log: `logs/respaldo.log`

---

### monitoreo.sh — 10 pts
Monitoreo de CPU y disco con umbrales configurables.

```bash
./monitoreo.sh localhost                  # umbrales default (70%)
./monitoreo.sh localhost 85 90            # umbral CPU=85%, disco=90%
./monitoreo.sh user@192.168.1.50 70 80  # modo remoto
```

- Registra CADA lectura en log, con o sin alerta
- Alerta Telegram solo cuando se supera el umbral
- Log: `logs/monitoreo.log`

---

### servicios.sh — 10 pts
Revisión y reinicio automático de servicios listados en config.txt.

```bash
./servicios.sh                        # modo local
./servicios.sh localhost              # modo local explícito
./servicios.sh user@192.168.1.87    # modo remoto
```

- Reinicia automáticamente servicios inactivos
- Notifica a Telegram el resultado de cada reinicio
- Log: `logs/servicios.log`

---

### remoto.sh — 10 pts
Copia y ejecuta un script en todos los hosts de hosts.txt.

```bash
./remoto.sh inventario.sh
./remoto.sh monitoreo.sh localhost 80 85
```

- Copia el script con scp a cada host
- Ejecuta vía SSH y captura la salida
- Genera reporte individual en `reportes/reporte_HOST_TIMESTAMP.log`
- Notifica resultado por Telegram
- Log: `logs/remoto.log`

---

### red.sh — 10 pts
Diagnóstico de conectividad y puertos desde config.txt sección `[red]`.

```bash
./red.sh
```

Formato en config.txt:
```
[red]
192.168.1.1:22,80,443
192.168.1.50
google.com:443
```

Clasificaciones:
- ✅ **ACCESIBLE** — ping OK y todos los puertos abiertos
- ⚠️ **PARCIAL** — ping OK pero algún puerto cerrado
- ❌ **SIN RESPUESTA** — no responde al ping

Log: `logs/red.log`

---

### inventario.sh — 10 pts
Inventario completo de hardware y sistema operativo.

```bash
./inventario.sh            # interactivo (muestra en pantalla)
./inventario.sh --cron     # silencioso, ideal para cron
```

Recopila: CPU (modelo, núcleos), RAM (total, usada, libre), disco por partición,
OS, kernel, hostname, paquetes instalados, servicios activos/fallidos.

Reporte guardado en: `/var/log/inventario_FECHA.txt`
(o en `logs/` si no hay permisos)

#### Programar en cron:
```bash
# Inventario diario a las 6am
crontab -e
0 6 * * * /ruta/completa/ProyectoProgramacion/inventario.sh --cron
```

Log: `logs/inventario.log`

---

## Dependencias

| Herramienta | Uso |
|-------------|-----|
| `curl`      | Notificaciones Telegram |
| `tar`       | Compresión de respaldos |
| `ssh`/`scp` | Ejecución y copia remota |
| `systemctl` | Control de servicios |
| `nc`        | Verificación de puertos (red.sh) |
| `ping`      | Conectividad básica |
| `bc`        | Cálculo de porcentajes |

```bash
# Instalar dependencias en Debian:
sudo apt install curl openssh-client netcat-openbsd bc
```
