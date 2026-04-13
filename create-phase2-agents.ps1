# Script para criar agentes da Fase 2 - PROPAGANDA CIDADE
# Producao de Audio: Carlos, Sofia, Pedro

$BasePath = "G:\Meu Drive\Geral\Propaganda_Cidade\SQUAD\Agentes"
$Date = Get-Date -Format "yyyyMMdd_HHmmss"

Write-Host "Criando agentes da Fase 2 - Producao de Audio" -ForegroundColor Cyan

function New-Agent {
    param($Name, $Specialty, $Description, $Skills)

    Write-Host "Criando agente: $Name" -ForegroundColor Yellow

    $AgentPath = Join-Path $BasePath $Name
    New-Item -ItemType Directory -Path $AgentPath -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $AgentPath "runner") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $AgentPath "config") -Force | Out-Null

    $Config = @{
        agent = @{
            name = $Name
            specialty = $Specialty
            description = $Description
            skills = $Skills
            level = "Novato"
            points = 10
            badges = @("Novo Agente")
            created = $Date
            status = "ativo"
        }
        gamification = @{
            current_level = "Novato"
            total_points = 10
            badges_earned = @("Novo Agente")
            last_updated = $Date
        }
    }

    $Config | ConvertTo-Json -Depth 10 | Out-File (Join-Path $AgentPath "config\agent-config.json") -Encoding UTF8

    $Runner = @"
param(
    [Parameter(Mandatory = `$false)]
    [string]`$Task = 'Execucao de tarefa de audio',
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
if (Test-Path -LiteralPath `$GamificationScript) {
    . `$GamificationScript
    if (Get-Command Register-AgentAction -ErrorAction SilentlyContinue) {
        if (`$Points -ge 0) {
            `$g = Add-AgentPoints -AgentName '$Name' -Points `$Points -Task `$Task -Badges @('Audio em Acao')
        } else {
            `$g = Register-AgentAction -AgentName '$Name' -Task `$Task -Category 'audio_production' -Complexity `$Complexity -Outcome `$Outcome -Badges @('Audio em Acao')
        }
        Write-Host ("Gamificacao: +{0} pontos (total {1})" -f `$g.pointsAwarded, `$g.totalPoints) -ForegroundColor Green
    }
}
"@
    $Runner | Out-File (Join-Path $AgentPath "runner\$Name.ps1") -Encoding UTF8

    Write-Host "$Name criado!" -ForegroundColor Green
}

New-Agent "Carlos" "Produtor Musical" "Composicao e producao musical" "Composicao, Arranjos, Producao Musical"
New-Agent "Sofia" "Locutora Profissional" "Locucao para comerciais" "Locucao, Voz Publicitaria, Dublagem"
New-Agent "Pedro" "Editor de Audio" "Mixagem e masterizacao" "Mixagem, Masterizacao, Edicao de Audio"

Write-Host "`nAgentes da Fase 2 criados com sucesso!" -ForegroundColor Green
Write-Host "Total: 3 agentes de producao de audio" -ForegroundColor Cyan
