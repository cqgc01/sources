# 1. Configuración de rutas
$apacheBin = "C:\HSLS-14.2\Apache\bin"
$serviceName = "HSLS14.2"
$maxRetries = 10
$registryPath = "HKLM:\SYSTEM\CurrentControlSet\Services\" + $serviceName

Write-Host "--- Iniciando Limpieza Profunda y Reinstalación de Apache ---" -ForegroundColor Cyan
Set-Location $apacheBin

# 2. BORRADO TOTAL (Servicio, SC y Regedit)
Write-Host "[1/5] Ejecutando limpieza de rastro previo..."

if (Get-Service -Name $serviceName -ErrorAction SilentlyContinue) {
    Write-Host "    - Deteniendo y desinstalando servicio..."
    Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
    & ./httpd.exe -k uninstall -n $serviceName 2>$null
    Start-Sleep -Seconds 1
}

# Borrado en Registro (Regedit)
if (Test-Path $registryPath) {
    Write-Host "    - Eliminando rastro en Regedit..." -ForegroundColor Yellow
    Remove-Item -Path $registryPath -Recurse -Force -ErrorAction SilentlyContinue
}

# Borrado con SC
sc.exe delete $serviceName | Out-Null
Write-Host "[OK] Limpieza total completada." -ForegroundColor Green

# 3. Instalación Nueva
Write-Host "[2/5] Registrando nueva instancia del servicio..."
& ./httpd.exe -k install -n $serviceName

# 4. Bucle de 10 reintentos con Taskkill
Write-Host "[3/5] Iniciando fase de arranque (Max 10 intentos)..."
$success = $false

for ($i = 1; $i -le $maxRetries; $i++) {
    $port443 = Get-NetTCPConnection -LocalPort 443 -State Listen -ErrorAction SilentlyContinue
    if ($port443) {
        $pidToKill = $port443.OwningProcess
        # Sintaxis modificada: quitamos los ':' pegados a la variable
        Write-Host ("    - Intento " + $i + " - Puerto 443 ocupado por PID " + $pidToKill + ". Ejecutando taskkill...") -ForegroundColor Gray
        taskkill /F /PID $pidToKill 2>$null
        Start-Sleep -Seconds 1
    }

    Start-Service -Name $serviceName -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    $check = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    if ($check.Status -eq "Running") {
        Write-Host (" -> ¡EXITOSO! Servicio iniciado en el intento " + $i) -ForegroundColor Green
        $success = $true
        break
    } else {
        Write-Host (" -> Intento " + $i + " fallido...") -ForegroundColor Yellow
    }
}

# 5. Diagnóstico Detallado Final
if (-not $success) {
    Write-Host "`n[4/5] DIAGNÓSTICO DE FALLO CRÍTICO" -ForegroundColor Red
    Write-Host "============================================="
    
    Write-Host "[+] ERROR DE SINTAXIS (httpd -t):" -ForegroundColor Cyan
    & ./httpd.exe -t 2>&1 | Write-Host -ForegroundColor Yellow

    Write-Host "`n[+] ESTADO DE PUERTOS:" -ForegroundColor Cyan
    $testPorts = @(80, 443)
    foreach ($p in $testPorts) {
        $c = Get-NetTCPConnection -LocalPort $p -State Listen -ErrorAction SilentlyContinue
        if ($c) { 
            $owner = $c.OwningProcess
            Write-Host ("Puerto " + $p + " - OCUPADO por PID " + $owner) -ForegroundColor Red 
        } else { 
            Write-Host ("Puerto " + $p + " - LIBRE") -ForegroundColor Green 
        }
    }

    Write-Host "`n[+] LOG DE EVENTOS (Windows):" -ForegroundColor Cyan
    $events = Get-WinEvent -FilterHashtable @{LogName='Application'; Level=2} -MaxEvents 5 -ErrorAction SilentlyContinue | 
              Where-Object { $_.Message -match "Apache" -or $_.Source -match "Apache" }
    if ($events) { $events | Select-Object TimeCreated, Message | Format-List | Out-String | Write-Host -ForegroundColor Yellow }
}

Write-Host "`n[5/5] Proceso finalizado."


[2/5] Registrando nueva instancia del servicio...
httpd.exe : Installing the 'HSLS14.2' service
At line:32 char:1
+ & ./httpd.exe -k install -n $serviceName
+ ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    + CategoryInfo          : NotSpecified: (Installing the 'HSLS14.2' service:String) [], RemoteException
    + FullyQualifiedErrorId : NativeCommandError
 
The 'HSLS14.2' service is successfully installed.
Testing httpd.conf....
Errors reported here must be corrected before the service can be started.
