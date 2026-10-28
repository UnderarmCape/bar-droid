# BAR's "Benchmark BAR" on the laptop (BAR's own Windows engine, an isolated write dir joined to the live install's
# packages, pool and rapid index read-only by junctions, removed at the end), for where the time goes while the phone
# is away: the engine's timers at the benchmark's start and end (debuginfo profiling), and optionally BAR's gadget
# profiler (its table in the benchmark's screenshot at frame 2015). The game: the phone's BAR release itself.
# -Widgets: every widget's time logged to infolog (tools/profile/dbg_bardroid_profile_log.lua in a tiny overlay game; it
# quits after its window, before the benchmark ends).
# -Modrules "sensors.los.losMipLevel=4;...": BAR's modrules with those keys changed (tools/research/modrules-override.py,
# generated from the install at run time into the overlay). -Speed n: the game forced to n x speed (the laptop then
# runs behind like the phone: game speed = throughput). Each run adds a row to build\laptop-bench\results.csv (-Label).
#   powershell -ExecutionPolicy Bypass -File tools\research\laptop-bench.ps1 [-Gadgets] [-Widgets] [-Settings @{ WorkerThreadCount = 4 }]
param([switch]$Gadgets, [switch]$Widgets, [switch]$Synced, [switch]$Unsynced, [switch]$Trim, [hashtable]$Settings = @{}, [string]$Engine = "recoil_2026.07.04",
  [string]$Release = "Beyond All Reason test-31691-a617033", [string]$Extra = "", [string[]]$Off = @(), [string]$Modrules = "",
  [int]$Speed = 0, [string]$Label = "", [switch]$Quiet, [string]$EngineDir = "", [hashtable]$Env = @{})
$ErrorActionPreference = "Stop"
$App = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $App "tools\toolchain.ps1")
Assert-BarData
$Work = Join-Path $App "build\laptop-bench"
$Data = Join-Path $Work "data"
Remove-Item -Recurse -Force "$Data\LuaUI", "$Data\screenshots", "$Data\games" -ErrorAction SilentlyContinue
$game = $Release
if ($Widgets -or $Synced -or $Unsynced -or $Trim -or $Modrules) {
  $sdd = Join-Path $Data "games\BAR-wprof.sdd"
  New-Item -ItemType Directory -Force "$sdd\luaui\Widgets", "$sdd\luarules\gadgets" | Out-Null
  if ($Widgets) { Copy-Item (Join-Path $App "tools\profile\dbg_bardroid_profile_log.lua") "$sdd\luaui\Widgets\" }
  if ($Synced) { Copy-Item (Join-Path $PSScriptRoot "dbg_hm_synced_profile.lua") "$sdd\luarules\gadgets\" }
  if ($Trim) {   # the gadget-trim overlay of tools/research/levers.ps1 (PushOverlay)
    . (Join-Path $PSScriptRoot "levers.ps1")
    foreach ($g in $TrimGadgets) { "return false -- hail-mary: off" | Set-Content "$sdd\luarules\gadgets\$g.lua" -Encoding ascii }
  }
  if ($Modrules) {
    & (Join-Path $TC "hosttools\python\python.exe") -I (Join-Path $PSScriptRoot "modrules-override.py") $BarData $Release $Modrules "$sdd\gamedata\modrules.lua"
    if ($LASTEXITCODE) { throw "modrules override failed" }
    Copy-Item (Join-Path $PSScriptRoot "dbg_hm_modrules_echo.lua") "$sdd\luaui\Widgets\"
  }
  if ($Unsynced) {
    Copy-Item (Join-Path $App "tools\profile\dbg_bardroid_gadget_profile.lua") "$sdd\luarules\gadgets\"
    $Settings["bardroid_profile_go"] = 1; $Settings["bardroid_profile_warmup"] = 25; $Settings["bardroid_profile_window"] = 45
  }
  "return { name = `"BAR wprof`", shortName = `"BYAR`", version = `"1`", game = `"Beyond All Reason`", shortGame = `"BYAR`", modtype = 1, depend = { `"$Release`" } }" |
    Set-Content "$sdd\modinfo.lua" -Encoding ascii
  $game = "BAR wprof 1"
  $Settings["bardroid_profile_warmup"] = 30; $Settings["bardroid_profile_window"] = 40; $Settings["bardroid_profile_detail"] = "none"
}
New-Item -ItemType Directory -Force -Path "$Data\LuaUI\Widgets", "$Data\LuaUI\Config", "$Data\maps" | Out-Null
Copy-Item (Join-Path $App "app\src\main\assets\bardroid\bardroid_bench.lua") "$Data\LuaUI\Widgets\" -Force
"1" | Set-Content "$Data\LuaUI\Config\bardroid_bench.txt" -Encoding ascii
# the widget orders launch-bar.sh sets on the phone (and Mission Info off for benchmarks), plus -Off
$off = @("Bloom Shader Deferred", "SSAO", "Distortion GL4", "Snow", "Map Edge Extension", "Show Builder Queue",
  "Deferred rendering GL4", "Decals GL4", "Ground AO Plates GL4", "Ground AO Plates Features GL4", "Map Grass GL4",
  "Commands FX", "Contrast Adaptive Sharpen", "Jammed Units Highlight", "Keybind/Mouse Info", "Changelog Info",
  "Picture-in-Picture Minimap", "Fog Diagonal Lines GL4", "Info", "Mission Info") + $Off
$orders = @($off | ForEach-Object { "`t`t[`"$_`"] = 0," }) + "`t`t[`"Minimap`"] = 1,"
"-- Widget Custom data and order, order = 0 disabled widget`nreturn {`n`tdata = {`n`t},`n`torder = {`n$($orders -join "`n")`n`t},`n}" |
  Set-Content "$Data\LuaUI\Config\BYAR.lua" -Encoding ascii
@"
Fullscreen = 0
WindowBorderless = 0
XResolutionWindowed = 1280
YResolutionWindowed = 720
WindowPosX = 40
WindowPosY = 40
snd_volmaster = 0
LogFlushLevel = 0
VSync = 0
MSAALevel = 0
Shadows = 0
AdvMapShading = 0
Water = 0
UnitIconFadeStart = 1
UnitIconFadeVanish = 1
$(($Settings.GetEnumerator() | ForEach-Object { "$($_.Key) = $($_.Value)" }) -join "`n")
"@ | Set-Content "$Data\springsettings.cfg" -Encoding ascii
$cmds = "16:debuginfo profiling|2010:debuginfo profiling" + $(if ($Speed) { "|21:setmaxspeed $Speed|22:setminspeed $Speed" } else { "" }) + $(if ($Gadgets) { "|40:luarules profile" } else { "" }) + $(if ($Extra) { "|$Extra" } else { "" })
$tpl = Get-Content (Join-Path $App "app\src\main\assets\bardroid\benchmark.template.txt") -Raw
$tpl.Replace("@GAME@", $game).Replace("|20:vsync 0|", "|20:vsync 0|$cmds|") | Set-Content "$Work\bench.txt" -Encoding ascii
$links = foreach ($d in "packages", "pool", "rapid") {
  $link = Join-Path $Data $d
  if (-not (Test-Path $link)) { cmd /c mklink /J "$link" "$(Join-Path $BarData $d)" | Out-Null }
  $link
}
try {
  if (-not (Test-Path "$Data\maps\starwatcher_1.0.sd7")) { Copy-Item (Join-Path $BarData "maps\starwatcher_1.0.sd7") "$Data\maps\" }
  $log = Join-Path $Data "infolog.txt"; Remove-Item $log -ErrorAction SilentlyContinue
  $ed = if ($EngineDir) { $EngineDir } else { Join-Path $BarData "engine\$Engine" }
  foreach ($k in $Env.Keys) { Set-Item "env:$k" $Env[$k] }   # research switches (HM_*) for the engine process
  $p = Start-Process -FilePath (Join-Path $ed "spring.exe") -WorkingDirectory $ed -PassThru `
    -ArgumentList "--isolation", "--write-dir", "`"$Data`"", "`"$Work\bench.txt`""
  if (-not $p.WaitForExit(900000)) { $p.Kill(); Write-Host "[laptop-bench] timed out" }
  foreach ($k in $Env.Keys) { Remove-Item "env:$k" -ErrorAction SilentlyContinue }
  if (-not $Quiet) {
    Get-Content $log | Select-String -Pattern '(Draw|Sim|Update) \d+ frames|Worker \d thread|Optimal|Core Mask|\[bardroid-profile\]|\[hm-sprofile\]|\[bardroid-gprofile\]|\[hm-modrules\]|Error|error' |
      ForEach-Object { $_.Line -replace '^\[t=[^\]]+\](\[f=[^\]]+\])? ', '' }
  }
  $saved = Join-Path $Work "infolog-$((Get-Date).ToString('HHmmss'))-$($Label -replace '[^\w.-]', '_').txt"
  Copy-Item $log $saved
  # the engine timers of the run, one CSV row
  $py = Join-Path $TC "hosttools\python\python.exe"
  $tm = & $py -I (Join-Path $PSScriptRoot "timers.py") $saved
  $get = { param($k) $m = $tm | Select-String ("^" + [regex]::Escape($k) + "\s+([\d.]+)"); if ($m) { [double]$m.Matches[0].Groups[1].Value } else { $null } }
  $row = [pscustomobject]@{ when = (Get-Date).ToString("HH:mm:ss"); label = $Label; speed_forced = $Speed
    sim = (& $get "Sim"); lua_sync = (& $get "Lua::Callins::Synced"); lua_unsync = (& $get "Lua::Callins::Unsynced")
    draw = (& $get "Draw"); game_speed = (& $get "game speed (x real time)"); infolog = (Split-Path $saved -Leaf) }
  $row | Export-Csv -Path (Join-Path $Work "results.csv") -Append -NoTypeInformation
  Write-Host ("[laptop-bench] {0}: engine Sim {1} ms/frame, Lua synced {2}, unsynced {3}, Draw {4}, game speed x{5}" -f $Label, $row.sim, $row.lua_sync, $row.lua_unsync, $row.draw, $row.game_speed)
  Get-ChildItem "$Data\screenshots" -ErrorAction SilentlyContinue | Copy-Item -Destination $Work
} finally {
  foreach ($l in $links) { if (Test-Path $l) { cmd /c rmdir "$l" } }
}
