# 1. Configuración de rutas
$apacheBin = "C:\HSLS-14.2\Apache\bin"
$serviceName = "HSLS14.2"
$maxRetries = 10

Write-Host "--- Iniciando instalación y control de reintentos ---" -ForegroundColor Cyan
Set-Location $apacheBin

# 2. Limpieza agresiva inicial
Write-Host "Limpiando registros antiguos..."
net stop $serviceName 2>$null
./httpd.exe -k uninstall -n $serviceName 2>$null

# 3. Instalación
Write-Host "Registrando el servicio..."
./httpd.exe -k install -n $serviceName

# 4. Bucle de reintentos (Máximo 10)
$retryCount = 1
$success = $false

while ($retryCount -le $maxRetries) {
    Write-Host "Intento de inicio $retryCount de $maxRetries..." -NoNewline
    
    # Intentar liberar el puerto 443 antes de cada arranque
    $port443 = Get-NetTCPConnection -LocalPort 443 -State Listen -ErrorAction SilentlyContinue
    if ($port443) {
        $pidToKill = $port443.OwningProcess
        taskkill /F /PID $pidToKill 2>$null
        Start-Sleep -Seconds 1
    }

    Start-Service -Name $serviceName -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2 # Tiempo para que el servicio intente estabilizarse

    if ((Get-Service $serviceName).Status -eq "Running") {
        Write-Host " ¡LOGRADO!" -ForegroundColor Green
        $success = $true
        break
    } else {
        Write-Host " Fallido." -ForegroundColor Yellow
        $retryCount++
    }
}

# 5. Diagnóstico de Causas si falló
if (-not $success) {
    Write-Host "`n--- DIAGNÓSTICO DE FALLO FINAL ---" -ForegroundColor Red
    
    # Causa 1: Error de Sintaxis
    Write-Host "[1] Revisando errores de configuración..." -ForegroundColor Cyan
    $syntax = ./httpd.exe -t 2>&1
    if ($syntax -match "Syntax error") {
        Write-Host "CAUSA DETECTADA: Error de sintaxis en httpd.conf." -ForegroundColor Yellow
        Write-Host "DETALLE: $syntax"
    } else {
        Write-Host "Sintaxis de Apache: OK."
    }

    # Causa 2: Puertos Ocupados (80/443)
    Write-Host "[2] Revisando conflictos de puertos..." -ForegroundColor Cyan
    $ports = 80, 443 | ForEach-Object { Get-NetTCPConnection -LocalPort $_ -State Listen -ErrorAction SilentlyContinue }
    if ($ports) {
        foreach ($p in $ports) {
            $proc = Get-Process -Id $p.OwningProcess
            Write-Host "CAUSA DETECTADA: Puerto $($p.LocalPort) sigue bloqueado por $($proc.ProcessName) (PID: $($proc.Id))" -ForegroundColor Yellow
        }
    } else {
        Write-Host "Puertos 80 y 443: Libres."
    }

    # Causa 3: Event Viewer (Errores de Windows)
    Write-Host "[3] Últimos errores en el Visor de Eventos:" -ForegroundColor Cyan
    Get-WinEvent -LogName Application -MaxEvents 5 | Where-Object { $_.Message -match "Apache" -or $_.Message -match $serviceName } | Select-Object TimeCreated, Message | Format-Table -Wrap
}

Write-Host "`nProceso finalizado."


