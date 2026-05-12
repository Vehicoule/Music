param(
    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Debug'
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$manifest = Join-Path $root 'native/streambox_core/Cargo.toml'
$profile = if ($Configuration -eq 'Release') { 'release' } else { 'debug' }
$cargoArgs = @('build', '--manifest-path', $manifest)

if ($Configuration -eq 'Release') {
    $cargoArgs += '--release'
}

Push-Location $root
try {
    & cargo @cargoArgs
    if ($LASTEXITCODE -ne 0) {
        throw "cargo build failed with exit code $LASTEXITCODE"
    }

    $source = Join-Path $root "native/streambox_core/target/$profile/streambox_core.dll"
    if (-not (Test-Path -LiteralPath $source)) {
        throw "Rust DLL was not produced at $source"
    }

    $destinationDir = Join-Path $root "frontend/build/windows/x64/runner/$Configuration"
    New-Item -ItemType Directory -Force -Path $destinationDir | Out-Null
    $destination = Join-Path $destinationDir 'streambox_core.dll'
    Copy-Item -LiteralPath $source -Destination $destination -Force

    Write-Host "Copied streambox_core.dll to $destination"
}
finally {
    Pop-Location
}
