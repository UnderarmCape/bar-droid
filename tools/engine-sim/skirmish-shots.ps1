# A drawing change, the quick look (Kailil, 2026-11-06: "join a skirmish 1v1 over and over to test"): a skirmish on
# the dev phone with an engine-branch build and the given settings, three screenshots at game second 20 (the camera
# close, middle and far over the units: bardroid_simdraw.lua "shots"; the skirmish's own start camera draws units as
# icons), the engine's lines matching -Grep; then the phone's files as they were. ~2 min.
#   skirmish-shots.ps1 -Engine gcc-x [-Settings "Key = value", ...] [-Label x] [-Grep "BarDroid\]"] [-Wait 95]
param([string]$Engine = "gcc-tex", [string[]]$Settings = @(), [string]$Label = "", [string]$Grep = "BarDroid\]",
      [int]$Wait = 95, [string]$Device = "R5CW22GVC3D")
$ErrorActionPreference = "Stop"
. "C:\Tools\BARANDROID\bar-droid-app\tools\toolchain.ps1"
$adb = Join-Path $TC "android-sdk\platform-tools\adb.exe"
$runs = "C:\Tools\BARANDROID\engine-sim\runs"
$tmp = Join-Path $env:TEMP "skirmish-shots"; New-Item -ItemType Directory -Force $tmp | Out-Null
function AppRun([string]$text, [string]$name) {
  $f = Join-Path $tmp $name
  [IO.File]::WriteAllText($f, ($text -replace "`r", ""), (New-Object Text.ASCIIEncoding))
  Invoke-AppScript $adb $f $Device
}
& $adb -s $Device shell am force-stop com.underarmcape.bardroid
& "$PSHOME\powershell.exe" -ExecutionPolicy Bypass -File "$PSScriptRoot\phone-engine.ps1" -Use $Engine -Device $Device | Out-Null
if ("$(AppRun 'cat files/bar/dev-env.sh' 'ss-check.sh')" -notmatch [regex]::Escape("engine-sim/$Engine")) { throw "dev-env.sh does not start $Engine" }
$ss = if ($Settings.Count) { "printf '%s\n' " + (($Settings | ForEach-Object { "'$_'" }) -join ' ') + " > files/bar/dev-springsettings.cfg" } else { "rm -f files/bar/dev-springsettings.cfg" }
AppRun "$ss; cp files/bar/springsettings.cfg files/bar/.springsettings-before-run; rm -f files/bar/infolog.txt files/bar/screenshots/*.png" "ss-set.sh" | Out-Null
Send-AppFile $adb "$PSScriptRoot\bardroid_simdraw.lua" "files/bar/LuaUI/Widgets/bardroid_simdraw.lua" $Device
AppRun "echo 'shots 20' > files/bar/LuaUI/Config/bardroid_simdraw.txt" "ss-shots.sh" | Out-Null
try {
  & $adb -s $Device shell am start -n com.underarmcape.bardroid/.LauncherActivity --es start skirmish | Out-Null
  Start-Sleep $Wait
  $base = "$runs\$((Get-Date).ToString('yyyyMMdd-HHmmss'))-skirmish-$Engine$(if ($Label) { '-' + $Label })"
  $names = @("$(AppRun 'ls -tr files/bar/screenshots/*.png 2>/dev/null | tail -3' 'ss-list.sh')" -split '\s+' | Where-Object { $_ })
  $i = 0
  foreach ($n in $names) { $i++; & cmd /c "`"$adb`" -s $Device exec-out run-as com.underarmcape.bardroid cat `"$n`" > `"$base-shot$i.png`"" }
  if (-not $names.Count) { & cmd /c "`"$adb`" -s $Device exec-out screencap -p > `"$base-screen.png`""; "no engine screenshots; the screen: $base-screen.png" }
  else { "screenshots: $($names.Count) ($base-shot1.png ...)" }
  AppRun "grep -E '$Grep' files/bar/infolog.txt | head -12 | cut -c1-220" "ss-log.sh"
} finally {
  & $adb -s $Device shell am force-stop com.underarmcape.bardroid
  AppRun "rm -f files/bar/dev-env.sh files/bar/dev-springsettings.cfg files/bar/LuaUI/Widgets/bardroid_simdraw.lua files/bar/LuaUI/Config/bardroid_simdraw.txt files/bar/screenshots/*.png; [ -f files/bar/.springsettings-before-run ] && mv files/bar/.springsettings-before-run files/bar/springsettings.cfg; true" "ss-clean.sh" | Out-Null
}
