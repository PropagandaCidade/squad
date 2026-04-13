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

$registry = Sync-AgentRegistry -EnsureMemoryFiles
$agents = @($registry.agents)

Assert-True -Condition ($agents.Count -gt 0) -Message "Registry should have at least one agent"

$projectRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
foreach ($agent in $agents) {
    $ws = Join-Path $projectRoot ($agent.working_set -replace "/", "\")
    $profile = Join-Path $projectRoot ($agent.profile -replace "/", "\")
    Assert-True -Condition (Test-Path -LiteralPath $ws) -Message "Missing working set for $($agent.name)"
    Assert-True -Condition (Test-Path -LiteralPath $profile) -Message "Missing profile for $($agent.name)"
}

Write-Host ("OK registry-integrity ({0} agents)" -f $agents.Count) -ForegroundColor Green
