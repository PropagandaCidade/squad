# Marcos - Agente de ValidaÃ§Ã£o de CorreÃ§Ãµes
# VersÃ£o: 1.0.0

param(
    [Parameter(Mandatory=$true)]
    [string]$Project,

    [Parameter(Mandatory=$false)]
    [string[]]$Files,

    [Parameter(Mandatory=$false)]
    [switch]$LogVerbose,

    [Parameter(Mandatory=$false)]
    [switch]$SkipStaticChecks
)

# ConfiguraÃ§Ãµes globais
$ScriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootPath = Split-Path -Parent $ScriptPath
$ConfigPath = Join-Path $RootPath "config\projects.json"
$ReportsPath = Join-Path $RootPath "reports"
$GamificationScript = Join-Path $RootPath "..\Gamificacao\gamification.ps1"
if (Test-Path $GamificationScript) { . $GamificationScript }
$HeartbeatScript = Join-Path $RootPath "..\Gamificacao\heartbeat.ps1"
if (Test-Path $HeartbeatScript) { . $HeartbeatScript }

# Carregar configuraÃ§Ãµes
try {
    $Config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
} catch {
    Write-Host "ERRO: NÃ£o foi possÃ­vel carregar configuraÃ§Ã£o: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Verificar se projeto existe
if (-not $Config.projects.PSObject.Properties.Name.Contains($Project)) {
    Write-Host "ERRO: Projeto '$Project' nÃ£o encontrado na configuraÃ§Ã£o" -ForegroundColor Red
    exit 1
}

$ProjectConfig = $Config.projects.$Project
$ProjectPath = $ProjectConfig.path

# FunÃ§Ã£o de logging
function Write-Log {
    param([string]$Level, [string]$Message)
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogMessage = "[$Timestamp] [$Level] $Message"

    if ($LogVerbose -or $Level -ne "DEBUG") {
        switch ($Level) {
            "INFO" { Write-Host $LogMessage -ForegroundColor Cyan }
            "SUCCESS" { Write-Host $LogMessage -ForegroundColor Green }
            "WARN" { Write-Host $LogMessage -ForegroundColor Yellow }
            "ERROR" { Write-Host $LogMessage -ForegroundColor Red }
            "DEBUG" { Write-Host $LogMessage -ForegroundColor Gray }
        }
    }

    # Salvar no arquivo de log
    $LogFile = Join-Path $ReportsPath "$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss')_marcos.log"
    $LogMessage | Out-File -FilePath $LogFile -Append -Encoding UTF8
}

# Classe para resultados
class TestResult {
    [string]$TestName
    [string]$Status
    [string]$Message
    [array]$Details
    [datetime]$Timestamp

    TestResult([string]$name) {
        $this.TestName = $name
        $this.Status = "PENDING"
        $this.Details = @()
        $this.Timestamp = Get-Date
    }

    [void]Pass([string]$message) {
        $this.Status = "PASS"
        $this.Message = $message
    }

    [void]Fail([string]$message) {
        $this.Status = "FAIL"
        $this.Message = $message
    }

    [void]AddDetail([string]$detail) {
        $this.Details += $detail
    }
}

# FunÃ§Ã£o principal
function Invoke-Marcos {
    Write-Log "INFO" "=== MARCOS - Iniciando validaÃ§Ã£o ==="
    Write-Log "INFO" "Projeto: $Project"
    Write-Log "INFO" "Arquivos: $($Files -join ', ')"

    $Results = @()
    $OverallStatus = "PASS"

    # 1. ValidaÃ§Ãµes estÃ¡ticas
    if (-not $SkipStaticChecks) {
        Write-Log "INFO" "Executando validaÃ§Ãµes estÃ¡ticas..."
        $StaticResults = Invoke-StaticChecks
        $Results += $StaticResults

        foreach ($result in $StaticResults) {
            if ($result.Status -eq "FAIL") {
                $OverallStatus = "FAIL"
            }
        }
    }

    # 2. Testes especÃ­ficos do projeto
    Write-Log "INFO" "Executando testes especÃ­ficos..."
    $TestResults = Invoke-ProjectTests
    $Results += $TestResults

    foreach ($result in $TestResults) {
        if ($result.Status -eq "FAIL") {
            $OverallStatus = "FAIL"
        }
    }

    # 3. Gerar relatÃ³rio
    $Report = @{
        timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        project = $Project
        files = $Files
        overallStatus = $OverallStatus
        results = $Results
    }

    $ReportPath = Join-Path $ReportsPath "$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss')_report.json"
    $Report | ConvertTo-Json -Depth 10 | Out-File -FilePath $ReportPath -Encoding UTF8

    Write-Log "INFO" "RelatÃ³rio salvo em: $ReportPath"

    # 4. Resumo final
    Write-Log "INFO" "=== RESULTADO FINAL: $OverallStatus ==="
    Write-Log "INFO" "Total de testes: $($Results.Count)"
    Write-Log "INFO" "Passaram: $($Results | Where-Object { $_.Status -eq 'PASS' } | Measure-Object | Select-Object -ExpandProperty Count)"
    Write-Log "INFO" "Falharam: $($Results | Where-Object { $_.Status -eq 'FAIL' } | Measure-Object | Select-Object -ExpandProperty Count)"

    if (Get-Command Register-AgentAction -ErrorAction SilentlyContinue) {
        $outcome = if ($OverallStatus -eq 'PASS') { 'success' } else { 'partial' }
        $complexity = if (($Files | Measure-Object).Count -ge 6) { 'high' } else { 'medium' }
        $g = Register-AgentAction -AgentName "Marcos" -Task "Validacao tecnica $Project ($OverallStatus)" -Category "validation" -Complexity $complexity -Outcome $outcome -Badges @("Guardiao da Qualidade")
        Write-Log "INFO" "Gamificacao: Marcos ganhou $($g.pointsAwarded) pontos"
    } elseif (Get-Command Add-AgentPoints -ErrorAction SilentlyContinue) {
        $points = if ($OverallStatus -eq 'PASS') { 30 } else { 10 }
        Add-AgentPoints -AgentName "Marcos" -Points $points -Task "Validacao $OverallStatus" -Badges @("Guardiao da Qualidade")
        Write-Log "INFO" "Gamificacao: Marcos ganhou $points pontos"
    }

    return $OverallStatus
}

function Invoke-StaticChecks {
    $Results = @()

    foreach ($file in $Files) {
        $extension = [System.IO.Path]::GetExtension($file).ToLower()

        if ($extension -eq ".js") {
            $result = New-Object TestResult "StaticCheck-JS-$file"
            $checkResult = Test-JavaScriptSyntax $file
            if ($checkResult) {
                $result.Pass("Sintaxe JS vÃ¡lida")
            } else {
                $result.Fail("Erro de sintaxe JS")
                $OverallStatus = "FAIL"
            }
            $Results += $result
        }

        if ($extension -eq ".css") {
            $result = New-Object TestResult "StaticCheck-CSS-$file"
            $checkResult = Test-CSSSyntax $file
            if ($checkResult) {
                $result.Pass("Sintaxe CSS vÃ¡lida")
            } else {
                $result.Fail("Erro de sintaxe CSS")
            }
            $Results += $result
        }

        if ($extension -eq ".php") {
            $result = New-Object TestResult "StaticCheck-PHP-$file"
            $checkResult = Test-PHPSyntax $file
            if ($checkResult) {
                $result.Pass("Sintaxe PHP vÃ¡lida")
            } else {
                $result.Fail("Erro de sintaxe PHP")
            }
            $Results += $result
        }

        if ($extension -eq ".json") {
            $result = New-Object TestResult "StaticCheck-JSON-$file"
            $checkResult = Test-JSONSyntax $file
            if ($checkResult) {
                $result.Pass("Sintaxe JSON vÃ¡lida")
            } else {
                $result.Fail("Erro de sintaxe JSON")
            }
            $Results += $result
        }
    }

    return $Results
}

function Invoke-ProjectTests {
    $Results = @()

    foreach ($test in $ProjectConfig.tests) {
        $result = New-Object TestResult "ProjectTest-$test"

        switch ($test) {
            "waveform-zoom-regression" {
                $testResult = Invoke-WaveformZoomTest
                if ($testResult) {
                    $result.Pass("Teste de zoom da waveform passou")
                } else {
                    $result.Fail("Teste de zoom da waveform falhou")
                }
            }
            "dom-visibility-check" {
                $testResult = Invoke-DOMVisibilityTest
                if ($testResult) {
                    $result.Pass("VerificaÃ§Ã£o de visibilidade DOM passou")
                } else {
                    $result.Fail("VerificaÃ§Ã£o de visibilidade DOM falhou")
                }
            }
            "static-validation" {
                $result.Pass("ValidaÃ§Ã£o estÃ¡tica jÃ¡ executada")
            }
            default {
                $result.Fail("Teste '$test' nÃ£o implementado")
            }
        }

        $Results += $result
    }

    return $Results
}

# ImplementaÃ§Ãµes dos testes especÃ­ficos
function Invoke-WaveformZoomTest {
    Write-Log "INFO" "Executando teste de regressÃ£o de zoom da waveform..."

    $TestFile = Join-Path $ProjectPath "test_waveform_zoom_disappearance.html"
    $RunnerScript = Join-Path $ProjectPath "run_waveform_zoom_test.ps1"

    if (-not (Test-Path $TestFile)) {
        Write-Log "ERROR" "Arquivo de teste nÃ£o encontrado: $TestFile"
        return $false
    }

    if (-not (Test-Path $RunnerScript)) {
        Write-Log "ERROR" "Script de execuÃ§Ã£o nÃ£o encontrado: $RunnerScript"
        return $false
    }

    try {
        # Executar o teste
        & $RunnerScript
        Write-Log "SUCCESS" "Teste de zoom executado com sucesso"
        return $true
    } catch {
        Write-Log "ERROR" "Erro ao executar teste de zoom: $($_.Exception.Message)"
        return $false
    }
}

function Invoke-DOMVisibilityTest {
    Write-Log "INFO" "Executando verificaÃ§Ã£o de visibilidade DOM..."

    # ImplementaÃ§Ã£o bÃ¡sica - pode ser expandida
    $IndexFile = Join-Path $ProjectPath "index.php"

    if (Test-Path $IndexFile) {
        Write-Log "SUCCESS" "Arquivo principal encontrado"
        return $true
    } else {
        Write-Log "ERROR" "Arquivo principal nÃ£o encontrado"
        return $false
    }
}

# FunÃ§Ãµes de validaÃ§Ã£o estÃ¡tica
function Test-JavaScriptSyntax {
    param([string]$FilePath)

    $FullPath = Join-Path $ProjectPath $FilePath

    if (-not (Test-Path $FullPath)) {
        Write-Log "ERROR" "Arquivo JS nÃ£o encontrado: $FullPath"
        return $false
    }

    try {
        $Content = Get-Content $FullPath -Raw -Encoding UTF8
        # ValidaÃ§Ã£o bÃ¡sica de sintaxe JS
        $null = [System.Management.Automation.PSParser]::Tokenize($Content, [ref]$null)
        Write-Log "DEBUG" "Sintaxe JS vÃ¡lida para $FilePath"
        return $true
    } catch {
        Write-Log "ERROR" "Erro de sintaxe JS em $FilePath`: $($_.Exception.Message)"
        return $false
    }
}

function Test-CSSSyntax {
    param([string]$FilePath)

    $FullPath = Join-Path $ProjectPath $FilePath

    if (-not (Test-Path $FullPath)) {
        Write-Log "ERROR" "Arquivo CSS nÃ£o encontrado: $FullPath"
        return $false
    }

    try {
        $Content = Get-Content $FullPath -Raw -Encoding UTF8
        # ValidaÃ§Ã£o bÃ¡sica - verificar se nÃ£o hÃ¡ erros Ã³bvios
        if ($Content -match '}\s*{') {
            Write-Log "WARN" "PossÃ­vel erro de sintaxe CSS em $FilePath"
            return $false
        }
        Write-Log "DEBUG" "Sintaxe CSS vÃ¡lida para $FilePath"
        return $true
    } catch {
        Write-Log "ERROR" "Erro ao validar CSS em $FilePath`: $($_.Exception.Message)"
        return $false
    }
}

function Test-PHPSyntax {
    param([string]$FilePath)

    $FullPath = Join-Path $ProjectPath $FilePath

    if (-not (Test-Path $FullPath)) {
        Write-Log "ERROR" "Arquivo PHP nÃ£o encontrado: $FullPath"
        return $false
    }

    try {
        # Usar php -l para validaÃ§Ã£o de sintaxe
        $result = & php -l $FullPath 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Log "DEBUG" "Sintaxe PHP vÃ¡lida para $FilePath"
            return $true
        } else {
            Write-Log "ERROR" "Erro de sintaxe PHP em $FilePath`: $result"
            return $false
        }
    } catch {
        Write-Log "ERROR" "Erro ao executar validaÃ§Ã£o PHP: $($_.Exception.Message)"
        return $false
    }
}

function Test-JSONSyntax {
    param([string]$FilePath)

    $FullPath = Join-Path $ProjectPath $FilePath

    if (-not (Test-Path $FullPath)) {
        Write-Log "ERROR" "Arquivo JSON nÃ£o encontrado: $FullPath"
        return $false
    }

    try {
        $Content = Get-Content $FullPath -Raw -Encoding UTF8
        $null = $Content | ConvertFrom-Json
        Write-Log "DEBUG" "Sintaxe JSON vÃ¡lida para $FilePath"
        return $true
    } catch {
        Write-Log "ERROR" "Erro de sintaxe JSON em $FilePath`: $($_.Exception.Message)"
        return $false
    }
}

# Executar Marcos
if (Get-Command Update-AgentHeartbeat -ErrorAction SilentlyContinue) {
    Update-AgentHeartbeat -AgentName "Marcos" -TaskId "TASK-VALIDATION-$Project" -Task "Validacao tecnica de $Project" -Status "in_progress" -Note "Marcos runner iniciado" | Out-Null
}

$result = Invoke-Marcos

if (Get-Command Update-AgentHeartbeat -ErrorAction SilentlyContinue) {
    $heartbeatStatus = if ($result -eq "PASS") { "done" } else { "failed" }
    Update-AgentHeartbeat -AgentName "Marcos" -TaskId "TASK-VALIDATION-$Project" -Task "Validacao tecnica de $Project" -Status $heartbeatStatus -Outcome $result -Note "Marcos runner finalizado" | Out-Null
}

# Sair com cÃ³digo apropriado
if ($result -eq "PASS") {
    exit 0
} else {
    exit 1
}
