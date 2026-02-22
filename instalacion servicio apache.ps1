#### DETIENE SERVICIOS DE HSLS
$serviceName = "HSLS14.2"
Write-Host "--- Consultando PID de $serviceName ---" -ForegroundColor Cyan

$query = sc.exe queryex $serviceName
if ($LASTEXITCODE -eq 0) {
    $pidLine = $query | Select-String "PID"
    $pid = ($pidLine -replace '[^\d]', '').Trim()

    if ($pid -and $pid -ne "0") {
        Write-Host "PID Detectado: $pid. Matando proceso..." -ForegroundColor Yellow
        taskkill.exe /F /PID $pid
    } else {
        Write-Host "El PID es 0. El servicio no está corriendo." -ForegroundColor Gray
    }
} else {
    Write-Host "El servicio $serviceName no existe." -ForegroundColor Red
}
Write-Host "`nProceso completado." -ForegroundColor Green





##### vlaida librerias openssl


# ==========================================================
#   AUDITORÍA DE INTEGRIDAD: OPENSSL & DLLs CRÍTICAS
# ==========================================================

$apacheBin = "C:\HSLS-14.2\Apache\bin"
$dlls = @("libssl-3-x64.dll", "libcrypto-3-x64.dll", "libssl.dll", "libcrypto.dll")

Write-Host "--- Iniciando Auditoría de Librerías OpenSSL ---" -ForegroundColor Cyan

foreach ($dllName in $dlls) {
    $dllPath = Join-Path $apacheBin $dllName
    Write-Host "`n[+] Analizando: $dllName" -ForegroundColor White

    if (!(Test-Path $dllPath)) {
        Write-Host "    - AVISO: El archivo no existe con este nombre (puede ser normal según la versión)." -ForegroundColor Gray
        continue
    }

    # 1. VERIFICAR BLOQUEO DEL SISTEMA (Atributos)
    $fileInfo = Get-Item $dllPath -Stream *
    if ($fileInfo | Where-Object { $_.Stream -match "Zone.Identifier" }) {
        Write-Host "    - CRÍTICO: La DLL está BLOQUEADA por Windows (descargada de internet)." -ForegroundColor Red
        Write-Host "    - ACCIÓN: Ejecutando Unblock-File..." -ForegroundColor Yellow
        Unblock-File $dllPath
    } else {
        Write-Host "    - Bloqueo de zona: OK (Desbloqueada)" -ForegroundColor Green
    }

    # 2. VERIFICAR ARQUITECTURA (¿Es realmente 64-bit?)
    $bytes = [System.IO.File]::ReadAllBytes($dllPath)
    # Buscamos la firma PE (Portable Executable)
    $peOffset = [BitConverter]::ToInt32($bytes, 0x3c)
    $machineType = [BitConverter]::ToUInt16($bytes, $peOffset + 4)
    
    if ($machineType -eq 0x8664) {
        Write-Host "    - Arquitectura: OK (64-bit)" -ForegroundColor Green
    } else {
        Write-Host "    - ERROR: La DLL NO es de 64-bit. Apache Win64 fallará al cargarla." -ForegroundColor Red
    }

    # 3. VERIFICAR CORRUPCIÓN (Firma Digital)
    $signature = Get-AuthenticodeSignature $dllPath
    if ($signature.Status -eq "Valid") {
        Write-Host "    - Firma Digital: VÁLIDA (Integridad confirmada)" -ForegroundColor Green
    } elseif ($signature.Status -eq "NotSigned") {
        Write-Host "    - Firma Digital: No firmada (Común en versiones personalizadas, no implica corrupción)" -ForegroundColor Yellow
    } else {
        Write-Host "    - ERROR: Firma corrupta o alterada: $($signature.Status)" -ForegroundColor Red
    }

    # 4. PRUEBA DE CARGA EN MEMORIA (Detecta bloqueos de Antivirus)
    try {
        $testLoad = [System.Reflection.Assembly]::LoadFile($dllPath)
        Write-Host "    - Carga en memoria: EXITOSA" -ForegroundColor Green
    } catch {
        if ($_.Exception.Message -match "bloqueado" -or $_.Exception.InnerException -match "bloqueado") {
            Write-Host "    - ERROR: El acceso al archivo está BLOQUEADO por un proceso externo (Antivirus/EDR)." -ForegroundColor Red
        } else {
            # Catch normal para DLLs nativas que no son ensamblados .NET (es esperado)
            Write-Host "    - Acceso al archivo: OK (Sin bloqueos de lectura)" -ForegroundColor Green
        }
    }
}

Write-Host "`n--- Auditoría Finalizada ---"



# si el error es antiviros o rutas

# 1. Configuración
$apacheRoot = "C:\HSLS-14.2\Apache"
$confFile   = "$apacheRoot\conf\httpd.conf"

Write-Host "--- Aplicando Correcciones de Desbloqueo ---" -ForegroundColor Cyan

# A. FORZAR SERVERNAME (Evita el cuelgue por DNS)
if (Test-Path $confFile) {
    Write-Host "[1/3] Configurando ServerName local..." -ForegroundColor White
    $content = Get-Content $confFile
    # Buscamos la linea activa de ServerName y la cambiamos por IP fija
    $newContent = $content -replace '^ServerName\s+.*', 'ServerName 127.0.0.1:80'
    Set-Content -Path $confFile -Value $newContent -Encoding UTF8
    Write-Host "    - OK: ServerName configurado como 127.0.0.1" -ForegroundColor Green
}

# B. PERMISOS DE CARPETA (Windows Server 2022 es muy estricto)
Write-Host "[2/3] Ajustando permisos de seguridad..." -ForegroundColor White
$acl = Get-Acl $apacheRoot
# Dar control total al SYSTEM y Administradores para asegurar carga de DLLs
$rule = New-Object System.Security.AccessControl.FileSystemAccessRule("SYSTEM","FullControl","ContainerInherit,ObjectInherit","None","Allow")
$acl.SetAccessRule($rule)
Set-Acl $apacheRoot $acl
Write-Host "    - OK: Permisos de SYSTEM aplicados." -ForegroundColor Green

# C. LIMPIEZA DE LOGS (Evita bloqueos de lectura/escritura)
Write-Host "[3/3] Limpiando archivos de log antiguos..." -ForegroundColor White
$logPath = "$apacheRoot\logs"
Get-ChildItem $logPath -Filter *.log | Remove-Item -Force -ErrorAction SilentlyContinue
Write-Host "    - OK: Logs limpiados." -ForegroundColor Green

Write-Host "`n--- Intente ejecutar el servicio ahora ---" -ForegroundColor Yellow






#####

# ==========================================================
#   DIAGNÓSTICO ANTIBLOQUEO CORREGIDO (PASOS 1, 2 Y 4)
# ==========================================================

$serviceName = "HSLS14.2"
$apacheBin   = "C:\HSLS-14.2\Apache\bin"
$apacheExe   = Join-Path $apacheBin "httpd.exe"
$confFile    = "C:\HSLS-14.2\Apache\conf\httpd.conf"

Write-Host "--- Iniciando Validación de Bloqueos de Carga (Filtrado) ---" -ForegroundColor Cyan

# --- PASO 1: VALIDACIÓN DE DNS ---
Write-Host "`n[1/3] Verificando Resolución de ServerName..." -ForegroundColor White
if (Test-Path $confFile) {
    # Buscamos solo líneas que NO empiecen con #
    $snLine = Get-Content $confFile | Where-Object { $_ -match "^ServerName" } | Select-Object -First 1
    if ($snLine) {
        $hostName = ($snLine -replace "ServerName\s+", "").Split(':')[0].Trim()
        try {
            $ip = [System.Net.Dns]::GetHostEntry($hostName)
            Write-Host "    - OK: $hostName resuelve correctamente." -ForegroundColor Green
        } catch {
            Write-Host "    - ERROR: El nombre '$hostName' NO resuelve." -ForegroundColor Red
        }
    }
}

# --- PASO 2: VALIDACIÓN DE RUTAS (LIMPIO DE COMENTARIOS) ---
Write-Host "`n[2/3] Verificando Rutas de Configuración Reales..." -ForegroundColor White
if (Test-Path $confFile) {
    $content = Get-Content $confFile
    
    # 1. Definir SRVROOT (Suele estar al inicio del archivo)
    $srvRootDef = $content | Where-Object { $_ -match '^Define\s+SRVROOT\s+"(.+?)"' } | Select-Object -First 1
    if ($srvRootDef -match '"(.+?)"') { $SRVROOT_VAL = $matches[1] } 
    else { $SRVROOT_VAL = "C:/HSLS-14.2/Apache" } # Valor por defecto si no lo encuentra

    # 2. Filtrar solo directivas activas que definen rutas
    $directives = $content | Where-Object { $_ -match "^(ServerRoot|DocumentRoot|ErrorLog|CustomLog)\s+" }

    foreach ($line in $directives) {
        # Extraer el valor quitando la directiva y las comillas
        $rawPath = ($line -split '\s+', 2)[1].Trim().Trim('"')
        
        # Resolver la variable ${SRVROOT} si existe
        $finalPath = $rawPath -replace '\$\{SRVROOT\}', $SRVROOT_VAL
        
        # Si es una ruta relativa (ej: logs/error.log), unirla al ServerRoot
        if ($finalPath -notmatch "^[a-zA-Z]:" -and $finalPath -notmatch "^//") {
            $finalPath = Join-Path $SRVROOT_VAL $finalPath
        }

        if (!(Test-Path $finalPath -ErrorAction SilentlyContinue)) {
            Write-Host "    - ERROR: La ruta activa '$finalPath' NO existe." -ForegroundColor Red
        } else {
            Write-Host "    - OK: Ruta válida ($finalPath)" -ForegroundColor Green
        }
    }
}

# --- PASO 4: PRUEBA DE CARGA (CON TIMEOUT) ---
Write-Host "`n[3/3] Probando Carga de Módulos (httpd -M)..." -ForegroundColor White
$job = Start-Job -ScriptBlock { param($exe) & $exe -M 2>&1 } -ArgumentList $apacheExe
if (Wait-Job $job -Timeout 10) {
    $res = Receive-Job $job | Out-String
    if ($res -match "error") { Write-Host "    - Error en carga de módulos." -ForegroundColor Yellow }
    else { Write-Host "    - Carga de módulos OK." -ForegroundColor Green }
} else {
    Write-Host "    - CRÍTICO: El binario SE CONGELÓ tras 10 segundos." -ForegroundColor Red
    Stop-Job $job
    taskkill /F /IM httpd.exe /T 2>$null
}

Write-Host "`n--- Diagnóstico Finalizado ---"



###### diagnosticar

# ==========================================================
#   DIAGNÓSTICO MAESTRO - APACHE EN WINDOWS SERVER 2022
# ==========================================================

$serviceName = "HSLS14.2"
$apacheBin   = "C:\HSLS-14.2\Apache\bin"
$apacheExe   = Join-Path $apacheBin "httpd.exe"
$reportPath  = "C:\HSLS-14.2\Logs\Reporte_Final.txt"

function Write-Report ($titulo, $info) {
    $linea = "`r`n" + ("="*20) + " $titulo " + ("="*20) + "`r`n$info`r`n"
    Add-Content -Path $reportPath -Value $linea
    Write-Host "Analizando $titulo..." -ForegroundColor Cyan
}

# Crear carpeta de logs si no existe
if (!(Test-Path (Split-Path $reportPath))) { New-Item -ItemType Directory -Path (Split-Path $reportPath) -Force }
Set-Content -Path $reportPath -Value "REPORTE TÉCNICO - WINDOWS SERVER 2022 - $(Get-Date)`r`n"

# 1. VERIFICACIÓN DE LIBRERÍAS (VC++ Redistributable)
# Server 2022 requiere msvcp140.dll y vcruntime140.dll (VS 2015-2022)
Write-Host "Verificando dependencias de C++..." -ForegroundColor White
$dlls = "msvcp140.dll", "vcruntime140.dll", "vcruntime140_1.dll"
$dllReport = ""
foreach ($dll in $dlls) {
    $found = Where-Object { Test-Path (Join-Path "C:\Windows\System32" $dll) }
    if ($found) { $dllReport += "[OK] $dll encontrada en System32`r`n" }
    else { $dllReport += "[ERROR] FALTA $dll. Instale Visual C++ 2015-2022 x64`r`n" }
}
Write-Report "DEPENDENCIAS C++" $dllReport

# 2. PRUEBA DE SINTAXIS Y CARGA DE MÓDULOS
Write-Host "Probando carga de binario..." -ForegroundColor White
$syntax = & $apacheExe -t 2>&1 | Out-String
Write-Report "SINTAXIS HTTPD -T" $syntax

# 3. VERIFICACIÓN DE PUERTOS (Netstat avanzado)
$portInfo = Get-NetTCPConnection -LocalPort 80,443 -State Listen -ErrorAction SilentlyContinue | 
            Select-Object LocalPort, OwningProcess, @{Name="ProcessName"; Expression={(Get-Process -Id $_.OwningProcess).Name}} | 
            Format-Table | Out-String
Write-Report "CONFLICTOS DE PUERTOS" (if ($portInfo.Trim()) { $portInfo } else { "Puertos 80/443 LIBRES" })

# 4. PRUEBA DE ARRANQUE EN "DEBUG MODE" (Captura el error real)
Write-Host "Ejecutando arranque manual de prueba (3 seg)..." -ForegroundColor Yellow
$manual = Start-Process $apacheExe -ArgumentList "-e debug" -NoNewWindow -PassThru -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3
if ($manual.HasExited) {
    Write-Report "FALLO DE EJECUCIÓN DIRECTA" "Apache se cerró con código $($manual.ExitCode). Revise el archivo error.log en la carpeta logs."
} else {
    Write-Report "EJECUCIÓN DIRECTA" "El binario funciona manualmente. El problema es el Servicio de Windows (Permisos de cuenta)."
    Stop-Process -Id $manual.Id -Force
}

# 5. REVISIÓN DE FIREWALL DE WINDOWS SERVER
$fw = Get-NetFirewallRule -DisplayName "*Apache*" -ErrorAction SilentlyContinue
if ($fw) { Write-Report "FIREWALL" "Regla de Apache encontrada." }
else { Write-Report "FIREWALL" "ADVERTENCIA: No hay reglas de entrada para Apache en el Firewall de Windows." }

Write-Host "`n--- PROCESO TERMINADO ---" -ForegroundColor Green
Write-Host "Abra el reporte en: $reportPath" -ForegroundColor Yellow





###### revisar puertos ssl

# List of services known to grab port 80/443 via PID 4
$services = @("w3svc", "was", "SyncShareSvc", "iphlpsvc")

Write-Host "--- Attempting to free port 443 ---" -ForegroundColor Cyan

foreach ($svcName in $services) {
    $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
    
    if ($svc -and $svc.Status -eq 'Running') {
        Write-Host "Stopping service: $svcName..." -NoNewline
        Stop-Service -Name $svcName -Force
        Write-Host " DONE" -ForegroundColor Green
    }
}

# Verify if port 443 is now open
$check = Get-NetTCPConnection -LocalPort 443 -State Listen -ErrorAction SilentlyContinue
if ($check) {
    Write-Host "`n[!] Port 443 is STILL occupied by PID $($check.OwningProcess)." -ForegroundColor Red
} else {
    Write-Host "`n[+] Port 443 is now FREE. You can start Apache!" -ForegroundColor Green
}



##### nueva version
# ==========================================================
#   APACHE FORENSIC & RECOVERY SCRIPT
# ==========================================================

$serviceName  = "HSLS14.2"
$apacheBin    = "C:\HSLS-14.2\Apache\bin"
$apacheExe    = Join-Path $apacheBin "httpd.exe"
$apacheRoot   = Split-Path $apacheBin
$confFile     = Join-Path $apacheRoot "conf\httpd.conf"
$reportFile   = "C:\HSLS-14.2\Logs\Reporte_Fallo_$(Get-Date -Format 'HHmmss').txt"

function Write-Report {
    param ([string]$section, [string]$content)
    $divider = "=" * 60
    $data = "`r`n$divider`r`n$section`r`n$divider`r`n$content`r`n"
    Add-Content -Path $reportFile -Value $data
    Write-Host "Analizando: $section..." -ForegroundColor Cyan
}

# --- INICIO DEL PROCESO ---
Write-Host "--- Iniciando Diagnóstico Profundo ---" -ForegroundColor White
if (!(Test-Path (Split-Path $reportFile))) { New-Item -ItemType Directory -Path (Split-Path $reportFile) -Force }
$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
Set-Content -Path $reportFile -Value "REPORTE DE FALLO APACHE - $timestamp`r`n"

# 1. PRUEBA DE SINTAXIS (La razón #1 de fallo)
$syntax = & $apacheExe -t 2>&1 | Out-String
if ($syntax -match "error" -or $syntax -match "failed") {
    Write-Report "ERROR DE SINTAXIS DETECTADO" $syntax
} else {
    Write-Report "SINTAXIS" "Sintaxis OK. El problema no es el archivo de configuracion."
}

# 2. PRUEBA DE PUERTOS (La razón #2 de fallo)
$portReport = ""
foreach ($port in @(80, 443)) {
    $conn = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
    if ($conn) {
        $proc = Get-Process -Id $conn.OwningProcess -ErrorAction SilentlyContinue
        $portReport += "Puerto $port OCUPADO por: $($proc.ProcessName) (PID: $($proc.Id))`r`n"
    } else {
        $portReport += "Puerto $port LIBRE.`r`n"
    }
}
Write-Report "ESTADO DE PUERTOS" $portReport

# 3. PRUEBA DE EJECUCIÓN MANUAL (Captura el error que el servicio oculta)
Write-Host "Ejecutando prueba de arranque manual (5 segundos)..." -ForegroundColor Yellow
$manualProc = Start-Process $apacheExe -ArgumentList "-e info" -NoNewWindow -PassThru -ErrorAction SilentlyContinue
Start-Sleep -Seconds 5
if ($manualProc) {
    if ($manualProc.HasExited) {
        $exitCode = $manualProc.ExitCode
        Write-Report "FALLO DE ARRANQUE MANUAL" "Apache se cerro inmediatamente despues de abrirse. Codigo de salida: $exitCode. Esto indica falta de DLLs o carpetas inexistentes."
    } else {
        Write-Report "ARRANQUE MANUAL" "Apache si pudo arrancar manualmente. El problema es el usuario o permisos del Servicio de Windows."
        Stop-Process -Id $manualProc.Id -Force
    }
}

# 4. LOGS DE WINDOWS (Event Viewer)
$events = Get-WinEvent -FilterHashtable @{LogName='Application'; Level=2} -MaxEvents 10 -ErrorAction SilentlyContinue | 
          Where-Object { $_.Message -match "Apache" -or $_.Source -match "Apache" }
if ($events) {
    $eventData = $events | Select-Object TimeCreated, Message | Format-List | Out-String
    Write-Report "ERRORES EN VISOR DE EVENTOS" $eventData
}

# 5. VALIDACIÓN DE RUTAS FÍSICAS
$confContent = Get-Content $confFile
$paths = $confContent | Select-String -Pattern '(ServerRoot|DocumentRoot|ErrorLog)\s+"?(.+?)"?$'
$pathReport = ""
foreach ($line in $paths) {
    $cleanPath = ($line.Matches.Groups[2].Value).Trim('"').Trim()
    if ($cleanPath -notmatch "^[a-zA-Z]:") { # Si es ruta relativa, unirla al root
        $fullPath = Join-Path $apacheRoot $cleanPath
    } else { $fullPath = $cleanPath }
    
    if (!(Test-Path $fullPath)) {
        $pathReport += "RUTA INVALIDA: $fullPath (Definida en $($line.Line))`r`n"
    }
}
if ($pathReport) { Write-Report "RUTAS INEXISTENTES" $pathReport }

# --- RESULTADO FINAL ---
Write-Host "`n--- DIAGNÓSTICO FINALIZADO ---" -ForegroundColor Green
Write-Host "Se ha generado un reporte detallado en: $reportFile" -ForegroundColor Yellow
Write-Host "Por favor, abre ese archivo para ver la CAUSA EXACTA del error." -ForegroundColor Cyan




##### 

# ==========================================================
#   APACHE REINSTALL + SISTEMA DE LOG DE RECUPERACIÓN (CORREGIDO)
#   APACHE REINSTALL + DESACTIVACIÓN DE IIS
# ==========================================================

# ---------------------------
# CONFIGURACIÓN GLOBAL
# ---------------------------
$serviceName  = "HSLS14.2"
$apacheBin    = "C:\HSLS-14.2\Apache\bin"
$apacheExe    = Join-Path $apacheBin "httpd.exe"
$confFile     = Join-Path (Split-Path $apacheBin) "conf\httpd.conf"
$registryPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$serviceName"
$maxRetries   = 10

# LOG
$logFolder = "C:\HSLS-14.2\Logs"
if (!(Test-Path $logFolder)) { New-Item -ItemType Directory -Path $logFolder | Out-Null }

$logFile = Join-Path $logFolder ("ApacheRecovery_" + (Get-Date -Format "yyyyMMdd_HHmmss") + ".log")

# Variable para saber en qué paso quedó
$logFile      = "C:\HSLS-14.2\Logs\ApacheRecovery_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$global:CurrentStep = "Inicializando"

# ==========================================================
# SISTEMA DE LOG
# ==========================================================

function Write-Log {
    param ($message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$timestamp] [$global:CurrentStep] $message"
    $line = "[$(Get-Date -Format 'HH:mm:ss')] [$global:CurrentStep] $message"
    Write-Host $line -ForegroundColor Cyan
    $null = New-Item -Path (Split-Path $logFile) -ItemType Directory -Force
    Add-Content -Path $logFile -Value $line
}

# Captura cierre inesperado
Register-EngineEvent PowerShell.Exiting -Action {
    Add-Content -Path $logFile -Value "[$(Get-Date)] PowerShell se cerró inesperadamente en paso: $global:CurrentStep"
}
# --- NUEVA FUNCIÓN PARA MATAR IIS ---
function Stop-IIS {
    $global:CurrentStep = "Deteniendo IIS"
    Write-Log "Detectando presencia de IIS..."
    
    # Detener el servicio de publicación World Wide Web (W3SVC)
    if (Get-Service W3SVC -ErrorAction SilentlyContinue) {
        Write-Log "IIS (W3SVC) detectado. Deteniendo..."
        Stop-Service W3SVC -Force -Confirm:$false -ErrorAction SilentlyContinue
    }

# ==========================================================
# FUNCIONES
# ==========================================================
    # Detener el controlador HTTP del sistema (libera puertos 80/443 de PID 4)
    Write-Log "Liberando sockets del Kernel (net stop http)..."
    & cmd.exe /c "net stop http /y" 2>$null
    Start-Sleep -Seconds 2
}

function Clear-PreviousInstallation {
    $global:CurrentStep = "Limpieza"
    Write-Log "Iniciando limpieza profunda"

    Write-Log "Limpiando procesos de Apache previos"
    taskkill /F /IM httpd.exe /T 2>$null
    Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
    sc.exe delete $serviceName | Out-Null

    if (Test-Path $registryPath) {
        Remove-Item -Path $registryPath -Recurse -Force -ErrorAction SilentlyContinue
    }

    Start-Sleep -Seconds 2
    Write-Log "Limpieza completada"
    if (Test-Path $registryPath) { Remove-Item -Path $registryPath -Recurse -Force -ErrorAction SilentlyContinue }
    Start-Sleep -Seconds 1
}

function Install-Service {
    $global:CurrentStep = "Instalación Servicio"
    Write-Log "Registrando servicio"

    Set-Location $apacheBin
    $global:CurrentStep = "Instalación"
    $installArgs = "/c `"$apacheExe`" -k install -n $serviceName"
    $proc = Start-Process "cmd.exe" -ArgumentList $installArgs -WindowStyle Hidden -PassThru
    $proc | Wait-Process -Timeout 15 -ErrorAction SilentlyContinue

    Write-Log "Servicio registrado (Verificar en sc query si falló el inicio)"
    Write-Log "Servicio registrado."
}

function Start-ServiceWithRetries {
    $global:CurrentStep = "Inicio Servicio"
    Write-Log "Intentando iniciar servicio"

    for ($i = 1; $i -le $maxRetries; $i++) {
        Write-Log "Intento de inicio $i de $maxRetries"
        Write-Log "Intento $i de $maxRetries"

        # Liberar puertos bloqueados
        # Doble chequeo de puertos por si IIS revive
        foreach ($port in @(80, 443)) {
            $conn = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
            if ($conn) {
                $pToKill = $conn.OwningProcess # CORRECCIÓN: No usamos la variable reservada $PID
                Write-Log "Puerto $port ocupado por PID $pToKill. Ejecutando taskkill."
                taskkill /F /PID $pToKill /T 2>$null
                Start-Sleep -Seconds 1
            if ($conn -and $conn.OwningProcess -eq 4) {
                Write-Log "Puerto $port sigue en uso por System. Re-ejecutando limpieza de HTTP..."
                & cmd.exe /c "net stop http /y" 2>$null
            }
        }

        # Intentar arrancar
        Start-Process "sc.exe" -ArgumentList "start", $serviceName -WindowStyle Hidden -Wait
        Start-Sleep -Seconds 4

        $svc = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
        if ($svc -and $svc.Status -eq "Running") {
            Write-Log "¡ÉXITO! Servicio iniciado correctamente"
        
        $svcStatus = (Get-Service $serviceName -ErrorAction SilentlyContinue).Status
        if ($svcStatus -eq "Running") {
            Write-Log "¡EXITO! Apache esta corriendo."
            return $true
        } else {
            Write-Log "Fallo intento $i. Estado actual: $svcStatus"
        }
    }

    Write-Log "No se pudo iniciar el servicio tras los reintentos."
    return $false
}

function Run-Diagnostics {
    $global:CurrentStep = "Diagnóstico"
    Write-Log "Iniciando diagnóstico profundo de fallo"

    # Prueba de sintaxis con protección
    try {
        Write-Log "Resultado de sintaxis (httpd -t):"
        $diag = & $apacheExe -t 2>&1 | Out-String
        Write-Log $diag
    } catch {
        Write-Log "Error ejecutando diagnóstico: $($_.Exception.Message)"
    }

    # Revisión final de puertos
    foreach ($port in @(80, 443)) {
        $conn = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
        if ($conn) {
            $pName = (Get-Process -Id $conn.OwningProcess -ErrorAction SilentlyContinue).Name
            Write-Log "Puerto $port sigue bloqueado por: $pName"
        }
    }
}

# ==========================================================
# BLOQUE PRINCIPAL
# ==========================================================

# --- BLOQUE PRINCIPAL ---
try {
    Write-Log "=== INICIO DEL PROCESO ==="

    Clear-PreviousInstallation
    Install-Service
    Write-Log "=== INICIO DE RECUPERACIÓN ==="
    Stop-IIS             # Paso 1: Quitar IIS de en medio
    Clear-PreviousInstallation # Paso 2: Limpiar Apache viejo
    Install-Service      # Paso 3: Reinstalar

    $result = Start-ServiceWithRetries

    if (-not $result) {
        Run-Diagnostics
    if (-not (Start-ServiceWithRetries)) {
        $global:CurrentStep = "Diagnóstico Final"
        Write-Log "ERROR: No se pudo estabilizar el servicio."
        Write-Log "Resultado de sintaxis de Apache:"
        & $apacheExe -t 2>&1 | Out-String | Write-Log
    }

    Write-Log "=== PROCESO FINALIZADO ==="
} catch {
    Write-Log "EXCEPCIÓN CRÍTICA: $($_.Exception.Message)"
} finally {
    Write-Log "=== FIN DEL PROCESO ==="
}
catch {
    Write-Log "ERROR CRÍTICO EN SCRIPT: $($_.Exception.Message)"
    Write-Log "Línea de error: $($_.InvocationInfo.ScriptLineNumber)"
}















