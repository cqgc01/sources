# 1. Configuración de rutas
$apacheBin = "C:\HSL14.2\Apache\bin"
$serviceName = "HSL14.2"

Write-Host "--- Iniciando proceso de instalación de Apache ---" -ForegroundColor Cyan
Set-Location $apacheBin

# Función para limpiar puerto 443
function Libera-Puerto443 {
    $port443 = Get-NetTCPConnection -LocalPort 443 -State Listen -ErrorAction SilentlyContinue
    if ($port443) {
        $pidToKill = $port443.OwningProcess[0]
        $proceso = Get-Process -Id $pidToKill
        Write-Host "Liberando puerto 443 (Cerrando $($proceso.ProcessName)...)" -ForegroundColor Yellow
        Stop-Process -Id $pidToKill -Force -Confirm:$false
        Start-Sleep -Seconds 2 # Espera a que el sistema libere el socket
    }
}

# 2. Limpieza inicial
Write-Host "Limpiando registros y puertos antiguos..."
net stop $serviceName 2>$null
./httpd.exe -k uninstall -n $serviceName 2>$null
Libera-Puerto443

# 3. Instalación del servicio
Write-Host "Registrando el servicio..."
./httpd.exe -k install -n $serviceName

# 4. Intento de inicio y reintento si falla
Write-Host "Intentando iniciar el servicio..."
Start-Service -Name $serviceName -ErrorAction SilentlyContinue

if ((Get-Service $serviceName).Status -ne "Running") {
    Write-Host "El servicio no inició. Reintentando tras limpieza profunda..." -ForegroundColor Yellow
    
    # Segundo intento: Forzar limpieza total
    Libera-Puerto443
    ./httpd.exe -k uninstall -n $serviceName 2>$null
    ./httpd.exe -k install -n $serviceName
    Start-Service -Name $serviceName -ErrorAction SilentlyContinue
}

# 5. Verificación Final
$finalStatus = Get-Service $serviceName -ErrorAction SilentlyContinue
if ($finalStatus.Status -eq "Running") {
    Write-Host "¡ÉXITO! Apache está corriendo correctamente." -ForegroundColor Green
} else {
    Write-Host "¡ERROR CRÍTICO! No se pudo iniciar Apache." -ForegroundColor Red
    # Diagnóstico de sintaxis rápido
    ./httpd.exe -t
}
