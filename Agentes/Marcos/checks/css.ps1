# Validações Estáticas - CSS
# Marcos Agent

function Test-CSSSyntax {
    param([string]$FilePath, [string]$ProjectPath)

    $FullPath = Join-Path $ProjectPath $FilePath

    Write-Host "🎨 Validando sintaxe CSS: $FilePath" -ForegroundColor Cyan

    if (-not (Test-Path $FullPath)) {
        Write-Host "❌ Arquivo não encontrado: $FullPath" -ForegroundColor Red
        return $false
    }

    try {
        $Content = Get-Content $FullPath -Raw -Encoding UTF8

        # Verificar se tem conteúdo
        if ([string]::IsNullOrWhiteSpace($Content)) {
            Write-Host "⚠️ Arquivo vazio" -ForegroundColor Yellow
            return $true
        }

        $Issues = @()

        # Verificar chaves não fechadas
        $openBraces = ($Content -split '{').Count - 1
        $closeBraces = ($Content -split '}').Count - 1
        if ($openBraces -ne $closeBraces) {
            $Issues += "Chaves não balanceadas: $openBraces abertas, $closeBraces fechadas"
        }

        # Verificar ponto e vírgula faltantes (básico)
        $lines = $Content -split '\r?\n'
        for ($i = 0; $i -lt $lines.Count; $i++) {
            $line = $lines[$i].Trim()
            if ($line -match '^[a-zA-Z0-9\-_\s]+:\s*[^;]+$' -and $line -notmatch ';$') {
                $Issues += "Linha $($i + 1): Possível ponto e vírgula faltante"
            }
        }

        # Verificar seletores malformados
        if ($Content -match '}\s*{') {
            $Issues += "Possível seletor vazio ou malformado detectado"
        }

        # Verificar !important mal usado
        $importantCount = ($Content | Select-String -Pattern '!important' -AllMatches).Matches.Count
        if ($importantCount -gt 10) {
            $Issues += "Muitos usos de !important ($importantCount) - considere refatorar"
        }

        if ($Issues.Count -gt 0) {
            Write-Host "❌ Problemas encontrados:" -ForegroundColor Red
            foreach ($issue in $Issues) {
                Write-Host "  $issue" -ForegroundColor Red
            }
            return $false
        }

        Write-Host "✅ Sintaxe CSS válida" -ForegroundColor Green
        return $true

    } catch {
        Write-Host "❌ Erro ao validar CSS: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# Exportar função
Export-ModuleMember -Function Test-CSSSyntax