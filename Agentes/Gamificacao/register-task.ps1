param(
    [Parameter(Mandatory = $true)]
    [string]$AgentName,

    [Parameter(Mandatory = $true)]
    [string]$Task,

    [Parameter(Mandatory = $false)]
    [string]$Category = "execution",

    [Parameter(Mandatory = $false)]
    [string]$Complexity = "medium",

    [Parameter(Mandatory = $false)]
    [string]$Outcome = "success",

    [Parameter(Mandatory = $false)]
    [int]$Points = -1,

    [Parameter(Mandatory = $false)]
    [string[]]$Badges = @(),

    [Parameter(Mandatory = $false)]
    [string]$TaskId = ""
)

$GamificationScript = Join-Path $PSScriptRoot "gamification.ps1"
if (-not (Test-Path -LiteralPath $GamificationScript)) {
    Write-Error "gamification.ps1 nao encontrado em $GamificationScript"
    exit 1
}

. $GamificationScript

$HeartbeatScript = Join-Path $PSScriptRoot "heartbeat.ps1"
if (Test-Path -LiteralPath $HeartbeatScript) {
    . $HeartbeatScript
}

if ($Points -ge 0) {
    $result = Add-AgentPoints -AgentName $AgentName -Points $Points -Task $Task -Badges $Badges
} else {
    $result = Register-AgentAction -AgentName $AgentName -Task $Task -Category $Category -Complexity $Complexity -Outcome $Outcome -Badges $Badges
}

Write-Host ("OK: {0} | +{1} pts | total={2} | nivel={3}" -f $result.agent, $result.pointsAwarded, $result.totalPoints, $result.level) -ForegroundColor Green
$result | ConvertTo-Json -Depth 6

if (Get-Command Update-AgentHeartbeat -ErrorAction SilentlyContinue) {
    $heartbeatStatus = switch (([string]$Outcome).ToLower()) {
        "success" { "done" }
        "blocked" { "blocked" }
        "failed" { "failed" }
        default { "idle" }
    }

    $resolvedTaskId = $TaskId
    if ([string]::IsNullOrWhiteSpace($resolvedTaskId) -and $Task -match "(TASK-[0-9]+)") {
        $resolvedTaskId = $matches[1]
    }

    Update-AgentHeartbeat -AgentName $AgentName -TaskId $resolvedTaskId -Task $Task -Status $heartbeatStatus -Outcome $Outcome -Note "register-task" | Out-Null
}
