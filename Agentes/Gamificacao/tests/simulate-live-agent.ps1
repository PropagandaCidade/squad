param(
    [Parameter(Mandatory = $false)]
    [string]$AgentName = "Thiago",

    [Parameter(Mandatory = $false)]
    [string]$TaskId = "TASK-9999",

    [Parameter(Mandatory = $false)]
    [string]$Task = "Simulacao de execucao ao vivo",

    [Parameter(Mandatory = $false)]
    [int]$DurationSec = 20
)

$ErrorActionPreference = "Stop"
$HeartbeatScript = Join-Path $PSScriptRoot "..\heartbeat.ps1"
. $HeartbeatScript

for ($i = 1; $i -le $DurationSec; $i++) {
    Update-AgentHeartbeat -AgentName $AgentName -TaskId $TaskId -Task $Task -Status "in_progress" -Note ("tick {0}/{1}" -f $i, $DurationSec) | Out-Null
    Start-Sleep -Seconds 1
}

Update-AgentHeartbeat -AgentName $AgentName -TaskId $TaskId -Task $Task -Status "done" -Outcome "success" -Note "simulacao finalizada" | Out-Null
Write-Host ("OK simulate-live-agent ({0}, {1}s)" -f $AgentName, $DurationSec) -ForegroundColor Green
