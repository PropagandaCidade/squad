$ErrorActionPreference = "Stop"

$tests = @(
    "registry-integrity.ps1",
    "heartbeat-runtime-smoke.ps1",
    "register-task-heartbeat.ps1",
    "runner-heartbeat-smoke.ps1"
)

$passed = 0
foreach ($test in $tests) {
    $path = Join-Path $PSScriptRoot $test
    Write-Host ("[TEST] {0}" -f $test) -ForegroundColor Cyan
    & powershell -NoProfile -ExecutionPolicy Bypass -File $path
    $passed++
}

Write-Host ("ALL TESTS PASSED: {0}/{1}" -f $passed, $tests.Count) -ForegroundColor Green
