[CmdletBinding()]
param(
    [string]$WsUrl = "wss://jarvina-production.up.railway.app/ws/live",
    [string]$AdminToken = "1",
    [int]$ReceiveTimeoutSec = 8,
    [switch]$BypassProxy
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-ExceptionDetails {
    param([System.Exception]$Ex)

    if ($null -eq $Ex) { return "n/a" }

    $lines = New-Object System.Collections.Generic.List[string]
    $depth = 0
    $current = $Ex
    while ($null -ne $current -and $depth -lt 5) {
        $lines.Add("[$depth] $($current.GetType().FullName): $($current.Message)") | Out-Null
        $current = $current.InnerException
        $depth += 1
    }

    return ($lines -join " | ")
}

function Invoke-Preflight {
    param([string]$TargetWsUrl)

    $uri = [System.Uri]::new($TargetWsUrl)
    $targetHost = $uri.Host
    $healthUrl = "https://$targetHost/"

    Write-Host "[INFO] Preflight TCP 443..."
    $tnc = Test-NetConnection -ComputerName $targetHost -Port 443 -WarningAction SilentlyContinue
    if (-not $tnc.TcpTestSucceeded) {
        throw "TCP 443 falhou para $targetHost."
    }
    Write-Host "[INFO] TCP 443 OK."

    Write-Host "[INFO] Preflight HTTPS..."
    $invokeParams = @{
        Method = "Get"
        Uri = $healthUrl
        TimeoutSec = 10
        ErrorAction = "Stop"
    }
    if ($PSVersionTable.PSVersion.Major -lt 6) {
        $invokeParams.UseBasicParsing = $true
    }

    try {
        $resp = Invoke-WebRequest @invokeParams
        Write-Host "[INFO] HTTPS status: $([int]$resp.StatusCode)"
    } catch {
        $details = Get-ExceptionDetails -Ex $_.Exception
        throw "HTTPS preflight falhou: $details"
    }
}

$ws = New-Object System.Net.WebSockets.ClientWebSocket
$cts = New-Object System.Threading.CancellationTokenSource
$cts.CancelAfter([TimeSpan]::FromSeconds($ReceiveTimeoutSec))

try {
    try {
        [System.Net.ServicePointManager]::SecurityProtocol = `
            [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12
    } catch {}

    $uri = [System.Uri]::new($WsUrl)
    Invoke-Preflight -TargetWsUrl $WsUrl

    if ($BypassProxy) {
        $ws.Options.Proxy = $null
        Write-Host "[INFO] WebSocket proxy bypass ativo."
    }
    [void]$ws.ConnectAsync($uri, $cts.Token).GetAwaiter().GetResult()

    if ($ws.State -ne [System.Net.WebSockets.WebSocketState]::Open) {
        throw "WebSocket did not open. State=$($ws.State)"
    }

    $setup = @{ admin_token = $AdminToken } | ConvertTo-Json -Compress
    $sendBytes = [System.Text.Encoding]::UTF8.GetBytes($setup)
    $sendBuffer = [System.ArraySegment[byte]]::new($sendBytes)
    [void]$ws.SendAsync(
        $sendBuffer,
        [System.Net.WebSockets.WebSocketMessageType]::Text,
        $true,
        $cts.Token
    ).GetAwaiter().GetResult()

    $recvBytes = New-Object byte[] 8192
    $recvBuffer = [System.ArraySegment[byte]]::new($recvBytes)
    $result = $null

    $recvCts = New-Object System.Threading.CancellationTokenSource
    $recvCts.CancelAfter([TimeSpan]::FromSeconds($ReceiveTimeoutSec))
    try {
        $result = $ws.ReceiveAsync($recvBuffer, $recvCts.Token).GetAwaiter().GetResult()
    } catch [System.OperationCanceledException] {
        Write-Host "[WARN] Nenhuma mensagem recebida dentro do timeout; conexao WS e setup estao OK." -ForegroundColor Yellow
        Write-Host "[PASS] WS connected and setup sent." -ForegroundColor Green
        exit 0
    } finally {
        $recvCts.Dispose()
    }

    if ($result.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close) {
        throw "Server closed socket immediately."
    }

    $text = [System.Text.Encoding]::UTF8.GetString($recvBytes, 0, $result.Count)
    Write-Host "[PASS] WS connected and received first message." -ForegroundColor Green
    Write-Host "Message: $text"
    exit 0
}
catch {
    Write-Host "[FAIL] WS check failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
finally {
    if ($ws.State -eq [System.Net.WebSockets.WebSocketState]::Open) {
        try {
            $closeToken = [System.Threading.CancellationToken]::None
            $ws.CloseAsync(
                [System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure,
                "qa-end",
                $closeToken
            ).GetAwaiter().GetResult()
        } catch {}
    }
    $ws.Dispose()
    $cts.Dispose()
}
