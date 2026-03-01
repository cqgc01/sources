
# Crear punto de restauración (ejecutar como Administrador)
Checkpoint-Computer -Description "Backup antes de eliminar servicio" -RestorePointType "MODIFY_SETTINGS"
-------------

# Remove-Service-Complete.ps1
# Ejecutar SIEMPRE como Administrador

param(
    [Parameter(Mandatory=$true)]
    [string]$ServiceName,
    
    [Parameter(Mandatory=$true)]
    [string]$ServiceDisplayName,
    
    [switch]$WhatIf,        # Solo mostrar lo que se haría
    [switch]$Force,         # Omitir confirmaciones
    [switch]$BackupRegistry # Crear backup del registro antes de eliminar
)

# Verificar privilegios de administrador
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "⚠️  Este script debe ejecutarse como Administrador"
    exit 1
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Eliminación Completa de Servicio" -ForegroundColor Cyan
Write-Host "  Servicio: $ServiceDisplayName ($ServiceName)" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Función para crear backup de clave de registro
function Backup-RegistryKey {
    param([string]$KeyPath)
    $BackupPath = "$env:TEMP\RegistryBackup_$(Get-Date -Format 'yyyyMMdd_HHmmss').reg"
    reg export "$KeyPath" "$BackupPath" /y 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  ✓ Backup creado: $BackupPath" -ForegroundColor Green
        return $BackupPath
    }
    return $null
}

# Función para eliminar clave de registro con manejo de errores
function Remove-RegistryKeySafe {
    param([string]$KeyPath)
    try {
        if (Test-Path "Registry::$KeyPath") {
            Remove-Item -Path "Registry::$KeyPath" -Recurse -Force -ErrorAction Stop
            Write-Host "  ✓ Eliminado: $KeyPath" -ForegroundColor Green
            return $true
        } else {
            Write-Host "  ℹ No encontrado: $KeyPath" -ForegroundColor Yellow
            return $false
        }
    }
    catch {
        Write-Warning "  ✗ Error al eliminar $KeyPath : $_"
        return $false
    }
}

# ==================== PASO 1: Detener y eliminar servicio ====================
Write-Host "[1/6] Deteniendo y eliminando servicio..." -ForegroundColor Yellow

$service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($service) {
    if ($service.Status -ne 'Stopped') {
        Write-Host "  • Deteniendo servicio..."
        Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 3
    }
    
    if ($WhatIf) {
        Write-Host "  [WhatIf] Se eliminaría el servicio: $ServiceName" -ForegroundColor Cyan
    } else {
        sc.exe delete $ServiceName | Out-Null
        Start-Sleep -Seconds 2
        Write-Host "  ✓ Servicio eliminado con sc.exe" -ForegroundColor Green
    }
} else {
    Write-Host "  ℹ El servicio '$ServiceName' no está instalado o ya fue eliminado" -ForegroundColor Yellow
}

# ==================== PASO 2: Limpieza de Registro - Servicios ====================
Write-Host ""
Write-Host "[2/6] Limpiando registro de servicios..." -ForegroundColor Yellow

$ServiceRegPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$ServiceName"
if ($BackupRegistry) { Backup-RegistryKey "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\$ServiceName" }
Remove-RegistryKeySafe $ServiceRegPath

# También verificar en ControlSet001, ControlSet002, etc.
$ControlSets = Get-ChildItem "HKLM:\SYSTEM" -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'ControlSet[0-9]+' }
foreach ($cs in $ControlSets) {
    $path = "$($cs.PSPath)\Services\$ServiceName"
    if ($BackupRegistry -and (Test-Path $path)) { 
        Backup-RegistryKey "$($cs.Name)\Services\$ServiceName" 
    }
    Remove-RegistryKeySafe $path
}

# ==================== PASO 3: Limpieza DCOM - AppID ====================
Write-Host ""
Write-Host "[3/6] Buscando y limpiando entradas DCOM (AppID)..." -ForegroundColor Yellow

$appidPath = "HKCR:\AppID"
if (Test-Path $appidPath) {
    $appids = Get-ChildItem $appidPath -ErrorAction SilentlyContinue
    foreach ($appid in $appids) {
        try {
            $value = Get-ItemProperty $appid.PSPath -ErrorAction SilentlyContinue
            # Buscar por nombre de servicio o ejecutable
            if ($value -and ($value.AppID -like "*$ServiceName*" -or 
                            $value."(Default)" -like "*$ServiceDisplayName*" -or
                            $value.ServiceDll -like "*$ServiceName*")) {
                
                if ($BackupRegistry) { Backup-RegistryKey "$($appid.PSPath)" }
                Write-Host "  • Encontrado AppID relacionado: $($appid.PSChildName)" -ForegroundColor Magenta
                if (-not $WhatIf) {
                    Remove-Item $appid.PSPath -Recurse -Force -ErrorAction SilentlyContinue
                    Write-Host "  ✓ Eliminado AppID: $($appid.PSChildName)" -ForegroundColor Green
                }
            }
        } catch { Write-Warning "  Error procesando AppID: $($appid.PSChildName)" }
    }
}

# ==================== PASO 4: Limpieza DCOM - CLSID ====================
Write-Host ""
Write-Host "[4/6] Buscando y limpiando entradas DCOM (CLSID)..." -ForegroundColor Yellow

$clsidPath = "HKCR:\CLSID"
if (Test-Path $clsidPath) {
    $clsids = Get-ChildItem $clsidPath -ErrorAction SilentlyContinue
    foreach ($clsid in $clsids) {
        try {
            $value = Get-ItemProperty $clsid.PSPath -ErrorAction SilentlyContinue
            if ($value -and ($value."(Default)" -like "*$ServiceDisplayName*" -or
                            $value.LocalServer32 -like "*$ServiceName*" -or
                            $value.LocalService -like "*$ServiceName*")) {
                
                if ($BackupRegistry) { Backup-RegistryKey "$($clsid.PSPath)" }
                Write-Host "  • Encontrado CLSID relacionado: $($clsid.PSChildName)" -ForegroundColor Magenta
                if (-not $WhatIf) {
                    Remove-Item $clsid.PSPath -Recurse -Force -ErrorAction SilentlyContinue
                    Write-Host "  ✓ Eliminado CLSID: $($clsid.PSChildName)" -ForegroundColor Green
                }
            }
        } catch { Write-Warning "  Error procesando CLSID: $($clsid.PSChildName)" }
    }
}

# ==================== PASO 5: Limpieza adicional ====================
Write-Host ""
Write-Host "[5/6] Limpieza adicional..." -ForegroundColor Yellow

# Eliminar posibles entradas en EventLog
$EventLogReg = "HKLM:\SYSTEM\CurrentControlSet\Services\EventLog\Application\$ServiceName"
if ($BackupRegistry -and (Test-Path $EventLogReg)) { Backup-RegistryKey "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\EventLog\Application\$ServiceName" }
Remove-RegistryKeySafe $EventLogReg

# Eliminar entradas de firewall si existen
$FirewallReg = "HKLM:\SYSTEM\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy\FirewallRules"
if (Test-Path $FirewallReg) {
    $rules = Get-ItemProperty $FirewallReg -ErrorAction SilentlyContinue | 
             Get-Member -MemberType NoteProperty | 
             Where-Object { $_.Name -like "*$ServiceName*" -or $_.Name -like "*$ServiceDisplayName*" }
    foreach ($rule in $rules) {
        if (-not $WhatIf) {
            Remove-ItemProperty -Path $FirewallReg -Name $rule.Name -Force -ErrorAction SilentlyContinue
            Write-Host "  ✓ Eliminado regla de firewall: $($rule.Name)" -ForegroundColor Green
        }
    }
}

# ==================== PASO 6: Verificación final ====================
Write-Host ""
Write-Host "[6/6] Verificación final..." -ForegroundColor Yellow

$remaining = @()
$remaining += Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
$remaining += Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Services" -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "*$ServiceName*" }
$remaining += Get-ChildItem "HKCR:\AppID" -ErrorAction SilentlyContinue | Where-Object { 
    (Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue)."(Default)" -like "*$ServiceDisplayName*" 
}

if ($remaining.Count -eq 0) {
    Write-Host ""
    Write-Host "✅ ¡Eliminación completada exitosamente!" -ForegroundColor Green
    Write-Host "   Se recomienda REINICIAR el equipo para aplicar todos los cambios." -ForegroundColor Cyan
} else {
    Write-Host ""
    Write-Host "⚠️  Aún se encontraron $($remaining.Count) elementos relacionados:" -ForegroundColor Red
    $remaining | ForEach-Object { Write-Host "   • $($_.Name)" -ForegroundColor Red }
    Write-Host ""
    Write-Host "   Puede requerir reinicio o eliminación manual adicional." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan



==========
==========
# httpd-error-monitor.ps1

param(
    [int]$Days = 7,
    [string[]]$LogNames = @("Application", "System"),
    [switch]$ExportCSV,
    [string]$ExportPath = ".\httpd_errors_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv",
    [switch]$Detailed,
    [switch]$SendEmail,
    [string]$EmailTo,
    [string]$EmailFrom,
    [string]$SmtpServer
)

function Get-HttpdErrors {
    param(
        [string]$LogName,
        [datetime]$StartDate,
        [datetime]$EndDate
    )
    
    try {
        $Events = Get-WinEvent -FilterHashtable @{
            LogName = $LogName
            Level = 1,2,3
            StartTime = $StartDate
            EndTime = $EndDate
        } -ErrorAction SilentlyContinue | 
        Where-Object { 
            $_.Message -like "*httpd.exe*" -or 
            $_.ProviderName -like "*httpd*" -or
            $_.Message -like "*Apache*"
        }
        
        return $Events
    }
    catch {
        Write-Warning "Error searching $LogName : $_"
        return $null
    }
}

$StartDate = (Get-Date).AddDays(-$Days)
$EndDate = Get-Date

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  httpd.exe Event Error Detector" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Search Period: $StartDate to $EndDate"
Write-Host "Log Names: $($LogNames -join ', ')"
Write-Host ""

$AllEvents = @()

foreach ($LogName in $LogNames) {
    Write-Host "Searching $LogName log..." -ForegroundColor Yellow
    $Events = Get-HttpdErrors -LogName $LogName -StartDate $StartDate -EndDate $EndDate
    
    if ($Events) {
        $AllEvents += $Events
        Write-Host "  Found $($Events.Count) event(s) in $LogName" -ForegroundColor Green
    }
}

if ($AllEvents.Count -gt 0) {
    Write-Host ""
    Write-Host "Total Errors Found: $($AllEvents.Count)" -ForegroundColor Red
    Write-Host ""
    
    # Group by error level
    $ErrorSummary = $AllEvents | Group-Object LevelDisplayName | 
    Select-Object Name, Count | Sort-Object Count -Descending
    
    Write-Host "Error Summary:" -ForegroundColor Cyan
    $ErrorSummary | Format-Table -AutoSize
    
    if ($Detailed) {
        Write-Host ""
        Write-Host "Detailed Event Information:" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan
        
        foreach ($Event in $AllEvents) {
            Write-Host ""
            Write-Host "Time: $($Event.TimeCreated)" -ForegroundColor Yellow
            Write-Host "Level: $($Event.LevelDisplayName)" -ForegroundColor $(
                if ($Event.LevelDisplayName -eq "Error") { "Red" }
                elseif ($Event.LevelDisplayName -eq "Warning") { "Yellow" }
                else { "Green" }
            )
            Write-Host "Event ID: $($Event.Id)"
            Write-Host "Source: $($Event.ProviderName)"
            Write-Host "Message: $($Event.Message)"
            Write-Host "----------------------------------------"
        }
    }
    else {
        Write-Host ""
        Write-Host "Recent Events (Last 10):" -ForegroundColor Cyan
        $AllEvents | Select-Object -First 10 | 
        Select-Object TimeCreated, LevelDisplayName, Id, ProviderName, 
            @{Name="Message";Expression={$_.Message.Substring(0, [Math]::Min(100, $_.Message.Length))}} |
        Format-Table -AutoSize -Wrap
    }
    
    if ($ExportCSV) {
        $AllEvents | Select-Object TimeCreated, LevelDisplayName, Id, ProviderName, Message | 
        Export-Csv -Path $ExportPath -NoTypeInformation -Encoding UTF8
        Write-Host ""
        Write-Host "Results exported to: $ExportPath" -ForegroundColor Green
    }
    
    if ($SendEmail -and $EmailTo -and $EmailFrom -and $SmtpServer) {
        $Body = $AllEvents | ConvertTo-Html -Fragment | Out-String
        Send-MailMessage -To $EmailTo -From $EmailFrom -Subject "httpd.exe Errors Detected" -Body $Body -SmtpServer $SmtpServer
        Write-Host "Email notification sent to $EmailTo" -ForegroundColor Green
    }
}
else {
    Write-Host ""
    Write-Host "No httpd.exe errors found in the specified period." -ForegroundColor Green
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
=====

# Quick search for httpd.exe errors in last 24 hours
Get-WinEvent -FilterHashtable @{LogName='Application'; StartTime=(Get-Date).AddHours(-24)} | Where-Object {$_.Message -like "*httpd.exe*"}

# Count httpd.exe errors
(Get-WinEvent -FilterHashtable @{LogName='Application'; StartTime=(Get-Date).AddDays(-7)} | Where-Object {$_.Message -like "*httpd.exe*"}).Count

# Export to CSV
Get-WinEvent -FilterHashtable @{LogName='Application'; StartTime=(Get-Date).AddDays(-7)} | Where-Object {$_.Message -like "*httpd.exe*"} | Select-Object TimeCreated, LevelDisplayName, Id, Message | Export-Csv httpd_errors.csv -NoTypeInformation
======

$f1 = Get-ChildItem -Recurse -Path "C:\ruta\carpeta1"
$f2 = Get-ChildItem -Recurse -Path "C:\ruta\carpeta2"

Compare-Object -ReferenceObject $f1 -DifferenceObject $f2 -Property Name, Length -PassThru


############

$hostsPath = "C:\Windows\System32\drivers\etc\hosts"

Write-Host "--- Otorgando Control Total sobre el archivo Hosts ---" -ForegroundColor Cyan

try {
    # 1. Quitar el atributo de 'Solo lectura' (Read-only) del sistema
    attrib -r $hostsPath

    # 2. Obtener el ACL actual
    $acl = Get-Acl $hostsPath

    # 3. Crear la regla: Usuario actual + Control Total + Permitir
    $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule($currentUser, "FullControl", "Allow")

    # 4. Aplicar la regla al objeto ACL y guardarlo en el archivo
    $acl.SetAccessRule($rule)
    Set-Acl -Path $hostsPath -AclObject $acl

    Write-Host "[OK] Permisos concedidos a: $currentUser" -ForegroundColor Green
}
catch {
    Write-Host "[ERROR] No se pudo cambiar los permisos. Detalle: $($_.Exception.Message)" -ForegroundColor Red
}


#############



$hostsPath = "C:\Windows\System32\drivers\etc\hosts"
$nombreBusqueda = "localhost" # Cambia esto por el nombre que quieres probar

Write-Host "--- Validando Archivo Hosts ---" -ForegroundColor Cyan

# A. Verificar existencia y permisos
if (Test-Path $hostsPath) {
    Write-Host "[OK] Archivo encontrado." -ForegroundColor Green
} else {
    Write-Host "[ERROR] El archivo no existe en la ruta estandar." -ForegroundColor Red
}

# B. Buscar el nombre dentro del texto
$linea = Get-Content $hostsPath | Where-Object { $_ -match "^[^#].*$nombreBusqueda" }
if ($linea) {
    Write-Host "[OK] Se encontro la regla activa: $linea" -ForegroundColor Green
} else {
    Write-Host "[AVISO] No se encontro una regla activa para '$nombreBusqueda'." -ForegroundColor Yellow
}

# C. Limpiar Cache de DNS (Paso critico para que funcione)
Write-Host "Limpiando cache de DNS para refrescar cambios..." -ForegroundColor Gray
ipconfig /flushdns | Out-Null
Write-Host "[OK] Cache limpia." -ForegroundColor Green



#####este hace que pase la valdiacion de sintaxis httpd.conf

# 1. Configuración de rutas
$serviceName = "HSLS14.2"
$apacheBin = "C:\HSLS-14.2\Apache\bin"
$apacheExe = "$apacheBin\httpd.exe"

Write-Host "--- DESBLOQUEO CRÍTICO DE VALIDACIÓN ---" -ForegroundColor Cyan

# 2. MATAR PROCESOS ZOMBIES (Culpables de que se quede pegado)
Write-Host "[1/4] Forzando cierre de cualquier instancia de Apache..." -ForegroundColor Yellow
taskkill /F /IM httpd.exe /T 2>$null
taskkill /F /IM conhost.exe /T 2>$null # A veces la consola se queda trabada con el proceso
Start-Sleep -Seconds 2

# 3. PRUEBA DE EJECUCIÓN DIRECTA (MODO DEPURACIÓN)
# Si -t se queda pegado, -X nos dirá qué módulo es el que causa el cuelgue
Write-Host "[2/4] Intentando cargar en Modo Depuración (Timeout 10s)..." -ForegroundColor Cyan
Set-Location $apacheBin

$job = Start-Job -ScriptBlock {
    param($exe)
    & $exe -X -t 2>&1
} -ArgumentList $apacheExe

Wait-Job $job -Timeout 10
$output = Receive-Job $job
Stop-Job $job
Remove-Job $job

if ($output) {
    Write-Host "SALIDA DETECTADA: $output" -ForegroundColor Magenta
} else {
    Write-Host "ADVERTENCIA: La validación sigue sin responder. Posible bloqueo de Antivirus o DLL faltante." -ForegroundColor Red
}

# 4. TRUCO DE REEMPLAZO DE SERVICIO (Por si el registro está corrupto)
Write-Host "[3/4] Limpiando servicio y registro..." -ForegroundColor Yellow
sc.exe stop $serviceName 2>$null
sc.exe delete $serviceName 2>$null
Remove-Item -Path "HKLM:\SYSTEM\CurrentControlSet\Services\$serviceName" -Recurse -Force -ErrorAction SilentlyContinue

# 5. REGISTRO RÁPIDO E INTENTO DE ARRANQUE POR CMD
Write-Host "[4/4] Reinstalando y arrancando desde CMD..." -ForegroundColor Cyan
cmd.exe /c "$apacheExe -k install -n $serviceName"
Start-Sleep -Seconds 2
cmd.exe /c "net start $serviceName"

Write-Host "`n------------------------------------------------"
Read-Host "Proceso terminado. Presiona ENTER para salir"



######### este valida error 1053

# 1. Configuración de rutas
$serviceName = "HSLS14.2"
$apacheBin = "C:\HSLS-14.2\Apache\bin"
$apacheExe = "$apacheBin\httpd.exe"
$logFile = "C:\HSLS-14.2\Apache\logs\error.log"

Write-Host "--- SOLUCIONANDO ERROR 1053 EN $serviceName ---" -ForegroundColor Cyan

# 2. Limpieza de procesos previos para evitar bloqueos de archivos
Write-Host "[1/4] Limpiando procesos huérfanos..." -ForegroundColor Yellow
taskkill /F /IM httpd.exe /T 2>$null
Start-Sleep -Seconds 2

# 3. PRUEBA DE FUEGO: ¿Por qué no arranca? (Validación de Sintaxis)
Write-Host "[2/4] Validando sintaxis de httpd.conf..." -ForegroundColor Cyan
Set-Location $apacheBin
$syntaxCheck = & $apacheExe -t 2>&1

if ($syntaxCheck -match "Syntax error" -or $syntaxCheck -match "error") {
    Write-Host "¡ERROR DE CONFIGURACIÓN DETECTADO!" -ForegroundColor Red
    Write-Host "DETALLE: $syntaxCheck" -ForegroundColor Magenta
    Write-Host "El servicio NUNCA subirá con ese error. Corrígelo en el .conf y reintenta." -ForegroundColor Yellow
    Read-Host "Presiona ENTER para salir"; exit
} else {
    Write-Host "Sintaxis OK. El problema es de tiempo o permisos." -ForegroundColor Green
}

# 4. Aumento del tiempo de espera en el Registro (Timeout)
Write-Host "[3/4] Aumentando tiempo de respuesta de servicios a 60 seg..." -ForegroundColor Yellow
$regPath = "HKLM:\SYSTEM\CurrentControlSet\Control"
Set-ItemProperty -Path $regPath -Name "ServicesPipeTimeout" -Value 60000 -ErrorAction SilentlyContinue

# 5. Intento de inicio final
Write-Host "[4/4] Intentando iniciar el servicio..." -ForegroundColor Cyan
net start $serviceName

if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR 1053 PERSISTE. Leyendo últimas líneas del log de errores..." -ForegroundColor Red
    if (Test-Path $logFile) {
        Get-Content $logFile -Tail 10 | Write-Host -ForegroundColor Gray
    }
} else {
    Write-Host "¡ÉXITO! El servicio HSLS14.2 ha iniciado." -ForegroundColor Green
}

Write-Host "`n------------------------------------------------"
Read-Host "Presiona ENTER para finalizar"




################################# forzando registro

$serviceName = "HSLS14.2"
$apacheBin = "C:\HSLS-14.2\Apache\bin"
$apacheExe = "$apacheBin\httpd.exe"

Write-Host "--- FORZANDO REGISTRO DE $serviceName ---" -ForegroundColor Cyan

# 1. LIMPIEZA RADICAL DE PROCESOS
Write-Host "Paso 1: Matando procesos bloqueantes..." -ForegroundColor Yellow
taskkill /F /IM httpd.exe /T 2>$null
taskkill /F /IM sc.exe /T 2>$null
Start-Sleep -Seconds 2

# 2. BORRADO TOTAL DEL SERVICIO (LISTA Y REGISTRO)
Write-Host "Paso 2: Borrando servicio previo..." -ForegroundColor Yellow
sc.exe delete $serviceName 2>$null
Remove-Item -Path "HKLM:\SYSTEM\CurrentControlSet\Services\$serviceName" -Recurse -Force -ErrorAction SilentlyContinue

# 3. REGISTRO MANUAL (SIN ESPERAR RESPUESTA)
Write-Host "Paso 3: Intentando registro rápido..." -ForegroundColor Cyan
Set-Location $apacheBin
# Ejecutamos el registro en segundo plano para que no bloquee PowerShell
$proc = Start-Process -FilePath $apacheExe -ArgumentList "-k install -n $serviceName" -NoNewWindow -PassThru
$proc | Wait-Process -Timeout 5 -ErrorAction SilentlyContinue

# Si sigue pegado tras 5 segundos, lo matamos (el registro suele ser instantáneo)
if (-not $proc.HasExited) {
    Write-Host "El instalador se colgó. Forzando cierre para continuar..." -ForegroundColor Red
    $proc | Stop-Process -Force
}

# 4. VERIFICACIÓN DE PUERTOS (Culpable común del bloqueo)
Write-Host "Paso 4: Verificando si el puerto 80/443 está libre..." -ForegroundColor Cyan
$port80 = Get-NetTCPConnection -LocalPort 80 -ErrorAction SilentlyContinue
if ($port80) {
    $owner = Get-Process -Id $port80.OwningProcess[0]
    Write-Host "¡PUERTO 80 OCUPADO por: $($owner.ProcessName)! Por eso Apache no sube." -ForegroundColor Red
}

# 5. INTENTO DE INICIO POR CMD
Write-Host "Paso 5: Intentando arranque..." -ForegroundColor Cyan
cmd.exe /c "net start $serviceName"

Write-Host "`n------------------------------------------------"
Read-Host "Proceso terminado. Presiona ENTER para salir"






##############################

# 1. Configuración de rutas y variables
$serviceName = "HSLS14.2"
$apacheBin = "C:\HSLS-14.2\Apache\bin"
$apacheExe = "$apacheBin\httpd.exe"
$regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$serviceName"

Write-Host "--- UNIFICADO: LIMPIEZA, DESBLOQUEO Y REINSTALACIÓN DE $serviceName ---" -ForegroundColor Cyan

# 2. Detección de PID y Matado de procesos específicos
Write-Host "[1/6] Consultando PID actual de $serviceName..." -ForegroundColor Yellow
$query = sc.exe queryex $serviceName
if ($LASTEXITCODE -eq 0) {
    $pidLine = $query | Select-String "PID"
    $pid = ($pidLine -replace '[^\d]', '').Trim()

    if ($pid -and $pid -ne "0") {
        Write-Host "PID Detectado: $pid. Matando proceso específico..." -ForegroundColor Yellow
        taskkill.exe /F /PID $pid 2>$null
    } else {
        Write-Host "El PID es 0. El servicio no está corriendo activamente." -ForegroundColor Gray
    }
}

# 3. Limpieza de seguridad (Matar cualquier httpd.exe huérfano)
Write-Host "[2/6] Limpiando procesos genéricos de Apache..." -ForegroundColor Yellow
taskkill.exe /F /IM httpd.exe /T 2>$null
Start-Sleep -Seconds 2

# 4. Detener y borrar el servicio de la lista de Windows
Write-Host "[3/6] Eliminando servicio de la base de datos de Windows..." -ForegroundColor Yellow
if (Get-Service -Name $serviceName -ErrorAction SilentlyContinue) {
    Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
}
sc.exe delete $serviceName | Out-Null
Write-Host "Servicio marcado para eliminación." -ForegroundColor Gray

# 5. Limpieza agresiva del Registro (Regedit)
Write-Host "[4/6] Borrando entradas residuales en el Registro..." -ForegroundColor Yellow
if (Test-Path $regPath) {
    Remove-Item -Path $regPath -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "Registro limpiado con éxito." -ForegroundColor Gray
}

# 6. Instalación Limpia (Modo Directo con Log de errores)
Write-Host "[5/6] Registrando el servicio nuevamente..." -ForegroundColor Cyan
if (Test-Path $apacheExe) {
    Set-Location $apacheBin
    $p = Start-Process -FilePath $apacheExe -ArgumentList "-k install -n $serviceName" -NoNewWindow -PassThru -Wait -RedirectStandardError "install_error.log"
    
    if ($p.ExitCode -eq 0) {
        Write-Host "¡Servicio instalado correctamente!" -ForegroundColor Green
    } else {
        Write-Host "Error durante la instalación. Código: $($p.ExitCode)" -ForegroundColor Red
        if (Test-Path "install_error.log") { Get-Content "install_error.log" }
    }
} else {
    Write-Host "ERROR CRÍTICO: No se encontró el ejecutable en $apacheExe" -ForegroundColor Red
    Read-Host "Presiona ENTER para salir"; exit
}

# 7. Intento de inicio final y validación
Write-Host "[6/6] Iniciando el servicio..." -ForegroundColor Cyan
Start-Service -Name $serviceName -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3

$finalStatus = (Get-Service $serviceName -ErrorAction SilentlyContinue).Status
if ($finalStatus -eq "Running") {
    Write-Host "¡PROCESO COMPLETADO! El servicio $serviceName está en ejecución." -ForegroundColor Green
} else {
    Write-Host "ADVERTENCIA: El servicio no subió automáticamente." -ForegroundColor Red
    Write-Host "Sugerencia: Ejecuta '.\httpd.exe -t' en la carpeta bin para ver errores de sintaxis." -ForegroundColor Yellow
}

Write-Host "`n------------------------------------------------"
Read-Host "Presiona ENTER para finalizar"

############################ ********************************
## desinatalar hsls

# 1. Configuración de rutas y variables
$serviceName = "HSLS14.2"
$apacheBin = "C:\HSLS-14.2\Apache\bin"
$apacheExe = "$apacheBin\httpd.exe"
$regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$serviceName"

Write-Host "--- REINSTALACIÓN TOTAL Y DESBLOQUEO DE $serviceName ---" -ForegroundColor Cyan

# 2. Matar procesos huérfanos que bloquean archivos o el registro
Write-Host "[1/5] Matando procesos de Apache para liberar recursos..." -ForegroundColor Yellow
taskkill.exe /F /IM httpd.exe /T 2>$null
Start-Sleep -Seconds 2

# 3. Detener y borrar el servicio de la lista de Windows
Write-Host "[2/5] Eliminando servicio de la lista del sistema..." -ForegroundColor Yellow
$service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
if ($service) {
    Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
}
sc.exe delete $serviceName | Out-Null
Write-Host "Servicio marcado para eliminación." -ForegroundColor Gray

# 4. Limpieza agresiva del Registro (Regedit)
Write-Host "[3/5] Borrando entradas residuales en el Registro..." -ForegroundColor Yellow
if (Test-Path $regPath) {
    Remove-Item -Path $regPath -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "Registro limpiado con éxito." -ForegroundColor Gray
} else {
    Write-Host "No se encontraron residuos en el Registro." -ForegroundColor Gray
}

# 5. Instalación Limpia (Modo Directo para evitar bloqueos)
Write-Host "[4/5] Registrando el servicio nuevamente..." -ForegroundColor Cyan
if (Test-Path $apacheExe) {
    Set-Location $apacheBin
    # Usamos Start-Process con redirección para capturar errores si se queda pegado
    $p = Start-Process -FilePath $apacheExe -ArgumentList "-k install -n $serviceName" -NoNewWindow -PassThru -Wait -RedirectStandardError "install_error.log"
    
    if ($p.ExitCode -eq 0) {
        Write-Host "¡Servicio instalado correctamente!" -ForegroundColor Green
    } else {
        Write-Host "Error durante la instalación. Código: $($p.ExitCode)" -ForegroundColor Red
        if (Test-Path "install_error.log") { Get-Content "install_error.log" }
    }
} else {
    Write-Host "ERROR CRÍTICO: No se encontró httpd.exe en $apacheExe" -ForegroundColor Red
    Read-Host "Presiona ENTER para salir"; exit
}

# 6. Intento de inicio final y validación
Write-Host "[5/5] Iniciando el servicio..." -ForegroundColor Cyan
Start-Service -Name $serviceName -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3

$finalStatus = (Get-Service $serviceName -ErrorAction SilentlyContinue).Status
if ($finalStatus -eq "Running") {
    Write-Host "¡TODO LISTO! El servicio $serviceName está en ejecución." -ForegroundColor Green
} else {
    Write-Host "ADVERTENCIA: El servicio no subió." -ForegroundColor Red
    Write-Host "Ejecuta: .\httpd.exe -t para ver errores de configuración en $apacheBin" -ForegroundColor Yellow
}

Write-Host "`n------------------------------------------------"
Read-Host "Proceso terminado. Presiona ENTER para salir"



######



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


######################## *************************************


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








































