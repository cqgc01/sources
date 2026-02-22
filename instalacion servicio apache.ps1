
Id     Name            PSJobTypeName   State         HasMoreData     Location             Command                  
--     ----            -------------   -----         -----------     --------             -------                  
11     PowerShell.E...                 NotStarted    False                                ...                      
Transcript started, output file is C:\HSLS-14.2\Logs\Powershell\ApacheRecovery_20260222_123725.log
Add-Content : The process cannot access the file 'C:\HSLS-14.2\Logs\Powershell\ApacheRecovery_20260222_123725.log' because it is being used by another process.
At line:33 char:5
+     Add-Content -Path $logFile -Value $line
+     ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    + CategoryInfo          : WriteError: (C:\HSLS-14.2\Lo...0222_123725.log:String) [Add-Content], IOException
    + FullyQualifiedErrorId : GetContentWriterIOError,Microsoft.PowerShell.Commands.AddContentCommand
 
Add-Content : The process cannot access the file 'C:\HSLS-14.2\Logs\Powershell\ApacheRecovery_20260222_123725.log' because it is being used by another process.
At line:33 char:5
+     Add-Content -Path $logFile -Value $line
+     ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    + CategoryInfo          : WriteError: (C:\HSLS-14.2\Lo...0222_123725.log:String) [Add-Content], IOException
    + FullyQualifiedErrorId : GetContentWriterIOError,Microsoft.PowerShell.Commands.AddContentCommand
 
SUCCESS: The process with PID 24432 (child process of PID 16504) has been terminated.
Add-Content : The process cannot access the file 'C:\HSLS-14.2\Logs\Powershell\ApacheRecovery_20260222_123725.log' because it is being used by another process.
At line:33 char:5
+     Add-Content -Path $logFile -Value $line
+     ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    + CategoryInfo          : WriteError: (C:\HSLS-14.2\Lo...0222_123725.log:String) [Add-Content], IOException
    + FullyQualifiedErrorId : GetContentWriterIOError,Microsoft.PowerShell.Commands.AddContentCommand
 
Add-Content : The process cannot access the file 'C:\HSLS-14.2\Logs\Powershell\ApacheRecovery_20260222_123725.log' because it is being used by another process.
At line:33 char:5
+     Add-Content -Path $logFile -Value $line
+     ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    + CategoryInfo          : WriteError: (C:\HSLS-14.2\Lo...0222_123725.log:String) [Add-Content], IOException
    + FullyQualifiedErrorId : GetContentWriterIOError,Microsoft.PowerShell.Commands.AddContentCommand


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

