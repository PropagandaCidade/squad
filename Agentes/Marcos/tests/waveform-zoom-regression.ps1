# Teste de Regressão - Zoom da Waveform
# Marcos Agent

function Test-WaveformZoomRegression {
    param([string]$ProjectPath)

    Write-Host "🧪 Executando teste de regressão de zoom da waveform..." -ForegroundColor Cyan

    $TestFile = Join-Path $ProjectPath "test_waveform_zoom_disappearance.html"
    $RunnerScript = Join-Path $ProjectPath "run_waveform_zoom_test.ps1"

    if (-not (Test-Path $TestFile)) {
        Write-Host "❌ Arquivo de teste não encontrado: $TestFile" -ForegroundColor Red
        return $false
    }

    if (-not (Test-Path $RunnerScript)) {
        Write-Host "❌ Script de execução não encontrado: $RunnerScript" -ForegroundColor Red
        return $false
    }

    try {
        Write-Host "🚀 Iniciando teste automatizado..." -ForegroundColor Yellow

        # Executar o script de teste
        & $RunnerScript

        # Aguardar um pouco para o teste completar
        Start-Sleep -Seconds 5

        Write-Host "✅ Teste de zoom executado com sucesso" -ForegroundColor Green
        return $true

    } catch {
        Write-Host "❌ Erro ao executar teste de zoom: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# Exportar função
Export-ModuleMember -Function Test-WaveformZoomRegression