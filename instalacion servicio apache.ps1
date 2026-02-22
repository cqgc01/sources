# ==========================================================
#   APACHE REINSTALL - FILTRO AGRESIVO DE PUERTO 443
# ==========================================================

$serviceName  = "HSLS14.2"
$apacheBin    = "C:\HSLS-14.2\Apache\bin"
$apacheExe    = Join-Path $apacheBin "httpd.exe"
$logFile      = "C:\HSLS-14.2\Logs\ApacheRecovery_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$global:CurrentStep = "Inicializando"

function Write-Log {
    param ($message)
    $line = "[$(Get-Date -Format 'HH:mm:ss')] [$global:CurrentStep] $message"
    Write-Host $line -ForegroundColor Cyan
    $null = New-Item -Path (Split-Path $logFile) -ItemType Directory -Force
    Add-Content -Path $logFile -Value $line
}

# --- FUNCIÓN: LIMPIEZA TOTAL DE PUERTOS Y PROCESOS ---
function Kill-ConflictiveProcesses {
    $global:CurrentStep = "Limpieza de Puertos"
    Write-Log "Buscando procesos bloqueando el puerto 443..."

    # 1. Matar por nombre de imagen (Cualquier httpd.exe suelto)
    Write-Log "Terminando cualquier instancia de httpd.exe..."
    taskkill /F /IM httpd.exe /T 2>$null
    Start-Sleep -Seconds 1

    # 2. Matar específicamente al dueño del puerto 443
    $conn = Get-NetTCPConnection -LocalPort 443 -State Listen -ErrorAction SilentlyContinue
    if ($conn) {
        $pId = $conn.OwningProcess
        $pName = (Get-Process -Id $pId -ErrorAction SilentlyContinue).Name
        Write-Log "Puerto 443 ocupado por PID $pId ($pName). Ejecutando TASKKILL forzado..."
        
        # Intentar detener el servicio IIS si es el dueño (PID 4 suele ser System/IIS)
        if ($pId -eq 4) {
            & cmd.exe /c "net stop http /y" 2>$null
        } else {
            taskkill /F /PID $pId /T 2>$null
        }
        Start-Sleep -Seconds 2
    } else {
        Write-Log "Puerto 443 libre."
    }
}

function Reinstall-And-Start {
    $global:CurrentStep = "Reinstalación"
    Write-Log "Eliminando servicio viejo y registrando nuevo..."
    
    # Desinstalar y borrar rastro en registro
    Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
    sc.exe delete $serviceName | Out-Null
    
    # Instalación limpia
    $installArgs = "/c `"$apacheExe`" -k install -n $serviceName"
    $p = Start-Process "cmd.exe" -ArgumentList $installArgs -WindowStyle Hidden -PassThru
    $p | Wait-Process -Timeout 10 -ErrorAction SilentlyContinue
    Write-Host "Servicio registrado." -ForegroundColor Gray

    $global:CurrentStep = "Arranque"
    for ($i = 1; $i -le 5; $i++) {
        Write-Log "Intento de inicio $i..."
        
        # Lanzar inicio
        Start-Process "sc.exe" -ArgumentList "start", $serviceName -WindowStyle Hidden -Wait
        Start-Sleep -Seconds 5
        
        $status = (Get-Service $serviceName -ErrorAction SilentlyContinue).Status
        if ($status -eq "Running") {
            Write-Log "¡LOGRADO! Apache esta corriendo en el puerto 443."
            return $true
        } else {
            Write-Log "Fallo intento $i. Estado: $status"
            # Si falló, volvemos a intentar matar cualquier httpd que se haya quedado pegado
            taskkill /F /IM httpd.exe /T 2>$null
        }
    }
    return $false
}

# --- BLOQUE PRINCIPAL ---
try {
    Write-Log "=== INICIO DE OPERACIÓN DE RESCATE ==="
    
    # Paso Crítico: Asegurar que nada use el 443 antes de empezar
    Kill-ConflictiveProcesses
    
    if (-not (Reinstall-And-Start)) {
        $global:CurrentStep = "Diagnóstico Final"
        Write-Log "ERROR: El servicio no sube. Revisando sintaxis de archivos..."
        
        # Prueba de sintaxis con timeout para que no se cuelgue el script
        $syntaxTest = & $apacheExe -t 2>&1 | Out-String
        Write-Log "Resultado httpd -t:`n$syntaxTest"
    }
} catch {
    Write-Log "ERROR CRÍTICO: $($_.Exception.Message)"
} finally {
    Write-Log "=== FIN ==="
}
