param(
    [ValidateSet("studio-hub", "studio-master-cursor")]
    [string]$Project = "studio-hub",

    [int]$Runs = 3
)

Write-Host "Agente: Otavio" -ForegroundColor Cyan
Write-Host "Especialidade: QA Zoom Studio Hub" -ForegroundColor Yellow
Write-Host "Projeto: $Project" -ForegroundColor White

$ScriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$AgentRoot = Split-Path -Parent $ScriptPath
$GamificationScript = Join-Path $AgentRoot "..\Gamificacao\gamification.ps1"
$HeartbeatScript = Join-Path $AgentRoot "..\Gamificacao\heartbeat.ps1"
$TestScript = Join-Path $AgentRoot "tests\studio-hub-zoom-qa.ps1"

if (Test-Path -LiteralPath $HeartbeatScript) {
    . $HeartbeatScript
}

$taskId = if ($Project -eq "studio-hub") { "TASK-ZOOM-HUB" } else { "TASK-ZOOM-CURSOR" }
if (Get-Command Update-AgentHeartbeat -ErrorAction SilentlyContinue) {
    Update-AgentHeartbeat -AgentName "Otavio" -TaskId $taskId -Task "QA Zoom $Project" -Status "in_progress" -Note "Otavio runner iniciado" | Out-Null
}

$qaOutcome = "success"
try {
    & powershell -NoProfile -ExecutionPolicy Bypass -File $TestScript -Project $Project -Runs $Runs
    if ($LASTEXITCODE -ne 0) {
        $qaOutcome = "failed"
        throw "Suite QA retornou codigo $LASTEXITCODE"
    }
    Write-Host "QA: PASS" -ForegroundColor Green
} catch {
    $qaOutcome = "failed"
    Write-Host "QA: FAIL - $($_.Exception.Message)" -ForegroundColor Red
}

if (Test-Path -LiteralPath $GamificationScript) {
    . $GamificationScript
    if (Get-Command Register-AgentAction -ErrorAction SilentlyContinue) {
        $complexity = if ($Project -eq "studio-master-cursor") { "high" } else { "medium" }
        $category = if ($Project -eq "studio-master-cursor") { "qa_regression" } else { "triage" }
        $outcome = if ($qaOutcome -eq "success") { "success" } else { "failed" }
        $g = Register-AgentAction -AgentName "Otavio" -Task "QA Zoom $Project ($qaOutcome)" -Category $category -Complexity $complexity -Outcome $outcome -Badges @("Zoom Guard")
        Write-Host ("Gamificacao: +{0} pontos (total {1})" -f $g.pointsAwarded, $g.totalPoints) -ForegroundColor Green
    }
}

if (Get-Command Update-AgentHeartbeat -ErrorAction SilentlyContinue) {
    $status = if ($qaOutcome -eq "success") { "done" } else { "failed" }
    Update-AgentHeartbeat -AgentName "Otavio" -TaskId $taskId -Task "QA Zoom $Project" -Status $status -Outcome $qaOutcome -Note "Otavio runner finalizado" | Out-Null
}

if ($qaOutcome -eq "success") {
    exit 0
}

exit 1
