# 1. Configuración de rutas
$apacheBin = "C:\HSLS-14.2\Apache\bin"
$serviceName = "HSLS14.2"
$maxRetries = 10
$registryPath = "HKLM:\SYSTEM\CurrentControlSet\Services\" + $serviceName

Write-Host "--- Iniciando Limpieza Profunda y Reinstalación de Apache ---" -ForegroundColor Cyan
Set-Location $apacheBin

# 2. LIMPIEZA TOTAL
Write-Host "[1/5] Limpiando procesos y servicios previos..." -ForegroundColor Yellow
taskkill /F /IM httpd.exe /T 2>$null
Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
sc.exe delete $serviceName | Out-Null

if (Test-Path $registryPath) {
    Remove-Item -Path $registryPath -Recurse -Force -ErrorAction SilentlyContinue
}
Start-Sleep -Seconds 2

# 3. INSTALACIÓN (CORREGIDO: Sin conflicto de parámetros)
Write-Host "[2/5] Registrando nueva instancia del servicio..."
$installArgs = "/c " + $apacheBin + "\httpd.exe -k install -n " + $serviceName

# Usamos solo -WindowStyle Hidden para que trabaje en segundo plano sin errores
$p = Start-Process "cmd.exe" -ArgumentList $installArgs -PassThru -WindowStyle Hidden
$p | Wait-Process -Timeout 15 -ErrorAction SilentlyContinue

Write-Host "    - Registro completado." -ForegroundColor Gray

# 4. BUCLE DE ARRANQUE (10 Intentos)
Write-Host "[3/5] Iniciando fase de arranque (Max 10 intentos)..."
$success = $false

for ($i = 1; $i -le $maxRetries; $i++) {
    # Liberar puerto 443 antes de intentar subir
    $port443 = Get-NetTCPConnection -LocalPort 443 -State Listen -ErrorAction SilentlyContinue
    if ($port443) {
        $pidToKill = $port443.OwningProcess
        Write-Host ("    - Intento " + $i + " - Liberando puerto 443 (PID " + $pidToKill + ")...") -ForegroundColor Gray
        taskkill /F /PID $pidToKill /T 2>$null
        Start-Sleep -Seconds 1
    }

    # Intentar arrancar
    Start-Process "sc.exe" -ArgumentList "start", $serviceName -WindowStyle Hidden -Wait
    Start-Sleep -Seconds 3

    $check = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    if ($check.Status -eq "Running") {
        Write-Host (" -> ¡ÉXITO! Servicio en línea en el intento " + $i) -ForegroundColor Green
        $success = $true ; break
    } else {
        Write-Host (" -> Intento " + $i + " fallido. Reintentando...") -ForegroundColor Yellow
    }
}

# 5. DIAGNÓSTICO PROFUNDO SI FALLA
if (-not $success) {
    Write-Host "`n[4/5] --- DIAGNÓSTICO DE FALLO ---" -ForegroundColor Red
    
    Write-Host "[+] Verificando Sintaxis (httpd -t):" -ForegroundColor Cyan
    $diag = & ./httpd.exe -t 2>&1
    $diag | Out-String | Write-Host -ForegroundColor Yellow

    Write-Host "`n[+] Verificando existencia del servicio:" -ForegroundColor Cyan
    if (Get-Service -Name $serviceName -ErrorAction SilentlyContinue) {
        Write-Host "    - El servicio esta registrado pero no pudo iniciar." -ForegroundColor Yellow
    } else {
        Write-Host "    - El servicio NO se registro. Revise permisos de Administrador." -ForegroundColor Red
    }
}

Write-Host "`n[5/5] Proceso finalizado."


//////************************************

# 1. Configuración de variables
$serviceName = "HSLS14.2"
$apacheBin = "C:\HSLS-14.2\Apache\bin"
$apacheExe = Join-Path $apacheBin "httpd.exe"

Write-Host "--- Iniciando Monitor de Servicio Apache (Modo No-Bloqueante) ---" -ForegroundColor Cyan

# 2. Intento de arranque desacoplado
$svc = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
if (-not $svc) {
    Write-Host ("[!] El servicio " + $serviceName + " no esta registrado.") -ForegroundColor Red
    exit
}

if ($svc.Status -ne "Running") {
    Write-Host "Lanzando comando de arranque (Sin esperar confirmacion)..."
    # Usamos Start-Process para que PowerShell NO se quede colgado esperando
    Start-Process "sc.exe" -ArgumentList "start", $serviceName -NoNewWindow
    Start-Sleep -Seconds 5
}

# 3. Diagnóstico Inmediato (Incluso si sc.exe sigue trabajando)
Write-Host "`n[ANALISIS] Verificando estado y posibles causas de fallo..." -ForegroundColor White
$checkSvc = Get-Service -Name $serviceName -ErrorAction SilentlyContinue

if ($checkSvc.Status -ne "Running") {
    Write-Host "===============================================================" -ForegroundColor Red
    
    # CAUSA 1: Error de Sintaxis (La mas probable)
    Write-Host "[+] PRUEBA DE SINTAXIS (httpd -t)" -ForegroundColor Cyan
    if (Test-Path $apacheExe) {
        $syntax = & $apacheExe -t 2>&1
        $syntaxStr = $syntax | Out-String
        if ($syntaxStr -match "error" -or $syntaxStr -match "failed") {
            Write-Host "[!] ERROR ENCONTRADO EN httpd.conf" -ForegroundColor Yellow
            Write-Host $syntaxStr
        } else { 
            Write-Host "    - Sintaxis - OK" -ForegroundColor Green 
        }
    }

    # CAUSA 2: Conflictos de Puertos
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

    # CAUSA 3: Intento de ejecucion manual para ver el error real
    Write-Host "`n[+] EJECUCION MANUAL DE PRUEBA" -ForegroundColor Cyan
    Write-Host "Si Apache no inicia, aqui deberia aparecer el motivo tecnico:" -ForegroundColor Gray
    # Ejecutamos con -e info para forzar la salida de errores al terminal
    $manualRun = & $apacheExe -e info -t 2>&1
    $manualRun | Out-String | Write-Host -ForegroundColor Yellow

} else {
    Write-Host "EXITO - El servicio esta en ejecucion." -ForegroundColor Green
}

Write-Host "`n--- Auditoria Finalizada ---"


/////
# 1. Configuración de rutas
$serviceName = "HSLS14.2"
$apacheBin = "C:\HSLS-14.2\Apache\bin"
$apacheExe = Join-Path $apacheBin "httpd.exe"

Write-Host "--- Iniciando Diagnóstico con Protección contra Congelamiento ---" -ForegroundColor Cyan

# 2. Matar cualquier proceso previo que pueda estar bloqueando
Write-Host "Limpiando procesos zombis..." -ForegroundColor Gray
taskkill /F /IM httpd.exe /T 2>$null
Start-Sleep -Seconds 1

# 3. Intento de arranque asíncrono
Write-Host "Lanzando comando de inicio..."
Start-Process "sc.exe" -ArgumentList "start", $serviceName -NoNewWindow
Start-Sleep -Seconds 3

# 4. DIAGNÓSTICO CON TIMEOUT (Para que no se quede pegado)
Write-Host "`n[ANALISIS] Verificando causas de fallo..."
$checkSvc = Get-Service -Name $serviceName -ErrorAction SilentlyContinue

if ($checkSvc.Status -ne "Running") {
    Write-Host "===============================================================" -ForegroundColor Red
    
    # PRUEBA DE SINTAXIS CON TIEMPO LÍMITE
    Write-Host "[+] PRUEBA DE SINTAXIS (Max 5 segundos)..." -ForegroundColor Cyan
    $syntaxTask = Start-Process -FilePath $apacheExe -ArgumentList "-t" -NoNewWindow -PassThru -ErrorAction SilentlyContinue
    
    # Esperar 5 segundos, si no, lo matamos
    $wait = $syntaxTask | Wait-Process -Timeout 5 -ErrorAction SilentlyContinue
    
    if ($null -eq $wait) {
        Write-Host "[!] CRITICO - El comando 'httpd -t' SE CONGELÓ." -ForegroundColor Red
        Write-Host "CAUSA PROBABLE - Apache esta intentando conectar a una ruta de red invalida o un DNS que no responde." -ForegroundColor Yellow
        taskkill /F /ID $syntaxTask.Id /T 2>$null
    } else {
        # Si terminó a tiempo, capturamos el error
        $errorMsg = & $apacheExe -t 2>&1
        $errorMsg | Out-String | Write-Host -ForegroundColor Yellow
    }

    # CAUSA 2: Puertos
    Write-Host "`n[+] ANALIZANDO PUERTOS (80/443)..." -ForegroundColor Cyan
    $testPorts = @(80, 443)
    foreach ($p in $testPorts) {
        $conn = Get-NetTCPConnection -LocalPort $p -State Listen -ErrorAction SilentlyContinue
        if ($conn) {
            $procName = (Get-Process -Id $conn.OwningProcess).ProcessName
            Write-Host ("    - Puerto " + $p + " bloqueado por - " + $procName) -ForegroundColor Red
        } else { 
            Write-Host ("    - Puerto " + $p + " - Libre") -ForegroundColor Green 
        }
    }

    # CAUSA 3: Verificación de rutas en el archivo
    Write-Host "`n[+] REVISIÓN DE RUTAS EN EL ARCHIVO CONF..." -ForegroundColor Cyan
    $confFile = Join-Path (Split-Path $apacheBin) "conf\httpd.conf"
    if (Test-Path $confFile) {
        $content = Get-Content $confFile
        $serverRoot = $content | Select-String "ServerRoot" | Select-Object -First 1
        Write-Host ("    - " + $serverRoot) -ForegroundColor Gray
    }

} else {
    Write-Host "EXITO - El servicio esta corriendo." -ForegroundColor Green
}

Write-Host "`n--- Diagnostico Finalizado ---"


//////
# 1. Configuración de rutas
$serviceName = "HSLS14.2"
$apacheBin = "C:\HSLS-14.2\Apache\bin"
$apacheExe = Join-Path $apacheBin "httpd.exe"
$confFile = Join-Path (Split-Path $apacheBin) "conf\httpd.conf"

Write-Host "--- Iniciando Escaneo de Rutas Críticas ---" -ForegroundColor Cyan

# 2. Extraer rutas del archivo de configuración
if (Test-Path $confFile) {
    Write-Host "[+] Verificando carpetas configuradas en httpd.conf" -ForegroundColor White
    $content = Get-Content $confFile
    
    # Buscamos ServerRoot, DocumentRoot y Listen
    $sRoot = ($content | Select-String "^ServerRoot\s+`"(.+?)`"" | ForEach-Object { $_.Matches.Groups[1].Value }) -replace '"', ''
    $dRoot = ($content | Select-String "^DocumentRoot\s+`"(.+?)`"" | ForEach-Object { $_.Matches.Groups[1].Value }) -replace '"', ''
    
    $rutas = @{ "ServerRoot" = $sRoot; "DocumentRoot" = $dRoot }

    foreach ($nombre in $rutas.Keys) {
        $ruta = $rutas[$nombre]
        if ($ruta) {
            if (Test-Path $ruta) {
                Write-Host ("    - " + $nombre + " [" + $ruta + "] - OK (Existe)") -ForegroundColor Green
            } else {
                Write-Host ("    - " + $nombre + " [" + $ruta + "] - ERROR (No existe o inaccesible)") -ForegroundColor Red
            }
        } else {
            Write-Host ("    - " + $nombre + " - No encontrada en el .conf (Usando valor por defecto)") -ForegroundColor Yellow
        }
    }
}

# 3. Diagnóstico de Puertos (80/443) con Taskkill automático
Write-Host "`n[+] Analizando y liberando puertos" -ForegroundColor White
$puertos = @(80, 443)
foreach ($p in $puertos) {
    $c = Get-NetTCPConnection -LocalPort $p -State Listen -ErrorAction SilentlyContinue
    if ($c) {
        $proc = Get-Process -Id $c.OwningProcess
        Write-Host ("    - Puerto " + $p + " ocupado por " + $proc.ProcessName + " (PID " + $proc.Id + ")") -ForegroundColor Red
        Write-Host "    - Intentando cerrar proceso bloqueador..." -ForegroundColor Gray
        taskkill /F /PID $proc.Id /T 2>$null
        Start-Sleep -Seconds 1
    } else {
        Write-Host ("    - Puerto " + $p + " - LIBRE") -ForegroundColor Green
    }
}

# 4. Intento final de arranque manual para ver el error
Write-Host "`n[+] Prueba de arranque forzado (Mira si sale algun error abajo):" -ForegroundColor Cyan
& $apacheExe -t 2>&1 | Out-String | Write-Host -ForegroundColor Yellow

Write-Host "`n--- Escaneo Finalizado ---"




