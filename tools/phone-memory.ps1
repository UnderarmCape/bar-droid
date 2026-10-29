# How much memory BAR's engine takes on the phone (Kailil, 2026-10-29: "Work on getting the game to fit on a smaller
# ram phone"): one game with engine settings for that run only (dev-springsettings.cfg in the app's BAR folder, which
# launch-bar.sh appends to springsettings.cfg; removed afterwards), the phone's background apps stopped first (am
# kill-all: runs compare), and every 5 s (tools/phone-memory.sh) the engine's GPU memory (Android's GL mtrack: RAM on a
# phone, never swapped), its resident and swapped memory and the phone's available memory. Prints the peaks, how far
# the game got (its last simulated frame) and whether Android ended it; each run is added to build\phone-memory.csv.
# Runs on the dev phone (..\phone-device.txt), one heavy run at a time (..\phone-bench.lock).
#   powershell -ExecutionPolicy Bypass -File tools\phone-memory.ps1 [-Mode skirmish|bench] [-Settings @{ Water = 0 }]
#     [-Seconds 150] [-Label text] [-Device serial]
param([ValidateSet("skirmish", "bench")][string]$Mode = "skirmish", [hashtable]$Settings = @{}, [int]$Seconds = 150,
  [string]$Label = "", [string]$Device = "", [int]$Scale = 0)   # -Scale: the app's render resolution for the run (100, 85, 70)
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "toolchain.ps1")
$App = Split-Path -Parent $PSScriptRoot
$adb = Join-Path $TC "android-sdk\platform-tools\adb.exe"
$pkg = "com.underarmcape.bardroid"
if (-not $Device) { $Device = Get-PhoneDevice $adb }
if (-not $Device) { throw "No phone: connect one over adb, or name it (-Device, BARDROID_DEVICE, phone-device.txt)" }

$lock = Join-Path (Split-Path $TC) "phone-bench.lock"
while (Test-Path $lock) {
  $holder = (Get-Content $lock -ErrorAction SilentlyContinue | Select-Object -First 1)
  if (-not $holder -or [int]$holder -eq $PID -or -not (Get-Process -Id ([int]$holder) -ErrorAction SilentlyContinue)) { break }
  Write-Host "[phone-memory] phone busy (lock held by process $holder): waiting"
  Start-Sleep 30
}
Set-Content -Path $lock -Value $PID -Encoding ascii

# (a file into the app's own folder: pushed, then copied by the app's user; "" removes it)
function AppFile([string]$path, [string]$text) {
  if ($text) {
    New-Item -ItemType Directory -Force (Join-Path $TC "tmp") | Out-Null
    $tmp = Join-Path $TC "tmp\bardroid-appfile"
    [IO.File]::WriteAllText($tmp, ($text -replace "`r", ""), (New-Object Text.ASCIIEncoding))
    $eap = $ErrorActionPreference; $ErrorActionPreference = "Continue"
    try { $null = & $adb -s $Device push $tmp /data/local/tmp/bardroid-appfile 2>&1 } finally { $ErrorActionPreference = $eap }
    & $adb -s $Device shell "run-as $pkg sh -c 'cat /data/local/tmp/bardroid-appfile > $path'; rm -f /data/local/tmp/bardroid-appfile"
  } else {
    & $adb -s $Device shell "run-as $pkg rm -f $path"
  }
}

# (a script run as the app, from its own folder: the app's saved settings in shared_prefs/bardroid.xml)
function RunAs([string]$script) {
  New-Item -ItemType Directory -Force (Join-Path $TC "tmp") | Out-Null
  $tmp = Join-Path $TC "tmp\bardroid-runas.sh"
  [IO.File]::WriteAllText($tmp, ($script -replace "`r", ""), (New-Object Text.ASCIIEncoding))
  $eap = $ErrorActionPreference; $ErrorActionPreference = "Continue"
  try { $null = & $adb -s $Device push $tmp /data/local/tmp/bardroid-runas.sh 2>&1 } finally { $ErrorActionPreference = $eap }
  & $adb -s $Device shell "run-as $pkg sh -c 'cat /data/local/tmp/bardroid-runas.sh > files/bardroid-runas.sh; sh files/bardroid-runas.sh'"
}
$userScale = $null
try {
  & $adb -s $Device shell "am force-stop $pkg"
  if ($Scale) {   # (as tools\phone-bench.ps1 -Scale; the player's own value back afterwards)
    $userScale = (RunAs "sed -n 's/.*name=`"renderScale`" value=`"\([0-9-]*\)`".*/\1/p' shared_prefs/bardroid.xml | head -n 1" | Out-String).Trim()
    RunAs "f=shared_prefs/bardroid.xml; sed -i '/name=`"renderScale`"/d' `$f; sed -i 's|</map>|    <int name=`"renderScale`" value=`"$Scale`" />\n</map>|' `$f"
  }
  $lines = @($Settings.GetEnumerator() | Sort-Object Name | ForEach-Object { "$($_.Name) = $($_.Value)" })
  # (launch-bar.sh appends the file to springsettings.cfg and the engine saves that file at its end: the run's settings
  # would stay for every game after; the file as it was goes back afterwards)
  # (a dev-springsettings.cfg the phone keeps, as the dev phone's CompressTextures = 1, is set aside for the run, so a
  # run measures the app's own settings plus the run's, and goes back afterwards)
  & $adb -s $Device shell "run-as $pkg sh -c 'cp files/bar/springsettings.cfg files/bar/.springsettings.pre-memory; [ -f files/bar/dev-springsettings.cfg ] && mv files/bar/dev-springsettings.cfg files/bar/.dev-springsettings.pre-memory; true'"
  AppFile "files/bar/dev-springsettings.cfg" ($lines -join "`n")
  & $adb -s $Device shell "am kill-all"
  Start-Sleep 3
  $sampler = Join-Path $PSScriptRoot "phone-memory.sh"
  $eap = $ErrorActionPreference; $ErrorActionPreference = "Continue"
  try { $null = & $adb -s $Device push $sampler /data/local/tmp/bardroid-mem.sh 2>&1 } finally { $ErrorActionPreference = $eap }
  $since = (& $adb -s $Device shell "date +%H:%M:%S").Trim()
  $job = Start-Job -ScriptBlock { param($a, $d, $s) & $a -s $d shell "sed -i 's/\r$//' /data/local/tmp/bardroid-mem.sh; sh /data/local/tmp/bardroid-mem.sh $s /data/local/tmp/bardroid-mem.txt" } -ArgumentList $adb, $Device, ($Seconds + 30)
  Start-Sleep 2
  & $adb -s $Device shell "am start -n $pkg/.LauncherActivity --es start $Mode" | Out-Null
  Write-Host "[phone-memory] $Mode started at $since$(if ($lines) { ' with ' + ($lines -join ', ') })"
  Wait-Job $job -Timeout ($Seconds + 90) | Out-Null
  Remove-Job $job -Force

  $samples = @(& $adb -s $Device shell cat /data/local/tmp/bardroid-mem.txt | Where-Object { $_ -match '^\d+ \d+ \d+ \d+ \d+$' } |
    ForEach-Object { $f = $_ -split ' '; [pscustomobject]@{ t = [int]$f[0]; gl = [int]$f[1]; rss = [int]$f[2]; swap = [int]$f[3]; avail = [int]$f[4] } })
  $gone = [bool](& $adb -s $Device shell cat /data/local/tmp/bardroid-mem.txt | Select-String -SimpleMatch "gone")
  $frame = (& $adb -s $Device exec-out run-as $pkg sh -c "grep -o '\[f=[0-9]*\]' files/bar/infolog.txt | tail -n 1" | Out-String).Trim() -replace '\D', ''
  # (what a setting can break: an atlas the engine could not draw into, as with CompressTextures; a Lua error)
  $broken = @(& $adb -s $Device exec-out run-as $pkg sh -c "grep -E 'atlasRendered=0|Unsupported textures|Error in [A-Za-z]+\(\)|Removed widget' files/bar/infolog.txt" |
    ForEach-Object { ($_ -replace '^\[t=[^\]]*\](\[f=[^\]]*\])? ', '').Trim() } | Sort-Object -Unique)
  # (the launcher's lines since the start, filtered here: adb's quoting through PowerShell is fragile)
  $exit = @(& $adb -s $Device exec-out run-as $pkg sh -c "grep -E 'engine exited|BAR Droid .* starting' files/logs/launcher.log" |
    Where-Object { $_ -match '^(\d\d:\d\d:\d\d) ' -and $Matches[1] -ge $since }) | Select-Object -Last 1
} finally {
  & $adb -s $Device shell "am force-stop $pkg"
  AppFile "files/bar/dev-springsettings.cfg" ""
  & $adb -s $Device shell "run-as $pkg sh -c '[ -f files/bar/.springsettings.pre-memory ] && mv files/bar/.springsettings.pre-memory files/bar/springsettings.cfg; [ -f files/bar/.dev-springsettings.pre-memory ] && mv files/bar/.dev-springsettings.pre-memory files/bar/dev-springsettings.cfg; true'"
  if ($Scale) {
    $back = if ($userScale) { "sed -i 's|</map>|    <int name=`"renderScale`" value=`"$userScale`" />\n</map>|' `$f" } else { "true" }
    RunAs "f=shared_prefs/bardroid.xml; sed -i '/name=`"renderScale`"/d' `$f; $back"
  }
  Remove-Item $lock -ErrorAction SilentlyContinue
}

function MB($kb) { [math]::Round($kb / 1024) }
# (Android's resident total includes the GPU memory, which is mapped into the engine: its own heap is the rest, partly
# swapped)
$peakGl = ($samples | Measure-Object gl -Maximum).Maximum
$peakRss = ($samples | ForEach-Object { $_.rss - $_.gl } | Measure-Object -Maximum).Maximum
$peakSwap = ($samples | Measure-Object swap -Maximum).Maximum
$peakAll = ($samples | ForEach-Object { $_.rss + $_.swap } | Measure-Object -Maximum).Maximum
$minAvail = ($samples | Measure-Object avail -Minimum).Minimum
$ended = if ($gone -and $exit -match 'starting') { "Android ended the app" } elseif ($gone) { "engine ended: $($exit -replace '^\S+ ', '')" } else { "ran $Seconds s" }
$row = [pscustomobject]@{
  date = (Get-Date -Format "yyyy-MM-dd HH:mm"); label = $Label; mode = $Mode; settings = ($lines -join '; ')
  gl_peak_mb = MB $peakGl; rss_peak_mb = MB $peakRss; swap_peak_mb = MB $peakSwap; all_peak_mb = MB $peakAll
  avail_min_mb = MB $minAvail; last_frame = $frame; samples = $samples.Count; ended = $ended; broken = ($broken -join ' | ')
}
$csv = Join-Path $App "build\phone-memory.csv"
New-Item -ItemType Directory -Force -Path (Split-Path $csv) | Out-Null
$old = @(if (Test-Path $csv) { Import-Csv $csv })
@($old) + $row | Export-Csv -Path $csv -NoTypeInformation
Write-Host ("[phone-memory] {0}: GPU (GL mtrack) up to {1} MB, heap resident {2} MB, swapped {3} MB (the engine up to {4} MB); phone's available memory down to {5} MB; game frame {6}; {7}" -f
  $(if ($Label) { $Label } else { $Mode }), $row.gl_peak_mb, $row.rss_peak_mb, $row.swap_peak_mb, $row.all_peak_mb, $row.avail_min_mb, $(if ($frame) { $frame } else { "none" }), $ended)
if ($broken) { $broken | ForEach-Object { Write-Host "[phone-memory] broken: $_" } }
