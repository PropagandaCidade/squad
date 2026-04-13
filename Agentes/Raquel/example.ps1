# Raquel - Exemplos de Uso
# Demonstrações práticas da agente de design

Write-Host "🎨 RAQUEL - Agente de Design" -ForegroundColor Magenta
Write-Host "=============================" -ForegroundColor Magenta
Write-Host ""

$RaquelPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$RunnerPath = Join-Path $RaquelPath "runner\raquel.ps1"

if (-not (Test-Path $RunnerPath)) {
    Write-Host "ERRO: Script da Raquel nao encontrado em $RunnerPath" -ForegroundColor Red
    Write-Host "Certifique-se de executar este script do diretorio Raquel/" -ForegroundColor Yellow
    exit 1
}

# Exemplos de uso
Write-Host "EXEMPLOS DE USO:" -ForegroundColor Yellow
Write-Host ""

Write-Host "1. Criar pagina web moderna:" -ForegroundColor White
Write-Host "   .\runner\raquel.ps1 -Project 'studio-master' -DesignType 'webpage' -Style 'modern'" -ForegroundColor Gray
Write-Host ""

Write-Host "2. Criar landing page interativa:" -ForegroundColor White
Write-Host "   .\runner\raquel.ps1 -Project 'studio-master' -DesignType 'landing' -Style 'bold' -Interactive" -ForegroundColor Gray
Write-Host ""

Write-Host "3. Criar dashboard elegante:" -ForegroundColor White
Write-Host "   .\runner\raquel.ps1 -Project 'studio-master' -DesignType 'dashboard' -Style 'elegant' -ExportAssets" -ForegroundColor Gray
Write-Host ""

Write-Host "4. Criar componente minimalista:" -ForegroundColor White
Write-Host "   .\runner\raquel.ps1 -Project 'studio-master' -DesignType 'component' -Style 'minimal'" -ForegroundColor Gray
Write-Host ""

Write-Host "TIPOS DE DESIGN:" -ForegroundColor White
Write-Host "• webpage   - Paginas web completas" -ForegroundColor Gray
Write-Host "• component - Componentes reutilizaveis" -ForegroundColor Gray
Write-Host "• landing   - Paginas de destino" -ForegroundColor Gray
Write-Host "• dashboard - Paineis administrativos" -ForegroundColor Gray
Write-Host ""

Write-Host "ESTILOS DISPONIVEIS:" -ForegroundColor White
Write-Host "• modern  - Gradientes e elementos modernos" -ForegroundColor Gray
Write-Host "• minimal - Design limpo e simples" -ForegroundColor Gray
Write-Host "• bold    - Cores fortes e marcantes" -ForegroundColor Gray
Write-Host "• elegant - Design sofisticado" -ForegroundColor Gray
Write-Host ""

Write-Host "EXECUTANDO EXEMPLO AUTOMATICO..." -ForegroundColor Green
Write-Host ""

$TestDesign = "webpage"
$TestStyle = "modern"

Write-Host "Criando design de exemplo:" -ForegroundColor Cyan
Write-Host "• Tipo: $TestDesign" -ForegroundColor White
Write-Host "• Estilo: $TestStyle" -ForegroundColor White
Write-Host ""

try {
    & $RunnerPath -Project "studio-master" -DesignType $TestDesign -Style $TestStyle
    Write-Host ""
    Write-Host "Design criado com sucesso pela Raquel!" -ForegroundColor Green
    Write-Host "Verifique os arquivos gerados no projeto studio-master." -ForegroundColor Cyan
} catch {
    Write-Host "Erro ao criar design: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Write-Host "Para mais exemplos, consulte o README.md" -ForegroundColor Yellow