# ==========================================================
#   APACHE REINSTALL + SISTEMA DE LOG DE RECUPERACIÓN (CORREGIDO)
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
    Write-Host $line -ForegroundColor Cyan
    Add-Content -Path $logFile -Value $line
}

# Captura cierre inesperado
Register-EngineEvent PowerShell.Exiting -Action {
    Add-Content -Path $logFile -Value "[$(Get-Date)] PowerShell se cerró inesperadamente en paso: $global:CurrentStep"
}

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

function Install-Service {
    $global:CurrentStep = "Instalación Servicio"
    Write-Log "Registrando servicio"

    Set-Location $apacheBin
    $installArgs = "/c `"$apacheExe`" -k install -n $serviceName"
    $proc = Start-Process "cmd.exe" -ArgumentList $installArgs -WindowStyle Hidden -PassThru
    $proc | Wait-Process -Timeout 15 -ErrorAction SilentlyContinue

    Write-Log "Servicio registrado (Verificar en sc query si falló el inicio)"
}

function Start-ServiceWithRetries {
    $global:CurrentStep = "Inicio Servicio"
    Write-Log "Intentando iniciar servicio"

    for ($i = 1; $i -le $maxRetries; $i++) {
        Write-Log "Intento de inicio $i de $maxRetries"

        # Liberar puertos bloqueados
        foreach ($port in @(80, 443)) {
            $conn = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
            if ($conn) {
                $pToKill = $conn.OwningProcess # CORRECCIÓN: No usamos la variable reservada $PID
                Write-Log "Puerto $port ocupado por PID $pToKill. Ejecutando taskkill."
                taskkill /F /PID $pToKill /T 2>$null
                Start-Sleep -Seconds 1
            }
        }

        # Intentar arrancar
        Start-Process "sc.exe" -ArgumentList "start", $serviceName -WindowStyle Hidden -Wait
        Start-Sleep -Seconds 4

        $svc = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
        if ($svc -and $svc.Status -eq "Running") {
            Write-Log "¡ÉXITO! Servicio iniciado correctamente"
            return $true
        }
    }

    Write-Log "No se pudo iniciar el servicio tras los reintentos."
    return $false
}

function Run-Diagnostics {
    $global:CurrentStep = "Diagnóstico"
    Write-Log "Iniciando diagnóstico profundo de fallo"

    # Prueba de sintaxis con protección
    try {
        Write-Log "Resultado de sintaxis (httpd -t):"
        $diag = & $apacheExe -t 2>&1 | Out-String
        Write-Log $diag
    } catch {
        Write-Log "Error ejecutando diagnóstico: $($_.Exception.Message)"
    }

    # Revisión final de puertos
    foreach ($port in @(80, 443)) {
        $conn = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
        if ($conn) {
            $pName = (Get-Process -Id $conn.OwningProcess -ErrorAction SilentlyContinue).Name
            Write-Log "Puerto $port sigue bloqueado por: $pName"
        }
    }
}

# ==========================================================
# BLOQUE PRINCIPAL
# ==========================================================

try {
    Write-Log "=== INICIO DEL PROCESO ==="

    Clear-PreviousInstallation
    Install-Service
    
    $result = Start-ServiceWithRetries

    if (-not $result) {
        Run-Diagnostics
    }

    Write-Log "=== PROCESO FINALIZADO ==="
}
catch {
    Write-Log "ERROR CRÍTICO EN SCRIPT: $($_.Exception.Message)"
    Write-Log "Línea de error: $($_.InvocationInfo.ScriptLineNumber)"
}
