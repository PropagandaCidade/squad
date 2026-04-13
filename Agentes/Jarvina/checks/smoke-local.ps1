[CmdletBinding()]
param(
    [string]$BaseUrl = "http://127.0.0.1:8094",
    [string]$JarvinaPath = "/Agentes/Jarvina",
    [switch]$AllowStaticPhp
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$script:PassCount = 0
$script:FailCount = 0
$script:Failures = New-Object System.Collections.Generic.List[string]

function Write-Pass {
    param([string]$Message)
    $script:PassCount += 1
    Write-Host "[PASS] $Message" -ForegroundColor Green
}

function Write-Fail {
    param([string]$Message)
    $script:FailCount += 1
    $script:Failures.Add($Message) | Out-Null
    Write-Host "[FAIL] $Message" -ForegroundColor Red
}

function Write-Warn {
    param([string]$Message)
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Join-Url {
    param(
        [string]$Base,
        [string]$Path
    )

    $cleanBase = $Base.TrimEnd("/")
    if ($Path.StartsWith("/")) {
        return "$cleanBase$Path"
    }
    return "$cleanBase/$Path"
}

function Invoke-Get {
    param([string]$Url)

    try {
        $invokeParams = @{
            Method = "Get"
            Uri = $Url
            TimeoutSec = 20
            ErrorAction = "Stop"
        }

        if ($PSVersionTable.PSVersion.Major -lt 6) {
            $invokeParams.UseBasicParsing = $true
        }

        $response = Invoke-WebRequest @invokeParams
        $contentText = ""
        if ($response.Content -is [byte[]]) {
            $contentText = [System.Text.Encoding]::UTF8.GetString($response.Content)
        } else {
            $contentText = [string]$response.Content
        }

        return @{
            Success = $true
            StatusCode = [int]$response.StatusCode
            Content = $contentText
            Error = $null
        }
    } catch {
        $statusCode = $null
        $errorMessage = $_.Exception.Message

        try {
            $hasResponseProp = $null -ne $_.Exception.PSObject.Properties["Response"]
            if ($hasResponseProp -and $_.Exception.Response) {
                $hasStatusCodeProp = $null -ne $_.Exception.Response.PSObject.Properties["StatusCode"]
                if ($hasStatusCodeProp -and $_.Exception.Response.StatusCode) {
                    $statusCode = [int]$_.Exception.Response.StatusCode
                }
            }
        } catch {
            $statusCode = $null
            if (-not $errorMessage) {
                $errorMessage = $_.Exception.Message
            }
        }

        return @{
            Success = $false
            StatusCode = $statusCode
            Content = ""
            Error = $errorMessage
        }
    }
}

function Assert-Status200 {
    param(
        [string]$Name,
        [string]$Url
    )

    $result = Invoke-Get -Url $Url
    if ($result.StatusCode -eq 200) {
        Write-Pass "$Name returned HTTP 200 ($Url)"
    } else {
        $detail = if ($result.StatusCode) { "HTTP $($result.StatusCode)" } else { "no status" }
        Write-Fail "$Name did not return HTTP 200 ($detail) ($Url). Error: $($result.Error)"
    }

    return $result
}

function Assert-StatusIn {
    param(
        [string]$Name,
        [string]$Url,
        [int[]]$AllowedStatus
    )

    $result = Invoke-Get -Url $Url
    if ($AllowedStatus -contains [int]$result.StatusCode) {
        Write-Pass "$Name returned allowed HTTP $($result.StatusCode) ($Url)"
    } else {
        $allowed = ($AllowedStatus | ForEach-Object { $_.ToString() }) -join ","
        $detail = if ($result.StatusCode) { "HTTP $($result.StatusCode)" } else { "no status" }
        Write-Fail "$Name returned $detail, expected one of [$allowed] ($Url). Error: $($result.Error)"
    }

    return $result
}

function Assert-Contains {
    param(
        [string]$Name,
        [string]$Haystack,
        [string[]]$Needles
    )

    foreach ($needle in $Needles) {
        if ($Haystack.Contains($needle)) {
            Write-Pass "$Name contains '$needle'"
        } else {
            Write-Fail "$Name is missing '$needle'"
        }
    }
}

function Assert-PhpExecuted {
    param(
        [string]$Name,
        [string]$Content
    )

    if (-not $Content) { return }

    $requirePhpExecution = -not $AllowStaticPhp

    if ($Content -match '<\?php') {
        if ($requirePhpExecution) {
            Write-Fail "$Name appears to be served as static text (PHP not executed)."
        } else {
            Write-Warn "$Name appears static (PHP not executed), but AllowStaticPhp is enabled."
        }
    } else {
        Write-Pass "$Name is being rendered by PHP runtime."
    }
}

Write-Host "Jarvina local smoke check"
Write-Host "BaseUrl: $BaseUrl"
Write-Host "JarvinaPath: $JarvinaPath"
Write-Host ("Started: " + (Get-Date -Format "yyyy-MM-dd HH:mm:ss"))
Write-Host ""

$indexUrl = Join-Url -Base $BaseUrl -Path "$JarvinaPath/templates/index.php"
$jarvinaUrl = Join-Url -Base $BaseUrl -Path "$JarvinaPath/jarvina.php"
$mainJsUrl = Join-Url -Base $BaseUrl -Path "$JarvinaPath/templates/main.js"
$mediaJsUrl = Join-Url -Base $BaseUrl -Path "$JarvinaPath/templates/media-handler.js"
$geminiJsUrl = Join-Url -Base $BaseUrl -Path "$JarvinaPath/templates/gemini-client.js"
$pcmJsUrl = Join-Url -Base $BaseUrl -Path "$JarvinaPath/templates/pcm-processor.js"

$jarvinaResult = Assert-StatusIn -Name "jarvina.php" -Url $jarvinaUrl -AllowedStatus @(200, 302, 401, 403)
$indexResult = Assert-StatusIn -Name "index.php (auth gate)" -Url $indexUrl -AllowedStatus @(200, 302, 401, 403)
Assert-Status200 -Name "main.js" -Url $mainJsUrl | Out-Null
Assert-Status200 -Name "media-handler.js" -Url $mediaJsUrl | Out-Null
Assert-Status200 -Name "gemini-client.js" -Url $geminiJsUrl | Out-Null
Assert-Status200 -Name "pcm-processor.js" -Url $pcmJsUrl | Out-Null

if ($jarvinaResult.StatusCode -eq 200 -and $jarvinaResult.Content) {
    Assert-PhpExecuted -Name "jarvina.php" -Content $jarvinaResult.Content
    Assert-Contains -Name "jarvina.php" -Haystack $jarvinaResult.Content -Needles @(
        '<iframe',
        'templates/index.php',
        'Voltar ao Admin'
    )

    if ($jarvinaResult.Content -match 'admin_token=') {
        Write-Fail "jarvina.php still exposes admin_token in iframe URL"
    } else {
        Write-Pass "jarvina.php does not expose admin_token in iframe URL"
    }
}

if ($indexResult.StatusCode -eq 200 -and $indexResult.Content) {
    Assert-PhpExecuted -Name "index.php" -Content $indexResult.Content
    Assert-Contains -Name "index.php" -Haystack $indexResult.Content -Needles @(
        'id="live-btn"',
        'id="status-text"',
        'id="vu-fill"',
        'window.JARVINA_CONFIG',
        'media-handler.js?v=',
        'gemini-client.js',
        'main.js'
    )

    if ($indexResult.Content -match 'admin_token=' -or $indexResult.Content -match '[?&]admin_token') {
        Write-Fail "index.php leaks admin_token in URL/query"
    } else {
        Write-Pass "index.php does not leak admin_token in query"
    }
} elseif ($indexResult.StatusCode -in @(302, 401, 403)) {
    Write-Pass "index.php auth gate active without admin session"
}

$mainJsResult = Invoke-Get -Url $mainJsUrl
if ($mainJsResult.StatusCode -eq 200 -and $mainJsResult.Content) {
    Assert-Contains -Name "main.js" -Haystack $mainJsResult.Content -Needles @(
        'RAILWAY_WS_URL',
        'client.connect',
        'window.JARVINA_CONFIG?.adminToken',
        'audio/pcm;rate=${'
    )

    if ($mainJsResult.Content -match 'admin_token' -and $mainJsResult.Content -match 'URLSearchParams') {
        Write-Fail "main.js still reads admin_token from query string"
    } else {
        Write-Pass "main.js no longer depends on admin_token query string"
    }
}

$geminiJsResult = Invoke-Get -Url $geminiJsUrl
if ($geminiJsResult.StatusCode -eq 200 -and $geminiJsResult.Content) {
    Assert-Contains -Name "gemini-client.js" -Haystack $geminiJsResult.Content -Needles @(
        'new WebSocket',
        'sendRealtimeChunk',
        'sendEndOfTurn'
    )
}

Write-Host ""
Write-Host "Summary: $($script:PassCount) passed, $($script:FailCount) failed."

if ($script:FailCount -gt 0) {
    Write-Host "Failures:"
    foreach ($failure in $script:Failures) {
        Write-Host "- $failure"
    }
    exit 1
}

exit 0
