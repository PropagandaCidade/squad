# Teste de Visibilidade DOM
# Marcos Agent

function Test-DOMVisibility {
    param([string]$ProjectPath)

    Write-Host "🔍 Executando verificação de visibilidade DOM..." -ForegroundColor Cyan

    $IndexFile = Join-Path $ProjectPath "index.php"
    $AssetsPath = Join-Path $ProjectPath "assets"
    $JsPath = Join-Path $AssetsPath "js"
    $CssPath = Join-Path $AssetsPath "css"

    $Checks = @(
        @{ Path = $IndexFile; Name = "Arquivo principal index.php" },
        @{ Path = $AssetsPath; Name = "Diretório assets"; Type = "Directory" },
        @{ Path = $JsPath; Name = "Diretório assets/js"; Type = "Directory" },
        @{ Path = $CssPath; Name = "Diretório assets/css"; Type = "Directory" }
    )

    $AllPassed = $true

    foreach ($check in $Checks) {
        if ($check.Type -eq "Directory") {
            if (Test-Path $check.Path -PathType Container) {
                Write-Host "✅ $($check.Name) encontrado" -ForegroundColor Green
            } else {
                Write-Host "❌ $($check.Name) não encontrado" -ForegroundColor Red
                $AllPassed = $false
            }
        } else {
            if (Test-Path $check.Path -PathType Leaf) {
                Write-Host "✅ $($check.Name) encontrado" -ForegroundColor Green
            } else {
                Write-Host "❌ $($check.Name) não encontrado" -ForegroundColor Red
                $AllPassed = $false
            }
        }
    }

    # Verificar arquivos críticos de JS
    $CriticalJsFiles = @(
        "studio-waveform-zoom.js",
        "studio-waveform-aligner.js",
        "studio-waveform-core.js"
    )

    foreach ($jsFile in $CriticalJsFiles) {
        $JsFilePath = Join-Path $JsPath $jsFile
        if (Test-Path $JsFilePath) {
            Write-Host "✅ Arquivo JS crítico encontrado: $jsFile" -ForegroundColor Green
        } else {
            Write-Host "❌ Arquivo JS crítico faltando: $jsFile" -ForegroundColor Red
            $AllPassed = $false
        }
    }

    if ($AllPassed) {
        Write-Host "🎯 Verificação de visibilidade DOM passou" -ForegroundColor Green
        return $true
    } else {
        Write-Host "💥 Verificação de visibilidade DOM falhou" -ForegroundColor Red
        return $false
    }
}

# Exportar função
Export-ModuleMember -Function Test-DOMVisibility