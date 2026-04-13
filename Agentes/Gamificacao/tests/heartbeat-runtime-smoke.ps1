param(
    [Parameter(Mandatory = $false)]
    [string]$AgentName = "Carlos"
)

$ErrorActionPreference = "Stop"
$HeartbeatScript = Join-Path $PSScriptRoot "..\heartbeat.ps1"
. $HeartbeatScript

function Assert-True {
    param(
        [Parameter(Mandatory = $true)]
        [bool]$Condition,
        [Parameter(Mandatory = $true)]
        [string]$Message
    )
    if (-not $Condition) {
        throw "ASSERT FAILED: $Message"
    }
}

$taskId = "TASK-9901"
Update-AgentHeartbeat -AgentName $AgentName -TaskId $taskId -Task "Smoke runtime start" -Status "in_progress" -Note "test-start" | Out-Null
Start-Sleep -Milliseconds 150
Update-AgentHeartbeat -AgentName $AgentName -TaskId $taskId -Task "Smoke runtime done" -Status "done" -Outcome "success" -Note "test-done" | Out-Null

$projectRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
$runtimeFile = Join-Path $projectRoot "memory-enterprise\60_AGENT_MEMORY\runtime\agent-heartbeats.json"
$runtime = Get-Content -LiteralPath $runtimeFile -Raw | ConvertFrom-Json
$slug = $AgentName.ToLowerInvariant()
$entry = $runtime.agents.$slug

Assert-True -Condition ($null -ne $entry) -Message "Entry not found in runtime store for $slug"
Assert-True -Condition ($entry.status -eq "done") -Message "Expected status done, got '$($entry.status)'"
Assert-True -Condition (($entry.history | Measure-Object).Count -ge 2) -Message "History should contain at least 2 records"

$wsFile = Join-Path $projectRoot "memory-enterprise\60_AGENT_MEMORY\working_sets\$slug.yaml"
$wsText = Get-Content -LiteralPath $wsFile -Raw
Assert-True -Condition ($wsText -match "status:\s+done") -Message "Working set should be done"
Assert-True -Condition ($wsText -match "active_task_ids:\s+\[\]") -Message "Working set should have empty active_task_ids"

Write-Host "OK heartbeat-runtime-smoke ($AgentName)" -ForegroundColor Green
