# Validações Estáticas - JavaScript
# Marcos Agent

function Test-JavaScriptSyntax {
    param([string]$FilePath, [string]$ProjectPath)

    $FullPath = Join-Path $ProjectPath $FilePath

    Write-Host "🔍 Validando sintaxe JavaScript: $FilePath" -ForegroundColor Cyan

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

        # Validação básica de sintaxe usando PowerShell parser
        $errors = $null
        $tokens = [System.Management.Automation.PSParser]::Tokenize($Content, [ref]$errors)

        if ($errors.Count -gt 0) {
            Write-Host "❌ Erros de sintaxe encontrados:" -ForegroundColor Red
            foreach ($error in $errors) {
                Write-Host "  Linha $($error.Token.StartLine): $($error.Message)" -ForegroundColor Red
            }
            return $false
        }

        # Verificações adicionais
        $Issues = @()

        # Verificar chaves não fechadas
        $openBraces = ($Content -split '{').Count - 1
        $closeBraces = ($Content -split '}').Count - 1
        if ($openBraces -ne $closeBraces) {
            $Issues += "Chaves não balanceadas: $openBraces abertas, $closeBraces fechadas"
        }

        # Verificar parênteses não fechados
        $openParens = ($Content -split '\(').Count - 1
        $closeParens = ($Content -split '\)').Count - 1
        if ($openParens -ne $closeParens) {
            $Issues += "Parênteses não balanceados: $openParens abertos, $closeParens fechados"
        }

        # Verificar colchetes não fechados
        $openBrackets = ($Content -split '\[').Count - 1
        $closeBrackets = ($Content -split '\]').Count - 1
        if ($openBrackets -ne $closeBrackets) {
            $Issues += "Colchetes não balanceados: $openBrackets abertos, $closeBrackets fechados"
        }

        if ($Issues.Count -gt 0) {
            Write-Host "❌ Problemas encontrados:" -ForegroundColor Red
            foreach ($issue in $Issues) {
                Write-Host "  $issue" -ForegroundColor Red
            }
            return $false
        }

        Write-Host "✅ Sintaxe JavaScript válida" -ForegroundColor Green
        return $true

    } catch {
        Write-Host "❌ Erro ao validar JavaScript: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Lint-JavaScript {
    param([string]$FilePath, [string]$ProjectPath)

    $FullPath = Join-Path $ProjectPath $FilePath

    Write-Host "🔧 Executando lint JavaScript: $FilePath" -ForegroundColor Cyan

    # Verificar se tem ESLint disponível
    try {
        $eslintVersion = & eslint --version 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "📦 Usando ESLint para linting" -ForegroundColor Gray

            $result = & eslint $FullPath 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Host "✅ Nenhum problema de linting encontrado" -ForegroundColor Green
                return $true
            } else {
                Write-Host "⚠️ Problemas de linting encontrados:" -ForegroundColor Yellow
                Write-Host $result -ForegroundColor Yellow
                return $false
            }
        }
    } catch {
        Write-Host "📦 ESLint não encontrado, pulando linting avançado" -ForegroundColor Gray
    }

    # Fallback: validações básicas
    try {
        $Content = Get-Content $FullPath -Raw -Encoding UTF8

        $Warnings = @()

        # Verificar uso de var (preferir let/const)
        $varCount = ($Content | Select-String -Pattern '\bvar\s+' -AllMatches).Matches.Count
        if ($varCount -gt 0) {
            $Warnings += "Encontrados $varCount usos de 'var' (considere usar 'let' ou 'const')"
        }

        # Verificar console.log deixados no código
        $consoleLogCount = ($Content | Select-String -Pattern 'console\.log' -AllMatches).Matches.Count
        if ($consoleLogCount -gt 0) {
            $Warnings += "Encontrados $consoleLogCount usos de 'console.log' (considere remover para produção)"
        }

        if ($Warnings.Count -gt 0) {
            Write-Host "⚠️ Avisos de linting:" -ForegroundColor Yellow
            foreach ($warning in $Warnings) {
                Write-Host "  $warning" -ForegroundColor Yellow
            }
            return $false
        }

        Write-Host "✅ Linting básico passou" -ForegroundColor Green
        return $true

    } catch {
        Write-Host "❌ Erro durante linting: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# Exportar funções
Export-ModuleMember -Function Test-JavaScriptSyntax, Lint-JavaScript