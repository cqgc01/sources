# 1. Configuración de rutas
$apacheBin = "C:\HSLS-14.2\Apache\bin"
$serviceName = "HSLS14.2"
$maxRetries = 10

Write-Host "--- Iniciando Instalación con Diagnóstico Avanzado ---" -ForegroundColor Cyan
Set-Location $apacheBin

# 2. Limpieza previa
Write-Host "[1/4] Limpiando residuos..."
net stop $serviceName 2>$null
./httpd.exe -k uninstall -n $serviceName 2>$null

# 3. Instalación
Write-Host "[2/4] Registrando servicio..."
./httpd.exe -k install -n $serviceName

# 4. Bucle de reintentos
Write-Host "[3/4] Intentando subir el servicio (Máx 10 veces)..."
$success = $false
for ($i = 1; $i -le $maxRetries; $i++) {
    # Liberar puerto 443 antes de cada intento
    $port443 = Get-NetTCPConnection -LocalPort 443 -State Listen -ErrorAction SilentlyContinue
    if ($port443) {
        taskkill /F /PID $port443.OwningProcess 2>$null
        Start-Sleep -Seconds 1
    }
    
    Start-Service -Name $serviceName -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    
    if ((Get-Service $serviceName).Status -eq "Running") {
        Write-Host " -> Intento $i: ¡EXITOSO!" -ForegroundColor Green
        $success = $true
        break
    } else {
        Write-Host " -> Intento $i: Fallido..." -ForegroundColor Yellow
    }
}

# 5. DIAGNÓSTICO DETALLADO (Si falló)
if (-not $success) {
    Write-Host "`n[4/4] INICIANDO DIAGNÓSTICO PROFUNDO..." -ForegroundColor Red
    Write-Host "============================================="

    # A. Prueba de Sintaxis (La causa #1)
    Write-Host "`n[+] Verificando Sintaxis de Apache:" -ForegroundColor Cyan
    $syntaxResult = ./httpd.exe -t 2>&1
    if ($syntaxResult -match "Syntax error") {
        Write-Host "[!] ERROR DE CONFIGURACIÓN DETECTADO:" -ForegroundColor Red
        $syntaxResult | Out-String | Write-Host -ForegroundColor Yellow
    } else {
        Write-Host "    - Sintaxis: OK" -ForegroundColor Green
    }

    # B. Conflicto de Puertos Críticos
    Write-Host "`n[+] Verificando Puertos (80/443):" -ForegroundColor Cyan
    $puertos = 80, 443
    foreach ($p in $puertos) {
        $con = Get-NetTCPConnection -LocalPort $p -State Listen -ErrorAction SilentlyContinue
        if ($con) {
            $proc = Get-Process -Id $con.OwningProcess
            Write-Host "[!] El puerto $p está ocupado por: $($proc.ProcessName) (PID: $($proc.Id))" -ForegroundColor Red
            Write-Host "    Ruta del proceso: $($proc.Path)" -ForegroundColor Gray
        } else {
            Write-Host "    - Puerto $p: Libre" -ForegroundColor Green
        }
    }

    # C. Verificación de Rutas y Permisos
    Write-Host "`n[+] Verificando Permisos y Directorios:" -ForegroundColor Cyan
    $confPath = Join-Path (Split-Path $apacheBin) "conf\httpd.conf"
    if (Test-Path $confPath) {
        Write-Host "    - Archivo de config existe." -ForegroundColor Green
    } else {
        Write-Host "[!] CRÍTICO: No se encuentra httpd.conf en $confPath" -ForegroundColor Red
    }

    # D. Análisis del Visor de Eventos (Event Viewer)
    Write-Host "`n[+] Analizando logs del Sistema (Windows Events):" -ForegroundColor Cyan
    $events = Get-WinEvent -FilterHashtable @{LogName='Application'; Level=2} -MaxEvents 20 | 
              Where-Object { $_.Message -match "Apache" -or $_.Source -match "Apache" }
    
    if ($events) {
        $events | Select-Object TimeCreated, Message | Format-Table -AutoSize -Wrap | Out-String | Write-Host -ForegroundColor Yellow
    } else {
        Write-Host "    - No se encontraron errores específicos en el log de Windows." -ForegroundColor Green
    }

    # E. Intento de ejecución manual (Para ver error en tiempo real)
    Write-Host "`n[+] Ejecución de prueba manual (Salida directa):" -ForegroundColor Cyan
    Write-Host "Lanzando httpd.exe sin servicio..." -ForegroundColor Gray
    Start-Process ./httpd.exe -ArgumentList "-k start" -NoNewWindow -Wait -ErrorAction SilentlyContinue
}

Write-Host "`nProcedimiento finalizado."




