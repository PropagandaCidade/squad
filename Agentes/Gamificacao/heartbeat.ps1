# Heartbeat and memory sync for SQUAD agents
# Persists runtime status and keeps memory-enterprise working sets/profile scaffolding in sync.

$HeartbeatScriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$HeartbeatAgentsRoot = Split-Path -Parent $HeartbeatScriptPath
$HeartbeatProjectRoot = Split-Path -Parent $HeartbeatAgentsRoot
$HeartbeatMemoryRoot = Join-Path $HeartbeatProjectRoot "memory-enterprise"
$HeartbeatAgentMemoryRoot = Join-Path $HeartbeatMemoryRoot "60_AGENT_MEMORY"
$HeartbeatWorkingSetsRoot = Join-Path $HeartbeatAgentMemoryRoot "working_sets"
$HeartbeatProfilesRoot = Join-Path $HeartbeatAgentMemoryRoot "profiles"
$HeartbeatRuntimeRoot = Join-Path $HeartbeatAgentMemoryRoot "runtime"
$HeartbeatRegistryFile = Join-Path $HeartbeatRuntimeRoot "agents-registry.json"
$HeartbeatStoreFile = Join-Path $HeartbeatRuntimeRoot "agent-heartbeats.json"

function ConvertTo-HeartbeatUtcIso {
    return (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
}

function ConvertTo-HeartbeatSlug {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text
    )

    $slug = $Text.ToLowerInvariant()
    $slug = [regex]::Replace($slug, "[^a-z0-9]+", "-")
    $slug = $slug.Trim("-")
    if ([string]::IsNullOrWhiteSpace($slug)) {
        return "agent"
    }
    return $slug
}

function Ensure-HeartbeatDirectory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Write-HeartbeatJsonFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        $Data
    )

    $dir = Split-Path -Parent $Path
    Ensure-HeartbeatDirectory -Path $dir

    $json = $Data | ConvertTo-Json -Depth 30
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)

    $lastError = $null
    for ($attempt = 1; $attempt -le 8; $attempt++) {
        try {
            [System.IO.File]::WriteAllText($Path, $json, $utf8NoBom)
            return
        } catch {
            $lastError = $_
            Start-Sleep -Milliseconds (70 * $attempt)
        }
    }

    throw "Falha ao salvar heartbeat em '$Path': $($lastError.Exception.Message)"
}

function Read-HeartbeatJsonFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        $Fallback
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return $Fallback
    }

    try {
        return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    } catch {
        return $Fallback
    }
}

function Escape-YamlQuoted {
    param(
        [Parameter(Mandatory = $false)]
        [string]$Text = ""
    )

    $safe = $Text -replace "\\", "\\\\"
    $safe = $safe -replace '"', '\"'
    return $safe
}

function Read-YamlBulletValues {
    param(
        [Parameter(Mandatory = $false)]
        [string]$Content = "",

        [Parameter(Mandatory = $true)]
        [string]$Section
    )

    $lines = $Content -split "`r?`n"
    $values = @()
    $inSection = $false

    foreach ($line in $lines) {
        $trimmed = $line.Trim()
        if (-not $inSection -and $trimmed -eq "${Section}:") {
            $inSection = $true
            continue
        }

        if (-not $inSection) { continue }

        if ($trimmed -match "^[a-zA-Z0-9_]+:" -and -not $trimmed.StartsWith("- ")) {
            break
        }

        if ($trimmed -match "^- (.+)$") {
            $item = $Matches[1].Trim().Trim('"').Trim("'")
            if (-not [string]::IsNullOrWhiteSpace($item)) {
                $values += $item
            }
        }
    }

    return @($values)
}

function Format-YamlList {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $false)]
        [string[]]$Values = @()
    )

    if (-not $Values -or $Values.Count -eq 0) {
        return @("${Name}: []")
    }

    $lines = @("${Name}:")
    foreach ($value in $Values) {
        $safe = Escape-YamlQuoted -Text ([string]$value)
        $lines += "  - ""$safe"""
    }
    return $lines
}

function Get-AgentConfigSpecialty {
    param(
        [Parameter(Mandatory = $true)]
        [string]$AgentDir
    )

    $configPath = Join-Path $AgentDir "config\agent-config.json"
    if (-not (Test-Path -LiteralPath $configPath)) {
        return "specialist"
    }

    try {
        $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
        $specialty = [string]$config.agent.specialty
        if ([string]::IsNullOrWhiteSpace($specialty)) {
            return "specialist"
        }
        return $specialty
    } catch {
        return "specialist"
    }
}

function Ensure-AgentProfileFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$AgentName,

        [Parameter(Mandatory = $true)]
        [string]$Slug,

        [Parameter(Mandatory = $true)]
        [string]$Specialty
    )

    Ensure-HeartbeatDirectory -Path $HeartbeatProfilesRoot
    $profilePath = Join-Path $HeartbeatProfilesRoot "$Slug.yaml"
    if (Test-Path -LiteralPath $profilePath) {
        return $profilePath
    }

    $specialtySafe = Escape-YamlQuoted -Text $Specialty
    $content = @(
        "agent_name: $Slug"
        "role: $specialtySafe"
        "owned_areas: []"
        "known_constraints: []"
        "decision_rights: []"
        "handoff_requirements:"
        "  - ""Update working set and session log"""
    ) -join [Environment]::NewLine

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($profilePath, $content + [Environment]::NewLine, $utf8NoBom)
    return $profilePath
}

function Ensure-AgentWorkingSetFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$AgentName,

        [Parameter(Mandatory = $true)]
        [string]$Slug
    )

    Ensure-HeartbeatDirectory -Path $HeartbeatWorkingSetsRoot
    $workingSetPath = Join-Path $HeartbeatWorkingSetsRoot "$Slug.yaml"
    if (Test-Path -LiteralPath $workingSetPath) {
        return $workingSetPath
    }

    $now = ConvertTo-HeartbeatUtcIso
    $content = @(
        "updated_at: $now"
        "agent_name: $Slug"
        "status: idle"
        'current_task_id: ""'
        'current_task: ""'
        "active_task_ids: []"
        "short_term_context:"
        "  - ""Working set initialized"""
        "pending_questions: []"
        "next_3_actions: []"
    ) -join [Environment]::NewLine

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($workingSetPath, $content + [Environment]::NewLine, $utf8NoBom)
    return $workingSetPath
}

function Get-AgentDirectoryEntries {
    $agentDirs = Get-ChildItem -LiteralPath $HeartbeatAgentsRoot -Directory | Where-Object { $_.Name -ne "Gamificacao" }
    $rows = @()
    foreach ($dir in $agentDirs) {
        $agentName = $dir.Name
        $slug = ConvertTo-HeartbeatSlug -Text $agentName
        $specialty = Get-AgentConfigSpecialty -AgentDir $dir.FullName
        $rows += [ordered]@{
            name = $agentName
            slug = $slug
            specialty = $specialty
            working_set = "memory-enterprise/60_AGENT_MEMORY/working_sets/$slug.yaml"
            profile = "memory-enterprise/60_AGENT_MEMORY/profiles/$slug.yaml"
        }
    }

    $virtualAgents = @(
        [ordered]@{ name = "assistant"; slug = "assistant"; specialty = "coordinator" },
        [ordered]@{ name = "volta"; slug = "volta"; specialty = "strategy" },
        [ordered]@{ name = "bohr"; slug = "bohr"; specialty = "quality" },
        [ordered]@{ name = "halley"; slug = "halley"; specialty = "performance" }
    )

    foreach ($virtual in $virtualAgents) {
        $existing = $rows | Where-Object { $_.slug -eq $virtual.slug } | Select-Object -First 1
        if ($null -ne $existing) { continue }
        $rows += [ordered]@{
            name = $virtual.name
            slug = $virtual.slug
            specialty = $virtual.specialty
            working_set = "memory-enterprise/60_AGENT_MEMORY/working_sets/$($virtual.slug).yaml"
            profile = "memory-enterprise/60_AGENT_MEMORY/profiles/$($virtual.slug).yaml"
        }
    }

    return $rows | Sort-Object -Property slug
}

function Sync-AgentRegistry {
    param(
        [Parameter(Mandatory = $false)]
        [switch]$EnsureMemoryFiles
    )

    Ensure-HeartbeatDirectory -Path $HeartbeatRuntimeRoot
    $entries = Get-AgentDirectoryEntries

    if ($EnsureMemoryFiles) {
        foreach ($entry in $entries) {
            Ensure-AgentProfileFile -AgentName $entry.name -Slug $entry.slug -Specialty $entry.specialty | Out-Null
            Ensure-AgentWorkingSetFile -AgentName $entry.name -Slug $entry.slug | Out-Null
        }
    }

    $registry = [ordered]@{
        generated_at = ConvertTo-HeartbeatUtcIso
        agents = @($entries)
    }
    Write-HeartbeatJsonFile -Path $HeartbeatRegistryFile -Data $registry
    return $registry
}

function Get-HeartbeatStore {
    Ensure-HeartbeatDirectory -Path $HeartbeatRuntimeRoot
    $fallback = [ordered]@{
        generated_at = ConvertTo-HeartbeatUtcIso
        agents = [ordered]@{}
    }
    $data = Read-HeartbeatJsonFile -Path $HeartbeatStoreFile -Fallback $fallback
    $normalizedAgents = [ordered]@{}
    if ($null -ne $data.agents) {
        if ($data.agents -is [System.Collections.IDictionary]) {
            foreach ($key in $data.agents.Keys) {
                $normalizedAgents[[string]$key] = $data.agents[$key]
            }
        } else {
            foreach ($prop in $data.agents.PSObject.Properties) {
                $normalizedAgents[[string]$prop.Name] = $prop.Value
            }
        }
    }
    $data.agents = $normalizedAgents
    return $data
}

function Save-HeartbeatStore {
    param(
        [Parameter(Mandatory = $true)]
        $Data
    )

    $Data.generated_at = ConvertTo-HeartbeatUtcIso
    Write-HeartbeatJsonFile -Path $HeartbeatStoreFile -Data $Data
}

function Ensure-HeartbeatAgentEntry {
    param(
        [Parameter(Mandatory = $true)]
        $Store,

        [Parameter(Mandatory = $true)]
        [string]$AgentName
    )

    $slug = ConvertTo-HeartbeatSlug -Text $AgentName
    $keys = @($Store.agents.Keys | ForEach-Object { [string]$_ })
    if (-not ($keys -contains $slug)) {
        $Store.agents[$slug] = [ordered]@{
            name = $AgentName
            slug = $slug
            status = "idle"
            updated_at = ConvertTo-HeartbeatUtcIso
            started_at = ""
            current_task_id = ""
            current_task = ""
            active_task_ids = @()
            last_outcome = ""
            note = ""
            run_count = 0
            history = @()
        }
    }
    return $Store.agents[$slug]
}

function Save-WorkingSetSnapshot {
    param(
        [Parameter(Mandatory = $true)]
        [string]$AgentName,

        [Parameter(Mandatory = $true)]
        [string]$Slug,

        [Parameter(Mandatory = $true)]
        $Entry
    )

    $workingSetPath = Ensure-AgentWorkingSetFile -AgentName $AgentName -Slug $Slug
    $current = ""
    if (Test-Path -LiteralPath $workingSetPath) {
        $current = Get-Content -LiteralPath $workingSetPath -Raw
    }

    $shortTerm = Read-YamlBulletValues -Content $current -Section "short_term_context"
    $pending = Read-YamlBulletValues -Content $current -Section "pending_questions"
    $nextActions = Read-YamlBulletValues -Content $current -Section "next_3_actions"

    $inject = @()
    if (-not [string]::IsNullOrWhiteSpace([string]$Entry.current_task)) {
        $inject += "Current task: $([string]$Entry.current_task)"
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$Entry.note)) {
        $inject += "Note: $([string]$Entry.note)"
    }

    $shortTerm = @($inject + $shortTerm | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique | Select-Object -First 4)

    $lines = @()
    $lines += "updated_at: $([string]$Entry.updated_at)"
    $lines += "agent_name: $Slug"
    $lines += "status: $([string]$Entry.status)"
    $lines += "current_task_id: ""$(Escape-YamlQuoted -Text ([string]$Entry.current_task_id))"""
    $lines += "current_task: ""$(Escape-YamlQuoted -Text ([string]$Entry.current_task))"""

    $activeTasks = @()
    foreach ($id in @($Entry.active_task_ids)) {
        $text = [string]$id
        if (-not [string]::IsNullOrWhiteSpace($text)) {
            $activeTasks += $text
        }
    }

    $lines += @(Format-YamlList -Name "active_task_ids" -Values $activeTasks)
    $lines += @(Format-YamlList -Name "short_term_context" -Values $shortTerm)
    $lines += @(Format-YamlList -Name "pending_questions" -Values $pending)
    $lines += @(Format-YamlList -Name "next_3_actions" -Values $nextActions)

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($workingSetPath, ($lines -join [Environment]::NewLine) + [Environment]::NewLine, $utf8NoBom)
}

function Update-AgentHeartbeat {
    param(
        [Parameter(Mandatory = $true)]
        [string]$AgentName,

        [Parameter(Mandatory = $false)]
        [string]$TaskId = "",

        [Parameter(Mandatory = $false)]
        [string]$Task = "",

        [Parameter(Mandatory = $false)]
        [ValidateSet("in_progress", "done", "idle", "blocked", "failed", "cancelled")]
        [string]$Status = "in_progress",

        [Parameter(Mandatory = $false)]
        [string]$Outcome = "",

        [Parameter(Mandatory = $false)]
        [string]$Note = ""
    )

    $registry = Sync-AgentRegistry -EnsureMemoryFiles
    $slug = ConvertTo-HeartbeatSlug -Text $AgentName
    $registryEntry = $registry.agents | Where-Object { $_.slug -eq $slug } | Select-Object -First 1

    if ($null -eq $registryEntry) {
        $registryEntry = [ordered]@{
            name = $AgentName
            slug = $slug
            specialty = "specialist"
            working_set = "memory-enterprise/60_AGENT_MEMORY/working_sets/$slug.yaml"
            profile = "memory-enterprise/60_AGENT_MEMORY/profiles/$slug.yaml"
        }
    }

    $store = Get-HeartbeatStore
    $entry = Ensure-HeartbeatAgentEntry -Store $store -AgentName $registryEntry.name
    $now = ConvertTo-HeartbeatUtcIso

    $taskIdSafe = [string]$TaskId
    $taskSafe = [string]$Task
    $statusSafe = [string]$Status
    $outcomeSafe = [string]$Outcome
    $noteSafe = [string]$Note

    if ($statusSafe -eq "in_progress") {
        if ([string]::IsNullOrWhiteSpace([string]$entry.started_at)) {
            $entry.started_at = $now
        }
        $entry.run_count = [int]$entry.run_count + 1
    }

    $active = @()
    foreach ($id in @($entry.active_task_ids)) {
        $txt = [string]$id
        if (-not [string]::IsNullOrWhiteSpace($txt)) { $active += $txt }
    }

    if (-not [string]::IsNullOrWhiteSpace($taskIdSafe)) {
        if ($statusSafe -eq "in_progress") {
            if (-not ($active -contains $taskIdSafe)) { $active += $taskIdSafe }
        } else {
            $active = @($active | Where-Object { $_ -ne $taskIdSafe })
        }
    }

    if ($statusSafe -eq "in_progress") {
        if (-not [string]::IsNullOrWhiteSpace($taskIdSafe)) { $entry.current_task_id = $taskIdSafe }
        if (-not [string]::IsNullOrWhiteSpace($taskSafe)) { $entry.current_task = $taskSafe }
    } elseif ($statusSafe -in @("done", "idle", "blocked", "failed", "cancelled")) {
        if (-not [string]::IsNullOrWhiteSpace($taskIdSafe) -and $entry.current_task_id -eq $taskIdSafe) {
            $entry.current_task_id = ""
        }
        if ($statusSafe -eq "idle" -or $statusSafe -eq "done") {
            if ([string]::IsNullOrWhiteSpace($taskIdSafe) -or $entry.current_task_id -eq "") {
                $entry.current_task = ""
            }
        }
    }

    $entry.status = $statusSafe
    $entry.active_task_ids = @($active | Select-Object -Unique)
    $entry.updated_at = $now
    if (-not [string]::IsNullOrWhiteSpace($outcomeSafe)) { $entry.last_outcome = $outcomeSafe }
    if (-not [string]::IsNullOrWhiteSpace($noteSafe)) { $entry.note = $noteSafe }

    $history = @()
    foreach ($item in @($entry.history)) {
        if ($null -ne $item) { $history += $item }
    }
    $history += [ordered]@{
        at = $now
        status = $statusSafe
        task_id = $taskIdSafe
        task = $taskSafe
        outcome = $outcomeSafe
        note = $noteSafe
    }
    if ($history.Count -gt 50) {
        $history = @($history | Select-Object -Last 50)
    }
    $entry.history = $history

    Save-HeartbeatStore -Data $store
    Save-WorkingSetSnapshot -AgentName $registryEntry.name -Slug $registryEntry.slug -Entry $entry

    return [pscustomobject]@{
        agent = $registryEntry.name
        slug = $registryEntry.slug
        status = $entry.status
        taskId = $entry.current_task_id
        updatedAt = $entry.updated_at
        activeTasks = @($entry.active_task_ids)
    }
}

# Keep runtime artifacts fresh when imported.
Sync-AgentRegistry -EnsureMemoryFiles | Out-Null
if (-not (Test-Path -LiteralPath $HeartbeatStoreFile)) {
    Save-HeartbeatStore -Data ([ordered]@{
        generated_at = ConvertTo-HeartbeatUtcIso
        agents = [ordered]@{}
    })
}
