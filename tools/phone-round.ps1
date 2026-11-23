# A round of the phone tests on the dev phone (docs/DELIVERY.md "Release candidate 0.2.0", item 2): the smoke set at
# every build train, the full set nightly. A test passes with a PASS line and no FAIL line (as engine-gate.ps1). A run
# that failed while the GPU driver's fault closed the game (DriverWatch: "GPU driver refused" in launcher.log) or
# Android's low-memory killer took the app (an exit record LOW_MEMORY after the test began) runs once more: FLAKY when
# the rerun passes, FAIL when not. A fail whose FAIL lines are all known flakes ($Quarantine) is FLAKY too.
#   powershell -ExecutionPolicy Bypass -File tools\phone-round.ps1 [-Set smoke|full] [-Build <commit>] [-Apk <file>]
#       [-Only "dock-phone-test,pad-test -Online"] [-Who train] [-List]   (-List: the tests it would run, nothing else)
# -Build: that commit built in a clean worktree (C:\Tools\BARANDROID\train\bar-droid-app: never this checkout's
# uncommitted edits, which another session may be making), installed on the dev phone, and its own tests run. The
# install is checked before every test: another session's install in between is put back (and noted). -Apk: that APK
# installed, this checkout's tests. Neither: the installed app as it is.
# The phone: devphone-lock.ps1 take <Who> for chunks of at most ~40 min of tests, freed between chunks (sessions side by
# side take turns), "am kill-all" before each test (the 8 GB phone's memory), dark after the round.
# Results: build\phone-round\<yyyyMMdd-HHmm>-<set>-<build>.txt, one line a test (PASS/FAIL/FLAKY, minutes, the first
# FAIL lines), and the summary line; the exit code is the number of tests that FAILED.
param([ValidateSet("smoke", "full")][string]$Set = "smoke", [string]$Build = "", [string]$Apk = "",
      [string[]]$Only = @(), [string]$Who = "train", [string]$Device = "", [switch]$List)
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "toolchain.ps1")
$env:BARDROID_TOOLCHAIN = $TC   # (the tests of a worktree beside this checkout find the same toolchain)
$env:ANDROID_USER_HOME = Join-Path $TC "home\.android"
$adb = Join-Path $TC "android-sdk\platform-tools\adb.exe"
if (-not $Device) { $Device = Get-PhoneDevice $adb }
if (-not $Device) { throw "no dev phone (BARDROID_DEVICE, or ..\phone-device.txt)" }
$repo = Split-Path $PSScriptRoot
$lockTool = "C:\Tools\BARANDROID\bar-droid-engine\tools\engine-sim\devphone-lock.ps1"
$trainRoot = Join-Path (Split-Path $TC) "train"
$wt = Join-Path $trainRoot "bar-droid-app"
$pkg = "com.underarmcape.bardroid"

# The sets: [script, arguments, minutes as their headers say]. Smoke: the suites that guard the release's blockers.
$Smoke = @(
  @("dock-phone-test", @(), 3), @("touchfix-phone-test", @(), 4), @("lobby-phone-test", @(), 1),
  @("pad-test", @(), 2), @("pad-test", @("-Online"), 2), @("overgame-phone-test", @(), 3),
  @("camctl-phone-test", @(), 2), @("touch-phone-test", @(), 2), @("bridge-phone-test", @(), 1.5),
  @("pregame-phone-test", @(), 2), @("remake-check", @(), 1), @("container-libs-phone-test", @(), 0.2))
# (pregame-phone-test in the smoke set: the dead faction buttons of 3104771e reached the Fold7 because no smoke test
# reached a pre-game, the in-play tour 2026-11-22; container-libs: a new container without libatomic1 ran the phone
# engine into 127, the fresh-install run the same night)
$Nightly = @(
  @("factory-preset-test", @(), 4), @("types-phone-test", @(), 3), @("attack-ping-test", @(), 2),
  @("walls-phone-test", @(), 3), @("stats-phone-test", @(), 2), @("settings-phone-test", @(), 2),
  @("replay-phone-test", @(), 2), @("lobbychat-phone-test", @(), 1.5), @("buildbar-phone-test", @(), 2),
  @("driverwatch-phone-test", @(), 4), @("x11-probe", @(), 0.5), @("retreat-phone-test", @(), 7),
  @("pad-test", @("-Dgun"), 2), @("pad-test", @("-Share"), 2), @("pad-test", @("-Chat"), 2),
  @("fp-save-test", @(), 1.5), @("pace-test", @(), 2), @("dgun-speed-test", @(), 3),
  @("retreat-phone-test", @("-Commander"), 3), @("exitrecord-phone-test", @(), 2), @("menusession-phone-test", @(), 5))
# Tests that measure rather than check: no PASS line; their end line is the pass, with no FAIL (the first full set,
# 2026-11-22, read both as "no PASS line": retreat every kind fell back, the D-gun walk 98 % of a plain move's speed)
$DoneIsPass = @{ "retreat-phone-test" = '\[retreattest\] done'; "dgun-speed-test" = '\[dguntest\] done'
  "x11-probe" = '\[x11probe\] path .*: connected' }   # (x11-probe: the app's own socket answers ...)
$FailToo = @{ "x11-probe" = '\[x11probe\] (abstract .*: connected|the X server is not running)' }   # (... and no other)
# Tests that look at a running game: the launcher's skirmish started first and its engine up ("the X server is not
# running", the same night)
$NeedsGame = @("x11-probe")
# Known flakes: a fail whose every FAIL line matches is FLAKY, not FAIL (each with the day it was seen).
$Quarantine = @{
  # (none now: dock-phone-test's 'FAIL Area Mex armed', "0 mex orders" once on 2026-11-20 05:50, lifted 2026-11-23 after
  # ~20 passing runs and 3 of 3 that morning on ccb4f0cc, with f6eeee24's circle case drawn every time)
}

$tests = if ($Set -eq "full") { $Smoke + $Nightly } else { $Smoke }
$only = @($Only | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
if ($only.Count) { $tests = @($tests | Where-Object { $only -contains (("$($_[0]) " + ($_[1] -join ' ')).Trim()) -or $only -contains $_[0] }) }
if (-not $tests.Count) { throw "no test of the $Set set matches -Only $($only -join ', ')" }
if ($List) { $tests | ForEach-Object { "{0} ({1} min)" -f ("$($_[0]) " + ($_[1] -join ' ')).Trim(), $_[2] }; return }

function Git([string]$dir, [string]$gitArgs) {
  $out = cmd /c "call `"$repo\scripts\env.bat`" >nul && git -C `"$dir`" $gitArgs 2>&1"
  if ($LASTEXITCODE) { throw "git $gitArgs (in $dir): $out" }
  $out
}
function Phone([string]$cmd) {
  $eap = $ErrorActionPreference; $ErrorActionPreference = "Continue"
  try { (& $adb -s $Device shell $cmd 2>&1 | ForEach-Object { "$_" }) } finally { $ErrorActionPreference = $eap }
}
function InApp([string]$cmd) {
  $eap = $ErrorActionPreference; $ErrorActionPreference = "Continue"
  try { (& $adb -s $Device exec-out run-as $pkg sh -c "$cmd" 2>&1 | ForEach-Object { "$_" }) } finally { $ErrorActionPreference = $eap }
}
function Installed { "$(Phone "dumpsys package $pkg | grep -m1 lastUpdateTime")".Trim() }
function PhoneNow { "$(Phone "date '+%Y-%m-%d %H:%M:%S'")".Trim() }
function FaultCount { [int]("0" + "$(InApp "cat files/logs/launcher.old.log files/logs/launcher.log 2>/dev/null | grep -a -c 'GPU driver refused'")".Trim()) }
function LowMemorySince([string]$since) {   # (Android's exit records, newest first: one LOW_MEMORY kill after $since)
  $ts = ""
  foreach ($l in (Phone "dumpsys activity exit-info $pkg")) {
    if ($l -match 'timestamp=(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d)') { $ts = $Matches[1] }
    elseif ($l -match 'reason=3 \(LOW_MEMORY\)' -and $ts -and $ts -ge $since) { return $true }
  }
  $false
}
$held = $false
function Take { if (-not $script:held) { & powershell -ExecutionPolicy Bypass -File $lockTool take $Who -Minutes 50 | Out-Host; $script:held = $true; $script:heldSince = Get-Date } }
function Free { if ($script:held) { & powershell -ExecutionPolicy Bypass -File $lockTool free $Who | Out-Host; $script:held = $false } }

# ------------------------------------------------------------------------------------------------ the train's build
$label = "installed"
$testsDir = $PSScriptRoot
if ($Build) {
  $sha = "$(Git $repo "rev-parse --short=8 $Build")".Trim()
  $label = $sha
  [void][IO.Directory]::CreateDirectory($trainRoot)
  if (-not (Test-Path (Join-Path $wt ".git"))) { Git $repo "worktree add --detach `"$wt`" $sha" | Out-Host }
  else { Git $wt "checkout --detach --force $sha" | Out-Host; Git $wt "clean -fdq" | Out-Host }
  Copy-Item (Join-Path $repo "local.properties") (Join-Path $wt "local.properties") -Force
  # (termux-x11 is fetched and patched, not tracked: copied from this checkout, again when the patches changed)
  $stamp = Join-Path $wt "termux-x11\.train-patches"
  $patches = "$(Git $wt "log -1 --format=%H -- patches")".Trim()
  if (-not (Test-Path (Join-Path $wt "termux-x11\lorie\build.gradle")) -or -not (Test-Path $stamp) -or ([IO.File]::ReadAllText($stamp).Trim() -ne $patches)) {
    & robocopy (Join-Path $repo "termux-x11") (Join-Path $wt "termux-x11") /MIR /XD build .cxx .gradle /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "robocopy of termux-x11 failed ($LASTEXITCODE)" }
    [IO.File]::WriteAllText($stamp, $patches)
  }
  $Apk = Join-Path $trainRoot "apk\bar-droid-train-$sha.apk"
  if (Test-Path $Apk) { "[round] $sha built before: $Apk" } else {   # (a rerun of the same train)
    "[round] building $sha in $wt"
    $buildLog = Join-Path $trainRoot "build-$sha.log"
    cmd /c "set `"BARDROID_TOOLCHAIN=$TC`"&& set `"BARDROID_OUT=$trainRoot`"&& set BARDROID_NOPAUSE=1&& call `"$wt\Build APK.bat`" phone > `"$buildLog`" 2>&1"
    if ($LASTEXITCODE) { Get-Content $buildLog -Tail 30 | Out-Host; throw "the train's build of $sha failed: $buildLog" }
    Copy-Item (Join-Path $trainRoot "apk\bar-droid-phone-debug.apk") $Apk -Force
  }
  $testsDir = Join-Path $wt "tools"
} elseif ($Apk) { $label = [IO.Path]::GetFileNameWithoutExtension($Apk) }

$results = New-Object System.Collections.Generic.List[string]
$failed = 0
$outDir = Join-Path $repo "build\phone-round"
[void][IO.Directory]::CreateDirectory($outDir)
$summary = Join-Path $outDir ("{0}-{1}-{2}.txt" -f (Get-Date -Format 'yyyyMMdd-HHmm'), $Set, $label)
function Note([string]$line) { $line; $script:results.Add($line); [IO.File]::WriteAllText($script:summary, (($script:results -join "`n") + "`n"), (New-Object Text.UTF8Encoding $false)) }
function Install {
  Phone "am force-stop $pkg" | Out-Null
  $eap = $ErrorActionPreference; $ErrorActionPreference = "Continue"
  try { $r = & $adb -s $Device install -r $Apk 2>&1 | ForEach-Object { "$_" } } finally { $ErrorActionPreference = $eap }
  if (-not ($r -match 'Success')) { throw "install of $Apk failed: $($r -join ' ')" }
  $script:installed = Installed
}

function Run-One($t) {
  $name = ("$($t[0]) " + ($t[1] -join ' ')).Trim()
  Phone "am kill-all" | Out-Null
  $since = PhoneNow
  $faults = FaultCount
  $start = Get-Date
  if ($NeedsGame -contains $t[0]) {
    Phone "input keyevent KEYCODE_WAKEUP; am start -n $pkg/.LauncherActivity --es start skirmish" | Out-Null
    $until = (Get-Date).AddMinutes(3)
    while ((Get-Date) -lt $until -and -not "$(Phone 'pidof spring')".Trim()) { Start-Sleep 5 }
    Start-Sleep 30   # (the engine's window and the app's X server up, the game loading)
  }
  $eap = $ErrorActionPreference; $ErrorActionPreference = "Continue"
  # (a test's stderr line, adb's "1 file pushed", is a NativeCommandError under "Stop"; engine-gate.ps1)
  try { $out = & powershell -ExecutionPolicy Bypass -File (Join-Path $testsDir "$($t[0]).ps1") @($t[1]) 2>&1 | ForEach-Object { "$_" } }
  catch { $out = @("FAIL $name stopped: $_") } finally { $ErrorActionPreference = $eap }
  $out | Out-Host
  # (case-sensitive: bridge-phone-test's "PASS ... refused, no file (failed)" is a pass; -match ignores case)
  $fails = @($out | Where-Object { $_ -cmatch '\bFAIL(ED)?\b' -or ($FailToo[$t[0]] -and $_ -match $FailToo[$t[0]]) })
  $done = $DoneIsPass[$t[0]]
  $pass = ($fails.Count -eq 0) -and (($out | Where-Object { $_ -cmatch '\bPASS\b' }) -or ($done -and ($out -match $done)))
  if ($NeedsGame -contains $t[0]) { Phone "am force-stop $pkg" | Out-Null }
  $why = ""
  if (-not $pass) {
    if ((FaultCount) -gt $faults -or ($out -match "GPU driver's rare fault")) { $why = "the GPU driver's fault" }
    elseif (LowMemorySince $since) { $why = "a low-memory kill" }
  }
  [pscustomobject]@{ Name = $name; Pass = [bool]$pass; Fails = $fails; Why = $why; Min = ((Get-Date) - $start).TotalMinutes }
}

Note ("phone round, {0} set, {1}, on the dev phone, {2}" -f $Set, $label, (Get-Date -Format 'yyyy-MM-dd HH:mm'))
try {
  $chunk = 0.0
  foreach ($t in $tests) {
    if ($held -and ($chunk + $t[2] -gt 40)) { Free; Start-Sleep 20; $chunk = 0.0 }   # (the others' turn)
    Take
    if ($Apk -and -not $script:installed) { Install }
    elseif ($Apk -and (Installed) -ne $script:installed) { Note "NOTE another install on the phone before $($t[0]): the round's APK put back"; Install }
    $r = Run-One $t
    $state = "PASS"; $detail = ""
    if (-not $r.Pass) {
      $q = if ($Quarantine.ContainsKey($t[0])) { @($Quarantine[$t[0]]) } else { @() }
      $known = $q.Count -and $r.Fails.Count -and -not @($r.Fails | Where-Object { $f = $_; -not ($q | Where-Object { $f -match $_ }) }).Count
      if ($r.Why) {
        $again = Run-One $t
        $state = if ($again.Pass) { "FLAKY" } else { "FAIL" }
        $detail = "$($r.Why), run again: $(if ($again.Pass) { 'PASS' } else { (($again.Fails | Select-Object -First 3) -join ' / ') + $(if ($again.Why) { " ($($again.Why))" }) })"
        $r.Min += $again.Min
      } elseif ($known) { $state = "FLAKY"; $detail = "quarantined: " + (($r.Fails | Select-Object -First 2) -join ' / ') }
      else { $state = "FAIL"; $detail = if ($r.Fails.Count) { ($r.Fails | Select-Object -First 3) -join ' / ' } else { "no PASS line" } }
    }
    if ($state -eq "FAIL") { $failed++ }
    $chunk += $r.Min
    Note ("{0,-5} {1} ({2:N1} min){3}" -f $state, $r.Name, $r.Min, $(if ($detail) { ": $detail" } else { "" }))
  }
} finally {
  Free
  & powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "devphone.ps1") dark 2>&1 | Out-Null
}
Note ("phone round {0}, {1}: {2}" -f $Set, $label, $(if ($failed -eq 0) { "ALL PASS (FLAKY counted as passing)" } else { "$failed FAILED" }))
"results: $summary"
exit $failed
