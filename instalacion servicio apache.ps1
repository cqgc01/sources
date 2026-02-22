##### nueva version
# ==========================================================
#   APACHE REINSTALL - VERSIÓN SILENCIOSA Y SIN BLOQUEOS
# ==========================================================

$serviceName  = "HSLS14.2"
$apacheBin    = "C:\HSLS-14.2\Apache\bin"
$apacheExe    = Join-Path $apacheBin "httpd.exe"
$confFile     = "C:\HSLS-14.2\Apache\conf\httpd.conf"
$logFile      = "C:\HSLS-14.2\Logs\ApacheRecovery_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$global:CurrentStep = "Inicializando"

function Write-Log {
    param ($message)
    $line = "[$(Get-Date -Format 'HH:mm:ss')] [$global:CurrentStep] $message"
    Write-Host $line -ForegroundColor Cyan
    if (!(Test-Path (Split-Path $logFile))) { New-Item -Path (Split-Path $logFile) -ItemType Directory -Force | Out-Null }
    Add-Content -Path $logFile -Value $line
}

# 1. LIMPIEZA SILENCIOSA
function Clear-Deep {
    $global:CurrentStep = "Limpieza"
    Write-Log "Limpiando procesos y servicios previos..."
    
    # Detenemos IIS/HTTP para liberar puertos 80/443
    & cmd.exe /c "net stop http /y" 2>$null
    
    # Matamos httpd.exe silenciosamente (evita el NativeCommandError)
    Stop-Process -Name "httpd" -Force -ErrorAction SilentlyContinue
    
    # Borramos servicio
    Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
    & sc.exe delete $serviceName 2>$null | Out-Null
    Start-Sleep -Seconds 2
}

# 2. AUTO-CORRECCIÓN DE SERVERNAME (Evita que se quede pegado)
function Fix-ServerName {
    $global:CurrentStep = "Configuracion"
    if (Test-Path $confFile) {
        Write-Log "Ajustando ServerName a localhost para evitar bloqueos de DNS..."
        $content = Get-Content $confFile
        # Reemplaza cualquier linea de ServerName por localhost
        $newContent = $content -replace '^#?ServerName\s+.*', 'ServerName localhost:80'
        Set-Content -Path $confFile -Value $newContent -Encoding UTF8
    }
}

# 3. REINSTALACIÓN Y ARRANQUE
function Install-And-Start {
    $global:CurrentStep = "Reinstalacion"
    Write-Log "Registrando servicio Apache..."
    Set-Location $apacheBin
    
    # Instalación
    $null = & .\httpd.exe -k install -n $serviceName 2>&1
    
    $global:CurrentStep = "Arranque"
    for ($i = 1; $i -le 5; $i++) {
        Write-Log "Intento de inicio $i de 5..."
        Start-Process "sc.exe" -ArgumentList "start", $serviceName -WindowStyle Hidden -Wait
        Start-Sleep -Seconds 4
        
        $status = (Get-Service $serviceName -ErrorAction SilentlyContinue).Status
        if ($status -eq "Running") {
            Write-Log "¡EXITO! Apache funcionando correctamente."
            return $true
        }
    }
    return $false
}

# --- EJECUCIÓN ---
try {
    Write-Log "=== INICIANDO PROCESO ANTIBLOQUEO ==="
    Clear-Deep
    Fix-ServerName
    
    if (-not (Install-And-Start)) {
        $global:CurrentStep = "Diagnostico"
        Write-Log "Fallo el arranque. Analizando sintaxis..."
        # Prueba de sintaxis rápida
        $diag = & .\httpd.exe -t 2>&1 | Out-String
        Write-Log "Resultado: $diag"
    }
} catch {
    Write-Log "ERROR: $($_.Exception.Message)"
} finally {
    Write-Log "=== PROCESO FINALIZADO ==="
}




##### 

# ==========================================================
#   APACHE REINSTALL + SISTEMA DE LOG DE RECUPERACIÓN (CORREGIDO)
#   APACHE REINSTALL + DESACTIVACIÓN DE IIS
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
$logFile      = "C:\HSLS-14.2\Logs\ApacheRecovery_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$global:CurrentStep = "Inicializando"

# ==========================================================
# SISTEMA DE LOG
# ==========================================================

function Write-Log {
    param ($message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$timestamp] [$global:CurrentStep] $message"
    $line = "[$(Get-Date -Format 'HH:mm:ss')] [$global:CurrentStep] $message"
    Write-Host $line -ForegroundColor Cyan
    $null = New-Item -Path (Split-Path $logFile) -ItemType Directory -Force
    Add-Content -Path $logFile -Value $line
}

# Captura cierre inesperado
Register-EngineEvent PowerShell.Exiting -Action {
    Add-Content -Path $logFile -Value "[$(Get-Date)] PowerShell se cerró inesperadamente en paso: $global:CurrentStep"
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

# ==========================================================
# FUNCIONES
# ==========================================================
    # Detener el controlador HTTP del sistema (libera puertos 80/443 de PID 4)
    Write-Log "Liberando sockets del Kernel (net stop http)..."
    & cmd.exe /c "net stop http /y" 2>$null
    Start-Sleep -Seconds 2
}

function Clear-PreviousInstallation {
    $global:CurrentStep = "Limpieza"
    Write-Log "Iniciando limpieza profunda"

    Write-Log "Limpiando procesos de Apache previos"
    taskkill /F /IM httpd.exe /T 2>$null
    Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
    sc.exe delete $serviceName | Out-Null

    if (Test-Path $registryPath) {
        Remove-Item -Path $registryPath -Recurse -Force -ErrorAction SilentlyContinue
    }

    Start-Sleep -Seconds 2
    Write-Log "Limpieza completada"
    if (Test-Path $registryPath) { Remove-Item -Path $registryPath -Recurse -Force -ErrorAction SilentlyContinue }
    Start-Sleep -Seconds 1
}

function Install-Service {
    $global:CurrentStep = "Instalación Servicio"
    Write-Log "Registrando servicio"

    Set-Location $apacheBin
    $global:CurrentStep = "Instalación"
    $installArgs = "/c `"$apacheExe`" -k install -n $serviceName"
    $proc = Start-Process "cmd.exe" -ArgumentList $installArgs -WindowStyle Hidden -PassThru
    $proc | Wait-Process -Timeout 15 -ErrorAction SilentlyContinue

    Write-Log "Servicio registrado (Verificar en sc query si falló el inicio)"
    Write-Log "Servicio registrado."
}

function Start-ServiceWithRetries {
    $global:CurrentStep = "Inicio Servicio"
    Write-Log "Intentando iniciar servicio"

    for ($i = 1; $i -le $maxRetries; $i++) {
        Write-Log "Intento de inicio $i de $maxRetries"
        Write-Log "Intento $i de $maxRetries"

        # Liberar puertos bloqueados
        # Doble chequeo de puertos por si IIS revive
        foreach ($port in @(80, 443)) {
            $conn = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
            if ($conn) {
                $pToKill = $conn.OwningProcess # CORRECCIÓN: No usamos la variable reservada $PID
                Write-Log "Puerto $port ocupado por PID $pToKill. Ejecutando taskkill."
                taskkill /F /PID $pToKill /T 2>$null
                Start-Sleep -Seconds 1
            if ($conn -and $conn.OwningProcess -eq 4) {
                Write-Log "Puerto $port sigue en uso por System. Re-ejecutando limpieza de HTTP..."
                & cmd.exe /c "net stop http /y" 2>$null
            }
        }

        # Intentar arrancar
        Start-Process "sc.exe" -ArgumentList "start", $serviceName -WindowStyle Hidden -Wait
        Start-Sleep -Seconds 4

        $svc = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
        if ($svc -and $svc.Status -eq "Running") {
            Write-Log "¡ÉXITO! Servicio iniciado correctamente"
        
        $svcStatus = (Get-Service $serviceName -ErrorAction SilentlyContinue).Status
        if ($svcStatus -eq "Running") {
            Write-Log "¡EXITO! Apache esta corriendo."
            return $true
        } else {
            Write-Log "Fallo intento $i. Estado actual: $svcStatus"
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

# --- BLOQUE PRINCIPAL ---
try {
    Write-Log "=== INICIO DEL PROCESO ==="

    Clear-PreviousInstallation
    Install-Service
    Write-Log "=== INICIO DE RECUPERACIÓN ==="
    Stop-IIS             # Paso 1: Quitar IIS de en medio
    Clear-PreviousInstallation # Paso 2: Limpiar Apache viejo
    Install-Service      # Paso 3: Reinstalar

    $result = Start-ServiceWithRetries

    if (-not $result) {
        Run-Diagnostics
    if (-not (Start-ServiceWithRetries)) {
        $global:CurrentStep = "Diagnóstico Final"
        Write-Log "ERROR: No se pudo estabilizar el servicio."
        Write-Log "Resultado de sintaxis de Apache:"
        & $apacheExe -t 2>&1 | Out-String | Write-Log
    }

    Write-Log "=== PROCESO FINALIZADO ==="
} catch {
    Write-Log "EXCEPCIÓN CRÍTICA: $($_.Exception.Message)"
} finally {
    Write-Log "=== FIN DEL PROCESO ==="
}
catch {
    Write-Log "ERROR CRÍTICO EN SCRIPT: $($_.Exception.Message)"
    Write-Log "Línea de error: $($_.InvocationInfo.ScriptLineNumber)"
}



