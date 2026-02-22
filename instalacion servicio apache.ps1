# 1. Configuración de rutas
$apacheBin = "C:\HSLS-14.2\Apache\bin"
$serviceName = "HSLS14.2"
$maxRetries = 10

Write-Host "--- Iniciando Reinstalación Limpia de Apache ---" -ForegroundColor Cyan
Set-Location $apacheBin

# 2. Verificación y Desinstalación del servicio existente
$existingService = Get-Service -Name $serviceName -ErrorAction SilentlyContinue

if ($existingService) {
    Write-Host "[!] El servicio '$serviceName' ya existe. Procediendo a eliminarlo..." -ForegroundColor Yellow
    
    # Detener si está corriendo
    if ($existingService.Status -eq "Running") {
        Write-Host "    - Deteniendo servicio activo..."
        Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
    }

    # Desinstalar usando el binario de Apache
    Write-Host "    - Ejecutando desinstalación (httpd -k uninstall)..."
    ./httpd.exe -k uninstall -n $serviceName 2>$null
    
    # Forzar eliminación del registro si httpd falló
    if (Get-Service -Name $serviceName -ErrorAction SilentlyContinue) {
        Write-Host "    - Forzando eliminación desde sc.exe..." -ForegroundColor Gray
        sc.exe delete $serviceName | Out-Null
    }
    
    Start-Sleep -Seconds 2
    Write-Host "[OK] Servicio previo eliminado." -ForegroundColor Green
}

# 3. Instalación Nueva
Write-Host "[1/4] Registrando nueva instancia del servicio..."
./httpd.exe -k install -n $serviceName

# 4. Bucle de reintentos (10 veces)
Write-Host "[2/4] Intentando subir el servicio..."
$success = $false
for ($i = 1; $i -le $maxRetries; $i++) {
    
    # Liberar puerto 443 con taskkill
    $port443 = Get-NetTCPConnection -LocalPort 443 -State Listen -ErrorAction SilentlyContinue
    if ($port443) {
        $pid = $port443.OwningProcess
        Write-Host "    - Liberando puerto 443 (PID: $pid)..." -ForegroundColor Gray
        taskkill /F /PID $pid 2>$null
        Start-Sleep -Seconds 1
    }

    Start-Service -Name $serviceName -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    if ((Get-Service $serviceName).Status -eq "Running") {
        Write-Host " -> Intento $i: ¡SERVICIO EN LINEA!" -ForegroundColor Green
        $success = $true
        break
    } else {
        Write-Host " -> Intento $i: Fallido, reintentando..." -ForegroundColor Yellow
    }
}

# 5. Diagnóstico Detallado en caso de Fallo Final
if (-not $success) {
    Write-Host "`n[!] ERROR CRÍTICO: No se pudo estabilizar el servicio tras $maxRetries intentos." -ForegroundColor Red
    Write-Host "============================================="
    
    Write-Host "[+] RESULTADO DE SINTAXIS:" -ForegroundColor Cyan
    ./httpd.exe -t
    
    Write-Host "`n[+] ESTADO DE PUERTOS:" -ForegroundColor Cyan
    80, 443 | ForEach-Object { 
        $c = Get-NetTCPConnection -LocalPort $_ -State Listen -ErrorAction SilentlyContinue
        if ($c) { Write-Host "Puerto $_ OCUPADO por PID $($c.OwningProcess)" -ForegroundColor Red }
        else { Write-Host "Puerto $_ LIBRE" -ForegroundColor Green }
    }

    Write-Host "`n[+] ÚLTIMO ERROR EN LOG DE WINDOWS:" -ForegroundColor Cyan
    Get-WinEvent -FilterHashtable @{LogName='Application'; Level=2} -MaxEvents 5 | 
    Where-Object { $_.Message -match "Apache" } | Select-Object TimeCreated, Message | Format-List
}

Write-Host "`nProceso finalizado."
