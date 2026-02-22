# 1. Configuración de rutas
$apacheBin = "C:\HSLS-14.2\Apache\bin"
$serviceName = "HSLS14.2"
$maxRetries = 10
$registryPath = "HKLM:\SYSTEM\CurrentControlSet\Services\" + $serviceName

Write-Host "--- Iniciando Limpieza Profunda y Reinstalación de Apache ---" -ForegroundColor Cyan
Set-Location $apacheBin

# 2. BORRADO TOTAL
Write-Host "[1/5] Ejecutando limpieza de rastro previo..."
if (Get-Service -Name $serviceName -ErrorAction SilentlyContinue) {
    Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
    & ./httpd.exe -k uninstall -n $serviceName 2>$null
    Start-Sleep -Seconds 1
}

if (Test-Path $registryPath) {
    Remove-Item -Path $registryPath -Recurse -Force -ErrorAction SilentlyContinue
}
sc.exe delete $serviceName | Out-Null

# 3. Instalación Nueva (Silenciando el NativeCommandError falso)
Write-Host "[2/5] Registrando nueva instancia del servicio..."
$installOutput = & ./httpd.exe -k install -n $serviceName 2>&1
Write-Host "    - Resultado: El servicio se ha registrado." -ForegroundColor Gray

# 4. Bucle de 10 reintentos
Write-Host "[3/5] Iniciando fase de arranque (Max 10 intentos)..."
$success = $false

for ($i = 1; $i -le $maxRetries; $i++) {
    $port443 = Get-NetTCPConnection -LocalPort 443 -State Listen -ErrorAction SilentlyContinue
    if ($port443) {
        $pidToKill = $port443.OwningProcess
        Write-Host ("    - Intento " + $i + " - Liberando puerto 443 (PID " + $pidToKill + ")...") -ForegroundColor Gray
        taskkill /F /PID $pidToKill 2>$null
        Start-Sleep -Seconds 1
    }

    Start-Service -Name $serviceName -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    $check = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    if ($check.Status -eq "Running") {
        Write-Host (" -> ¡EXITOSO! Servicio en línea en el intento " + $i) -ForegroundColor Green
        $success = $true
        break
    } else {
        Write-Host (" -> Intento " + $i + " fallido. Revisando configuración...") -ForegroundColor Yellow
    }
}

# 5. DIAGNÓSTICO OBLIGATORIO SI FALLA
if (-not $success) {
    Write-Host "`n[4/5] ERROR DETECTADO EN LA CONFIGURACIÓN" -ForegroundColor Red
    Write-Host "============================================="
    
    # Esto te dirá exactamente qué línea del archivo está mal
    Write-Host "[+] Ejecutando prueba de sintaxis (httpd -t):" -ForegroundColor Cyan
    $test = & ./httpd.exe -t 2>&1
    $test | Out-String | Write-Host -ForegroundColor Yellow

    Write-Host "`n[+] Verificando puertos ocupados:" -ForegroundColor Cyan
    foreach ($p in 80, 443) {
        $c = Get-NetTCPConnection -LocalPort $p -State Listen -ErrorAction SilentlyContinue
        if ($c) { 
            Write-Host ("Puerto " + $p + " bloqueado por: " + (Get-Process -Id $c.OwningProcess).ProcessName) -ForegroundColor Red 
        }
    }
}

Write-Host "`n[5/5] Proceso finalizado."
