$UserProfile    = [Environment]::GetFolderPath("UserProfile")
$EnterOnceRoot  = Join-Path $UserProfile ".enter-once-cache"
$ScriptCacheDir = Join-Path $EnterOnceRoot "ExecutionPolicy-Foundation"
$TargetDirFile  = Join-Path $ScriptCacheDir "TargetDir.txt"

if (-not (Test-Path $ScriptCacheDir)) {
    New-Item -ItemType Directory -Path $ScriptCacheDir | Out-Null
}

if (Test-Path $TargetDirFile) {
    $TargetDir = Get-Content $TargetDirFile -Raw
} else {
    $TargetDir = Join-Path $UserProfile "git/ExecutionPolicy-Foundation"
    # oder interaktiv:
    # $TargetDir = Read-Host "Target directory for ExecutionPolicy-Foundation"
    Set-Content -Path $TargetDirFile -Value $TargetDir -Encoding UTF8
}
