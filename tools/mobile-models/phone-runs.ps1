# Mobile models on the dev phone, one chunk at a time under the shared lock (devphone-lock.ps1, under ~45 min a hold):
#   phone-runs.ps1 -Chunk setup|ab-bar|ab-lod|abba1|abba2|desync [-DelayMinutes 40]
# setup: install gcc-mobile, push the models, three skirmishes (target set / + mobile / + mobile and coarse level)
# ab-bar: one replay alternating BAR's models (1) and the mobile ones (0) every 20 s (BarDroidModelOverrideAB)
# ab-lod: one replay alternating the coarse level off (0) and under 96 px (96), mobile models on
# abba1 / abba2: whole runs A B / B A, the target set (A) against it + mobile models + coarse level (B)
# desync: the whole 8v8 replay with B, the [DESYNC WARNING] count
# The run recipe of the 30 fps push (2026-11-06): render scale 70 % in the app's prefs, Android's performance game
# mode, screen awake, -KillAll, its dev-env lines; 120 s between runs; render scale back to 100 at the end.
param([Parameter(Mandatory)][ValidateSet("setup", "ab-bar", "ab-lod", "abba1", "abba2", "desync", "final", "shots-mobile")][string]$Chunk,
      [int]$DelayMinutes = 0, [int]$Pause = 120, [int]$LodPx = 96)
$ErrorActionPreference = "Continue"
$tools = "C:\Tools\BARANDROID\bar-droid-engine\tools"
$es = "$tools\engine-sim"
$adb = "C:\Tools\BARANDROID\toolchain\android-sdk\platform-tools\adb.exe"
$dev = "R5CW22GVC3D"
$pkg = "com.underarmcape.bardroid"
if ($Chunk -like "abba*" -and (Test-Path "$PSScriptRoot\skip-abba.flag")) { "$Chunk skipped (skip-abba.flag: the in-game A/B settled it; the phone is wanted elsewhere)"; return }
if ($DelayMinutes) { Start-Sleep ($DelayMinutes * 60) }   # (another session's turn first)
$minutes = @{ "setup" = 25; "ab-bar" = 25; "ab-lod" = 25; "abba1" = 30; "abba2" = 30; "desync" = 35; "final" = 45; "shots-mobile" = 15 }[$Chunk]
"$(Get-Date -Format HH:mm:ss) $Chunk : waiting for the dev phone"
& "$es\devphone-lock.ps1" take mobile-models -Minutes $minutes
for ($i = 0; $i -lt 240; $i++) {   # (and no replay-memory run or game of anyone's still going)
  $busy = $false
  if (Test-Path "C:\Tools\BARANDROID\engine-sim\replay-memory.lock") {
    $owner = 0; [void][int]::TryParse("$(Get-Content C:\Tools\BARANDROID\engine-sim\replay-memory.lock)".Trim(), [ref]$owner)
    $busy = $owner -gt 0 -and [bool](Get-Process -Id $owner -ErrorAction SilentlyContinue)
  }
  if (-not $busy -and -not "$(& $adb -s $dev shell pidof spring)".Trim()) { break }
  Start-Sleep 20
}
"$(Get-Date -Format HH:mm:ss) $Chunk : the phone is ours"
function Prep {
  & $adb -s $dev shell am force-stop $pkg
  & $adb -s $dev exec-out run-as $pkg sh -c "sed -i -E 's/name=.renderScale. value=.[0-9]+./name=\`"renderScale\`" value=\`"70\`"/' shared_prefs/bardroid.xml"
  & $adb -s $dev shell cmd game mode performance $pkg
  & $adb -s $dev shell input keyevent KEYCODE_WAKEUP
}
function L($a) { ($a | ForEach-Object { "'$_'" }) -join ',' }
$base = @('BarDroidDeferSwap = 1', 'BarDroidMaxSimPerDraw = 1', 'BarDroidModelSimplify = 0.1', 'BarDroidModelSimplifyError = 6',
  'BarDroidReflectionEvery = 8', 'MaxDrawnParticles = 300', 'BarDroidUnsyncedGadgetsOff = gfx_fire_smoke_gl4.lua',
  'BarDroidModelTextureMax = 2048', 'ProjectileAtlasDownscale = 4', 'NamedTextureMaxSize = 1024', 'BarDroidMapTileSkip = 1',
  'BarDroidSoundMaxRate = 24000', 'BarDroidIconMaxSize = 64', 'BarDroidModelSimplifySloppy = 0')
$mob = $base + @('BarDroidModelOverrideDir = bardroid-models')
$lod = $mob + @('BarDroidModelLodPixels = 96')
$devEnv = @('export BARDROID_PACE_LATE=0', 'export BARDROID_GAME_WIDGETS=1', 'widget_order "GUI Shader" 0')
try {
  switch ($Chunk) {
    "setup" {
      & powershell -ExecutionPolicy Bypass -File "$es\phone-engine.ps1" -Install gcc-mobile -Device $dev | Select-Object -Last 2
      & powershell -ExecutionPolicy Bypass -File "$tools\mobile-models\push.ps1" -Device $dev
      foreach ($run in @(@('mm-base', $base), @('mm-mobile', $mob), @('mm-lod96', $lod))) {
        Prep
        "$(Get-Date -Format HH:mm:ss) skirmish $($run[0])"
        try { & "$es\skirmish-shots.ps1" -Engine gcc-mobile -Label $run[0] -Grep "BarDroid\]|mobile model" -Settings $run[1] } catch { "skirmish failed: $_" }
        Start-Sleep 20
      }
    }
    "ab-bar" {
      Prep
      & "$es\ab-run.ps1" -Engine gcc-mobile -Key BarDroidModelDrawBar -Values 1,0 -Period 20 -From 1210 -Skip 1210 -Seconds 240 -Timers -Label mm-ab-bar -DevEnv $devEnv -Settings ($mob + @('BarDroidModelOverrideAB = 1')) |
        Select-String -Pattern "result:|phases|BarDroidModelDrawBar|pairwise|by phase|launcher.log and infolog|DESYNC"
    }
    "ab-lod" {
      Prep
      & "$es\ab-run.ps1" -Engine gcc-mobile -Key BarDroidModelLodPixels -Values 0,$LodPx -Period 20 -From 1210 -Skip 1210 -Seconds 240 -Timers -Label "mm-ab-lod$LodPx" -DevEnv $devEnv -Settings $mob |
        Select-String -Pattern "result:|phases|BarDroidModelLodPixels|pairwise|by phase|launcher.log and infolog|DESYNC"
    }
    { $_ -in "abba1", "abba2" } {
      $order = if ($Chunk -eq "abba1") { @("A", "B") } else { @("B", "A") }
      $first = $true
      foreach ($k in $order) {
        if (-not $first) { Start-Sleep $Pause }
        $first = $false
        $set = if ($k -eq "A") { $base } else { $lod }
        $label = if ($k -eq "A") { "mm-base" } else { "mm-mobile-lod96" }
        Prep
        "$(Get-Date -Format HH:mm:ss) $label"
        & "$es\replay-memory.ps1" -Engine gcc-mobile -Replay isthmus8v8-20261026.sdfz -Skip 1210 -Seconds 120 -KillAll -Label $label -DevEnv $devEnv -Settings $set |
          Select-String -Pattern "result:|replaybench\] done|launcher.log and infolog"
      }
    }
    "final" {   # the late 8v8's screenshots, target set / mobile + coarse level, then the coarse level 0 / $LodPx in one replay
      foreach ($run in @(@("mm-shots-base", $base), @("mm-shots-mobile", $lod))) {
        Prep
        "$(Get-Date -Format HH:mm:ss) $($run[0])"
        & "$es\replay-memory.ps1" -Engine gcc-mobile -Replay isthmus8v8-20261026.sdfz -Skip 1210 -Seconds 30 -Shots 1215 -KillAll -Label $run[0] -DevEnv $devEnv -Settings $run[1] |
          Select-String -Pattern "result:|screenshots:|launcher.log and infolog"
        Start-Sleep 30
      }
      Prep
      & "$es\ab-run.ps1" -Engine gcc-mobile -Key BarDroidModelLodPixels -Values 0,$LodPx -Period 20 -From 1210 -Skip 1210 -Seconds 160 -Timers -Label "mm-ab-lod$LodPx" -DevEnv $devEnv -Settings $mob |
        Select-String -Pattern "result:|phases|BarDroidModelLodPixels|pairwise|by phase|launcher.log and infolog|DESYNC"
    }
    "shots-mobile" {   # (the late 8v8's screenshots with the mobile set and its coarse level, as "final" meant to)
      Prep
      & "$es\replay-memory.ps1" -Engine gcc-mobile -Replay isthmus8v8-20261026.sdfz -Skip 1210 -Seconds 30 -Shots 1215 -KillAll -Label mm-shots-mobile -DevEnv $devEnv -Settings $lod |
        Select-String -Pattern "result:|screenshots:|launcher.log and infolog"
    }
    "desync" {
      Prep
      & "$es\phone-engine.ps1" -Replay isthmus8v8-20261026.sdfz -Engine gcc-mobile -Skip 1900 -Seconds 30 -Timeout 3000 -Device $dev -Settings $lod |
        Select-Object -Last 25
    }
  }
} finally {
  & $adb -s $dev shell am force-stop $pkg
  & $adb -s $dev exec-out run-as $pkg sh -c "sed -i -E 's/name=.renderScale. value=.[0-9]+./name=\`"renderScale\`" value=\`"100\`"/' shared_prefs/bardroid.xml; grep -c BarDroid files/bar/springsettings.cfg"
  & "$es\devphone-lock.ps1" free mobile-models
  "$(Get-Date -Format HH:mm:ss) $Chunk : done, the phone given back"
}
