param(
    [int]$ApiLevel = 23
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$manifest = Join-Path $root 'native/streambox_core/Cargo.toml'
$sdkRoot = $env:ANDROID_NDK_HOME

if (-not $sdkRoot) {
    $androidHome = $env:ANDROID_HOME
    if (-not $androidHome) {
        $androidHome = Join-Path $env:LOCALAPPDATA 'Android/Sdk'
    }
    $ndkRoot = Join-Path $androidHome 'ndk'
    if (-not (Test-Path -LiteralPath $ndkRoot)) {
        throw "Android NDK was not found. Set ANDROID_NDK_HOME or install the Android NDK."
    }
    $sdkRoot = Get-ChildItem -Directory -LiteralPath $ndkRoot |
        Sort-Object Name -Descending |
        Select-Object -First 1 -ExpandProperty FullName
}

$toolchainBin = Join-Path $sdkRoot 'toolchains/llvm/prebuilt/windows-x86_64/bin'
if (-not (Test-Path -LiteralPath $toolchainBin)) {
    throw "Android LLVM toolchain was not found at $toolchainBin"
}

$targets = @(
    @{
        RustTarget = 'aarch64-linux-android'
        Abi = 'arm64-v8a'
        Linker = "aarch64-linux-android$ApiLevel-clang.cmd"
    },
    @{
        RustTarget = 'x86_64-linux-android'
        Abi = 'x86_64'
        Linker = "x86_64-linux-android$ApiLevel-clang.cmd"
    }
)

foreach ($target in $targets) {
    & rustup target add $target.RustTarget
    if ($LASTEXITCODE -ne 0) {
        throw "rustup target add $($target.RustTarget) failed with exit code $LASTEXITCODE"
    }

    $linker = Join-Path $toolchainBin $target.Linker
    if (-not (Test-Path -LiteralPath $linker)) {
        throw "Android linker was not found at $linker"
    }

    if ($target.RustTarget -eq 'aarch64-linux-android') {
        $env:CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER = $linker
    }
    elseif ($target.RustTarget -eq 'x86_64-linux-android') {
        $env:CARGO_TARGET_X86_64_LINUX_ANDROID_LINKER = $linker
    }

    & cargo build --manifest-path $manifest --target $target.RustTarget
    if ($LASTEXITCODE -ne 0) {
        throw "cargo build for $($target.RustTarget) failed with exit code $LASTEXITCODE"
    }

    $source = Join-Path $root "native/streambox_core/target/$($target.RustTarget)/debug/libstreambox_core.so"
    if (-not (Test-Path -LiteralPath $source)) {
        throw "Android shared library was not produced at $source"
    }

    $destinationDir = Join-Path $root "frontend/android/app/src/main/jniLibs/$($target.Abi)"
    New-Item -ItemType Directory -Force -Path $destinationDir | Out-Null
    $destination = Join-Path $destinationDir 'libstreambox_core.so'
    Copy-Item -LiteralPath $source -Destination $destination -Force
    Write-Host "Copied libstreambox_core.so to $destination"
}
