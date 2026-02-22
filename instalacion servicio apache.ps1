# 1. Configuración de rutas
$apacheBin = "C:\HSLS-14.2\Apache\bin"
$serviceName = "HSLS14.2"
$maxRetries = 10
$registryPath = "HKLM:\SYSTEM\CurrentControlSet\Services\" + $serviceName

Write-Host "--- Iniciando Limpieza Profunda y Reinstalación de Apache ---" -ForegroundColor Cyan
Set-Location $apacheBin

# 2. BORRADO TOTAL (Reforzado)
Write-Host "[1/5] Ejecutando limpieza de rastro previo..."
Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
& ./httpd.exe -k uninstall -n $serviceName 2>$null

if (Test-Path $registryPath) {
    Remove-Item -Path $registryPath -Recurse -Force -ErrorAction SilentlyContinue
}
sc.exe delete $serviceName | Out-Null
Start-Sleep -Seconds 2

# 3. Instalación Nueva (CON TIMEOUT PARA QUE NO SE CONGELE)
Write-Host "[2/5] Registrando nueva instancia del servicio..."
$installParams = "-k install -n " + $serviceName
# Ejecuta en segundo plano y espera máximo 10 segundos
$process = Start-Process -FilePath "./httpd.exe" -ArgumentList $installParams -NoNewWindow -PassThru -ErrorAction SilentlyContinue
$process | Wait-Process -Timeout 10 -ErrorAction SilentlyContinue

Write-Host "    - Registro completado o tiempo de espera agotado." -ForegroundColor Gray

# 4. Bucle de 10 reintentos
Write-Host "[3/5] Intentando iniciar servicio (Max 10 intentos)..."
$success = $false
for ($i = 1; $i -le $maxRetries; $i++) {
    $port443 = Get-NetTCPConnection -LocalPort 443 -State Listen -ErrorAction SilentlyContinue
    if ($port443) {
        $pidToKill = $port443.OwningProcess
        Write-Host ("    - Liberando puerto 443 (PID " + $pidToKill + ")...") -ForegroundColor Gray
        taskkill /F /PID $pidToKill 2>$null
        Start-Sleep -Seconds 1
    }

    Start-Service -Name $serviceName -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    $check = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    if ($check.Status -eq "Running") {
        Write-Host (" -> ¡EXITOSO! Intento " + $i) -ForegroundColor Green
        $success = $true ; break
    } else {
        Write-Host (" -> Fallo en intento " + $i) -ForegroundColor Yellow
    }
}

# 5. DIAGNÓSTICO (Si no inició, aquí verás por qué)
if (-not $success) {
    Write-Host "`n[4/5] --- DIAGNÓSTICO DE FALLO ---" -ForegroundColor Red
    Write-Host "Revisando errores de sintaxis en httpd.conf..."
    $diag = & ./httpd.exe -t 2>&1
    $diag | Out-String | Write-Host -ForegroundColor Yellow
}

Write-Host "`n[5/5] Proceso finalizado."
