param(
    [int]$Port = 8095,
    [switch]$NoOpenBrowser
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

function Test-PortOpen {
    param([int]$TestPort)

    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $result = $client.BeginConnect("127.0.0.1", $TestPort, $null, $null)
        $connected = $result.AsyncWaitHandle.WaitOne(350)
        if (-not $connected) {
            $client.Close()
            return $false
        }
        $client.EndConnect($result)
        $client.Close()
        return $true
    }
    catch {
        return $false
    }
}

function Resolve-ServerCommand {
    $php = Get-Command php -ErrorAction SilentlyContinue
    if ($php -and (Test-Path (Join-Path $root "router.php"))) {
        return @{
            File = $php.Source
            Args = @("-S", "127.0.0.1:$Port", "router.php")
            Label = "php built-in server (router.php)"
        }
    }

    $python = Get-Command python -ErrorAction SilentlyContinue
    if ($python) {
        return @{
            File = $python.Source
            Args = @("-m", "http.server", "$Port", "--bind", "127.0.0.1")
            Label = "python http.server"
        }
    }

    $py = Get-Command py -ErrorAction SilentlyContinue
    if ($py) {
        return @{
            File = $py.Source
            Args = @("-m", "http.server", "$Port", "--bind", "127.0.0.1")
            Label = "py http.server"
        }
    }

    throw "Nenhum servidor local encontrado (python/py/php)."
}

$server = Resolve-ServerCommand
$url = "http://127.0.0.1:$Port/admin-memoria-squad.html"

$alreadyRunning = Test-PortOpen -TestPort $Port
if ($alreadyRunning) {
    if (-not $NoOpenBrowser) {
        Start-Process $url | Out-Null
    }
    Write-Host "Servidor já ativo na porta $Port." -ForegroundColor Yellow
    Write-Host "URL: $url" -ForegroundColor Green
    return
}

$proc = Start-Process -FilePath $server.File -ArgumentList $server.Args -WorkingDirectory $root -PassThru
Start-Sleep -Milliseconds 900
if (-not $NoOpenBrowser) {
    Start-Process $url | Out-Null
}

Write-Host "Servidor iniciado: $($server.Label)" -ForegroundColor Green
Write-Host "PID: $($proc.Id)" -ForegroundColor Cyan
Write-Host "URL: $url" -ForegroundColor Yellow
Write-Host "Para encerrar: Stop-Process -Id $($proc.Id)" -ForegroundColor Gray
