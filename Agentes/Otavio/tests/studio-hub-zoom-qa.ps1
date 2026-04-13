param(
    [ValidateSet("studio-hub", "studio-master-cursor")]
    [string]$Project = "studio-hub",

    [int]$Runs = 3
)

$ErrorActionPreference = "Stop"
$ScriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$AgentRoot = Split-Path -Parent $ScriptPath
$ConfigPath = Join-Path $AgentRoot "config\projects.json"

if (-not (Test-Path -LiteralPath $ConfigPath)) {
    throw "projects.json nao encontrado: $ConfigPath"
}

$config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
$projectCfg = $config.projects.$Project
if ($null -eq $projectCfg) {
    throw "Projeto nao configurado: $Project"
}

$projectPath = [string]$projectCfg.path
if (-not (Test-Path -LiteralPath $projectPath)) {
    throw "Projeto nao encontrado em disco: $projectPath"
}

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Message
    )
    if (-not $Condition) {
        throw "ASSERT FAILED: $Message"
    }
}

if ($Project -eq "studio-hub") {
    $waveformFile = Join-Path $projectPath "assets\js\studio-waveform.js"
    Assert-True -Condition (Test-Path -LiteralPath $waveformFile) -Message "Arquivo base da waveform nao encontrado"

    $content = Get-Content -LiteralPath $waveformFile -Raw

    $hasWheelHandler = $content -match "addEventListener\('wheel'|addEventListener\(\""wheel"""
    $hasZoomApi = $content -match "zoomIn|zoomOut|\.zoom\("
    $hasNeedleGuard = $content -match "sfx-stamp-visual|programmedSfx"

    if (-not $hasWheelHandler -or -not $hasZoomApi) {
        Write-Host "FAIL: studio-hub sem motor robusto de zoom por wheel (gap estrutural)." -ForegroundColor Red
        Write-Host "INFO: hasWheelHandler=$hasWheelHandler hasZoomApi=$hasZoomApi hasNeedleGuard=$hasNeedleGuard" -ForegroundColor Yellow
        exit 2
    }

    Write-Host "PASS: studio-hub possui estrutura minima de zoom." -ForegroundColor Green
    exit 0
}

if ($Project -eq "studio-master-cursor") {
    $editorRunner = Join-Path $projectPath "tools\run-editor-visual-master-tests.ps1"
    $zoomRunner = Join-Path $projectPath "tools\run-real-audio-zoom-stress.ps1"

    Assert-True -Condition (Test-Path -LiteralPath $editorRunner) -Message "runner visual nao encontrado"
    Assert-True -Condition (Test-Path -LiteralPath $zoomRunner) -Message "runner zoom real audio nao encontrado"

    & powershell -NoProfile -ExecutionPolicy Bypass -File $editorRunner
    if ($LASTEXITCODE -ne 0) {
        throw "Falha na suite visual master."
    }

    & powershell -NoProfile -ExecutionPolicy Bypass -File $zoomRunner -Runs $Runs -TimeoutMs 360000
    if ($LASTEXITCODE -ne 0) {
        throw "Falha na suite real audio zoom."
    }

    Write-Host "PASS: studio-master-cursor zoom suites ok." -ForegroundColor Green
    exit 0
}
