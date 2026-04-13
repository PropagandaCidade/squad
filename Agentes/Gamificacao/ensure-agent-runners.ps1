param(
    [Parameter(Mandatory = $false)]
    [switch]$Overwrite
)

$ScriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$AgentsRoot = Split-Path -Parent $ScriptPath

$agentDirs = Get-ChildItem -LiteralPath $AgentsRoot -Directory | Where-Object { $_.Name -ne "Gamificacao" }
$created = 0
$updated = 0
$skipped = 0

foreach ($dir in $agentDirs) {
    $agentName = $dir.Name
    $configPath = Join-Path $dir.FullName "config\agent-config.json"
    $specialty = "Especialista"

    if (Test-Path -LiteralPath $configPath) {
        try {
            $cfg = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
            if ($cfg.agent.specialty) { $specialty = [string]$cfg.agent.specialty }
        } catch {}
    }

    $runnerDir = Join-Path $dir.FullName "runner"
    if (-not (Test-Path -LiteralPath $runnerDir)) {
        New-Item -ItemType Directory -Path $runnerDir -Force | Out-Null
    }

    $runnerPath = Join-Path $runnerDir "$agentName.ps1"
    if ((Test-Path -LiteralPath $runnerPath) -and -not $Overwrite) {
        $skipped++
        continue
    }

    $content = @"
param(
    [Parameter(Mandatory = `$false)]
    [string]`$Task = 'Execucao de tarefa',
    [Parameter(Mandatory = `$false)]
    [string]`$Outcome = 'success',
    [Parameter(Mandatory = `$false)]
    [string]`$Complexity = 'low',
    [Parameter(Mandatory = `$false)]
    [int]`$Points = -1
)

Write-Host "Agente: $agentName" -ForegroundColor Cyan
Write-Host "Especialidade: $specialty" -ForegroundColor Yellow

`$ScriptPath = Split-Path -Parent `$MyInvocation.MyCommand.Path
`$AgentRoot = Split-Path -Parent `$ScriptPath
`$GamificationScript = Join-Path `$AgentRoot '..\Gamificacao\gamification.ps1'
`$HeartbeatScript = Join-Path `$AgentRoot '..\Gamificacao\heartbeat.ps1'
if (Test-Path -LiteralPath `$HeartbeatScript) {
    . `$HeartbeatScript
}

`$TaskId = ''
if (`$Task -match '(TASK-[0-9]+)') {
    `$TaskId = `$matches[1]
}

if (Get-Command Update-AgentHeartbeat -ErrorAction SilentlyContinue) {
    Update-AgentHeartbeat -AgentName '$agentName' -TaskId `$TaskId -Task `$Task -Status 'in_progress' -Note 'Runner iniciado' | Out-Null
}

if (Test-Path -LiteralPath `$GamificationScript) {
    . `$GamificationScript
    if (Get-Command Register-AgentAction -ErrorAction SilentlyContinue) {
        if (`$Points -ge 0) {
            `$g = Add-AgentPoints -AgentName '$agentName' -Points `$Points -Task `$Task -Badges @('Execucao Registrada')
        } else {
            `$g = Register-AgentAction -AgentName '$agentName' -Task `$Task -Category 'execution' -Complexity `$Complexity -Outcome `$Outcome -Badges @('Execucao Registrada')
        }
        Write-Host ("Gamificacao: +{0} pontos (total {1})" -f `$g.pointsAwarded, `$g.totalPoints) -ForegroundColor Green
    }
}

if (Get-Command Update-AgentHeartbeat -ErrorAction SilentlyContinue) {
    `$HeartbeatStatus = switch (([string]`$Outcome).ToLower()) {
        'success' { 'done' }
        'blocked' { 'blocked' }
        'failed' { 'failed' }
        default { 'idle' }
    }
    Update-AgentHeartbeat -AgentName '$agentName' -TaskId `$TaskId -Task `$Task -Status `$HeartbeatStatus -Outcome `$Outcome -Note 'Runner finalizado' | Out-Null
}
"@

    $content | Set-Content -LiteralPath $runnerPath -Encoding UTF8

    if (Test-Path -LiteralPath $runnerPath) {
        if ($Overwrite) { $updated++ } else { $created++ }
    }
}

Write-Host "Runners criados: $created" -ForegroundColor Green
Write-Host "Runners atualizados: $updated" -ForegroundColor Yellow
Write-Host "Runners mantidos (ja existentes): $skipped" -ForegroundColor Cyan
