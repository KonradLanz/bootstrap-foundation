# windows/bootstrap.ps1
# Windows Bootstrap - Thin Wrapper
# Setzt ExecutionPolicy, delegiert an ExecutionPolicy-Foundation
# PS 5.1 kompatibel
#
# STARTEN (PowerShell als Administrator):
#   iex ((New-Object Net.WebClient).DownloadString('https://raw.githubusercontent.com/KonradLanz/bootstrap-foundation/main/windows/bootstrap.ps1'))

param(
    [string]$GitHubUser = 'KonradLanz'
)

$ErrorActionPreference = 'Continue'

Write-Host ''
Write-Host '================================================' -ForegroundColor Cyan
Write-Host '  bootstrap-foundation: Windows' -ForegroundColor Cyan
Write-Host '================================================' -ForegroundColor Cyan
Write-Host ''

# 1) ExecutionPolicy
Write-Host '[1/3] ExecutionPolicy setzen...' -ForegroundColor Yellow
Set-ExecutionPolicy Bypass -Scope Process -Force
Write-Host '      OK' -ForegroundColor Green

# 2) ExecutionPolicy-Foundation bootstrappen
Write-Host '[2/3] ExecutionPolicy-Foundation laden...' -ForegroundColor Yellow
try {
    $foundationUrl = 'https://raw.githubusercontent.com/KonradLanz/ExecutionPolicy-Foundation/main/StartWithGithub.ps1'
    & ([scriptblock]::Create((New-Object Net.WebClient).DownloadString($foundationUrl)))
} catch {
    Write-Host "      [WARNUNG] Foundation nicht erreichbar: $_" -ForegroundColor Red
    Write-Host '      Fallback: git direkt pruefen...' -ForegroundColor Yellow
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Write-Host '      git nicht gefunden - installiere via winget...' -ForegroundColor Yellow
        winget install --id Git.Git -e --source winget --accept-source-agreements --accept-package-agreements
        $env:Path = [System.Environment]::GetEnvironmentVariable('Path','Machine') + ';' +
                    [System.Environment]::GetEnvironmentVariable('Path','User')
    }
    Write-Host '      git OK (Fallback)' -ForegroundColor Green
}

# 3) bootstrap-foundation Repo klonen
Write-Host '[3/3] bootstrap-foundation Repo klonen...' -ForegroundColor Yellow
$repoBase = Join-Path $env:USERPROFILE 'github'
New-Item -Path $repoBase -ItemType Directory -Force | Out-Null
$bfDir = Join-Path $repoBase 'bootstrap-foundation'
if (-not (Test-Path $bfDir)) {
    git clone "https://github.com/$GitHubUser/bootstrap-foundation.git" $bfDir
} else {
    Push-Location $bfDir; git pull; Pop-Location
}
Write-Host '      OK' -ForegroundColor Green

Write-Host ''
Write-Host '================================================' -ForegroundColor Green
Write-Host '  Windows Bootstrap abgeschlossen!' -ForegroundColor Green
Write-Host '================================================' -ForegroundColor Green
Write-Host ''
Write-Host 'Weiter mit projektspezifischem Bootstrap:' -ForegroundColor Cyan
Write-Host '  iex ((New-Object Net.WebClient).DownloadString(''https://raw.githubusercontent.com/KonradLanz/windows-disk-transition-toolkit/main/Bootstrap-Windows.ps1''))' -ForegroundColor Cyan
Write-Host ''
