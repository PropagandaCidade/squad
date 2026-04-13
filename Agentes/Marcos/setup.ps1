# Setup Script - Marcos Agent
# Instala dependências e configura o ambiente

Write-Host "MARCOS - Configuracao Inicial" -ForegroundColor Cyan
Write-Host "=============================" -ForegroundColor Cyan
Write-Host ""

$MarcosPath = Split-Path -Parent $MyInvocation.MyCommand.Path

# Verificar estrutura de diretórios
Write-Host "Verificando estrutura..." -ForegroundColor Yellow

$RequiredDirs = @(
    "config",
    "runner",
    "checks",
    "tests",
    "reports"
)

$AllDirsExist = $true
foreach ($dir in $RequiredDirs) {
    $dirPath = Join-Path $MarcosPath $dir
    if (Test-Path $dirPath -PathType Container) {
        Write-Host "  OK $dir" -ForegroundColor Green
    } else {
        Write-Host "  ERRO $dir (faltando)" -ForegroundColor Red
        $AllDirsExist = $false
    }
}

if (-not $AllDirsExist) {
    Write-Host ""
    Write-Host "ERRO: Estrutura de diretorios incompleta. Execute o script do diretorio Marcos/" -ForegroundColor Red
    exit 1
}

# Verificar arquivos críticos
Write-Host ""
Write-Host "Verificando arquivos criticos..." -ForegroundColor Yellow

$CriticalFiles = @(
    "config\projects.json",
    "runner\marcos.ps1",
    "README.md"
)

$AllFilesExist = $true
foreach ($file in $CriticalFiles) {
    $filePath = Join-Path $MarcosPath $file
    if (Test-Path $filePath -PathType Leaf) {
        Write-Host "  OK $file" -ForegroundColor Green
    } else {
        Write-Host "  ERRO $file (faltando)" -ForegroundColor Red
        $AllFilesExist = $false
    }
}

if (-not $AllFilesExist) {
    Write-Host ""
    Write-Host "ERRO: Arquivos criticos faltando" -ForegroundColor Red
    exit 1
}

# Verificar PowerShell
Write-Host ""
Write-Host "Verificando PowerShell..." -ForegroundColor Yellow

$PSVersion = $PSVersionTable.PSVersion
Write-Host "  OK PowerShell $PSVersion" -ForegroundColor Green

# Verificar PHP (opcional)
Write-Host ""
Write-Host "Verificando PHP..." -ForegroundColor Yellow

try {
    $phpOutput = & php --version 2>$null
    if ($LASTEXITCODE -eq 0) {
        $phpVersion = ($phpOutput | Select-String -Pattern "PHP (\d+\.\d+\.\d+)").Matches[0].Groups[1].Value
        Write-Host "  OK PHP $phpVersion encontrado" -ForegroundColor Green
        $PHP = $true
    } else {
        throw "PHP nao encontrado"
    }
} catch {
    Write-Host "  AVISO: PHP nao encontrado (validacoes PHP limitadas)" -ForegroundColor Yellow
    $PHP = $false
}

# Verificar Node.js (opcional)
Write-Host ""
Write-Host "Verificando Node.js..." -ForegroundColor Yellow

try {
    $nodeOutput = & node --version 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  OK Node.js $nodeOutput encontrado" -ForegroundColor Green
        $NodeJS = $true
    } else {
        throw "Node.js nao encontrado"
    }
} catch {
    Write-Host "  AVISO: Node.js nao encontrado (linting JS limitado)" -ForegroundColor Yellow
    $NodeJS = $false
}

# Verificar projetos configurados
Write-Host ""
Write-Host "Verificando projetos..." -ForegroundColor Yellow

try {
    $config = Get-Content (Join-Path $MarcosPath "config\projects.json") -Raw | ConvertFrom-Json
    $projects = $config.projects.PSObject.Properties.Name

    Write-Host "  OK $($projects.Count) projeto(s) configurado(s):" -ForegroundColor Green
    foreach ($project in $projects) {
        $projectPath = $config.projects.$project.path
        if (Test-Path $projectPath) {
            Write-Host "    • $project OK" -ForegroundColor Green
        } else {
            Write-Host "    • $project ERRO (caminho invalido)" -ForegroundColor Red
        }
    }
} catch {
    Write-Host "  ERRO: Erro na configuracao de projetos" -ForegroundColor Red
}

# Criar arquivo de configuração local
Write-Host ""
Write-Host "Criando configuracao local..." -ForegroundColor Yellow

$LocalConfig = @{
    installed = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    version = "1.0.0"
    php = $PHP
    nodejs = $NodeJS
    path = $MarcosPath
}

$LocalConfigPath = Join-Path $MarcosPath "config\local.json"
$LocalConfig | ConvertTo-Json | Out-File -FilePath $LocalConfigPath -Encoding UTF8
Write-Host "  OK Configuracao local salva" -ForegroundColor Green

# Teste básico
Write-Host ""
Write-Host "Executando teste basico..." -ForegroundColor Yellow

try {
    $testResult = & (Join-Path $MarcosPath "runner\marcos.ps1") -Project "studio-master" -Files "README.md" 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  OK Teste basico passou" -ForegroundColor Green
    } else {
        Write-Host "  AVISO: Teste basico com avisos" -ForegroundColor Yellow
    }
} catch {
    Write-Host "  ERRO: Erro no teste basico: $($_.Exception.Message)" -ForegroundColor Red
}

# Resumo final
Write-Host ""
Write-Host "CONFIGURACAO CONCLUIDA!" -ForegroundColor Green
Write-Host "========================" -ForegroundColor Green
Write-Host ""
Write-Host "Marcos instalado em: $MarcosPath" -ForegroundColor Cyan
Write-Host ""
Write-Host "Para usar:" -ForegroundColor White
Write-Host "   .\runner\marcos.ps1 -Project 'studio-master' -Files 'arquivo.js'" -ForegroundColor Gray
Write-Host ""
Write-Host "Para exemplos:" -ForegroundColor White
Write-Host "   .\example.ps1" -ForegroundColor Gray
Write-Host ""
Write-Host "Relatorios em: reports/" -ForegroundColor White
Write-Host ""
Write-Host "Pronto para validar correcoes!" -ForegroundColor Green