# 1. Configuración de rutas
$apacheBin = "C:\HSL14.2\Apache\bin"
$serviceName = "HSL14.2"

Write-Host "--- Iniciando proceso de instalación de Apache ---" -ForegroundColor Cyan
Set-Location $apacheBin

# 2. Limpieza de servicios previos
Write-Host "Limpiando registros antiguos..."
net stop $serviceName 2>$null
./httpd.exe -k uninstall -n $serviceName 2>$null

# 3. Instalación del servicio
Write-Host "Registrando el servicio..."
./httpd.exe -k install -n $serviceName

# 4. Intento de inicio y detección de errores
Write-Host "Intentando iniciar el servicio..."
$startResult = Start-Service -Name $serviceName -ErrorAction SilentlyContinue

$currentService = Get-Service $serviceName -ErrorAction SilentlyContinue

if (-not $currentService -or $currentService.Status -ne "Running") {
    Write-Host "¡ERROR! El servicio no subió. Iniciando diagnóstico..." -ForegroundColor Red
    
    # Prueba de Sintaxis
    $syntax = ./httpd.exe -t 2>&1
    if ($syntax -match "Syntax error" -or $syntax -match "error") {
        Write-Host "CAUSA DETECTADA: Error de configuración." -ForegroundColor Yellow
        Write-Host "DETALLE: $syntax"
    } 
    
    # Prueba de Puertos (80 y 443) - CORREGIDO
    $port80 = Get-NetTCPConnection -LocalPort 80 -ErrorAction SilentlyContinue | Select-Object -First 1
    $port443 = Get-NetTCPConnection -LocalPort 443 -ErrorAction SilentlyContinue | Select-Object -First 1
    
    if ($port80 -or $port443) {
        $pidToKill = if ($port80) { $port80.OwningProcess } else { $port443.OwningProcess }
        $occupant = Get-Process -Id $pidToKill -ErrorAction SilentlyContinue
        
        Write-Host "CAUSA DETECTADA: El puerto está OCUPADO." -ForegroundColor Yellow
        if ($occupant) {
            Write-Host "El programa que bloquea es: $($occupant.ProcessName) (PID: $($occupant.Id))"
        } else {
            Write-Host "El PID bloqueador es: $pidToKill (Posiblemente un servicio del Sistema)"
        }
    }
} else {
    Write-Host "¡ÉXITO! El servicio de Apache ($serviceName) está corriendo." -ForegroundColor Green
}
