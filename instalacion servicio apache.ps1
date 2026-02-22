# 1. Configuración de rutas
$apacheBin = "C:\HSLS-14.2\Apache\bin"
$serviceName = "HSLS14.2"
$maxRetries = 10

# 1. Configuración
$apacheBin = "C:\HSL14.2\Apache\bin"
$serviceName = "HSL14.2"
$maxRetries = 10
$registryPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$serviceName"

Write-Host "--- Iniciando Limpieza Profunda y Reinstalación de Apache ---" -ForegroundColor Cyan
Set-Location $apacheBin

# 2. BORRADO TOTAL (Servicio, SC y Regedit)
Write-Host "[1/5] Ejecutando limpieza de rastro previo..." -ForegroundColor White

if (Get-Service $serviceName -ErrorAction SilentlyContinue) {
    Write-Host "    - Deteniendo y desinstalando servicio..."
    Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
    ./httpd.exe -k uninstall -n $serviceName 2>$null
    Start-Sleep -Seconds 1
}

# Borrado en Registro (Regedit)
if (Test-Path $registryPath) {
    Write-Host "    - Eliminando rastro en Regedit ($registryPath)..." -ForegroundColor Yellow
    Remove-Item -Path $registryPath -Recurse -Force -ErrorAction SilentlyContinue
}

# Borrado con SC (Base de datos de servicios)
sc.exe delete $serviceName | Out-Null
Write-Host "[OK] Limpieza total completada." -ForegroundColor Green

# 3. Instalación Nueva
Write-Host "[2/5] Registrando nueva instancia del servicio..."
./httpd.exe -k install -n $serviceName

# 4. Bucle de 10 reintentos con Taskkill
Write-Host "[3/5] Iniciando fase de arranque (Máx 10 intentos)..."
$success = $false

for ($i = 1; $i -le $maxRetries; $i++) {
    # Verificar y matar proceso en puerto 443 antes de intentar subir
    $port443 = Get-NetTCPConnection -LocalPort 443 -State Listen -ErrorAction SilentlyContinue
    if ($port443) {
        $pid = $port443.OwningProcess
        Write-Host "    - Intento $i: Puerto 443 ocupado por PID $pid. Ejecutando taskkill /F..." -ForegroundColor Gray
        taskkill /F /PID $pid 2>$null
        Start-Sleep -Seconds 1
    }

    Start-Service -Name $serviceName -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    if ((Get-Service $serviceName -ErrorAction SilentlyContinue).Status -eq "Running") {
        Write-Host " -> ¡EXITOSO! Servicio iniciado en el intento $i." -ForegroundColor Green
        $success = $true
        break
    } else {
        Write-Host " -> Intento $i fallido..." -ForegroundColor Yellow
    }
}

# 5. Diagnóstico Detallado Final
if (-not $success) {
    Write-Host "`n[4/5] DIAGNÓSTICO DE FALLO CRÍTICO" -ForegroundColor Red
    Write-Host "============================================="
    
    Write-Host "[+] ERROR DE SINTAXIS (httpd -t):" -ForegroundColor Cyan
    ./httpd.exe -t 2>&1 | Write-Host -ForegroundColor Yellow

    Write-Host "`n[+] ESTADO DE PUERTOS:" -ForegroundColor Cyan
    80, 443 | ForEach-Object {
        $c = Get-NetTCPConnection -LocalPort $_ -State Listen -ErrorAction SilentlyContinue
        if ($c) { Write-Host "Puerto $_: OCUPADO por PID $($c.OwningProcess)" -ForegroundColor Red }
        else { Write-Host "Puerto $_: LIBRE" -ForegroundColor Green }
    }

    Write-Host "`n[+] LOG DE EVENTOS (Windows):" -ForegroundColor Cyan
    Get-WinEvent -FilterHashtable @{LogName='Application'; Level=2} -MaxEvents 3 | 
    Where-Object { $_.Message -match "Apache" } | Select-Object TimeCreated, Message | Format-List
}

Write-Host "`n[5/5] Proceso finalizado."
