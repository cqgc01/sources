# 1. Configuración de rutas
$apacheBin = "C:\HSL14.2\Apache\bin"
$serviceName = "HSL14.2"

Write-Host "--- Iniciando proceso de instalación de Apache ---" -ForegroundColor Cyan
Set-Location $apacheBin

# 2. Limpieza de procesos y servicios previos
Write-Host "Limpiando registros y liberando puertos..."

# Detener y desinstalar servicio si existe
net stop $serviceName 2>$null
./httpd.exe -k uninstall -n $serviceName 2>$null

# Buscar proceso en puerto 443
$port443 = Get-NetTCPConnection -LocalPort 443 -State Listen -ErrorAction SilentlyContinue

if ($port443) {
    $pidToKill = $port443.OwningProcess[0]
    Write-Host "Detectado proceso bloqueando el puerto 443 (PID: $pidToKill). Ejecutando Taskkill..." -ForegroundColor Yellow
    
    # PASO ADICIONADO: taskkill /F /PID
    taskkill /F /PID $pidToKill
    
    Start-Sleep -Seconds 2 # Pausa para asegurar que el puerto se libere en el kernel
}

# 3. Instalación del servicio
Write-Host "Registrando el servicio..."
./httpd.exe -k install -n $serviceName

# 4. Intento de inicio
Write-Host "Intentando iniciar el servicio..."
Start-Service -Name $serviceName -ErrorAction SilentlyContinue

# 5. Verificación final y diagnóstico
$status = Get-Service $serviceName -ErrorAction SilentlyContinue

if ($status.Status -eq "Running") {
    Write-Host "¡ÉXITO! Apache está corriendo." -ForegroundColor Green
} else {
    Write-Host "¡ERROR! El servicio no subió." -ForegroundColor Red
    Write-Host "Revisando sintaxis de httpd.conf..."
    ./httpd.exe -t
}
