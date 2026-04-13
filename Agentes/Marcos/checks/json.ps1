# Validações Estáticas - JSON
# Marcos Agent

function Test-JSONSyntax {
    param([string]$FilePath, [string]$ProjectPath)

    $FullPath = Join-Path $ProjectPath $FilePath

    Write-Host "📄 Validando sintaxe JSON: $FilePath" -ForegroundColor Cyan

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

        # Tentar fazer parse do JSON
        $parsedJson = $Content | ConvertFrom-Json

        # Verificações adicionais
        $Issues = @()

        # Verificar se é um objeto/array válido
        if ($parsedJson -isnot [System.Collections.IDictionary] -and $parsedJson -isnot [System.Collections.IList]) {
            $Issues += "JSON deve ser um objeto ou array no nível raiz"
        }

        # Verificar trailing commas (não suportadas em JSON padrão)
        if ($Content -match ',\s*[\]\}]') {
            $Issues += "Trailing commas detectadas (não suportadas em JSON)"
        }

        # Verificar comentários (não suportados em JSON padrão)
        if ($Content -match '^\s*//' -or $Content -match '/\*.*?\*/') {
            $Issues += "Comentários detectados (não suportados em JSON padrão)"
        }

        if ($Issues.Count -gt 0) {
            Write-Host "❌ Problemas encontrados:" -ForegroundColor Red
            foreach ($issue in $Issues) {
                Write-Host "  $issue" -ForegroundColor Red
            }
            return $false
        }

        Write-Host "✅ Sintaxe JSON válida" -ForegroundColor Green
        return $true

    } catch {
        Write-Host "❌ Erro de sintaxe JSON: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Validate-JSONStructure {
    param([string]$FilePath, [string]$ProjectPath)

    $FullPath = Join-Path $ProjectPath $FilePath

    Write-Host "🔍 Validando estrutura JSON: $FilePath" -ForegroundColor Cyan

    try {
        $Content = Get-Content $FullPath -Raw -Encoding UTF8
        $json = $Content | ConvertFrom-Json

        $Issues = @()

        # Validações específicas baseadas no tipo de arquivo
        $fileName = [System.IO.Path]::GetFileNameWithoutExtension($FilePath)

        switch ($fileName) {
            "package" {
                # Validar package.json
                if (-not $json.name) { $Issues += "Campo 'name' obrigatório faltando" }
                if (-not $json.version) { $Issues += "Campo 'version' obrigatório faltando" }
            }
            "tsconfig" {
                # Validar tsconfig.json
                if (-not $json.compilerOptions) { $Issues += "Campo 'compilerOptions' obrigatório faltando" }
            }
            default {
                # Validações genéricas
                if ($json -is [System.Collections.IDictionary]) {
                    if ($json.Count -eq 0) {
                        $Issues += "Objeto JSON vazio"
                    }
                } elseif ($json -is [System.Collections.IList]) {
                    if ($json.Count -eq 0) {
                        Write-Host "⚠️ Array JSON vazio" -ForegroundColor Yellow
                    }
                }
            }
        }

        if ($Issues.Count -gt 0) {
            Write-Host "❌ Problemas de estrutura:" -ForegroundColor Red
            foreach ($issue in $Issues) {
                Write-Host "  $issue" -ForegroundColor Red
            }
            return $false
        }

        Write-Host "✅ Estrutura JSON válida" -ForegroundColor Green
        return $true

    } catch {
        Write-Host "❌ Erro ao validar estrutura JSON: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# Exportar funções
Export-ModuleMember -Function Test-JSONSyntax, Validate-JSONStructure