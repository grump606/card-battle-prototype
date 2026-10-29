# Full validation: import, headless tests, main-scene smoke load.
# Engine: $env:GODOT, else the repo-local Godot_v4.7.2-stable_win64.exe console binary.
# Optional: $env:CHECK_TESTS_SCRIPT overrides the test script (used to prove the failure path).
$root = Split-Path -Parent $PSScriptRoot
$local = Join-Path $root 'Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe'
$godot = if ($env:GODOT) { $env:GODOT } else { $local }
if (-not (Test-Path -LiteralPath $godot -PathType Leaf)) {
    Write-Host "CHECK FAILED: Godot not found at '$godot'. Set the GODOT env var to the Godot 4.7 console executable, or place it at '$local'."
    exit 2
}
$testScript = if ($env:CHECK_TESTS_SCRIPT) { $env:CHECK_TESTS_SCRIPT } else { 'res://tests/run_tests.gd' }
$errPattern = 'SCRIPT ERROR|Parse Error|ERROR: Failed to load'

function Invoke-Step([string]$name, [string[]]$engineArgs) {
    Write-Host "== $name =="
    $out = & $godot @engineArgs 2>&1 | ForEach-Object { "$_" }
    $code = $LASTEXITCODE
    $out | ForEach-Object { Write-Host $_ }
    if ($code -ne 0) { Write-Host "CHECK FAILED: $name (exit code $code)"; exit 1 }
    if ($out -match $errPattern) { Write-Host "CHECK FAILED: $name (script errors in output)"; exit 1 }
}

Push-Location $root
try {
    Invoke-Step 'import' @('--headless', '--path', '.', '--import')
    Invoke-Step 'tests' @('--headless', '--path', '.', '-s', $testScript)
    Invoke-Step 'smoke' @('--headless', '--path', '.', '-s', 'res://tests/smoke_main.gd')
} finally { Pop-Location }
Write-Host 'CHECK PASSED'
exit 0
