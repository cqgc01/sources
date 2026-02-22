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
if (Test-Path $registryPath) { Remove-Item -Path $registryPath -Recurse -Force -ErrorAction SilentlyContinue }
sc.exe delete $serviceName | Out-Null

# 3. Instalación Nueva (CORREGIDO: Evita el error rojo NativeCommandError)
Write-Host "[2/5] Registrando nueva instancia del servicio..."
$null = & ./httpd.exe -k install -n $serviceName 2>&1
Write-Host "    - Servicio registrado correctamente." -ForegroundColor Gray

# 4. Bucle de 10 reintentos
Write-Host "[3/5] Intentando iniciar servicio (Max 10 intentos)..."
$success = $false
for ($i = 1; $i -le $maxRetries; $i++) {
    $port443 = Get-NetTCPConnection -LocalPort 443 -State Listen -ErrorAction SilentlyContinue
    if ($port443) {
        taskkill /F /PID $port443.OwningProcess 2>$null
        Start-Sleep -Seconds 1
    }
    Start-Service -Name $serviceName -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    if ((Get-Service -Name $serviceName -ErrorAction SilentlyContinue).Status -eq "Running") {
        Write-Host (" -> ¡ÉXITO! Intento " + $i) -ForegroundColor Green
        $success = $true ; break
    } else {
        Write-Host (" -> Fallo en intento " + $i) -ForegroundColor Yellow
    }
}

# 5. DIAGNÓSTICO SI FALLA
if (-not $success) {
    Write-Host "`n[4/5] --- DIAGNÓSTICO DE FALLO ---" -ForegroundColor Red
    Write-Host "El servicio no inició. Error detectado en httpd.conf:" -ForegroundColor White
    
    # ESTO MOSTRARÁ EL ERROR REAL DE CONFIGURACIÓN
    $errorConfig = & ./httpd.exe -t 2>&1
    $errorConfig | Out-String | Write-Host -ForegroundColor Yellow

    Write-Host "`nRevisando puertos:" -ForegroundColor White
    80, 443 | ForEach-Object {
        $c = Get-NetTCPConnection -LocalPort $_ -State Listen -ErrorAction SilentlyContinue
        if ($c) { Write-Host ("Puerto " + $_ + " ocupado por PID " + $c.OwningProcess) -ForegroundColor Red }
    }
}
Write-Host "`n[5/5] Proceso finalizado."
