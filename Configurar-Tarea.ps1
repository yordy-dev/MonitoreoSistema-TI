# Configurar-Tarea.ps1
# Este script configura la tarea programada para ejecutar el monitoreo automaticamente

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "  Configurador de Tarea Programada - MonitorTI  " -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host ""

# Verificar si se ejecuta como administrador
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "ERROR: Este script debe ejecutarse como ADMINISTRADOR" -ForegroundColor Red
    Write-Host ""
    Write-Host "Haz clic derecho en PowerShell y selecciona 'Ejecutar como administrador'" -ForegroundColor Yellow
    Write-Host ""
    pause
    exit 1
}

# Configuracion
$taskName = "MonitoreoSistema-TI"
$scriptPath = Join-Path $PSScriptRoot "Alertas-SOporte.ps1"
$intervalMinutes = 10

Write-Host "Configuracion:" -ForegroundColor Green
Write-Host "  Nombre de tarea: $taskName"
Write-Host "  Script: $scriptPath"
Write-Host "  Intervalo: Cada $intervalMinutes minutos"
Write-Host ""

# Verificar que el script existe
if (-not (Test-Path $scriptPath)) {
    Write-Host "ERROR: No se encuentra el script: $scriptPath" -ForegroundColor Red
    pause
    exit 1
}

# Eliminar tarea existente si existe
$existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($existingTask) {
    Write-Host "Eliminando tarea existente..." -ForegroundColor Yellow
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
}

# Crear la accion (ejecutar PowerShell con el script)
$action = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptPath`""

# Crear el trigger (cada X minutos, indefinidamente)
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) `
    -RepetitionInterval (New-TimeSpan -Minutes $intervalMinutes) `
    -RepetitionDuration ([TimeSpan]::MaxValue)

# Configuracion adicional
$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -RunOnlyIfNetworkAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 5)

# Crear el principal (usuario actual)
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -RunLevel Highest

# Registrar la tarea
try {
    Register-ScheduledTask -TaskName $taskName `
        -Action $action `
        -Trigger $trigger `
        -Settings $settings `
        -Principal $principal `
        -Description "Monitoreo automatico de CPU, RAM, Disco y Servicios con alertas a Discord" `
        -ErrorAction Stop
    
    Write-Host ""
    Write-Host "EXITO: Tarea programada creada correctamente!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Detalles de la tarea:" -ForegroundColor Cyan
    Write-Host "  - Se ejecutara cada $intervalMinutes minutos"
    Write-Host "  - Primera ejecucion: $(Get-Date).AddMinutes(1).ToString('HH:mm')"
    Write-Host "  - Se ejecutara incluso con bateria"
    Write-Host "  - Se ejecutara en segundo plano (sin ventana)"
    Write-Host ""
    Write-Host "Para ver la tarea:" -ForegroundColor Yellow
    Write-Host "  1. Abre 'Programador de tareas' (taskschd.msc)"
    Write-Host "  2. Busca: $taskName"
    Write-Host ""
    Write-Host "Para desactivar/eliminar la tarea:" -ForegroundColor Yellow
    Write-Host "  Ejecuta: Unregister-ScheduledTask -TaskName '$taskName' -Confirm:`$false"
    Write-Host ""
    
}
catch {
    Write-Host ""
    Write-Host "ERROR al crear la tarea: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    pause
    exit 1
}

Write-Host "Presiona cualquier tecla para salir..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
