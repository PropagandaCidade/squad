$ErrorActionPreference = "Stop"

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

$runnerScript = Join-Path $PSScriptRoot "..\..\Thiago\runner\Thiago.ps1"
$task = "TASK-9903 runner smoke"
powershell -NoProfile -ExecutionPolicy Bypass -File $runnerScript -Task $task -Outcome "success" -Complexity "low" | Out-Null

$projectRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
$runtimeFile = Join-Path $projectRoot "memory-enterprise\60_AGENT_MEMORY\runtime\agent-heartbeats.json"
$runtime = Get-Content -LiteralPath $runtimeFile -Raw | ConvertFrom-Json
$entry = $runtime.agents.thiago
$history = @($entry.history)
$lastTwo = @($history | Select-Object -Last 2)

Assert-True -Condition ($lastTwo.Count -eq 2) -Message "Expected two final history entries for Thiago"
Assert-True -Condition ($lastTwo[0].status -eq "in_progress") -Message "Expected penultimate status in_progress"
Assert-True -Condition ($lastTwo[1].status -eq "done") -Message "Expected final status done"
Assert-True -Condition ([string]$lastTwo[1].task -eq $task) -Message "Expected final task to match runner task"

Write-Host "OK runner-heartbeat-smoke (Thiago)" -ForegroundColor Green
