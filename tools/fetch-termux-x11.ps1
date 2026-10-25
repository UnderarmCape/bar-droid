# Fetches Termux:X11 (the X server library this app embeds) at the pinned commit, with submodules,
# and applies our one-line patch. Run from the project root in PowerShell. Requires git.
$ErrorActionPreference = "Stop"
$Commit = "7e5f5c5c9226e2cdab392b2efba91bc4bd86463e"
Set-Location (Join-Path $PSScriptRoot "..")
if (-not (Test-Path "termux-x11\.git")) { git clone https://github.com/termux/termux-x11.git termux-x11 }
Set-Location termux-x11
git fetch origin $Commit
git checkout -q $Commit
git submodule update --init --depth 1 --recursive
git apply --check ..\patches\0001-cmdentrypoint-explicit-libpath.patch 2>$null
if ($LASTEXITCODE -eq 0) { git apply ..\patches\0001-cmdentrypoint-explicit-libpath.patch } else { Write-Host "patch already applied or needs manual merge (look for TERMUX_X11_LIBXLORIE_PATH in CmdEntryPoint.java)" }
if (Select-String -Path "lorie\src\main\java\com\termux\x11\CmdEntryPoint.java" -Pattern "TERMUX_X11_LIBXLORIE_PATH" -Quiet) { Write-Host "termux-x11 ready at $Commit (patched)" }
