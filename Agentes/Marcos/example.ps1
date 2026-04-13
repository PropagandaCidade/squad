# Marcos - Exemplos de Uso
# Demonstrações práticas do agente de validação

Write-Host "MARCOS - Exemplos de Uso" -ForegroundColor Cyan
Write-Host "========================" -ForegroundColor Cyan
Write-Host ""

$MarcosPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$RunnerPath = Join-Path $MarcosPath "runner\marcos.ps1"

if (-not (Test-Path $RunnerPath)) {
    Write-Host "ERRO: Script do Marcos nao encontrado em $RunnerPath" -ForegroundColor Red
    Write-Host "Certifique-se de executar este script do diretorio Marcos/" -ForegroundColor Yellow
    exit 1
}

# Exemplos de uso
Write-Host "EXEMPLOS DE USO:" -ForegroundColor Yellow
Write-Host ""

Write-Host "1. Testar correcao no studio-master:" -ForegroundColor White
Write-Host "   .\runner\marcos.ps1 -Project 'studio-master' -Files 'assets\js\studio-waveform-zoom.js'" -ForegroundColor Gray
Write-Host ""

Write-Host "2. Testar multiplos arquivos:" -ForegroundColor White
Write-Host "   .\runner\marcos.ps1 -Project 'studio-master' -Files 'assets\js\studio-waveform-zoom.js', 'assets\js\studio-waveform-aligner.js'" -ForegroundColor Gray
Write-Host ""

Write-Host "3. Pular validacoes estaticas:" -ForegroundColor White
Write-Host "   .\runner\marcos.ps1 -Project 'studio-master' -Files 'assets\js\studio-waveform-zoom.js' -SkipStaticChecks" -ForegroundColor Gray
Write-Host ""

Write-Host "4. Modo verbose:" -ForegroundColor White
Write-Host "   .\runner\marcos.ps1 -Project 'studio-master' -Files 'assets\js\studio-waveform-zoom.js' -LogVerbose" -ForegroundColor Gray
Write-Host ""

# Executar exemplo automático
Write-Host "EXECUTANDO EXEMPLO AUTOMATICO..." -ForegroundColor Green
Write-Host ""

$TestFiles = @(
    "README.md"
)

Write-Host "Testando arquivos:" -ForegroundColor Cyan
foreach ($file in $TestFiles) {
    Write-Host "  • $file" -ForegroundColor White
}
Write-Host ""

try {
    & $RunnerPath -Project "studio-master" -Files $TestFiles
    Write-Host ""
    Write-Host "Exemplo executado com sucesso!" -ForegroundColor Green
} catch {
    Write-Host "Erro no exemplo: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

try {
    & $RunnerPath -Project "studio-master" -Files $TestFiles
    $exitCode = $LASTEXITCODE

    Write-Host ""
    if ($exitCode -eq 0) {
        Write-Host "✅ EXEMPLO CONCLUÍDO COM SUCESSO!" -ForegroundColor Green
    } else {
        Write-Host "❌ EXEMPLO FALHOU!" -ForegroundColor Red
    }

} catch {
    Write-Host "Erro ao executar exemplo: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Write-Host "RELATORIOS SALVOS EM: reports/" -ForegroundColor Cyan
Write-Host "DOCUMENTACAO: README.md" -ForegroundColor Cyan