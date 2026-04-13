param(
    [ValidateSet("smoke-local", "ws-connect", "ws-audio-probe", "full-live")]
    [string]$Suite = "full-live",

    [string]$BaseUrl = "http://127.0.0.1:8094",
    [string]$JarvinaPath = "/Agentes/Jarvina",
    [string]$WsUrl = "wss://jarvina-production.up.railway.app/ws/live",
    [string]$AdminToken = "1",
    [int]$ReceiveTimeoutSec = 20,
    [switch]$BypassProxy
)

$ErrorActionPreference = "Stop"

$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$agentRoot = Split-Path -Parent $scriptPath
$checksRoot = Join-Path $agentRoot "checks"

$smokeScript = Join-Path $checksRoot "smoke-local.ps1"
$wsConnectScript = Join-Path $checksRoot "ws-connect.ps1"
$wsAudioProbeScript = Join-Path $checksRoot "ws-audio-probe.ps1"

$gamificationScript = Join-Path $agentRoot "..\Gamificacao\gamification.ps1"
$heartbeatScript = Join-Path $agentRoot "..\Gamificacao\heartbeat.ps1"

if (Test-Path -LiteralPath $heartbeatScript) { . $heartbeatScript }
if (Test-Path -LiteralPath $gamificationScript) { . $gamificationScript }

function Invoke-AgentCheck {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$ScriptFile,
        [Parameter(Mandatory = $false)][hashtable]$Arguments = @{}
    )

    if (-not (Test-Path -LiteralPath $ScriptFile)) {
        throw "Script nao encontrado: $ScriptFile"
    }

    Write-Host ("[RUN] {0}" -f $Name) -ForegroundColor Cyan

    $call = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $ScriptFile)
    foreach ($key in $Arguments.Keys) {
        $value = $Arguments[$key]
        if ($value -is [switch] -or $value -is [bool]) {
            if ([bool]$value) { $call += "-$key" }
            continue
        }
        if ($null -eq $value) { continue }
        $call += "-$key"
        $call += [string]$value
    }

    & powershell @call
    if ($LASTEXITCODE -ne 0) {
        throw ("Falha em {0} (exit={1})" -f $Name, $LASTEXITCODE)
    }

    Write-Host ("[PASS] {0}" -f $Name) -ForegroundColor Green
}

$taskId = "TASK-JARVINA-LIVE-KIT"
$taskName = "Jarvina runner suite: $Suite"

if (Get-Command Update-AgentHeartbeat -ErrorAction SilentlyContinue) {
    Update-AgentHeartbeat -AgentName "Jarvina" -TaskId $taskId -Task $taskName -Status "in_progress" -Note "Jarvina runner iniciado" | Out-Null
}

$outcome = "success"
try {
    switch ($Suite) {
        "smoke-local" {
            Invoke-AgentCheck -Name "smoke-local" -ScriptFile $smokeScript -Arguments @{
                BaseUrl = $BaseUrl
                JarvinaPath = $JarvinaPath
            }
        }
        "ws-connect" {
            Invoke-AgentCheck -Name "ws-connect" -ScriptFile $wsConnectScript -Arguments @{
                WsUrl = $WsUrl
                AdminToken = $AdminToken
                ReceiveTimeoutSec = $ReceiveTimeoutSec
                BypassProxy = [bool]$BypassProxy
            }
        }
        "ws-audio-probe" {
            Invoke-AgentCheck -Name "ws-audio-probe" -ScriptFile $wsAudioProbeScript -Arguments @{
                WsUrl = $WsUrl
                AdminToken = $AdminToken
                ReceiveTimeoutSec = $ReceiveTimeoutSec
                BypassProxy = [bool]$BypassProxy
            }
        }
        "full-live" {
            Invoke-AgentCheck -Name "smoke-local" -ScriptFile $smokeScript -Arguments @{
                BaseUrl = $BaseUrl
                JarvinaPath = $JarvinaPath
            }
            Invoke-AgentCheck -Name "ws-connect" -ScriptFile $wsConnectScript -Arguments @{
                WsUrl = $WsUrl
                AdminToken = $AdminToken
                ReceiveTimeoutSec = $ReceiveTimeoutSec
                BypassProxy = [bool]$BypassProxy
            }
            Invoke-AgentCheck -Name "ws-audio-probe" -ScriptFile $wsAudioProbeScript -Arguments @{
                WsUrl = $WsUrl
                AdminToken = $AdminToken
                ReceiveTimeoutSec = $ReceiveTimeoutSec
                BypassProxy = [bool]$BypassProxy
            }
        }
    }
}
catch {
    $outcome = "failed"
    Write-Host ("[FAIL] {0}" -f $_.Exception.Message) -ForegroundColor Red
}

if (Get-Command Register-AgentAction -ErrorAction SilentlyContinue) {
    $complexity = if ($Suite -eq "full-live") { "high" } else { "medium" }
    $category = "voice_live_ops"
    $result = Register-AgentAction -AgentName "Jarvina" -Task $taskName -Category $category -Complexity $complexity -Outcome $outcome -Badges @("Live Voice Guardian")
    if ($null -ne $result) {
        Write-Host ("[GAMIFICATION] +{0} pts (total {1})" -f $result.pointsAwarded, $result.totalPoints) -ForegroundColor Yellow
    }
}

if (Get-Command Update-AgentHeartbeat -ErrorAction SilentlyContinue) {
    $status = if ($outcome -eq "success") { "done" } else { "failed" }
    Update-AgentHeartbeat -AgentName "Jarvina" -TaskId $taskId -Task $taskName -Status $status -Outcome $outcome -Note "Jarvina runner finalizado" | Out-Null
}

if ($outcome -eq "success") {
    Write-Host "[DONE] Jarvina runner finalizado com sucesso." -ForegroundColor Green
    exit 0
}

exit 1
