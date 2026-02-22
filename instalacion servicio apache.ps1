# ==========================================================
#   APACHE REINSTALL + DESACTIVACIÓN DE IIS
# ==========================================================

$serviceName  = "HSLS14.2"
$apacheBin    = "C:\HSLS-14.2\Apache\bin"
$apacheExe    = Join-Path $apacheBin "httpd.exe"
$registryPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$serviceName"
$maxRetries   = 10
$logFile      = "C:\HSLS-14.2\Logs\ApacheRecovery_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$global:CurrentStep = "Inicializando"

function Write-Log {
    param ($message)
    $line = "[$(Get-Date -Format 'HH:mm:ss')] [$global:CurrentStep] $message"
    Write-Host $line -ForegroundColor Cyan
    $null = New-Item -Path (Split-Path $logFile) -ItemType Directory -Force
    Add-Content -Path $logFile -Value $line
}

# --- NUEVA FUNCIÓN PARA MATAR IIS ---
function Stop-IIS {
    $global:CurrentStep = "Deteniendo IIS"
    Write-Log "Detectando presencia de IIS..."
    
    # Detener el servicio de publicación World Wide Web (W3SVC)
    if (Get-Service W3SVC -ErrorAction SilentlyContinue) {
        Write-Log "IIS (W3SVC) detectado. Deteniendo..."
        Stop-Service W3SVC -Force -Confirm:$false -ErrorAction SilentlyContinue
    }

    # Detener el controlador HTTP del sistema (libera puertos 80/443 de PID 4)
    Write-Log "Liberando sockets del Kernel (net stop http)..."
    & cmd.exe /c "net stop http /y" 2>$null
    Start-Sleep -Seconds 2
}

function Clear-PreviousInstallation {
    $global:CurrentStep = "Limpieza"
    Write-Log "Limpiando procesos de Apache previos"
    taskkill /F /IM httpd.exe /T 2>$null
    Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
    sc.exe delete $serviceName | Out-Null
    if (Test-Path $registryPath) { Remove-Item -Path $registryPath -Recurse -Force -ErrorAction SilentlyContinue }
    Start-Sleep -Seconds 1
}

function Install-Service {
    $global:CurrentStep = "Instalación"
    $installArgs = "/c `"$apacheExe`" -k install -n $serviceName"
    $proc = Start-Process "cmd.exe" -ArgumentList $installArgs -WindowStyle Hidden -PassThru
    $proc | Wait-Process -Timeout 15 -ErrorAction SilentlyContinue
    Write-Log "Servicio registrado."
}

function Start-ServiceWithRetries {
    $global:CurrentStep = "Inicio Servicio"
    for ($i = 1; $i -le $maxRetries; $i++) {
        Write-Log "Intento $i de $maxRetries"

        # Doble chequeo de puertos por si IIS revive
        foreach ($port in @(80, 443)) {
            $conn = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
            if ($conn -and $conn.OwningProcess -eq 4) {
                Write-Log "Puerto $port sigue en uso por System. Re-ejecutando limpieza de HTTP..."
                & cmd.exe /c "net stop http /y" 2>$null
            }
        }

        Start-Process "sc.exe" -ArgumentList "start", $serviceName -WindowStyle Hidden -Wait
        Start-Sleep -Seconds 4
        
        $svcStatus = (Get-Service $serviceName -ErrorAction SilentlyContinue).Status
        if ($svcStatus -eq "Running") {
            Write-Log "¡EXITO! Apache esta corriendo."
            return $true
        } else {
            Write-Log "Fallo intento $i. Estado actual: $svcStatus"
        }
    }
    return $false
}

# --- BLOQUE PRINCIPAL ---
try {
    Write-Log "=== INICIO DE RECUPERACIÓN ==="
    Stop-IIS             # Paso 1: Quitar IIS de en medio
    Clear-PreviousInstallation # Paso 2: Limpiar Apache viejo
    Install-Service      # Paso 3: Reinstalar
    
    if (-not (Start-ServiceWithRetries)) {
        $global:CurrentStep = "Diagnóstico Final"
        Write-Log "ERROR: No se pudo estabilizar el servicio."
        Write-Log "Resultado de sintaxis de Apache:"
        & $apacheExe -t 2>&1 | Out-String | Write-Log
    }
} catch {
    Write-Log "EXCEPCIÓN CRÍTICA: $($_.Exception.Message)"
} finally {
    Write-Log "=== FIN DEL PROCESO ==="
}
