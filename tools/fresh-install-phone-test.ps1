# The first run end to end on the dev phone (RC 0.2.0 item 9, docs/DELIVERY.md): the app's data cleared (pm clear) as a
# new player's phone, then the launcher's "start skirmish" (a developer build: the install, BAR's update and the first
# game, as Play does) timed from the start to the installed status and to the game's first simulated frame, and the
# space the app takes measured after. The player's things on the dev phone are backed up to the laptop first and put
# back after, the run ending as it may: replays (demos), saves, maps, widget settings (LuaUI/Config), springsettings.cfg,
# the launcher's settings (shared_prefs) and the app's runtime permissions (the microphone's never touched: it stays as
# the phone has it). One line a step in build\phone-round\<stamp>-fresh.txt.
#   powershell -ExecutionPolicy Bypass -File tools\fresh-install-phone-test.ps1 [-Minutes 75] [-Device <serial>]
# The dev phone only (never the Fold7: its player's data would go); held by devphone-lock.ps1 for the whole run (the
# download cannot be cut into chunks). The backup stays in ..\toolchain\tmp\fresh-backup\<stamp> until removed by hand.
param([int]$Minutes = 75, [string]$Device = "", [string]$Who = "fresh")
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "toolchain.ps1")
$env:ANDROID_USER_HOME = Join-Path $TC "home\.android"
$adb = Join-Path $TC "android-sdk\platform-tools\adb.exe"
if (-not $Device) { $Device = Get-PhoneDevice $adb }
if (-not $Device) { throw "no dev phone (BARDROID_DEVICE, or ..\phone-device.txt)" }
$pkg = "com.underarmcape.bardroid"
$lockTool = "C:\Tools\BARANDROID\bar-droid-engine\tools\engine-sim\devphone-lock.ps1"
$stamp = Get-Date -Format "yyyyMMdd-HHmm"
$back = Join-Path $TC "tmp\fresh-backup\$stamp"
$tarFile = Join-Path $back "app-data.tar"
$resultDir = Join-Path (Split-Path -Parent $PSScriptRoot) "build\phone-round"
New-Item -ItemType Directory -Force $back, $resultDir | Out-Null
$result = Join-Path $resultDir "$stamp-fresh.txt"
$keep = @("files/bar/demos", "files/bar/Saves", "files/bar/maps", "files/bar/LuaUI/Config", "files/bar/springsettings.cfg",
  "shared_prefs")

function Say([string]$line) { Write-Host $line; Add-Content -Encoding utf8 $result $line }
function InApp([string]$command) { & $adb -s $Device exec-out run-as $pkg sh -c $command }
function Granted() {   # the app's runtime permissions granted now (dumpsys package: "<name>: granted=true")
  $lines = & $adb -s $Device shell dumpsys package $pkg
  $inRuntime = $false
  foreach ($l in $lines) {
    if ($l -match 'runtime permissions:') { $inRuntime = $true; continue }
    if ($inRuntime -and $l -match '^\s+([\w.]+): granted=true') { $Matches[1] }
    elseif ($inRuntime -and $l -notmatch '^\s+[\w.]+: granted=') { $inRuntime = $false }
  }
}
function Kb([string]$path) { $v = "$(InApp "du -sk $path 2>/dev/null | tail -1")".Trim(); if ($v -match '^(\d+)') { [long]$Matches[1] } else { 0 } }

$taken = & $lockTool take $Who -Minutes $Minutes
if ("$taken" -notmatch '^taken') { throw "the dev phone is busy: $taken" }
Say "fresh install on the dev phone, $stamp (the backup: $back)"
$restored = $false
try {
  & $adb -s $Device shell am force-stop $pkg
  $before = [math]::Round((Kb "files") / 1MB, 2)
  # 1. the backup: a tar of what exists (binary through cmd's redirection; PowerShell's would re-encode it)
  $have = @($keep | Where-Object { "$(InApp "[ -e $_ ] && echo yes")".Trim() -eq "yes" })
  cmd /c "$adb -s $Device exec-out run-as $pkg tar -cf - $($have -join ' ') > $tarFile"   # (no spaces in these paths)
  $entries = @(& tar.exe -tf $tarFile 2>$null).Count
  $mb = [math]::Round((Get-Item $tarFile).Length / 1MB, 1)
  if ($entries -lt 1) { throw "the backup is empty ($tarFile): nothing cleared" }
  $perms = @(Granted)
  Set-Content -Encoding utf8 (Join-Path $back "permissions.txt") $perms
  Say "backup: $($have -join ', ') - $entries entries, $mb MB; permissions granted: $($perms -join ', '); the app's data before: $before GB"

  # 2. a new player's phone: the app's data gone, then the launcher's start (install, update, first game)
  & $adb -s $Device shell pm clear $pkg | Out-Null
  Set-PhoneAwake $adb $Device
  $t0 = Get-Date
  & $adb -s $Device shell am start -n "$pkg/.LauncherActivity" --es start skirmish | Out-Null
  $installedAt = $null; $frameAt = $null; $failed = $null; $lastStatus = ""
  $until = $t0.AddMinutes($Minutes - 10)
  while ((Get-Date) -lt $until) {
    Start-Sleep 5
    $log = "$(InApp "grep -a '\[svc\]' files/logs/launcher.log 2>/dev/null | tail -3")"
    $status = ($log -split "`n" | Where-Object { $_ } | Select-Object -Last 1)
    if ($status -and $status -ne $lastStatus) { Write-Host ("  {0:mm\:ss} {1}" -f ((Get-Date) - $t0), $status.Trim()); $lastStatus = $status }
    if (-not $installedAt -and "$(InApp "grep -a -c '\[svc\] installed' files/logs/launcher.log 2>/dev/null")".Trim() -ne "0") {
      $installedAt = Get-Date
    }
    $fail = "$(InApp "grep -a -E '\[svc\] (install failed|launch failed|no map|X server did not|virgl server did not)' files/logs/launcher.log 2>/dev/null | tail -1")".Trim()
    if ($fail) { $failed = $fail; break }
    if ("$(InApp "grep -a -m1 -E '\[f=0*[1-9][0-9]*\]' files/bar/infolog.txt 2>/dev/null")".Trim()) { $frameAt = Get-Date; break }
  }
  $installMin = if ($installedAt) { [math]::Round(($installedAt - $t0).TotalMinutes, 1) } else { $null }
  $gameMin = if ($frameAt) { [math]::Round(($frameAt - $t0).TotalMinutes, 1) } else { $null }
  if ($frameAt) { Start-Sleep 20 }   # (the first game's own downloads and caches settled before the sizes)
  $files = [math]::Round((Kb "files") / 1MB, 2)
  $rootfs = [math]::Round((Kb "files/rootfs") / 1MB, 2)
  $bar = [math]::Round((Kb "files/bar") / 1MB, 2)
  $ext = "$(& $adb -s $Device shell "du -sk /sdcard/Android/data/$pkg 2>/dev/null | tail -1")".Trim()
  $extGb = if ($ext -match '^(\d+)') { [math]::Round([long]$Matches[1] / 1MB, 2) } else { "?" }
  $apkKb = "$(& $adb -s $Device shell "du -sk `$(dirname `$(pm path $pkg | head -1 | cut -d: -f2)) 2>/dev/null | tail -1")".Trim()
  $apkMb = if ($apkKb -match '^(\d+)') { [math]::Round([long]$Matches[1] / 1KB, 0) } else { "?" }
  if ($failed) { Say "FAIL the first run: $failed" }
  elseif (-not $frameAt) { Say "FAIL the first run: no game frame within $($Minutes - 10) min (last: $lastStatus)" }
  else { Say "PASS the first run: installed after $installMin min, the first game's first frame after $gameMin min" }
  Say "space after: the app's data $files GB (container $rootfs GB, BAR $bar GB), shared storage $extGb GB, the APK $apkMb MB"
} finally {
  # 3. the player's things back, whatever happened above
  try {
    & $adb -s $Device shell am force-stop $pkg
    if (Test-Path $tarFile) {
      & $adb -s $Device push $tarFile /data/local/tmp/bardroid-fresh.tar | Out-Null
      InApp "rm -rf files/bar/demos files/bar/Saves files/bar/maps files/bar/LuaUI/Config; mkdir -p files/bar/LuaUI; tar -xf /data/local/tmp/bardroid-fresh.tar && echo restored" |
        ForEach-Object { if ($_ -eq "restored") { $script:restored = $true } }
      & $adb -s $Device shell rm -f /data/local/tmp/bardroid-fresh.tar
    }
    $now = @(Granted)
    foreach ($p in (Get-Content (Join-Path $back "permissions.txt") -ErrorAction SilentlyContinue)) {
      if ($p -and $p -ne "android.permission.RECORD_AUDIO" -and $now -notcontains $p) { & $adb -s $Device shell pm grant $pkg $p 2>$null }
    }
    Say $(if ($restored) { "put back: the backup unpacked, the permissions as before (the microphone's untouched)" } else { "FAIL put back: the backup did not unpack ($tarFile)" })
  } finally {
    & $adb -s $Device shell am force-stop $pkg
    & (Join-Path $PSScriptRoot "devphone.ps1") dark | Out-Null
    & $lockTool free $Who | Out-Null
  }
}
Say "results: $result"
if (-not $restored -or (Get-Content $result | Select-String -CaseSensitive '\bFAIL\b')) { exit 1 }
