# monitor_alerts.ps1
# Monitor basico de CPU, RAM, Disco y estado de servicios.
# Envia alertas a Discord via Webhook cuando un umbral se supera.
# Genera log diario en carpeta: C:\MonitoringLogs\

# CONFIGURACION - EDITA ESTO
$discordWebhookUrl = "https://discord.com/api/webhooks/1441581492240388270/HTW_GBUDdEWFc3ILKoLVeM7nuTV_srB70VRqt8XJOT8tjvvX_brrRLZoeottMYxmMj2p"
$logFolder = "C:\MonitoringLogs"
$lowDiskThresholdPercent = 10
$highCpuThresholdPercent = 90
$highMemoryThresholdPercent = 90
$alertCooldownMinutes = 30
$servicesToCheck = @("Spooler", "wuauserv")

# FUNCIONES
function Initialize-LogFolder {
    param([string]$Path)
    if (-not (Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Write-MonitorLog {
    param([string]$Text)
    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $line = "$timestamp`t$Text"
    $logFile = Join-Path $logFolder ("monitor_" + (Get-Date).ToString("yyyyMMdd") + ".log")
    Add-Content -Path $logFile -Value $line
}

function Test-AlertCooldown {
    param([string]$AlertType)
    $stateFile = Join-Path $logFolder "alert_state.json"
    $now = Get-Date
    
    # Cargar estado de alertas previas
    if (Test-Path $stateFile) {
        try {
            $state = Get-Content $stateFile -Raw | ConvertFrom-Json
        }
        catch {
            $state = @{}
        }
    }
    else {
        $state = @{}
    }
    
    # Verificar si ya se envio esta alerta recientemente
    if ($state.$AlertType) {
        $lastAlert = [DateTime]::Parse($state.$AlertType)
        $minutesSince = ($now - $lastAlert).TotalMinutes
        if ($minutesSince -lt $alertCooldownMinutes) {
            Write-MonitorLog "ALERTA '$AlertType' omitida (cooldown: $([math]::Round($minutesSince,1)) min de $alertCooldownMinutes min)"
            return $false
        }
    }
    
    # Actualizar estado
    if (-not $state) { $state = @{} }
    $state | Add-Member -NotePropertyName $AlertType -NotePropertyValue $now.ToString("o") -Force
    $state | ConvertTo-Json | Set-Content $stateFile
    return $true
}

function Send-DiscordAlert {
    param(
        [string]$Title,
        [string]$Message,
        [string]$AlertType,
        [hashtable]$ExtraFields = @{}
    )
    
    # Verificar cooldown
    if (-not (Test-AlertCooldown -AlertType $AlertType)) {
        return
    }
    
    # Configurar color y emoji segun tipo de alerta
    $alertConfig = @{
        'CPU_HIGH'     = @{ Color = 16744192; Emoji = ':fire:' }
        'MEMORY_HIGH'  = @{ Color = 16744192; Emoji = ':warning:' }
        'DISK_LOW'     = @{ Color = 15158332; Emoji = ':floppy_disk:' }
        'SERVICE_DOWN' = @{ Color = 15158332; Emoji = ':wrench:' }
    }
    
    $config = $alertConfig[$AlertType]
    if (-not $config) {
        $config = @{ Color = 15158332; Emoji = ':warning:' }
    }
    
    # Obtener informacion del sistema
    $computerName = $env:COMPUTERNAME
    $userName = $env:USERNAME
    $timestamp = Get-Date -Format "dd/MM/yyyy HH:mm:ss"
    
    # Construir campos del embed
    $fields = @(
        @{
            name   = ":desktop: Equipo"
            value  = "``$computerName``"
            inline = $true
        }
        @{
            name   = ":bust_in_silhouette: Usuario"
            value  = "``$userName``"
            inline = $true
        }
        @{
            name   = ":clock1: Hora"
            value  = "``$timestamp``"
            inline = $true
        }
    )
    
    # Agregar campos extra si existen
    foreach ($key in $ExtraFields.Keys) {
        $fields += @{
            name   = $key
            value  = $ExtraFields[$key]
            inline = $false
        }
    }
    
    try {
        $body = @{
            username   = ":robot: Monitor TI"
            avatar_url = "https://cdn-icons-png.flaticon.com/512/3281/3281289.png"
            embeds     = @(
                @{
                    author      = @{
                        name     = "Sistema de Monitoreo"
                        icon_url = "https://cdn-icons-png.flaticon.com/512/2920/2920277.png"
                    }
                    title       = "$($config.Emoji) $Title"
                    description = "**Detalles del Problema:**`n$Message"
                    color       = $config.Color
                    fields      = $fields
                    footer      = @{
                        text     = "Monitoreo Automatico - $computerName"
                        icon_url = "https://cdn-icons-png.flaticon.com/512/1828/1828791.png"
                    }
                    timestamp   = (Get-Date).ToUniversalTime().ToString("o")
                }
            )
        } | ConvertTo-Json -Depth 10

        Invoke-RestMethod -Uri $discordWebhookUrl -Method Post -Body $body -ContentType 'application/json' -ErrorAction Stop
        Write-MonitorLog "ALERTA enviada: $Title"
    }
    catch {
        Write-MonitorLog "ERROR enviando alerta a Discord: $($_.Exception.Message)"
    }
}

# INICIO
Initialize-LogFolder -Path $logFolder
Write-MonitorLog "Inicio de monitoreo."

# METRICAS
# CPU - promediamos 3 muestras para mayor precision
try {
    Write-MonitorLog "Tomando muestras de CPU..."
    $cpuSamples = @()
    for ($i = 1; $i -le 3; $i++) {
        # Intentar primero en español, luego en ingles
        try {
            $sample = (Get-Counter '\Procesador(_Total)\% de tiempo de procesador' -ErrorAction Stop).CounterSamples.CookedValue
        }
        catch {
            $sample = (Get-Counter '\Processor(_Total)\% Processor Time' -ErrorAction Stop).CounterSamples.CookedValue
        }
        $cpuSamples += $sample
        if ($i -lt 3) { Start-Sleep -Milliseconds 500 }
    }
    $cpuPct = [math]::Round(($cpuSamples | Measure-Object -Average).Average, 1)
    Write-MonitorLog "CPU promedio de 3 muestras: $cpuPct%"
}
catch {
    $cpuPct = -1
    Write-MonitorLog "ERROR al leer CPU: $($_.Exception.Message)"
}

# Memoria
$os = Get-CimInstance -ClassName Win32_OperatingSystem
$totalMemoryMB = [math]::Round($os.TotalVisibleMemorySize / 1024, 1)
$freeMemoryMB = [math]::Round($os.FreePhysicalMemory / 1024, 1)
$usedMemoryPct = [math]::Round((($totalMemoryMB - $freeMemoryMB) / $totalMemoryMB) * 100, 1)

# Disco - chequea todas las unidades fijas (C:, D:, etc)
$disks = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" | Select-Object DeviceID, FreeSpace, Size
$diskAlerts = @()
foreach ($d in $disks) {
    if ($d.Size -and $null -ne $d.FreeSpace) {
        $freePct = [math]::Round((($d.FreeSpace / $d.Size) * 100), 1)
        if ($freePct -lt $lowDiskThresholdPercent) {
            $diskAlerts += "$($d.DeviceID) libre: $freePct%"
        }
    }
}

# Servicios
$serviceAlerts = @()
foreach ($s in $servicesToCheck) {
    try {
        $svc = Get-Service -Name $s -ErrorAction Stop
        if ($svc.Status -ne 'Running') {
            $serviceAlerts += "$s : $($svc.Status)"
        }
    }
    catch {
        $serviceAlerts += "$s : No encontrado"
    }
}

# ARMAR MENSAJE Y CONDICIONES
$messages = @()
if ($cpuPct -ge 0) {
    $messages += "CPU: $cpuPct% | Memoria usada: $usedMemoryPct% ($freeMemoryMB MB libres)"
    if ($cpuPct -ge $highCpuThresholdPercent) {
        $extraFields = @{
            ":bar_chart: Uso de CPU"            = "``$cpuPct%`` (Umbral: $highCpuThresholdPercent%)"
            ":chart_with_upwards_trend: Estado" = "**CRITICO** - Uso excesivo del procesador"
            ":bulb: Recomendacion"              = "Revisar procesos en ejecucion (Administrador de tareas)"
        }
        Send-DiscordAlert -Title "CPU Sobrecargada" -Message "El procesador esta funcionando al **$cpuPct%** de su capacidad (promedio de 3 muestras en 1 segundo)." -AlertType "CPU_HIGH" -ExtraFields $extraFields
    }
    if ($usedMemoryPct -ge $highMemoryThresholdPercent) {
        $extraFields = @{
            ":floppy_disk: Memoria Usada"       = "``$usedMemoryPct%`` (Umbral: $highMemoryThresholdPercent%)"
            ":package: RAM Disponible"          = "``$freeMemoryMB MB`` de ``$totalMemoryMB MB``"
            ":chart_with_upwards_trend: Estado" = "**ADVERTENCIA** - Memoria casi agotada"
            ":bulb: Recomendacion"              = "Cerrar aplicaciones innecesarias o reiniciar el sistema"
        }
        Send-DiscordAlert -Title "Memoria RAM Critica" -Message "La memoria RAM esta al **$usedMemoryPct%** de uso. Solo quedan **$freeMemoryMB MB** disponibles." -AlertType "MEMORY_HIGH" -ExtraFields $extraFields
    }
}
else {
    $messages += "CPU: error al leer metrica"
}

if ($diskAlerts.Count -gt 0) {
    $diskText = "Discos con poco espacio: " + ($diskAlerts -join "; ")
    $messages += $diskText
    $extraFields = @{
        ":cd: Discos Afectados"             = ($diskAlerts -join "`n")
        ":chart_with_upwards_trend: Estado" = "**CRITICO** - Espacio en disco insuficiente"
        ":bulb: Recomendacion"              = "Liberar espacio eliminando archivos temporales o programas no utilizados"
    }
    Send-DiscordAlert -Title "Espacio en Disco Bajo" -Message "Uno o mas discos estan quedandose sin espacio (menos del **$lowDiskThresholdPercent%** libre)." -AlertType "DISK_LOW" -ExtraFields $extraFields
}

if ($serviceAlerts.Count -gt 0) {
    $svcText = "Servicios con problema: " + ($serviceAlerts -join "; ")
    $messages += $svcText
    $servicesList = ($serviceAlerts | ForEach-Object { "- $_" }) -join "`n"
    $extraFields = @{
        ":wrench: Servicios Afectados"      = $servicesList
        ":chart_with_upwards_trend: Estado" = "**ADVERTENCIA** - Servicios detenidos o no encontrados"
        ":bulb: Recomendacion"              = "Verificar si los servicios deben estar activos e iniciarlos manualmente si es necesario"
    }
    Send-DiscordAlert -Title "Servicios de Windows Detenidos" -Message "Se detectaron **$($serviceAlerts.Count)** servicio(s) que no estan en ejecucion." -AlertType "SERVICE_DOWN" -ExtraFields $extraFields
}

# LOG FINAL
$fullMsg = $messages -join " | "
Write-MonitorLog $fullMsg
Write-MonitorLog "Fin de ejecucion."
