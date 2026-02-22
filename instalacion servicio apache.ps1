# ==========================================================
# APACHE ENTERPRISE SERVICE RECOVERY SCRIPT
# ==========================================================

$ErrorActionPreference = "Stop"

# ==============================
# CONFIGURACION
# ==============================

$ApacheServiceName = "HSLS14.2"
$ApacheBinPath     = "C:\HSLS-14.2\Apache\bin"
$LogRoot           = "C:\HSLS-14.2\Logs\Powershell"

# ==============================
# CREAR CARPETA LOG
# ==============================

if (!(Test-Path $LogRoot)) {
    New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null
}

$LogFile = Join-Path $LogRoot "ApacheRecovery_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

# ==============================
# FUNCION LOG
# ==============================

function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )

    $Time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $Line = "$Time [$Level] $Message"
    Add-Content -Path $LogFile -Value $Line
}

# Detectar cierre inesperado
Register-EngineEvent PowerShell.Exiting -Action {
    Add-Content -Path $LogFile -Value "$(Get-Date) [WARNING] PowerShell terminó."
} | Out-Null

Write-Log "==== INICIO SCRIPT RECOVERY ===="

# ==============================
# VALIDAR PUERTOS
# ==============================

function Test-Port {
    param($Port)

    $result = netstat -ano | findstr ":$Port"

    if ($result) {
        Write-Log "Puerto $Port ocupado" "WARNING"
        return $false
    }
    else {
        Write-Log "Puerto $Port libre"
        return $true
    }
}

Test-Port 80
Test-Port 443

# ==============================
# VALIDAR SINTAXIS APACHE
# ==============================

Write-Log "Validando configuración Apache"

$syntaxTest = & "$ApacheBinPath\httpd.exe" -t 2>&1

if ($LASTEXITCODE -ne 0) {
    Write-Log "Error en httpd.conf: $syntaxTest" "ERROR"
    exit 1
}
else {
    Write-Log "Sintaxis Apache OK"
}

# ==============================
# AMPLIAR TIMEOUT WINDOWS
# ==============================

Write-Log "Verificando ServicesPipeTimeout"

$timeout = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control" -Name ServicesPipeTimeout -ErrorAction SilentlyContinue

if (!$timeout) {
    New-ItemProperty `
        -Path "HKLM:\SYSTEM\CurrentControlSet\Control" `
        -Name ServicesPipeTimeout `
        -Value 180000 `
        -PropertyType DWord `
        -Force | Out-Null

    Write-Log "Timeout ampliado a 180000 ms"
}
else {
    Write-Log "Timeout ya configurado"
}

# ==============================
# INTENTAR INICIAR SERVICIO
# ==============================

try {

    Write-Log "Intentando iniciar servicio $ApacheServiceName"

    Start-Service -Name $ApacheServiceName -ErrorAction Stop
    Start-Sleep -Seconds 5

    $status = Get-Service -Name $ApacheServiceName

    if ($status.Status -eq "Running") {
        Write-Log "Servicio iniciado correctamente"
    }
    else {
        Write-Log "Servicio no inició correctamente" "ERROR"
        throw "Servicio detenido después de intento"
    }
}
catch {

    Write-Log "Error iniciando servicio: $($_.Exception.Message)" "ERROR"

    Write-Log "Intentando recuperación automática"

    # Matar procesos httpd colgados
    Get-Process httpd -ErrorAction SilentlyContinue | ForEach-Object {
        Write-Log "Terminando proceso httpd PID $($_.Id)"
        Stop-Process -Id $_.Id -Force
    }

    Start-Sleep -Seconds 3

    try {
        Start-Service -Name $ApacheServiceName
        Write-Log "Servicio iniciado después de recuperación"
    }
    catch {
        Write-Log "Falla crítica: no se pudo iniciar servicio" "CRITICAL"

        Write-EventLog -LogName Application `
            -Source "PowerShell" `
            -EntryType Error `
            -EventId 5001 `
            -Message "Apache no pudo iniciar - revisar logs"

        exit 1
    }
}

Write-Log "==== FIN SCRIPT ===="



**************************


# ==========================================================
#   APACHE REINSTALL + SISTEMA DE LOG DE RECUPERACIÓN
# ==========================================================

# ---------------------------
# CONFIGURACIÓN GLOBAL
# ---------------------------
$serviceName  = "HSLS14.2"
$apacheBin    = "C:\HSLS-14.2\Apache\bin"
$apacheExe    = Join-Path $apacheBin "httpd.exe"
$confFile     = Join-Path (Split-Path $apacheBin) "conf\httpd.conf"
$registryPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$serviceName"
$maxRetries   = 10

# LOG
$logFolder = "C:\HSLS-14.2\Logs"
if (!(Test-Path $logFolder)) { New-Item -ItemType Directory -Path $logFolder | Out-Null }

$logFile = Join-Path $logFolder ("ApacheRecovery_" + (Get-Date -Format "yyyyMMdd_HHmmss") + ".log")

# Variable para saber en qué paso quedó
$global:CurrentStep = "Inicializando"

# ==========================================================
# SISTEMA DE LOG
# ==========================================================

function Write-Log {
    param ($message)

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$timestamp] [$global:CurrentStep] $message"
    Add-Content -Path $logFile -Value $line
}

# Captura cierre inesperado del motor
Register-EngineEvent PowerShell.Exiting -Action {
    Add-Content -Path $logFile -Value "[$(Get-Date)] PowerShell se cerró inesperadamente en paso: $global:CurrentStep"
}

Start-Transcript -Path $logFile -Append

# ==========================================================
# FUNCIONES
# ==========================================================

function Clear-PreviousInstallation {
    $global:CurrentStep = "Limpieza"
    Write-Log "Iniciando limpieza profunda"

    taskkill /F /IM httpd.exe /T 2>$null
    Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
    sc.exe delete $serviceName | Out-Null

    if (Test-Path $registryPath) {
        Remove-Item -Path $registryPath -Recurse -Force -ErrorAction SilentlyContinue
    }

    Start-Sleep -Seconds 2
    Write-Log "Limpieza completada"
}

# ----------------------------------------------------------

function Install-Service {
    $global:CurrentStep = "Instalación Servicio"
    Write-Log "Registrando servicio"

    Set-Location $apacheBin
    $args = "/c `"$apacheExe`" -k install -n $serviceName"
    $proc = Start-Process "cmd.exe" -ArgumentList $args -WindowStyle Hidden -PassThru
    $proc | Wait-Process -Timeout 15 -ErrorAction SilentlyContinue

    Write-Log "Servicio registrado"
}

# ----------------------------------------------------------

function Start-ServiceWithRetries {
    $global:CurrentStep = "Inicio Servicio"
    Write-Log "Intentando iniciar servicio"

    for ($i = 1; $i -le $maxRetries; $i++) {

        Write-Log "Intento $i"

        foreach ($port in @(80,443)) {
            $conn = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
            if ($conn) {
                taskkill /F /PID $conn.OwningProcess /T 2>$null
                Write-Log "Puerto $port liberado"
            }
        }

        Start-Process "sc.exe" -ArgumentList "start", $serviceName -WindowStyle Hidden -Wait
        Start-Sleep -Seconds 3

        $svc = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
        if ($svc.Status -eq "Running") {
            Write-Log "Servicio iniciado correctamente"
            return $true
        }
    }

    Write-Log "No se pudo iniciar el servicio después de $maxRetries intentos"
    return $false
}

# ----------------------------------------------------------

function Run-Diagnostics {
    $global:CurrentStep = "Diagnóstico"
    Write-Log "Iniciando diagnóstico"

    try {
        & $apacheExe -t 2>&1 | Out-String | Write-Log
    } catch {
        Write-Log "Error en prueba de sintaxis: $($_.Exception.Message)"
    }

    foreach ($port in @(80,443)) {
        $conn = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
        if ($conn) {
            $proc = Get-Process -Id $conn.OwningProcess
            Write-Log "Puerto $port bloqueado por $($proc.ProcessName)"
        } else {
            Write-Log "Puerto $port libre"
        }
    }
}

# ==========================================================
# BLOQUE PRINCIPAL CON CAPTURA GLOBAL DE ERRORES
# ==========================================================

try {
    Write-Log "=== INICIO DEL PROCESO ==="

    Clear-PreviousInstallation
    Install-Service
    $result = Start-ServiceWithRetries

    if (-not $result) {
        Run-Diagnostics
    }

    Write-Log "Proceso finalizado correctamente"
}
catch {
    Write-Log "ERROR CRÍTICO: $($_.Exception.Message)"
    Write-Log "StackTrace: $($_.ScriptStackTrace)"
}
finally {
    Write-Log "Cierre del script"
    Stop-Transcript
}


