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

$registerScript = Join-Path $PSScriptRoot "..\register-task.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File $registerScript `
    -AgentName "Sofia" `
    -Task "Registro de tarefa de smoke" `
    -TaskId "TASK-9902" `
    -Category "execution" `
    -Complexity "low" `
    -Outcome "success" | Out-Null

$projectRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
$runtimeFile = Join-Path $projectRoot "memory-enterprise\60_AGENT_MEMORY\runtime\agent-heartbeats.json"
$runtime = Get-Content -LiteralPath $runtimeFile -Raw | ConvertFrom-Json
$entry = $runtime.agents.sofia

Assert-True -Condition ($null -ne $entry) -Message "Runtime entry not found for Sofia"
Assert-True -Condition ($entry.last_outcome -eq "success") -Message "Expected success outcome for Sofia"
Assert-True -Condition ($entry.status -eq "done") -Message "Expected status done for Sofia"

Write-Host "OK register-task-heartbeat (Sofia)" -ForegroundColor Green
