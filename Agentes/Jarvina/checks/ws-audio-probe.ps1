[CmdletBinding()]
param(
    [string]$WsUrl = "wss://jarvina-production.up.railway.app/ws/live",
    [string]$AdminToken = "1",
    [int]$ReceiveTimeoutSec = 20,
    [int]$SampleRate = 16000,
    [int]$ToneMs = 900,
    [int]$FrequencyHz = 440,
    [switch]$BypassProxy
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

try {
    # Ajuda em ambientes com TLS antigo no PowerShell 5.x
    [System.Net.ServicePointManager]::SecurityProtocol = `
        [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12
} catch {}

function Get-ExceptionDetails {
    param([System.Exception]$Ex)

    if ($null -eq $Ex) { return "n/a" }

    $lines = New-Object System.Collections.Generic.List[string]
    $depth = 0
    $current = $Ex
    while ($null -ne $current -and $depth -lt 6) {
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
        $code = [int]$resp.StatusCode
        Write-Host "[INFO] HTTPS status: $code"
    } catch {
        $details = Get-ExceptionDetails -Ex $_.Exception
        throw "HTTPS preflight falhou: $details"
    }
}

function Send-Json {
    param(
        [System.Net.WebSockets.ClientWebSocket]$Ws,
        [object]$Payload,
        [System.Threading.CancellationToken]$Token
    )

    $json = $Payload | ConvertTo-Json -Compress -Depth 12
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    $segment = [System.ArraySegment[byte]]::new($bytes)

    [void]$Ws.SendAsync(
        $segment,
        [System.Net.WebSockets.WebSocketMessageType]::Text,
        $true,
        $Token
    ).GetAwaiter().GetResult()
}

function Receive-WebSocketText {
    param(
        [System.Net.WebSockets.ClientWebSocket]$Ws,
        [System.Threading.CancellationToken]$Token
    )

    try {
        $buffer = New-Object byte[] 8192
        $builder = New-Object System.Text.StringBuilder

        do {
            $segment = [System.ArraySegment[byte]]::new($buffer)
            $result = $Ws.ReceiveAsync($segment, $Token).GetAwaiter().GetResult()

            if ($result.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close) {
                $code = if ($result.CloseStatus) { [string]$result.CloseStatus } else { "n/a" }
                $reason = if ($result.CloseStatusDescription) { $result.CloseStatusDescription } else { "" }
                throw "Server closed socket. Code=$code Reason=$reason"
            }

            if ($result.Count -gt 0) {
                [void]$builder.Append([System.Text.Encoding]::UTF8.GetString($buffer, 0, $result.Count))
            }
        } while (-not $result.EndOfMessage)

        return $builder.ToString()
    } catch [System.OperationCanceledException] {
        throw "Timeout waiting websocket message (global timeout)."
    }
}

function New-PcmToneBase64 {
    param(
        [int]$SampleRate,
        [int]$DurationMs,
        [int]$FrequencyHz
    )

    $totalSamples = [Math]::Max(1, [int]([Math]::Round($SampleRate * $DurationMs / 1000.0)))
    $bytes = New-Object byte[] ($totalSamples * 2)
    $amplitude = 0.20

    for ($i = 0; $i -lt $totalSamples; $i++) {
        $time = $i / [double]$SampleRate
        $value = [Math]::Sin(2.0 * [Math]::PI * $FrequencyHz * $time) * $amplitude
        $sample = [int16][Math]::Round($value * 32767.0)
        $pair = [System.BitConverter]::GetBytes($sample) # little-endian PCM16
        $bytes[$i * 2] = $pair[0]
        $bytes[$i * 2 + 1] = $pair[1]
    }

    return [Convert]::ToBase64String($bytes)
}

function Convert-FromJsonCompat {
    param([string]$JsonText)

    if ($PSVersionTable.PSVersion.Major -ge 6) {
        return ($JsonText | ConvertFrom-Json -Depth 30)
    }
    return ($JsonText | ConvertFrom-Json)
}

function Get-PropOrDefault {
    param(
        [object]$Obj,
        [string]$Name,
        $DefaultValue = $null
    )

    if ($null -eq $Obj) { return $DefaultValue }
    $prop = $Obj.PSObject.Properties[$Name]
    if ($null -eq $prop) { return $DefaultValue }
    return $prop.Value
}

$ws = New-Object System.Net.WebSockets.ClientWebSocket
$rootCts = New-Object System.Threading.CancellationTokenSource
$rootCts.CancelAfter([TimeSpan]::FromSeconds([Math]::Max(30, $ReceiveTimeoutSec + 15)))

$gotWelcome = $false
$gotMicDebug = $false
$micBytes = 0
$micChunks = 0
$gotModelContent = $false

Write-Host "Jarvina WS audio probe"
Write-Host "WS URL: $WsUrl"
Write-Host "SampleRate: $SampleRate Hz | Tone: $ToneMs ms @ $FrequencyHz Hz"
Write-Host ""

try {
    Invoke-Preflight -TargetWsUrl $WsUrl

    $uri = [System.Uri]::new($WsUrl)
    if ($BypassProxy) {
        $ws.Options.Proxy = $null
        Write-Host "[INFO] WebSocket proxy bypass ativo."
    }
    [void]$ws.ConnectAsync($uri, $rootCts.Token).GetAwaiter().GetResult()

    if ($ws.State -ne [System.Net.WebSockets.WebSocketState]::Open) {
        throw "WebSocket did not open. State=$($ws.State)"
    }

    Send-Json -Ws $ws -Payload @{ admin_token = $AdminToken } -Token $rootCts.Token
    Write-Host "[INFO] Setup sent."

    $toneB64 = New-PcmToneBase64 -SampleRate $SampleRate -DurationMs $ToneMs -FrequencyHz $FrequencyHz
    $audioPayload = @{
        realtime_input = @{
            media_chunks = @(
                @{
                    data = $toneB64
                    mime_type = "audio/pcm;rate=$SampleRate"
                }
            )
        }
    }

    Send-Json -Ws $ws -Payload $audioPayload -Token $rootCts.Token
    Send-Json -Ws $ws -Payload @{ end_of_turn = $true } -Token $rootCts.Token
    Write-Host "[INFO] Audio probe + end_of_turn sent."

    $probeEnd = [DateTime]::UtcNow.AddSeconds($ReceiveTimeoutSec)
    while ([DateTime]::UtcNow -lt $probeEnd) {
        $raw = Receive-WebSocketText -Ws $ws -Token $rootCts.Token
        if ([string]::IsNullOrWhiteSpace($raw)) { continue }

        $msg = $null
        try { $msg = Convert-FromJsonCompat -JsonText $raw } catch {
            $preview = if ($raw.Length -gt 180) { $raw.Substring(0, 180) + "..." } else { $raw }
            Write-Host "[WARN] Mensagem não-JSON durante probe: $preview"
            continue
        }

        $type = [string](Get-PropOrDefault -Obj $msg -Name "type" -DefaultValue "")

        if ($type -eq "welcome") {
            $gotWelcome = $true
            continue
        }

        if ($type -eq "error") {
            $code = [string](Get-PropOrDefault -Obj $msg -Name "code" -DefaultValue "")
            $text = [string](Get-PropOrDefault -Obj $msg -Name "text" -DefaultValue "")
            throw "Backend error during probe: $code $text"
        }

        if ($type -eq "mic_debug") {
            $gotMicDebug = $true
            $micBytes = [int](Get-PropOrDefault -Obj $msg -Name "bytes" -DefaultValue 0)
            $micChunks = [int](Get-PropOrDefault -Obj $msg -Name "chunks" -DefaultValue 0)
            $eot = [bool](Get-PropOrDefault -Obj $msg -Name "end_of_turn" -DefaultValue $false)
            Write-Host "[INFO] mic_debug chunks=$micChunks bytes=$micBytes end_of_turn=$eot"
        }

        $serverContent = Get-PropOrDefault -Obj $msg -Name "serverContent" -DefaultValue $null
        if ($null -eq $serverContent) {
            $serverContent = Get-PropOrDefault -Obj $msg -Name "server_content" -DefaultValue $null
        }
        if ($null -ne $serverContent) {
            $gotModelContent = $true
            Write-Host "[INFO] Model content observed in session."
        }

        if ($gotMicDebug -and $micBytes -gt 0 -and $gotModelContent) {
            break
        }
    }

    if (-not $gotWelcome) {
        Write-Host "[WARN] No welcome message received (optional)." -ForegroundColor Yellow
    }

    if (-not $gotMicDebug -or $micBytes -le 0) {
        Write-Host "[FAIL] No mic_debug with bytes>0. Audio may not be reaching Railway backend." -ForegroundColor Red
        exit 1
    }

    Write-Host "[PASS] Audio reached Railway backend (mic_debug bytes=$micBytes chunks=$micChunks)." -ForegroundColor Green

    if ($gotModelContent) {
        Write-Host "[PASS] Model content also observed in the same session." -ForegroundColor Green
    } else {
        Write-Host "[WARN] No model content observed in probe window; backend receive path is still confirmed." -ForegroundColor Yellow
    }

    exit 0
}
catch {
    $details = Get-ExceptionDetails -Ex $_.Exception
    Write-Host "[FAIL] Probe failed: $details" -ForegroundColor Red
    exit 1
}
finally {
    if ($ws.State -eq [System.Net.WebSockets.WebSocketState]::Open) {
        try {
            [void]$ws.CloseAsync(
                [System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure,
                "probe-end",
                [System.Threading.CancellationToken]::None
            ).GetAwaiter().GetResult()
        } catch {}
    }

    $ws.Dispose()
    $rootCts.Dispose()
}
