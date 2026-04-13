# Sistema de Gamificacao para Agentes
# Versao: 2.0.0
# Canonico: Agentes/agents-scores.json

$ScriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootPath = Split-Path -Parent $ScriptPath
$DataFile = Join-Path $RootPath "agents-scores.json"
$LegacyDataFile = Join-Path $RootPath "Gamificacao\agents-scores.json"
$LiveScoreJsFile = Join-Path $RootPath "agents-scores-live.js"
$MaxTaskTextLength = 240
$MaxBadgeTextLength = 80
$MaxTasksPerAgent = 300

function Normalize-GamificationText {
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [string]$Text = "",

        [Parameter(Mandatory = $false)]
        [int]$MaxLength = 120,

        [Parameter(Mandatory = $false)]
        [string]$Fallback = ""
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $Fallback
    }

    $normalized = $Text -replace "[`r`n`t]+", " "
    $normalized = [regex]::Replace($normalized, "\s{2,}", " ").Trim()

    if ([string]::IsNullOrWhiteSpace($normalized)) {
        return $Fallback
    }

    if ($MaxLength -gt 0 -and $normalized.Length -gt $MaxLength) {
        return ($normalized.Substring(0, $MaxLength).TrimEnd() + "...")
    }

    return $normalized
}

function Sanitize-AgentEntry {
    param(
        [Parameter(Mandatory = $true)]
        $Entry
    )

    if ($null -eq $Entry.badges) { $Entry.badges = @() }
    if ($null -eq $Entry.tasks) { $Entry.tasks = @() }
    if ($null -eq $Entry.points) { $Entry.points = 0 }
    if ([string]::IsNullOrWhiteSpace([string]$Entry.level)) { $Entry.level = "Novato" }
    if ([string]::IsNullOrWhiteSpace([string]$Entry.lastUpdated)) { $Entry.lastUpdated = (Get-Date -Format "yyyy-MM-dd HH:mm:ss") }

    $safeBadges = @()
    foreach ($badge in @($Entry.badges)) {
        $safeBadge = Normalize-GamificationText -Text ([string]$badge) -MaxLength $MaxBadgeTextLength -Fallback ""
        if (-not [string]::IsNullOrWhiteSpace($safeBadge)) {
            $safeBadges += $safeBadge
        }
    }
    $Entry.badges = @($safeBadges | Select-Object -Unique)

    $safeTasks = @()
    foreach ($taskItem in @($Entry.tasks)) {
        if ($null -eq $taskItem) { continue }

        $timestamp = [string]$taskItem.timestamp
        if ([string]::IsNullOrWhiteSpace($timestamp)) {
            $timestamp = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        }

        $safeTask = Normalize-GamificationText -Text ([string]$taskItem.task) -MaxLength $MaxTaskTextLength -Fallback "Registro sanitizado"
        $pointsValue = 0
        try { $pointsValue = [int]$taskItem.points } catch { $pointsValue = 0 }

        $safeTasks += [ordered]@{
            timestamp = $timestamp
            task = $safeTask
            points = $pointsValue
        }
    }

    if ($safeTasks.Count -gt $MaxTasksPerAgent) {
        $safeTasks = @($safeTasks | Select-Object -Last $MaxTasksPerAgent)
    }
    $Entry.tasks = $safeTasks

    $Entry.points = [Math]::Max(0, [int]$Entry.points)
    $Entry.level = Normalize-GamificationText -Text ([string]$Entry.level) -MaxLength 40 -Fallback "Novato"
    $Entry.lastUpdated = Normalize-GamificationText -Text ([string]$Entry.lastUpdated) -MaxLength 40 -Fallback (Get-Date -Format "yyyy-MM-dd HH:mm:ss")

    return $Entry
}

function New-DefaultGamificationData {
    return [ordered]@{
        agents = @{}
        levels = @(
            [ordered]@{ minPoints = 0; name = "Novato" },
            [ordered]@{ minPoints = 100; name = "Especialista" },
            [ordered]@{ minPoints = 250; name = "Veterano" },
            [ordered]@{ minPoints = 500; name = "Lenda" }
        )
    }
}

function Write-GamificationFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        $Data
    )

    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $json = $Data | ConvertTo-Json -Depth 20
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)

    $lastError = $null
    for ($attempt = 1; $attempt -le 6; $attempt++) {
        try {
            [System.IO.File]::WriteAllText($Path, $json, $utf8NoBom)
            return
        } catch {
            $lastError = $_
            Start-Sleep -Milliseconds (100 * $attempt)
        }
    }

    throw "Falha ao salvar arquivo de gamificacao em '$Path': $($lastError.Exception.Message)"
}

function Write-LiveScoreScript {
    param(
        [Parameter(Mandatory = $true)]
        $Data
    )

    $payload = [ordered]@{
        generatedAt = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        agents = $Data.agents
    }

    $json = $payload | ConvertTo-Json -Depth 20
    $content = @(
        "// Arquivo gerado automaticamente por Agentes/Gamificacao/gamification.ps1"
        "// Nao editar manualmente."
        "window.SQUAD_AGENT_SCORES = $json;"
    ) -join [Environment]::NewLine

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $lastError = $null
    for ($attempt = 1; $attempt -le 6; $attempt++) {
        try {
            [System.IO.File]::WriteAllText($LiveScoreJsFile, $content, $utf8NoBom)
            return
        } catch {
            $lastError = $_
            Start-Sleep -Milliseconds (100 * $attempt)
        }
    }

    throw "Falha ao salvar arquivo JS de placar em '$LiveScoreJsFile': $($lastError.Exception.Message)"
}

function Initialize-GamificationData {
    if (Test-Path -LiteralPath $DataFile) {
        try {
            $current = Get-Content -LiteralPath $DataFile -Raw | ConvertFrom-Json
            Write-LiveScoreScript -Data $current
            return
        } catch {
            # arquivo corrompido: segue para migracao/default
        }
    }

    if (Test-Path -LiteralPath $LegacyDataFile) {
        try {
            $legacy = Get-Content -LiteralPath $LegacyDataFile -Raw | ConvertFrom-Json
            Write-GamificationFile -Path $DataFile -Data $legacy
            Write-LiveScoreScript -Data $legacy
            return
        } catch {
            # legado invalido: segue para default
        }
    }

    $default = New-DefaultGamificationData
    Write-GamificationFile -Path $DataFile -Data $default
    Write-GamificationFile -Path $LegacyDataFile -Data $default
    Write-LiveScoreScript -Data $default
}

function Get-GamificationData {
    Initialize-GamificationData
    return Get-Content -LiteralPath $DataFile -Raw | ConvertFrom-Json
}

function Save-GamificationData {
    param(
        [Parameter(Mandatory = $true)]
        $Data
    )

    Write-GamificationFile -Path $DataFile -Data $Data
    # Mantem compatibilidade com scripts antigos que ainda leem o arquivo legado.
    Write-GamificationFile -Path $LegacyDataFile -Data $Data
    Write-LiveScoreScript -Data $Data
}

function Ensure-AgentEntry {
    param(
        [Parameter(Mandatory = $true)]
        $Data,

        [Parameter(Mandatory = $true)]
        [string]$AgentName
    )

    $agentNames = @($Data.agents.PSObject.Properties.Name)
    if (-not ($agentNames -contains $AgentName)) {
        $Data.agents | Add-Member -MemberType NoteProperty -Name $AgentName -Value ([ordered]@{
            points = 0
            level = "Novato"
            badges = @()
            tasks = @()
            lastUpdated = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        })
    }

    $entry = $Data.agents.$AgentName
    $entry = Sanitize-AgentEntry -Entry $entry

    return $Data
}

function Get-AgentEntry {
    param(
        [Parameter(Mandatory = $true)]
        [string]$AgentName
    )

    $data = Get-GamificationData
    $data = Ensure-AgentEntry -Data $data -AgentName $AgentName
    Save-GamificationData -Data $data
    return $data
}

function Get-AgentLevel {
    param(
        [Parameter(Mandatory = $true)]
        [int]$Points,

        [Parameter(Mandatory = $false)]
        $Data = $null
    )

    if ($null -eq $Data) { $Data = Get-GamificationData }

    $levels = @($Data.levels | Sort-Object -Property @{Expression = { [int]$_.minPoints }})
    $selected = $levels | Where-Object { [int]$_.minPoints -le $Points } | Select-Object -Last 1
    if ($selected) { return [string]$selected.name }
    return "Novato"
}

function Get-LevelMinPoints {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LevelName,

        [Parameter(Mandatory = $false)]
        $Data = $null
    )

    if ($null -eq $Data) { $Data = Get-GamificationData }
    $match = $Data.levels | Where-Object { [string]$_.name -eq $LevelName } | Select-Object -First 1
    if ($match) { return [int]$match.minPoints }
    return 0
}

function Add-AgentPoints {
    param(
        [Parameter(Mandatory = $true)]
        [string]$AgentName,

        [Parameter(Mandatory = $true)]
        [int]$Points,

        [Parameter(Mandatory = $false)]
        [string[]]$Badges = @(),

        [Parameter(Mandatory = $false)]
        [string]$Task = "",

        [Parameter(Mandatory = $false)]
        [string]$Timestamp = ""
    )

    if ([string]::IsNullOrWhiteSpace($Timestamp)) {
        $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    }
    $Timestamp = Normalize-GamificationText -Text $Timestamp -MaxLength 40 -Fallback (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    $Task = Normalize-GamificationText -Text $Task -MaxLength $MaxTaskTextLength -Fallback ""
    $Badges = @(
        $Badges |
            ForEach-Object { Normalize-GamificationText -Text ([string]$_) -MaxLength $MaxBadgeTextLength -Fallback "" } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Select-Object -Unique
    )

    $data = Get-GamificationData
    $data = Ensure-AgentEntry -Data $data -AgentName $AgentName
    $entry = $data.agents.$AgentName
    $oldLevel = [string]$entry.level

    $entry.points = [int]$entry.points + [int]$Points
    if ($entry.points -lt 0) { $entry.points = 0 }
    $computedLevel = Get-AgentLevel -Points ([int]$entry.points) -Data $data
    $oldLevelMin = Get-LevelMinPoints -LevelName $oldLevel -Data $data
    $newLevelMin = Get-LevelMinPoints -LevelName $computedLevel -Data $data

    if ($newLevelMin -lt $oldLevelMin) {
        # Dados legados podem estar inconsistentes; nunca faz downgrade automatico.
        $entry.level = $oldLevel
    } else {
        $entry.level = $computedLevel
    }

    if (-not [string]::IsNullOrWhiteSpace($Task)) {
        $entry.tasks += [ordered]@{
            timestamp = $Timestamp
            task = $Task
            points = [int]$Points
        }
    }
    if (@($entry.tasks).Count -gt $MaxTasksPerAgent) {
        $entry.tasks = @($entry.tasks | Select-Object -Last $MaxTasksPerAgent)
    }

    foreach ($badge in $Badges) {
        if (-not [string]::IsNullOrWhiteSpace($badge)) {
            if (-not ($entry.badges -contains $badge)) {
                $entry.badges += $badge
            }
        }
    }

    if ((Get-LevelMinPoints -LevelName $entry.level -Data $data) -gt $oldLevelMin) {
        $levelBadge = "Level Up: $($entry.level)"
        if (-not ($entry.badges -contains $levelBadge)) {
            $entry.badges += $levelBadge
        }
    }

    $entry.lastUpdated = $Timestamp
    Save-GamificationData -Data $data

    return [pscustomobject]@{
        agent = $AgentName
        pointsAwarded = [int]$Points
        totalPoints = [int]$entry.points
        level = [string]$entry.level
        task = $Task
        timestamp = $Timestamp
    }
}

function Register-AgentAction {
    param(
        [Parameter(Mandatory = $true)]
        [string]$AgentName,

        [Parameter(Mandatory = $true)]
        [string]$Task,

        [Parameter(Mandatory = $false)]
        [string]$Category = "execution",

        [Parameter(Mandatory = $false)]
        [string]$Complexity = "medium",

        [Parameter(Mandatory = $false)]
        [string]$Outcome = "success",

        [Parameter(Mandatory = $false)]
        [string[]]$Badges = @(),

        [Parameter(Mandatory = $false)]
        [Nullable[int]]$PointsOverride = $null
    )

    $categoryTable = @{
        "execution" = 10
        "validation" = 12
        "triage" = 15
        "bug_fix" = 20
        "hotfix" = 25
        "qa_regression" = 12
        "design" = 18
        "ux" = 14
        "ai" = 16
        "documentation" = 8
        "coordination" = 8
        "review" = 10
        "audio_production" = 14
    }

    $complexityTable = @{
        "low" = 0.8
        "medium" = 1.0
        "high" = 1.3
        "critical" = 1.6
    }

    $outcomeTable = @{
        "success" = 1.0
        "partial" = 0.6
        "blocked" = 0.3
        "failed" = 0.2
    }

    $categoryKey = $Category.ToLower()
    $complexityKey = $Complexity.ToLower()
    $outcomeKey = $Outcome.ToLower()

    if (-not $categoryTable.ContainsKey($categoryKey)) { $categoryKey = "execution" }
    if (-not $complexityTable.ContainsKey($complexityKey)) { $complexityKey = "medium" }
    if (-not $outcomeTable.ContainsKey($outcomeKey)) { $outcomeKey = "success" }

    if ($PointsOverride.HasValue) {
        $points = [int]$PointsOverride.Value
    } else {
        $base = [double]$categoryTable[$categoryKey]
        $complexityMul = [double]$complexityTable[$complexityKey]
        $outcomeMul = [double]$outcomeTable[$outcomeKey]
        $points = [Math]::Max(1, [int][Math]::Round($base * $complexityMul * $outcomeMul))
    }

    $autoBadges = @()
    switch ($categoryKey) {
        "hotfix" { if ($outcomeKey -eq "success") { $autoBadges += "Hotfix Hero" } }
        "triage" { if ($outcomeKey -eq "success") { $autoBadges += "Radar de Bugs" } }
        "validation" { if ($outcomeKey -eq "success") { $autoBadges += "Guardiao da Qualidade" } }
        "qa_regression" { if ($outcomeKey -eq "success") { $autoBadges += "QA em Acao" } }
        "ux" { if ($outcomeKey -eq "success") { $autoBadges += "UX Visionario" } }
        "ai" { if ($outcomeKey -eq "success") { $autoBadges += "AI Strategist" } }
        "design" { if ($outcomeKey -eq "success") { $autoBadges += "Design Moderno" } }
    }

    if ($complexityKey -eq "critical") { $autoBadges += "Missao Critica" }
    if ($Task -match "Studio Master") { $autoBadges += "Forca Studio Master" }
    if ($points -ge 25) { $autoBadges += "Entrega de Impacto" }

    $allBadges = @($Badges + $autoBadges | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
    return Add-AgentPoints -AgentName $AgentName -Points $points -Task $Task -Badges $allBadges
}

function Get-AgentScore {
    param(
        [Parameter(Mandatory = $true)]
        [string]$AgentName
    )

    $data = Get-GamificationData
    $agentNames = @($data.agents.PSObject.Properties.Name)
    if ($agentNames -contains $AgentName) {
        return $data.agents.$AgentName
    }
    return $null
}

function Add-AgentBadge {
    param(
        [Parameter(Mandatory = $true)]
        [string]$AgentName,

        [Parameter(Mandatory = $true)]
        [string]$Badge
    )

    $data = Get-GamificationData
    $data = Ensure-AgentEntry -Data $data -AgentName $AgentName
    $entry = $data.agents.$AgentName

    if (-not ($entry.badges -contains $Badge)) {
        $entry.badges += $Badge
        $entry.lastUpdated = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        Save-GamificationData -Data $data
    }

    return $entry
}

function Get-Leaderboard {
    param(
        [Parameter(Mandatory = $false)]
        [int]$Top = 10
    )

    $data = Get-GamificationData
    $rows = foreach ($name in $data.agents.PSObject.Properties.Name) {
        $entry = $data.agents.$name
        [pscustomobject]@{
            name = $name
            points = [int]$entry.points
            level = [string]$entry.level
            lastUpdated = [string]$entry.lastUpdated
        }
    }

    return $rows | Sort-Object -Property points -Descending | Select-Object -First $Top
}
