# BAR's "Benchmark BAR" scenario on the dev phone, ABBA: -A (the baseline engine build) against -B (the combined one),
# both with the dev phone's target set at 70 %, through tools\phone-bench.ps1 (its warm-up into the hot state, its csv).
param([string]$A = "gcc-fold7", [Parameter(Mandatory)][string]$B, [string]$Order = "ABBA", [int]$Pause = 120)
$ErrorActionPreference = "Continue"
$es = "C:\Tools\BARANDROID\bar-droid-engine\tools\engine-sim"
$app = "C:\Tools\BARANDROID\bar-droid-app\tools"
$adb = "C:\Tools\BARANDROID\toolchain\android-sdk\platform-tools\adb.exe"
$dev = "R5CW22GVC3D"
$pkg = "com.underarmcape.bardroid"
function T($m) { "$(Get-Date -Format HH:mm:ss) $m" }
$set = @{ BarDroidDeferSwap = 1; BarDroidMaxSimPerDraw = 1; BarDroidModelSimplify = 0.1; BarDroidModelSimplifyError = 6;
  BarDroidReflectionEvery = 8; MaxDrawnParticles = 300; BarDroidUnsyncedGadgetsOff = "gfx_fire_smoke_gl4.lua";
  BarDroidModelTextureMax = 2048; ProjectileAtlasDownscale = 4; NamedTextureMaxSize = 1024; BarDroidMapTileSkip = 1;
  BarDroidSoundMaxRate = 24000; BarDroidIconMaxSize = 64; BarDroidModelSimplifySloppy = 0; BarDroidModelTextureDir = "bardroid-astc" }
$devEnvLines = @('export BARDROID_PACE_LATE=0', 'export BARDROID_GAME_WIDGETS=1', 'export BARDROID_PHONE_LUA=1', 'widget_order "GUI Shader" 0')
function UseEngine([string]$build) {
  $tmp = "C:\Tools\BARANDROID\toolchain\tmp\bench-dev-env.sh"
  $text = "# bench-ab.ps1: $build`nENGINE=`"`$BAR/engine-sim/$build`"`nlog `"engine-sim: `$ENGINE`"`n" + ($devEnvLines -join "`n") + "`n"
  [IO.File]::WriteAllText($tmp, $text, (New-Object Text.ASCIIEncoding))
  & $adb -s $dev push $tmp /data/local/tmp/bench-dev-env.sh | Out-Null
  & $adb -s $dev shell chmod 644 /data/local/tmp/bench-dev-env.sh
  & $adb -s $dev exec-out run-as $pkg sh -c "cp /data/local/tmp/bench-dev-env.sh files/bar/dev-env.sh; sed -i -E '/^BarDroid/{/^BarDroidLowMemory *=/!d}' files/bar/springsettings.cfg; [ -x files/bar/engine-sim/$build/spring ] && echo engine $build ready || echo MISSING $build"
}
& "$es\devphone-lock.ps1" take bench -Minutes 90
try {
  foreach ($b in @($A, $B)) {
    $have = "$(& $adb -s $dev exec-out run-as $pkg sh -c "[ -x files/bar/engine-sim/$b/spring ] && echo yes")".Trim()
    if ($have -ne "yes" -or $b -eq $B) { & powershell -ExecutionPolicy Bypass -File "$es\phone-engine.ps1" -Install $b -Device $dev | Select-Object -Last 1 }
  }
  $i = 0
  foreach ($k in $Order.ToCharArray()) {
    $build = if ($k -eq 'A') { $A } else { $B }
    if ($i -gt 0) { Start-Sleep $Pause }
    $i++
    T "bench $k $build"
    UseEngine $build
    & powershell -ExecutionPolicy Bypass -Command "& '$app\phone-bench.ps1' -Scale 70 -Label 'ab-$k-$build' -Device $dev -Settings @{ $(($set.GetEnumerator() | ForEach-Object { if ($_.Value -is [string]) { "$($_.Key) = '$($_.Value)'" } else { "$($_.Key) = $($_.Value)" } }) -join '; ') }" 2>&1 |
      Select-Object -Last 14
  }
} finally {
  & $adb -s $dev shell am force-stop $pkg
  & $adb -s $dev exec-out run-as $pkg sh -c "rm -f files/bar/dev-env.sh; sed -i -E '/^BarDroid/{/^BarDroidLowMemory *=/!d}' files/bar/springsettings.cfg"
  & "$es\devphone-lock.ps1" free bench
  T "done, the phone given back"
}
