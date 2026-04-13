param(
    [Parameter(Mandatory = $false)]
    [string]$Task = 'Execucao de tarefa',
    [Parameter(Mandatory = $false)]
    [string]$Outcome = 'success',
    [Parameter(Mandatory = $false)]
    [string]$Complexity = 'low',
    [Parameter(Mandatory = $false)]
    [int]$Points = -1
)

Write-Host "Agente: Eduardo" -ForegroundColor Cyan
Write-Host "Especialidade: Closer" -ForegroundColor Yellow

$ScriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$AgentRoot = Split-Path -Parent $ScriptPath
$GamificationScript = Join-Path $AgentRoot '..\Gamificacao\gamification.ps1'
$HeartbeatScript = Join-Path $AgentRoot "..\Gamificacao\heartbeat.ps1"
if (Test-Path -LiteralPath $HeartbeatScript) {
    . $HeartbeatScript
}

$TaskId = ""
if ($Task -match "(TASK-[0-9]+)") {
    $TaskId = $matches[1]
}

if (Get-Command Update-AgentHeartbeat -ErrorAction SilentlyContinue) {
    Update-AgentHeartbeat -AgentName "Eduardo" -TaskId $TaskId -Task $Task -Status "in_progress" -Note "Runner iniciado" | Out-Null
}

if (Test-Path -LiteralPath $GamificationScript) {
    . $GamificationScript
    if (Get-Command Register-AgentAction -ErrorAction SilentlyContinue) {
        if ($Points -ge 0) {
            $g = Add-AgentPoints -AgentName 'Eduardo' -Points $Points -Task $Task -Badges @('Execucao Registrada')
        } else {
            $g = Register-AgentAction -AgentName 'Eduardo' -Task $Task -Category 'execution' -Complexity $Complexity -Outcome $Outcome -Badges @('Execucao Registrada')
        }
        Write-Host ("Gamificacao: +{0} pontos (total {1})" -f $g.pointsAwarded, $g.totalPoints) -ForegroundColor Green
    }
}

if (Get-Command Update-AgentHeartbeat -ErrorAction SilentlyContinue) {
    $heartbeatStatus = switch (([string]$Outcome).ToLower()) {
        "success" { "done" }
        "blocked" { "blocked" }
        "failed" { "failed" }
        default { "idle" }
    }
    Update-AgentHeartbeat -AgentName "Eduardo" -TaskId $TaskId -Task $Task -Status $heartbeatStatus -Outcome $Outcome -Note "Runner finalizado" | Out-Null
}
