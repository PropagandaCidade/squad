# Raquel - Agente de Design e Frontend
# VersÃ£o: 1.0.0

param(
    [Parameter(Mandatory=$true)]
    [string]$Project,

    [Parameter(Mandatory=$false)]
    [string]$DesignType = "webpage",

    [Parameter(Mandatory=$false)]
    [string]$Style = "modern",

    [Parameter(Mandatory=$false)]
    [switch]$Interactive,

    [Parameter(Mandatory=$false)]
    [switch]$ExportAssets
)

# ConfiguraÃ§Ãµes globais
$ScriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootPath = Split-Path -Parent $ScriptPath
$ConfigPath = Join-Path $RootPath "config\projects.json"
$TemplatesPath = Join-Path $RootPath "templates"
$AssetsPath = Join-Path $RootPath "assets"
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

    if ($Level -ne "DEBUG") {
        switch ($Level) {
            "INFO" { Write-Host $LogMessage -ForegroundColor Cyan }
            "SUCCESS" { Write-Host $LogMessage -ForegroundColor Green }
            "WARN" { Write-Host $LogMessage -ForegroundColor Yellow }
            "ERROR" { Write-Host $LogMessage -ForegroundColor Red }
        }
    }

    # Salvar no arquivo de log
    $LogFile = Join-Path $ReportsPath "$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss')_raquel.log"
    $LogMessage | Out-File -FilePath $LogFile -Append -Encoding UTF8
}

# Classe para designs
class DesignResult {
    [string]$DesignName
    [string]$Status
    [string]$Type
    [string]$Style
    [array]$Files
    [datetime]$Timestamp

    DesignResult([string]$name, [string]$type, [string]$style) {
        $this.DesignName = $name
        $this.Status = "CREATED"
        $this.Type = $type
        $this.Style = $style
        $this.Files = @()
        $this.Timestamp = Get-Date
    }

    [void]AddFile([string]$filePath) {
        $this.Files += $filePath
    }
}

# FunÃ§Ã£o principal
function Invoke-Raquel {
    Write-Log "INFO" "=== RAQUEL - Iniciando criaÃ§Ã£o de design ==="
    Write-Log "INFO" "Projeto: $Project"
    Write-Log "INFO" "Tipo: $DesignType"
    Write-Log "INFO" "Estilo: $Style"

    $Results = @()

    # Criar design baseado no tipo
    switch ($DesignType.ToLower()) {
        "webpage" {
            $result = New-WebPageDesign
            $Results += $result
        }
        "component" {
            $result = New-ComponentDesign
            $Results += $result
        }
        "landing" {
            $result = New-LandingPageDesign
            $Results += $result
        }
        "dashboard" {
            $result = New-DashboardDesign
            $Results += $result
        }
        default {
            Write-Log "ERROR" "Tipo de design '$DesignType' nÃ£o suportado"
            exit 1
        }
    }

    # Exportar assets se solicitado
    if ($ExportAssets) {
        Write-Log "INFO" "Exportando assets..."
        Export-DesignAssets
    }

    # Gerar relatÃ³rio
    $Report = @{
        timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        project = $Project
        designType = $DesignType
        style = $Style
        results = $Results
    }

    $ReportPath = Join-Path $ReportsPath "$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss')_design_report.json"
    $Report | ConvertTo-Json -Depth 10 | Out-File -FilePath $ReportPath -Encoding UTF8

    Write-Log "INFO" "RelatÃ³rio salvo em: $ReportPath"
    Write-Log "INFO" "=== Design criado com sucesso! ==="

    return $Results
}

function New-WebPageDesign {
    Write-Log "INFO" "Criando pÃ¡gina web com estilo $Style..."

    $DesignName = "webpage_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    $result = [DesignResult]::new($DesignName, "webpage", $Style)

    # Criar HTML
    if ($Style.ToLower() -eq 'agency') {
        $HtmlContent = Get-AgencyWebPageTemplate
        $CssContent = Get-AgencyCSSTemplate
    } else {
        $HtmlContent = Get-ModernWebPageTemplate
        $CssContent = Get-ModernCSSTemplate
    }

    $HtmlPath = Join-Path $ProjectPath "$DesignName.html"
    $HtmlContent | Out-File -FilePath $HtmlPath -Encoding UTF8
    $result.AddFile($HtmlPath)

    # Criar CSS
    $CssPath = Join-Path $ProjectPath "$DesignName.css"
    $CssContent | Out-File -FilePath $CssPath -Encoding UTF8
    $result.AddFile($CssPath)

    # Criar JS se necessÃ¡rio
    if ($Interactive) {
        $JsContent = Get-InteractiveJSTemplate
        $JsPath = Join-Path $ProjectPath "$DesignName.js"
        $JsContent | Out-File -FilePath $JsPath -Encoding UTF8
        $result.AddFile($JsPath)
    }

    Write-Log "SUCCESS" "PÃ¡gina web criada: $HtmlPath"
    return $result
}

function New-ComponentDesign {
    Write-Log "INFO" "Criando componente com estilo $Style..."

    $DesignName = "component_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    $result = [DesignResult]::new($DesignName, "component", $Style)

    # Criar componente HTML/CSS/JS
    $ComponentContent = Get-ModernComponentTemplate
    $ComponentPath = Join-Path $ProjectPath "$DesignName.html"
    $ComponentContent | Out-File -FilePath $ComponentPath -Encoding UTF8
    $result.AddFile($ComponentPath)

    Write-Log "SUCCESS" "Componente criado: $ComponentPath"
    return $result
}

function New-LandingPageDesign {
    Write-Log "INFO" "Criando landing page com estilo $Style..."

    $DesignName = "landing_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    $result = [DesignResult]::new($DesignName, "landing", $Style)

    # Criar landing page completa
    $LandingContent = Get-LandingPageTemplate
    $LandingPath = Join-Path $ProjectPath "$DesignName.html"
    $LandingContent | Out-File -FilePath $LandingPath -Encoding UTF8
    $result.AddFile($LandingPath)

    Write-Log "SUCCESS" "Landing page criada: $LandingPath"
    return $result
}

function New-DashboardDesign {
    Write-Log "INFO" "Criando dashboard com estilo $Style..."

    $DesignName = "dashboard_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    $result = [DesignResult]::new($DesignName, "dashboard", $Style)

    # Criar dashboard
    $DashboardContent = Get-DashboardTemplate
    $DashboardPath = Join-Path $ProjectPath "$DesignName.html"
    $DashboardContent | Out-File -FilePath $DashboardPath -Encoding UTF8
    $result.AddFile($DashboardPath)

    Write-Log "SUCCESS" "Dashboard criado: $DashboardPath"
    return $result
}

function Export-DesignAssets {
    # Criar assets base
    $CssAssets = @"
:root {
    --primary-color: #667eea;
    --secondary-color: #764ba2;
    --accent-color: #f093fb;
    --text-color: #333;
    --bg-color: #f8f9fa;
    --card-bg: #ffffff;
    --shadow: 0 4px 6px rgba(0,0,0,0.1);
}

* {
    margin: 0;
    padding: 0;
    box-sizing: border-box;
}

body {
    font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
    line-height: 1.6;
    color: var(--text-color);
    background: var(--bg-color);
}
"@

    $AssetsCssPath = Join-Path $AssetsPath "design-system.css"
    $CssAssets | Out-File -FilePath $AssetsCssPath -Encoding UTF8

    Write-Log "SUCCESS" "Assets exportados para: $AssetsCssPath"
}

# Templates de design
function Get-ModernWebPageTemplate {
    return @"
<!DOCTYPE html>
<html lang="pt-BR">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>PÃ¡gina Moderna - Criada por Raquel</title>
    <link rel="stylesheet" href="design-system.css">
    <style>
        .hero {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 100px 20px;
            text-align: center;
        }

        .container {
            max-width: 1200px;
            margin: 0 auto;
            padding: 20px;
        }

        .card {
            background: white;
            border-radius: 15px;
            padding: 30px;
            margin: 20px 0;
            box-shadow: var(--shadow);
            transition: transform 0.3s ease;
        }

        .card:hover {
            transform: translateY(-5px);
        }

        .btn {
            background: var(--primary-color);
            color: white;
            padding: 12px 24px;
            border: none;
            border-radius: 25px;
            cursor: pointer;
            transition: all 0.3s ease;
        }

        .btn:hover {
            background: var(--secondary-color);
            transform: scale(1.05);
        }
    </style>
</head>
<body>
    <div class="hero">
        <div class="container">
            <h1>âœ¨ Design IncrÃ­vel</h1>
            <p>Criado com amor pela Raquel</p>
            <button class="btn" onclick="alert('OlÃ¡! Sou a Raquel, sua designer favorita! âœ¨')">Clique Aqui</button>
        </div>
    </div>

    <div class="container">
        <div class="card">
            <h2>ðŸŽ¨ Design Moderno</h2>
            <p>Esta pÃ¡gina foi criada usando as melhores prÃ¡ticas de design e desenvolvimento web.</p>
        </div>

        <div class="card">
            <h2>ðŸš€ Tecnologias Utilizadas</h2>
            <ul>
                <li>HTML5 SemÃ¢ntico</li>
                <li>CSS3 com VariÃ¡veis</li>
                <li>JavaScript Moderno</li>
                <li>Design Responsivo</li>
            </ul>
        </div>
    </div>

    <script>
        // AnimaÃ§Ãµes suaves
        document.addEventListener('DOMContentLoaded', function() {
            const cards = document.querySelectorAll('.card');
            cards.forEach((card, index) => {
                card.style.opacity = '0';
                card.style.transform = 'translateY(30px)';
                setTimeout(() => {
                    card.style.transition = 'all 0.6s ease';
                    card.style.opacity = '1';
                    card.style.transform = 'translateY(0)';
                }, index * 200);
            });
        });
    </script>
</body>
</html>
"@
}

function Get-ModernCSSTemplate {
    return @"
/* CSS Moderno - Criado por Raquel */
@import url('https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700&display=swap');

:root {
    --primary: #667eea;
    --secondary: #764ba2;
    --accent: #f093fb;
    --success: #4ecdc4;
    --warning: #ffd93d;
    --error: #ff6b6b;
    --text: #2d3748;
    --bg: #f7fafc;
    --card: #ffffff;
    --border: #e2e8f0;
    --shadow: 0 4px 6px rgba(0, 0, 0, 0.1);
    --shadow-lg: 0 10px 25px rgba(0, 0, 0, 0.15);
}

* {
    margin: 0;
    padding: 0;
    box-sizing: border-box;
}

body {
    font-family: 'Inter', sans-serif;
    background: var(--bg);
    color: var(--text);
    line-height: 1.6;
}

.container {
    max-width: 1200px;
    margin: 0 auto;
    padding: 0 20px;
}

/* Utilities */
.text-center { text-align: center; }
.text-left { text-align: left; }
.text-right { text-align: right; }

.mb-1 { margin-bottom: 0.25rem; }
.mb-2 { margin-bottom: 0.5rem; }
.mb-3 { margin-bottom: 1rem; }
.mb-4 { margin-bottom: 1.5rem; }
.mb-5 { margin-bottom: 3rem; }

.mt-1 { margin-top: 0.25rem; }
.mt-2 { margin-top: 0.5rem; }
.mt-3 { margin-top: 1rem; }
.mt-4 { margin-top: 1.5rem; }
.mt-5 { margin-top: 3rem; }

/* Buttons */
.btn {
    display: inline-block;
    padding: 12px 24px;
    border: none;
    border-radius: 8px;
    font-weight: 500;
    text-decoration: none;
    cursor: pointer;
    transition: all 0.3s ease;
    font-size: 16px;
}

.btn-primary {
    background: var(--primary);
    color: white;
}

.btn-primary:hover {
    background: var(--secondary);
    transform: translateY(-2px);
    box-shadow: var(--shadow-lg);
}

.btn-secondary {
    background: var(--secondary);
    color: white;
}

.btn-secondary:hover {
    background: var(--accent);
    transform: translateY(-2px);
    box-shadow: var(--shadow-lg);
}

/* Cards */
.card {
    background: var(--card);
    border-radius: 12px;
    padding: 24px;
    box-shadow: var(--shadow);
    border: 1px solid var(--border);
    transition: all 0.3s ease;
}

.card:hover {
    transform: translateY(-4px);
    box-shadow: var(--shadow-lg);
}

/* Grid */
.grid {
    display: grid;
    gap: 24px;
}

.grid-2 { grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); }
.grid-3 { grid-template-columns: repeat(auto-fit, minmax(250px, 1fr)); }
.grid-4 { grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); }

/* Responsive */
@media (max-width: 768px) {
    .container {
        padding: 0 16px;
    }

    .grid-2,
    .grid-3,
    .grid-4 {
        grid-template-columns: 1fr;
    }

    .btn {
        width: 100%;
        text-align: center;
    }
}
"@
}

function Get-AgencyCSSTemplate {
    return @"
/* CSS AgÃªncia - Criado por Raquel */
@import url('https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700;800&display=swap');

:root {
    --bg: #060714;
    --surface: rgba(255, 255, 255, 0.08);
    --surface-strong: rgba(255, 255, 255, 0.14);
    --border: rgba(255, 255, 255, 0.15);
    --text: #f5f6fb;
    --text-muted: rgba(245, 246, 251, 0.72);
    --accent: #ffcb2d;
    --accent-secondary: #6bd8ff;
    --shadow: 0 24px 80px rgba(0, 0, 0, 0.35);
    --radius: 28px;
}

* {
    margin: 0;
    padding: 0;
    box-sizing: border-box;
}

body {
    font-family: 'Inter', sans-serif;
    background: radial-gradient(circle at top left, rgba(108, 216, 255, 0.12), transparent 30%),
                radial-gradient(circle at bottom right, rgba(255, 203, 45, 0.14), transparent 26%),
                var(--bg);
    color: var(--text);
    min-height: 100vh;
    line-height: 1.6;
}

.container {
    width: min(1160px, 100% - 40px);
    margin: 0 auto;
}

.section {
    padding: 80px 0;
}

.hero {
    display: grid;
    grid-template-columns: minmax(0, 1.1fr) minmax(320px, 0.9fr);
    gap: 40px;
    align-items: center;
    min-height: 90vh;
}

.hero-copy h1 {
    font-size: clamp(3.4rem, 5vw, 5.8rem);
    line-height: 0.98;
    letter-spacing: -0.06em;
    max-width: 720px;
}

.hero-copy p {
    margin: 24px 0 0;
    max-width: 620px;
    color: var(--text-muted);
    font-size: 1.05rem;
}

.hero-actions {
    display: flex;
    flex-wrap: wrap;
    gap: 18px;
    margin-top: 38px;
}

.btn-primary {
    background: linear-gradient(135deg, #ffcb2d 0%, #ffd36a 100%);
    color: #0f1121;
    padding: 18px 30px;
    border-radius: 999px;
    font-weight: 700;
    box-shadow: 0 18px 50px rgba(255, 203, 45, 0.24);
}

.btn-secondary {
    background: transparent;
    border: 1px solid rgba(255,255,255,0.18);
    color: var(--text);
}

.hero-visual {
    position: relative;
    min-height: 420px;
    background: linear-gradient(160deg, rgba(255,255,255,0.06), rgba(255,255,255,0.03));
    border-radius: 36px;
    border: 1px solid rgba(255,255,255,0.12);
    backdrop-filter: blur(16px);
    box-shadow: var(--shadow);
    overflow: hidden;
}

.hero-visual::before {
    content: '';
    position: absolute;
    inset: 0;
    background: radial-gradient(circle at 20% 30%, rgba(255,203,45,0.30), transparent 18%),
                radial-gradient(circle at 80% 20%, rgba(107,216,255,0.22), transparent 20%);
    pointer-events: none;
}

.stats-grid {
    display: grid;
    grid-template-columns: repeat(3, minmax(0, 1fr));
    gap: 18px;
    margin-top: 24px;
}

.stat-card {
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: 22px;
    padding: 24px;
    box-shadow: 0 18px 40px rgba(0, 0, 0, 0.18);
}

.stat-card h3 {
    margin-bottom: 12px;
    color: var(--accent);
    font-size: 1rem;
    text-transform: uppercase;
    letter-spacing: 0.18em;
}

.stat-card p {
    font-size: 1.9rem;
    font-weight: 800;
}

.services-grid {
    display: grid;
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: 24px;
}

.service-card {
    background: var(--surface-strong);
    border: 1px solid rgba(255,255,255,0.12);
    border-radius: 30px;
    padding: 32px;
    transition: transform 0.3s ease;
}

.service-card:hover {
    transform: translateY(-8px);
}

.service-card h4 {
    margin-bottom: 14px;
    font-size: 1.25rem;
}

.service-card p {
    color: var(--text-muted);
    line-height: 1.7;
}

.highlight-box {
    background: rgba(255,255,255,0.06);
    border: 1px solid rgba(255,255,255,0.14);
    border-radius: 28px;
    padding: 30px;
    margin-top: 32px;
}

.highlight-box h3 {
    margin-bottom: 14px;
}

.highlight-box p {
    color: var(--text-muted);
}

@media (max-width: 980px) {
    .hero {
        grid-template-columns: 1fr;
    }

    .stats-grid,
    .services-grid {
        grid-template-columns: 1fr;
    }
}

@media (max-width: 640px) {
    .section {
        padding: 60px 0;
    }

    .hero-copy h1 {
        font-size: 2.7rem;
    }

    .hero-actions {
        flex-direction: column;
    }
}
"@
}

function Get-AgencyWebPageTemplate {
    return @"
<!DOCTYPE html>
<html lang="pt-BR">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Propaganda Cidade Audio - AgÃªncia de Ãudio PublicitÃ¡rio</title>
    <link rel="stylesheet" href="design-system.css">
    <style>
        .hero {
            display: grid;
            grid-template-columns: minmax(0, 1.1fr) minmax(320px, 0.9fr);
            gap: 40px;
            align-items: center;
            min-height: 90vh;
        }

        .hero-copy h1 {
            font-size: clamp(3.4rem, 5vw, 5.8rem);
            line-height: 0.98;
            max-width: 720px;
        }

        .hero-copy p {
            margin-top: 22px;
            color: rgba(245, 246, 251, 0.78);
            max-width: 640px;
            font-size: 1.05rem;
        }

        .hero-actions {
            display: flex;
            flex-wrap: wrap;
            gap: 16px;
            margin-top: 34px;
        }

        .hero-visual {
            position: relative;
            min-height: 440px;
            border-radius: 36px;
            background: linear-gradient(180deg, rgba(255,255,255,0.08), rgba(255,255,255,0.02));
            border: 1px solid rgba(255,255,255,0.12);
            box-shadow: 0 35px 90px rgba(0, 0, 0, 0.28);
            overflow: hidden;
        }

        .hero-visual::before {
            content: '';
            position: absolute;
            inset: 0;
            background: radial-gradient(circle at 22% 28%, rgba(255, 203, 45, 0.24), transparent 18%),
                        radial-gradient(circle at 82% 18%, rgba(107, 216, 255, 0.18), transparent 20%);
            pointer-events: none;
        }

        .hero-visual .badge {
            position: absolute;
            top: 28px;
            left: 28px;
            padding: 14px 20px;
            background: rgba(255,255,255,0.14);
            border-radius: 999px;
            color: #f9f9fb;
            font-weight: 700;
            letter-spacing: 0.08em;
            text-transform: uppercase;
        }

        .stats-grid {
            display: grid;
            grid-template-columns: repeat(3, minmax(0, 1fr));
            gap: 20px;
            margin-top: 34px;
        }

        .section-title {
            margin-bottom: 24px;
            font-size: 1rem;
            text-transform: uppercase;
            letter-spacing: 0.22em;
            color: rgba(255,255,255,0.65);
        }

        .section-header h2 {
            font-size: clamp(2.6rem, 4vw, 3.4rem);
            line-height: 1.05;
            max-width: 640px;
        }

        .service-card {
            background: rgba(255,255,255,0.06);
            border: 1px solid rgba(255,255,255,0.12);
            border-radius: 28px;
            padding: 30px;
            transition: transform 0.3s ease;
        }

        .service-card:hover {
            transform: translateY(-6px);
        }

        .service-card h4 {
            margin-bottom: 14px;
        }

        .service-card p {
            color: rgba(245, 246, 251, 0.75);
            line-height: 1.75;
        }

        .highlight-grid {
            display: grid;
            grid-template-columns: 1.25fr 0.85fr;
            gap: 28px;
            margin-top: 40px;
        }

        .highlight-box {
            background: rgba(255,255,255,0.08);
            border: 1px solid rgba(255,255,255,0.14);
            border-radius: 32px;
            padding: 36px;
        }

        .highlight-box p {
            color: rgba(245, 246, 251, 0.78);
            line-height: 1.8;
        }

        .badge-pill {
            display: inline-flex;
            align-items: center;
            gap: 10px;
            padding: 12px 18px;
            border-radius: 999px;
            background: rgba(255,255,255,0.12);
            color: #f8f9fa;
            font-weight: 700;
        }

        .grid-2 {
            display: grid;
            grid-template-columns: repeat(2, minmax(0, 1fr));
            gap: 20px;
        }

        @media (max-width: 980px) {
            .hero,
            .highlight-grid,
            .stats-grid,
            .grid-2 {
                grid-template-columns: 1fr;
            }
        }

        @media (max-width: 680px) {
            .hero {
                gap: 28px;
            }

            .hero-copy h1 {
                font-size: 2.8rem;
            }

            .hero-actions {
                flex-direction: column;
            }
        }
    </style>
</head>
<body>
    <div class="container">
        <section class="section hero">
            <div class="hero-copy">
                <span class="section-title">Ãudio para publicidade</span>
                <h1>Ãudio publicitÃ¡rio com impacto, memÃ³ria e personalidade.</h1>
                <p>Crie campanhas sonoras que emocionam, vendem e permanecem na cabeÃ§a do pÃºblico. Spots, chamadas, espera telefÃ´nica e Ã¡udio institucional com voz profissional e produÃ§Ã£o premium.</p>
                <div class="hero-actions">
                    <a href="#contato" class="btn btn-primary">Solicitar orÃ§amento</a>
                    <a href="#servicos" class="btn btn-secondary">Ver serviÃ§os</a>
                </div>
                <div class="stats-grid">
                    <div class="stat-card">
                        <h3>Vozes Profissionais</h3>
                        <p>+100</p>
                    </div>
                    <div class="stat-card">
                        <h3>ProduÃ§Ãµes mensais</h3>
                        <p>85+</p>
                    </div>
                    <div class="stat-card">
                        <h3>Resultados Comerciais</h3>
                        <p>Impacto real</p>
                    </div>
                </div>
            </div>
            <div class="hero-visual">
                <div class="badge">Estilo Envato Agency</div>
            </div>
        </section>

        <section class="section" id="servicos">
            <div class="section-header">
                <span class="section-title">O que fazemos</span>
                <h2>Produzimos Ã¡udio para publicidade, varejo e atendimento.</h2>
            </div>
            <div class="grid-2">
                <div class="service-card">
                    <h4>Spots de rÃ¡dio</h4>
                    <p>CriaÃ§Ã£o de roteiros e produÃ§Ã£o sonora para campanhas de rÃ¡dio com impacto e conversÃ£o.</p>
                </div>
                <div class="service-card">
                    <h4>Chamadas para loja</h4>
                    <p>Ãudio direcionado para PDV, instore e campanhas de promoÃ§Ã£o no ponto de venda.</p>
                </div>
                <div class="service-card">
                    <h4>Espera telefÃ´nica</h4>
                    <p>Ãudio de espera profissional que informam, entretÃªm e fortalecem a marca.</p>
                </div>
                <div class="service-card">
                    <h4>Ãudio institucional</h4>
                    <p>PeÃ§as de branding sonoro para apresentaÃ§Ã£o de marca, vÃ­deos e comunicaÃ§Ã£o interna.</p>
                </div>
            </div>
        </section>

        <section class="section">
            <div class="highlight-grid">
                <div class="highlight-box">
                    <span class="section-title">Por que escolher</span>
                    <h2>Design de Ã¡udio pensado para resultados comerciais.</h2>
                    <p>Transformamos mensagens em experiÃªncias memorÃ¡veis. Nossa abordagem une criatividade publicitÃ¡ria com tÃ©cnica de estÃºdio profissional, para gerar resultados reais em campanhas e atendimento.</p>
                    <div class="badge-pill">Ãudio EstratÃ©gico</div>
                </div>
                <div class="highlight-box">
                    <span class="section-title">Diferenciais</span>
                    <div class="grid-2">
                        <div class="service-card">
                            <h4>ProduÃ§Ã£o Ã¡gil</h4>
                            <p>Processo rÃ¡pido desde o briefing atÃ© a entrega final.</p>
                        </div>
                        <div class="service-card">
                            <h4>Vozes profissionais</h4>
                            <p>LocuÃ§Ã£o de alta qualidade para cada perfil de campanha.</p>
                        </div>
                    </div>
                </div>
            </div>
        </section>
    </div>
</body>
</html>
"@
}

function Get-InteractiveJSTemplate {
    return @"
// JavaScript Interativo - Criado por Raquel
class RaquelUI {
    constructor() {
        this.init();
    }

    init() {
        this.setupEventListeners();
        this.animateOnScroll();
        this.setupThemeToggle();
    }

    setupEventListeners() {
        // BotÃµes animados
        const buttons = document.querySelectorAll('.btn');
        buttons.forEach(btn => {
            btn.addEventListener('click', this.handleButtonClick.bind(this));
        });

        // Cards interativos
        const cards = document.querySelectorAll('.card');
        cards.forEach(card => {
            card.addEventListener('mouseenter', this.handleCardHover.bind(this));
            card.addEventListener('mouseleave', this.handleCardLeave.bind(this));
        });
    }

    handleButtonClick(e) {
        const button = e.target;
        button.style.transform = 'scale(0.95)';

        setTimeout(() => {
            button.style.transform = 'scale(1)';
        }, 150);

        // Efeito de ripple
        this.createRipple(e);
    }

    handleCardHover(e) {
        const card = e.target.closest('.card');
        card.style.transform = 'translateY(-8px) rotate(1deg)';
    }

    handleCardLeave(e) {
        const card = e.target.closest('.card');
        card.style.transform = 'translateY(0) rotate(0deg)';
    }

    createRipple(e) {
        const button = e.target;
        const circle = document.createElement('span');
        const diameter = Math.max(button.clientWidth, button.clientHeight);
        const radius = diameter / 2;

        circle.style.width = circle.style.height = `${diameter}px`;
        circle.style.left = `${e.clientX - button.offsetLeft - radius}px`;
        circle.style.top = `${e.clientY - button.offsetTop - radius}px`;
        circle.classList.add('ripple');

        const ripple = button.getElementsByClassName('ripple')[0];
        if (ripple) {
            ripple.remove();
        }

        button.appendChild(circle);
    }

    animateOnScroll() {
        const observerOptions = {
            threshold: 0.1,
            rootMargin: '0px 0px -50px 0px'
        };

        const observer = new IntersectionObserver((entries) => {
            entries.forEach(entry => {
                if (entry.isIntersecting) {
                    entry.target.style.opacity = '1';
                    entry.target.style.transform = 'translateY(0)';
                }
            });
        }, observerOptions);

        // Observar elementos
        const animateElements = document.querySelectorAll('.card, .btn');
        animateElements.forEach(el => {
            el.style.opacity = '0';
            el.style.transform = 'translateY(30px)';
            el.style.transition = 'all 0.6s ease';
            observer.observe(el);
        });
    }

    setupThemeToggle() {
        // Toggle de tema (claro/escuro)
        const themeToggle = document.createElement('button');
        themeToggle.innerHTML = 'ðŸŒ“';
        themeToggle.className = 'theme-toggle';
        themeToggle.style.cssText = `
            position: fixed;
            top: 20px;
            right: 20px;
            background: var(--primary);
            color: white;
            border: none;
            border-radius: 50%;
            width: 50px;
            height: 50px;
            cursor: pointer;
            font-size: 20px;
            z-index: 1000;
            box-shadow: var(--shadow);
        `;

        document.body.appendChild(themeToggle);

        themeToggle.addEventListener('click', () => {
            document.body.classList.toggle('dark-theme');
            themeToggle.innerHTML = document.body.classList.contains('dark-theme') ? 'â˜€ï¸' : 'ðŸŒ“';
        });
    }
}

// Inicializar quando DOM estiver pronto
document.addEventListener('DOMContentLoaded', () => {
    new RaquelUI();
});

// Easter egg
console.log('ðŸŽ¨ OlÃ¡! Sou a Raquel, sua designer favorita!');
console.log('ðŸ’« Criando designs incrÃ­veis desde 2026!');
"@
}

function Get-ModernComponentTemplate {
    return @"
<!-- Componente Moderno - Criado por Raquel -->
<div class="modern-component">
    <div class="component-header">
        <h3>ðŸŽ¨ Componente Raquel</h3>
        <p>Design moderno e funcional</p>
    </div>

    <div class="component-body">
        <div class="feature-grid">
            <div class="feature-item">
                <div class="feature-icon">âœ¨</div>
                <h4>Moderno</h4>
                <p>Design atual e elegante</p>
            </div>
            <div class="feature-item">
                <div class="feature-icon">ðŸš€</div>
                <h4>RÃ¡pido</h4>
                <p>Performance otimizada</p>
            </div>
            <div class="feature-item">
                <div class="feature-icon">ðŸ“±</div>
                <h4>Responsivo</h4>
                <p>Funciona em todos os dispositivos</p>
            </div>
        </div>
    </div>
</div>

<style>
.modern-component {
    background: white;
    border-radius: 16px;
    padding: 24px;
    box-shadow: 0 8px 32px rgba(0,0,0,0.1);
    border: 1px solid #e5e7eb;
}

.component-header h3 {
    color: #1f2937;
    margin-bottom: 8px;
}

.component-header p {
    color: #6b7280;
}

.feature-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
    gap: 16px;
    margin-top: 20px;
}

.feature-item {
    text-align: center;
    padding: 16px;
    background: #f9fafb;
    border-radius: 12px;
    transition: transform 0.3s ease;
}

.feature-item:hover {
    transform: translateY(-4px);
}

.feature-icon {
    font-size: 2rem;
    margin-bottom: 8px;
}

.feature-item h4 {
    color: #1f2937;
    margin-bottom: 4px;
}

.feature-item p {
    color: #6b7280;
    font-size: 0.9rem;
}
</style>
"@
}

function Get-LandingPageTemplate {
    return @"
<!DOCTYPE html>
<html lang="pt-BR">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Landing Page IncrÃ­vel - Raquel Design</title>
    <link rel="stylesheet" href="design-system.css">
</head>
<body>
    <!-- Header -->
    <header class="hero">
        <nav class="navbar">
            <div class="container">
                <div class="logo">ðŸŽ¨ Raquel Design</div>
                <ul class="nav-links">
                    <li><a href="#home">Home</a></li>
                    <li><a href="#about">Sobre</a></li>
                    <li><a href="#services">ServiÃ§os</a></li>
                    <li><a href="#contact">Contato</a></li>
                </ul>
            </div>
        </nav>

        <div class="hero-content">
            <h1>Design que Encanta</h1>
            <p>Criando experiÃªncias visuais incrÃ­veis que conquistam seus usuÃ¡rios</p>
            <div class="hero-buttons">
                <a href="#contact" class="btn btn-primary">ComeÃ§ar Agora</a>
                <a href="#about" class="btn btn-secondary">Saiba Mais</a>
            </div>
        </div>
    </header>

    <!-- About Section -->
    <section id="about" class="section">
        <div class="container">
            <div class="section-header">
                <h2>Sobre a Raquel</h2>
                <p>Sua designer especializada em criar pÃ¡ginas HTML, CSS e JS incrÃ­veis</p>
            </div>

            <div class="grid grid-3">
                <div class="card">
                    <div class="card-icon">ðŸŽ¯</div>
                    <h3>Foco no UsuÃ¡rio</h3>
                    <p>Design centrado nas necessidades e experiÃªncia do usuÃ¡rio</p>
                </div>
                <div class="card">
                    <div class="card-icon">âš¡</div>
                    <h3>Performance</h3>
                    <p>CÃ³digos otimizados para carregamento rÃ¡pido</p>
                </div>
                <div class="card">
                    <div class="card-icon">ðŸ“±</div>
                    <h3>Responsivo</h3>
                    <p>Funciona perfeitamente em desktop, tablet e mobile</p>
                </div>
            </div>
        </div>
    </section>

    <!-- Services Section -->
    <section id="services" class="section section-alt">
        <div class="container">
            <div class="section-header">
                <h2>Nossos ServiÃ§os</h2>
                <p>SoluÃ§Ãµes completas de design e desenvolvimento</p>
            </div>

            <div class="grid grid-2">
                <div class="service-card">
                    <h3>ðŸŽ¨ Design de Interfaces</h3>
                    <p>CriaÃ§Ã£o de interfaces modernas e intuitivas</p>
                    <ul>
                        <li>Wireframes e ProtÃ³tipos</li>
                        <li>Design System</li>
                        <li>UI/UX Design</li>
                    </ul>
                </div>
                <div class="service-card">
                    <h3>ðŸ’» Desenvolvimento Frontend</h3>
                    <p>CodificaÃ§Ã£o de designs em HTML, CSS e JavaScript</p>
                    <ul>
                        <li>PÃ¡ginas Web</li>
                        <li>Componentes Interativos</li>
                        <li>AplicaÃ§Ãµes Web</li>
                    </ul>
                </div>
            </div>
        </div>
    </section>

    <!-- Contact Section -->
    <section id="contact" class="section">
        <div class="container">
            <div class="section-header">
                <h2>Vamos Conversar?</h2>
                <p>Entre em contato para criar algo incrÃ­vel juntos</p>
            </div>

            <div class="contact-form">
                <form>
                    <div class="form-group">
                        <input type="text" placeholder="Seu Nome" required>
                    </div>
                    <div class="form-group">
                        <input type="email" placeholder="Seu Email" required>
                    </div>
                    <div class="form-group">
                        <textarea placeholder="Conte-me sobre seu projeto..." rows="5" required></textarea>
                    </div>
                    <button type="submit" class="btn btn-primary">Enviar Mensagem</button>
                </form>
            </div>
        </div>
    </section>

    <!-- Footer -->
    <footer class="footer">
        <div class="container">
            <p>&copy; 2026 Raquel Design. Criando experiÃªncias incrÃ­veis.</p>
        </div>
    </footer>
</body>
</html>
"@
}

function Get-DashboardTemplate {
    return @"
<!DOCTYPE html>
<html lang="pt-BR">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Dashboard Raquel - Design IncrÃ­vel</title>
    <link rel="stylesheet" href="design-system.css">
</head>
<body>
    <div class="dashboard">
        <!-- Sidebar -->
        <aside class="sidebar">
            <div class="sidebar-header">
                <h2>ðŸŽ¨ Raquel</h2>
                <p>Dashboard Design</p>
            </div>

            <nav class="sidebar-nav">
                <a href="#" class="nav-item active">
                    <span class="nav-icon">ðŸ“Š</span>
                    Dashboard
                </a>
                <a href="#" class="nav-item">
                    <span class="nav-icon">ðŸŽ¯</span>
                    Projetos
                </a>
                <a href="#" class="nav-item">
                    <span class="nav-icon">ðŸ‘¥</span>
                    Clientes
                </a>
                <a href="#" class="nav-item">
                    <span class="nav-icon">âš™ï¸</span>
                    ConfiguraÃ§Ãµes
                </a>
            </nav>
        </aside>

        <!-- Main Content -->
        <main class="main-content">
            <header class="dashboard-header">
                <h1>Bem-vindo ao Dashboard Raquel</h1>
                <div class="user-info">
                    <span>OlÃ¡, Designer!</span>
                    <div class="user-avatar">ðŸ‘©â€ðŸŽ¨</div>
                </div>
            </header>

            <!-- Stats Cards -->
            <div class="stats-grid">
                <div class="stat-card">
                    <div class="stat-icon">ðŸŽ¨</div>
                    <div class="stat-content">
                        <h3>47</h3>
                        <p>Designs Criados</p>
                    </div>
                </div>
                <div class="stat-card">
                    <div class="stat-icon">ðŸš€</div>
                    <div class="stat-content">
                        <h3>23</h3>
                        <p>Projetos Ativos</p>
                    </div>
                </div>
                <div class="stat-card">
                    <div class="stat-icon">ðŸ’Ž</div>
                    <div class="stat-content">
                        <h3>156</h3>
                        <p>Clientes Satisfeitos</p>
                    </div>
                </div>
                <div class="stat-card">
                    <div class="stat-icon">â­</div>
                    <div class="stat-content">
                        <h3>4.9</h3>
                        <p>AvaliaÃ§Ã£o MÃ©dia</p>
                    </div>
                </div>
            </div>

            <!-- Charts Section -->
            <div class="charts-section">
                <div class="chart-card">
                    <h3>Performance Mensal</h3>
                    <div class="chart-placeholder">
                        <div class="chart-bar" style="height: 80%"></div>
                        <div class="chart-bar" style="height: 65%"></div>
                        <div class="chart-bar" style="height: 90%"></div>
                        <div class="chart-bar" style="height: 75%"></div>
                        <div class="chart-bar" style="height: 85%"></div>
                        <div class="chart-bar" style="height: 95%"></div>
                    </div>
                </div>

                <div class="chart-card">
                    <h3>Projetos por Categoria</h3>
                    <div class="pie-chart">
                        <div class="pie-segment web" style="background: #667eea">Web</div>
                        <div class="pie-segment mobile" style="background: #764ba2">Mobile</div>
                        <div class="pie-segment desktop" style="background: #f093fb">Desktop</div>
                    </div>
                </div>
            </div>

            <!-- Recent Projects -->
            <div class="projects-section">
                <h3>Projetos Recentes</h3>
                <div class="projects-list">
                    <div class="project-item">
                        <div class="project-icon">ðŸŒŸ</div>
                        <div class="project-info">
                            <h4>Landing Page E-commerce</h4>
                            <p>Design moderno para loja online</p>
                        </div>
                        <span class="project-status completed">ConcluÃ­do</span>
                    </div>
                    <div class="project-item">
                        <div class="project-icon">ðŸ“±</div>
                        <div class="project-info">
                            <h4>App Mobile UI</h4>
                            <p>Interface para aplicativo iOS/Android</p>
                        </div>
                        <span class="project-status in-progress">Em Andamento</span>
                    </div>
                    <div class="project-item">
                        <div class="project-icon">ðŸŽ¨</div>
                        <div class="project-info">
                            <h4>Brand Identity</h4>
                            <p>Identidade visual completa</p>
                        </div>
                        <span class="project-status review">Em RevisÃ£o</span>
                    </div>
                </div>
            </div>
        </main>
    </div>
</body>
</html>
"@
}

# Executar Raquel
if (Get-Command Update-AgentHeartbeat -ErrorAction SilentlyContinue) {
    Update-AgentHeartbeat -AgentName "Raquel" -TaskId "TASK-DESIGN-$Project" -Task "Design $DesignType ($Style) para $Project" -Status "in_progress" -Note "Raquel runner iniciado" | Out-Null
}

$result = Invoke-Raquel

if (Get-Command Register-AgentAction -ErrorAction SilentlyContinue) {
    $statusValues = @($result | ForEach-Object { $_.Status })
    $outcome = if ($statusValues -contains "CREATED") { "success" } else { "failed" }
    $complexity = if ($Interactive -or $ExportAssets) { "high" } else { "medium" }
    $g = Register-AgentAction -AgentName "Raquel" -Task "Design $DesignType ($Style) para $Project" -Category "design" -Complexity $complexity -Outcome $outcome -Badges @("Design Moderno")
    Write-Log "INFO" "Gamificacao: Raquel ganhou $($g.pointsAwarded) pontos"
}

if (Get-Command Update-AgentHeartbeat -ErrorAction SilentlyContinue) {
    $heartbeatStatus = if ($result.Status -eq "CREATED") { "done" } else { "failed" }
    Update-AgentHeartbeat -AgentName "Raquel" -TaskId "TASK-DESIGN-$Project" -Task "Design $DesignType ($Style) para $Project" -Status $heartbeatStatus -Outcome $result.Status -Note "Raquel runner finalizado" | Out-Null
}


# Sair com cÃ³digo apropriado
if ($result.Status -eq "CREATED") {
    exit 0
} else {
    exit 1
}
