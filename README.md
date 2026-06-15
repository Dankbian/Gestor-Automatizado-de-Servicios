# Gestor-Automatizado-de-Servicios
Gestor Automatizado de Servicios con Notificación por Telegram

# Estructura
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
