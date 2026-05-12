$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot

function Assert-FileContains($Path, $Pattern) {
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Missing expected file: $Path"
    }
    $content = Get-Content -Raw -LiteralPath $Path
    if ($content -notmatch $Pattern) {
        throw "Expected '$Path' to contain pattern '$Pattern'"
    }
}

Assert-FileContains (Join-Path $root '.gitignore') 'native/streambox_core/target/'
Assert-FileContains (Join-Path $root 'scripts/build-windows-core.ps1') 'streambox_core\.dll'
Assert-FileContains (Join-Path $root 'scripts/build-windows-core.ps1') 'cargo build'
Assert-FileContains (Join-Path $root 'scripts/build-android-core.ps1') 'aarch64-linux-android'
Assert-FileContains (Join-Path $root 'scripts/build-android-core.ps1') 'x86_64-linux-android'
Assert-FileContains (Join-Path $root 'scripts/build-android-core.ps1') 'jniLibs'

Write-Host 'Native packaging script checks passed.'
