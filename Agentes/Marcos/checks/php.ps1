# Validações Estáticas - PHP
# Marcos Agent

function Test-PHPSyntax {
    param([string]$FilePath, [string]$ProjectPath)

    $FullPath = Join-Path $ProjectPath $FilePath

    Write-Host "🐘 Validando sintaxe PHP: $FilePath" -ForegroundColor Cyan

    if (-not (Test-Path $FullPath)) {
        Write-Host "❌ Arquivo não encontrado: $FullPath" -ForegroundColor Red
        return $false
    }

    try {
        # Verificar se PHP está disponível
        $phpVersion = & php --version 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-Host "⚠️ PHP CLI não encontrado, pulando validação avançada" -ForegroundColor Yellow

            # Fallback: validações básicas
            $Content = Get-Content $FullPath -Raw -Encoding UTF8

            $Issues = @()

            # Verificar tags PHP abertas/fechadas
            $openTags = ($Content | Select-String -Pattern '<\?php' -AllMatches).Matches.Count
            $closeTags = ($Content | Select-String -Pattern '\?>' -AllMatches).Matches.Count

            if ($openTags -ne $closeTags) {
                $Issues += "Tags PHP não balanceadas: $openTags abertas, $closeTags fechadas"
            }

            # Verificar chaves PHP não fechadas
            $openBraces = ($Content -split '{').Count - 1
            $closeBraces = ($Content -split '}').Count - 1
            if ($openBraces -ne $closeBraces) {
                $Issues += "Chaves PHP não balanceadas: $openBraces abertas, $closeBraces fechadas"
            }

            if ($Issues.Count -gt 0) {
                Write-Host "❌ Problemas encontrados:" -ForegroundColor Red
                foreach ($issue in $Issues) {
                    Write-Host "  $issue" -ForegroundColor Red
                }
                return $false
            }

            Write-Host "✅ Validação básica PHP passou" -ForegroundColor Green
            return $true
        }

        # Usar php -l para validação completa
        Write-Host "📦 Usando PHP CLI para validação completa" -ForegroundColor Gray

        $result = & php -l $FullPath 2>&1

        if ($LASTEXITCODE -eq 0) {
            Write-Host "✅ Sintaxe PHP válida" -ForegroundColor Green
            return $true
        } else {
            Write-Host "❌ Erros de sintaxe PHP:" -ForegroundColor Red
            Write-Host $result -ForegroundColor Red
            return $false
        }

    } catch {
        Write-Host "❌ Erro ao validar PHP: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# Exportar função
Export-ModuleMember -Function Test-PHPSyntax