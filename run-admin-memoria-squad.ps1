param(
    [int]$Port = 8094
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

function Resolve-ServerCommand {
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

    $php = Get-Command php -ErrorAction SilentlyContinue
    if ($php) {
        return @{
            File = $php.Source
            Args = @("-S", "127.0.0.1:$Port", "-t", ".")
            Label = "php built-in server"
        }
    }

    throw "Nenhum servidor local encontrado (python/py/php)."
}

$server = Resolve-ServerCommand
$url = "http://127.0.0.1:$Port/admin-memoria-squad.html"

$proc = Start-Process -FilePath $server.File -ArgumentList $server.Args -WorkingDirectory $root -PassThru
Start-Sleep -Milliseconds 900
Start-Process $url | Out-Null

Write-Host "Servidor iniciado: $($server.Label)" -ForegroundColor Green
Write-Host "PID: $($proc.Id)" -ForegroundColor Cyan
Write-Host "URL: $url" -ForegroundColor Yellow
Write-Host "Para encerrar: Stop-Process -Id $($proc.Id)" -ForegroundColor Gray
