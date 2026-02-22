# 1. Configuración de rutas
$apacheBin = "C:\HSLS-14.2\Apache\bin"
$serviceName = "HSLS14.2"
$maxRetries = 10
$registryPath = "HKLM:\SYSTEM\CurrentControlSet\Services\" + $serviceName

Write-Host "--- Iniciando Limpieza Profunda y Reinstalación de Apache ---" -ForegroundColor Cyan
Set-Location $apacheBin

# 2. LIMPIEZA DE PROCESOS ZOMBIS (Solución al cuelgue)
Write-Host "[1/5] Matando procesos httpd.exe colgados..." -ForegroundColor Yellow
taskkill /F /IM httpd.exe /T 2>$null
Start-Sleep -Seconds 2

Write-Host "    - Limpiando rastro del servicio..."
Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
sc.exe delete $serviceName | Out-Null

if (Test-Path $registryPath) {
    Remove-Item -Path $registryPath -Recurse -Force -ErrorAction SilentlyContinue
}
Start-Sleep -Seconds 2

# 3. Instalación Nueva (MODO DESACOPLADO PARA EVITAR CONGELAMIENTO)
Write-Host "[2/5] Registrando nueva instancia del servicio..."
$installParams = "/c " + $apacheBin + "\httpd.exe -k install -n " + $serviceName
# Usamos cmd /c para lanzar el comando y desvincularlo del script de PowerShell
Start-Process "cmd.exe" -ArgumentList $installParams -NoNewWindow -Wait -WindowStyle Hidden
Write-Host "    - Comando de registro enviado." -ForegroundColor Gray

# 4. Bucle de 10 reintentos
Write-Host "[3/5] Iniciando fase de arranque (Max 10 intentos)..."
$success = $false

for ($i = 1; $i -le $maxRetries; $i++) {
    # Liberar puerto 443 antes de intentar subir
    $port443 = Get-NetTCPConnection -LocalPort 443 -State Listen -ErrorAction SilentlyContinue
    if ($port443) {
        $pidToKill = $port443.OwningProcess
        Write-Host ("    - Liberando puerto 443 (PID " + $pidToKill + ")...") -ForegroundColor Gray
        taskkill /F /PID $pidToKill 2>$null
        Start-Sleep -Seconds 1
    }

    # Intentar arrancar
    Start-Service -Name $serviceName -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3 # Un poco más de tiempo para el arranque inicial

    $check = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    if ($check.Status -eq "Running") {
        Write-Host (" -> ¡ÉXITO! Servicio en línea en el intento " + $i) -ForegroundColor Green
        $success = $true ; break
    } else {
        Write-Host (" -> Fallo en intento " + $i + ". Reintentando...") -ForegroundColor Yellow
    }
}

# 5. DIAGNÓSTICO FINAL SI FALLA
if (-not $success) {
    Write-Host "`n[4/5] --- DIAGNÓSTICO DE FALLO ---" -ForegroundColor Red
    Write-Host "Revisando errores de sintaxis en httpd.conf:" -ForegroundColor White
    $diag = & ./httpd.exe -t 2>&1
    $diag | Out-String | Write-Host -ForegroundColor Yellow
    
    Write-Host "`nVerificando si el servicio existe realmente:" -ForegroundColor White
    if (Get-Service -Name $serviceName -ErrorAction SilentlyContinue) {
        Write-Host "El servicio ESTÁ registrado pero no arranca." -ForegroundColor Yellow
    } else {
        Write-Host "El servicio NO se registró. Verifique permisos de Administrador." -ForegroundColor Red
    }
}

Write-Host "`n[5/5] Proceso finalizado."


////


//////

# 1. Configuración de variables
$serviceName = "HSLS14.2"
$apacheBin = "C:\HSLS-14.2\Apache\bin"
$apacheExe = Join-Path $apacheBin "httpd.exe"

Write-Host "--- Iniciando Monitor de Servicio Apache ---" -ForegroundColor Cyan

# 2. Intento de arranque con tiempo límite (Timeout)
$svc = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
if (-not $svc) {
    Write-Host "[!] El servicio " + $serviceName + " no esta registrado." -ForegroundColor Red
    exit
}

if ($svc.Status -ne "Running") {
    Write-Host "Arrancando servicio (espera maxima 5 seg)..."
    # Iniciamos el servicio sin esperar a que Windows termine de confirmarlo (que es donde se cuelga)
    Start-Service -Name $serviceName -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 5
}

# 3. Validación Final y Búsqueda de la Causa
$checkSvc = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
if ($checkSvc.Status -ne "Running") {
    Write-Host "`n[FALLO] El servicio no pudo estabilizarse." -ForegroundColor Red
    Write-Host "==============================================================="

    # CAUSA A: Error de Sintaxis (ESTO ES LO MÁS PROBABLE)
    Write-Host "[+] ANALIZANDO SINTAXIS EN EL ARCHIVO CONF" -ForegroundColor Cyan
    if (Test-Path $apacheExe) {
        # Ejecutamos el test de sintaxis y capturamos TODO el error
        $syntax = & $apacheExe -t 2>&1
        $syntaxStr = $syntax | Out-String
        if ($syntaxStr -match "error" -or $syntaxStr -match "failed") {
            Write-Host "[!] ERROR DE CONFIGURACION ENCONTRADO" -ForegroundColor Yellow
            Write-Host $syntaxStr
        } else { 
            Write-Host "    - Sintaxis - OK" -ForegroundColor Green 
        }
    }

    # CAUSA B: Puertos bloqueados
    Write-Host "`n[+] ANALIZANDO PUERTOS (80/443)" -ForegroundColor Cyan
    $testPorts = @(80, 443)
    foreach ($p in $testPorts) {
        $conn = Get-NetTCPConnection -LocalPort $p -State Listen -ErrorAction SilentlyContinue
        if ($conn) {
            $proc = Get-Process -Id $conn.OwningProcess
            Write-Host ("    - Puerto " + $p + " bloqueado por - " + $proc.ProcessName + " (PID - " + $proc.Id + ")") -ForegroundColor Red
        } else { 
            Write-Host ("    - Puerto " + $p + " - Libre") -ForegroundColor Green 
        }
    }

    # CAUSA C: Ejecución Manual para ver el error "en vivo"
    Write-Host "`n[+] PRUEBA DE ARRANQUE MANUAL (Salida directa de Apache)" -ForegroundColor Cyan
    Write-Host "Ejecutando httpd.exe directamente..." -ForegroundColor Gray
    # Lanzamos apache directamente para ver si escupe algun error en consola
    & $apacheExe -e info -t | Out-String | Write-Host -ForegroundColor Yellow

} else {
    Write-Host "EXITO - El servicio esta en ejecucion." -ForegroundColor Green
}

Write-Host "`n--- Auditoria Finalizada ---"
