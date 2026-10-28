# The laptop timing matrix of the second research round (docs/research-hail-mary.md): every variant once per round,
# rounds repeated (laptop runs vary ±15 %: compare medians), each a row of build\laptop-bench\results.csv.
#   powershell -ExecutionPolicy Bypass -File tools\research\laptop-matrix.ps1 [-Rounds 3] [-Set work|speed|engine]
param([int]$Rounds = 3, [string]$Set = "work")
$W = "C:\Tools\BARANDROID\hailmary-work\win-engine"   # Windows research builds (hailmary-work\scripts\build-engine-win.ps1)
$lb = Join-Path $PSScriptRoot "laptop-bench.ps1"
$los = "sensors.los.losMipLevel=4;sensors.los.airMipLevel=5;sensors.los.radarMipLevel=3"
$avoid = "movement.groundUnitCollisionAvoidanceUpdateRate=6"
$quadpos = "movement.unitQuadPositionUpdateRate=6"
$path = "system.pathFinderUpdateRateScale=0.5;system.qtMaxNodesSearched=4096"
$variants = if ($Set -eq "engine") { [ordered]@{
  # engine variants on the laptop (x86-64 builds of the same patches the phone levers use), work per simulated frame
  "official-clean" = @{ EngineDir = "$W\official-clean" }
  "sw-off"      = @{ EngineDir = "$W\sw" }
  "sw-dfs"      = @{ EngineDir = "$W\sw"; Env = @{ HM_ANIM_DFS = "1" } }
  "sw-nohash"   = @{ EngineDir = "$W\sw"; Env = @{ HM_NO_SYNC_HASH = "1" } }
  "sw-dmgsync"  = @{ EngineDir = "$W\sw"; Env = @{ HM_DMG_SYNCED_ONLY = "1" } }
  "sw-all"      = @{ EngineDir = "$W\sw"; Env = @{ HM_ANIM_DFS = "1"; HM_NO_SYNC_HASH = "1"; HM_DMG_SYNCED_ONLY = "1" } }
  "gs20"        = @{ EngineDir = "$W\gs20" }
  "syslibm"     = @{ EngineDir = "$W\syslibm" }
  "workers4"    = @{ EngineDir = "$W\official-clean"; Settings = @{ WorkerThreadCount = 4 } }
  "workers16"   = @{ EngineDir = "$W\official-clean"; Settings = @{ WorkerThreadCount = 16 } }
} } elseif ($Set -eq "work") { [ordered]@{
  # work per simulated frame at the scenario's own 1x (engine timers)
  "base"        = @{}
  "mr-los"      = @{ Modrules = $los }
  "mr-avoid6"   = @{ Modrules = $avoid }
  "mr-quadpos6" = @{ Modrules = $quadpos }
  "mr-quad256"  = @{ Modrules = "system.quadFieldQuadSizeInElmos=256" }
  "mr-quad64"   = @{ Modrules = "system.quadFieldQuadSizeInElmos=64" }
  "mr-path"     = @{ Modrules = $path }
  "mr-overlap"  = @{ Modrules = "movement.allowUnitCollisionOverlap=true" }
  "mr-all"      = @{ Modrules = "$los;$avoid;$quadpos;$path" }
  "sound-off"   = @{ Settings = @{ Sound = 0 } }
  "gadget-trim" = @{ Trim = $true }
  "luaui-off"   = @{ Extra = "17:luaui disable|2030:quitforce" }
} } else { [ordered]@{
  # throughput with the laptop behind (forced 3x, like the phone at 1x): simulated frames per second
  "x3-base"     = @{ Speed = 3 }
  "x3-balance05" = @{ Speed = 3; Settings = @{ MinSimDrawBalance = 0.05 } }
  "x3-balance0-draw1" = @{ Speed = 3; Settings = @{ MinSimDrawBalance = 0.0; MinDrawFPS = 1 } }
} }
for ($r = 1; $r -le $Rounds; $r++) {
  foreach ($k in $variants.Keys) {
    $a = $variants[$k].Clone()
    if ($a.EngineDir -and -not (Test-Path (Join-Path $a.EngineDir "spring.exe"))) { continue }   # a build that failed
    & $lb -Label "$k" -Quiet @a 2>&1 | Select-String '\[laptop-bench\]|\[hm-modrules\]' | ForEach-Object { "$(Get-Date -Format HH:mm:ss) r$r $($_.Line)" }
  }
}
