# Fetches Termux:X11 (the X server library this app embeds) at the pinned commit, with submodules,
# and applies our patches (patches/0*.patch). Run from the project root in PowerShell. Requires git.
$ErrorActionPreference = "Stop"
$Commit = "7e5f5c5c9226e2cdab392b2efba91bc4bd86463e"
Set-Location (Join-Path $PSScriptRoot "..")
if (-not (Test-Path "termux-x11\.git")) { git clone https://github.com/termux/termux-x11.git termux-x11 }
Set-Location termux-x11
git fetch origin $Commit
git checkout -q $Commit
git submodule update --init --depth 1 --recursive
foreach ($p in Get-ChildItem ..\patches\0*.patch | Sort-Object Name) {
    cmd /c "git apply --reverse --check `"$($p.FullName)`" 2>nul"
    if ($LASTEXITCODE -eq 0) { Write-Host "already applied: $($p.Name)"; continue }
    git apply $p.FullName
    if ($LASTEXITCODE -ne 0) { throw "patch does not apply: $($p.Name)" }
    Write-Host "applied: $($p.Name)"
}
if (Select-String -Path "lorie\src\main\java\com\termux\x11\CmdEntryPoint.java" -Pattern "TERMUX_X11_LIBXLORIE_PATH" -Quiet) { Write-Host "termux-x11 ready at $Commit (patched)" }
