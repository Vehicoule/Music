param(
    [int] $Port = 8000
)

$ErrorActionPreference = "Stop"

$BackendDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$BundledPython = Join-Path $env:USERPROFILE ".cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe"
$SitePackages = Join-Path $BackendDir ".venv\Lib\site-packages"
$ScriptsDir = Join-Path $BackendDir ".venv\Scripts"
$YtDlpExe = Join-Path $ScriptsDir "yt-dlp.exe"

if (-not (Test-Path $BundledPython)) {
    throw "Bundled Python was not found at $BundledPython. Install Python 3.12 or run from Codex with bundled runtimes available."
}

if (-not (Test-Path $SitePackages)) {
    throw "Backend dependencies were not found at $SitePackages. Run dependency setup first."
}

Set-Location $BackendDir

if (Test-Path $ScriptsDir) {
    $PathParts = $env:PATH -split ";"
    if ($PathParts -notcontains $ScriptsDir) {
        $env:PATH = "$ScriptsDir;$env:PATH"
    }
}

if (-not $env:YTDLP_PYTHON) {
    $env:YTDLP_PYTHON = $BundledPython
}

if (-not $env:YTDLP_BINARY -and (Test-Path $YtDlpExe)) {
    $env:YTDLP_BINARY = $YtDlpExe
}

if ($env:PYTHONPATH) {
    $env:PYTHONPATH = "$SitePackages;$env:PYTHONPATH"
} else {
    $env:PYTHONPATH = $SitePackages
}

Write-Host "Streambox backend dev server"
Write-Host "  Backend: $BackendDir"
Write-Host "  Python:  $BundledPython"
Write-Host "  yt-dlp:  $($env:YTDLP_PYTHON) -m yt_dlp"
Write-Host "  Port:    $Port"

& $BundledPython -m uvicorn app.main:app --reload --host 127.0.0.1 --port $Port
