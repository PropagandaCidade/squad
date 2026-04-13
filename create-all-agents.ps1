# Script simples para criar todos os agentes
$BasePath = "G:\Meu Drive\Geral\Propaganda_Cidade\SQUAD\Agentes"
$Date = Get-Date -Format "yyyyMMdd_HHmmss"

function New-Agent {
    param($Name, $Specialty, $Points = 10)
    $AgentPath = Join-Path $BasePath $Name
    New-Item -ItemType Directory -Path $AgentPath -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $AgentPath "runner") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $AgentPath "config") -Force | Out-Null

    $Config = @{
        agent = @{
            name = $Name
            specialty = $Specialty
            level = "Novato"
            points = $Points
            badges = @("Novo Agente")
            created = $Date
            status = "ativo"
        }
    }
    $Config | ConvertTo-Json | Out-File (Join-Path $AgentPath "config\agent-config.json") -Encoding UTF8

    $Runner = @"
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

Write-Host "Agente: $Name" -ForegroundColor Cyan
Write-Host "Especialidade: $Specialty" -ForegroundColor Yellow

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
    Update-AgentHeartbeat -AgentName '$Name' -TaskId `$TaskId -Task `$Task -Status 'in_progress' -Note 'Runner iniciado' | Out-Null
}

if (Test-Path -LiteralPath `$GamificationScript) {
    . `$GamificationScript
    if (Get-Command Register-AgentAction -ErrorAction SilentlyContinue) {
        if (`$Points -ge 0) {
            `$g = Add-AgentPoints -AgentName '$Name' -Points `$Points -Task `$Task -Badges @('Execucao Registrada')
        } else {
            `$g = Register-AgentAction -AgentName '$Name' -Task `$Task -Category 'execution' -Complexity `$Complexity -Outcome `$Outcome -Badges @('Execucao Registrada')
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
    Update-AgentHeartbeat -AgentName '$Name' -TaskId `$TaskId -Task `$Task -Status `$HeartbeatStatus -Outcome `$Outcome -Note 'Runner finalizado' | Out-Null
}
"@
    $Runner | Out-File (Join-Path $AgentPath "runner\$Name.ps1") -Encoding UTF8
    Write-Host "Criado: $Name"
}

# FASE 2
New-Agent "Lucas" "SEO Specialist" 10
New-Agent "Amanda" "Social Media Manager" 10
New-Agent "Bruno" "Designer Gráfico" 10
New-Agent "Julia" "Motion Designer" 10
New-Agent "Ricardo" "Full-Stack Developer" 10

# FASE 3
New-Agent "Mariana" "Copywriter" 10
New-Agent "Rafael" "Roteirista" 10
New-Agent "Ana" "Content Strategist" 10
New-Agent "Fernando" "Business Development" 10
New-Agent "Carla" "Account Manager" 10
New-Agent "Eduardo" "Closer" 10
New-Agent "Gustavo" "Data Analyst" 10
New-Agent "Helena" "Project Manager" 10
New-Agent "Igor" "Strategic Planner" 10
New-Agent "Laura" "Customer Success" 10
New-Agent "MarcosJr" "QA Senior" 10
New-Agent "Valentina" "UX Researcher" 10

# FASE 4
New-Agent "Roberto" "Regional Manager SP" 15
New-Agent "Patricia" "Regional Manager RJ" 15
New-Agent "Luiz" "Regional Manager Sul" 15
New-Agent "Sandra" "Regional Manager Nordeste" 15
New-Agent "Diego" "AI Specialist" 20
New-Agent "Natalia" "Innovation Manager" 20
New-Agent "Vinicius" "Performance Marketing" 15
New-Agent "Camila" "Influencer Marketing" 15
New-Agent "Antonio" "Executive Assistant" 15
New-Agent "Beatriz" "Legal Advisor" 15

# RH
New-Agent "Renata" "HR Manager" 25
New-Agent "Felipe" "Talent Acquisition" 15
New-Agent "Daniela" "People Development" 15
New-Agent "Thiago" "HR Analytics" 15

$Count = (Get-ChildItem $BasePath -Directory | Where-Object { $_.Name -ne "Gamificacao" }).Count
Write-Host "TOTAL AGENTES: $Count"
