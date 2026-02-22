# ==========================================================
#   REINSTALACIÓN Y DIAGNÓSTICO PROFUNDO DE APACHE
# ==========================================================

# ---------------------------
# CONFIGURACIÓN GLOBAL
# ---------------------------
$serviceName = "HSLS14.2"
$apacheBin   = "C:\HSLS-14.2\Apache\bin"
$apacheExe   = Join-Path $apacheBin "httpd.exe"
$confFile    = Join-Path (Split-Path $apacheBin) "conf\httpd.conf"
$registryPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$serviceName"
$maxRetries  = 10

# ==========================================================
# FUNCIONES
# ==========================================================

function Clear-PreviousInstallation {
    Write-Host "[1/5] Limpieza profunda..." -ForegroundColor Yellow

    taskkill /F /IM httpd.exe /T 2>$null
    Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
    sc.exe delete $serviceName | Out-Null

    if (Test-Path $registryPath) {
        Remove-Item -Path $registryPath -Recurse -Force -ErrorAction SilentlyContinue
    }

    Start-Sleep -Seconds 2
}

# ----------------------------------------------------------

function Install-Service {
    Write-Host "[2/5] Registrando servicio..." -ForegroundColor Yellow

    Set-Location $apacheBin
    $args = "/c `"$apacheExe`" -k install -n $serviceName"
    $proc = Start-Process "cmd.exe" -ArgumentList $args -WindowStyle Hidden -PassThru
    $proc | Wait-Process -Timeout 15 -ErrorAction SilentlyContinue

    Write-Host "    - Servicio registrado." -ForegroundColor Gray
}

# ----------------------------------------------------------

function Free-Port {
    param ($port)

    $connection = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
    if ($connection) {
        $pid = $connection.OwningProcess
        Write-Host "    - Liberando puerto $port (PID $pid)" -ForegroundColor Gray
        taskkill /F /PID $pid /T 2>$null
        Start-Sleep -Seconds 1
    }
}

# ----------------------------------------------------------

function Start-ServiceWithRetries {
    Write-Host "[3/5] Intentando iniciar servicio..." -ForegroundColor Yellow
    $success = $false

    for ($i = 1; $i -le $maxRetries; $i++) {

        Free-Port 80
        Free-Port 443

        Start-Process "sc.exe" -ArgumentList "start", $serviceName -WindowStyle Hidden -Wait
        Start-Sleep -Seconds 3

        $svc = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
        if ($svc.Status -eq "Running") {
            Write-Host "✔ Servicio iniciado en intento $i" -ForegroundColor Green
            $success = $true
            break
        } else {
            Write-Host "Intento $i fallido..." -ForegroundColor Yellow
        }
    }

    return $success
}

# ----------------------------------------------------------

function Test-ApacheSyntax {
    Write-Host "[+] Verificando sintaxis Apache..." -ForegroundColor Cyan

    $process = Start-Process -FilePath $apacheExe -ArgumentList "-t" -PassThru -NoNewWindow
    $finished = $process | Wait-Process -Timeout 5 -ErrorAction SilentlyContinue

    if ($null -eq $finished) {
        Write-Host "ERROR: httpd -t se congeló." -ForegroundColor Red
        taskkill /F /PID $process.Id /T 2>$null
    } else {
        & $apacheExe -t 2>&1 | Out-String | Write-Host -ForegroundColor Yellow
    }
}

# ----------------------------------------------------------

function Check-ConfigPaths {
    Write-Host "[+] Verificando rutas críticas..." -ForegroundColor Cyan

    if (Test-Path $confFile) {

        $content = Get-Content $confFile
        $serverRoot = ($content | Select-String "^ServerRoot\s+`"(.+?)`"" |
                      ForEach-Object { $_.Matches.Groups[1].Value })

        $documentRoot = ($content | Select-String "^DocumentRoot\s+`"(.+?)`"" |
                        ForEach-Object { $_.Matches.Groups[1].Value })

        $paths = @{
            "ServerRoot"   = $serverRoot
            "DocumentRoot" = $documentRoot
        }

        foreach ($key in $paths.Keys) {
            $path = $paths[$key]
            if ($path -and (Test-Path $path)) {
                Write-Host "    - $key [$path] OK" -ForegroundColor Green
            } else {
                Write-Host "    - $key [$path] ERROR" -ForegroundColor Red
            }
        }
    }
}

# ----------------------------------------------------------

function Check-Ports {
    Write-Host "[+] Verificando puertos 80 y 443..." -ForegroundColor Cyan

    foreach ($port in @(80,443)) {
        $conn = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
        if ($conn) {
            $proc = Get-Process -Id $conn.OwningProcess
            Write-Host "    - Puerto $port bloqueado por $($proc.ProcessName)" -ForegroundColor Red
        } else {
            Write-Host "    - Puerto $port libre" -ForegroundColor Green
        }
    }
}

# ----------------------------------------------------------

function Run-Diagnostics {
    Write-Host "`n[4/5] DIAGNÓSTICO PROFUNDO" -ForegroundColor Red
    Test-ApacheSyntax
    Check-Ports
    Check-ConfigPaths
}

# ==========================================================
# FLUJO PRINCIPAL
# ==========================================================

Write-Host "`n=== INICIANDO REINSTALACIÓN COMPLETA DE APACHE ===" -ForegroundColor Cyan

Clear-PreviousInstallation
Install-Service
$result = Start-ServiceWithRetries

if (-not $result) {
    Run-Diagnostics
}

Write-Host "`n[5/5] PROCESO FINALIZADO" -ForegroundColor Cyan
