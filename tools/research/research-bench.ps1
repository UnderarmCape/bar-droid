# Hail-mary research benchmarks (branch research/hail-mary, docs/research-hail-mary.md): BAR's "Benchmark BAR" on the
# phone with one research lever at a time, through tools/phone-bench.ps1 (same cooling, parsing and CSV), with the
# mainline APK installed. A lever is files under files/bar/research plus files/bar/dev-env.sh (only a MODE=bench start
# with research/lever.conf reads them, see dev-env.sh); everything is taken away again before the phone lock is let go.
#   powershell -ExecutionPolicy Bypass -File tools\research\research-bench.ps1 -Lever baseline,workers7 [-Runs 2]
#     [-Scale 100] [-Cap 0] [-NoWarm] [-Profile gadgets|widgets] [-Perf 40]   (-Perf: simpleperf on the engine, seconds)
#   ... -Train       PGO training: the run goes to the engine's own exit (no phone-bench.ps1), profiles to hailmary-work\pgo
#   ... -Cleanup     only take everything away (lever files, dev-env.sh, Game Mode); -Purge also the research folder
param([string[]]$Lever = @("baseline"), [int]$Runs = 1, [int]$Scale = 100, [int]$Cap = 0, [switch]$NoWarm, [string]$Profile = "",
  [int]$Perf = 0, [switch]$Train, [switch]$Cleanup, [switch]$Purge, [string]$Device = "192.168.1.196:5555")
$ErrorActionPreference = "Stop"
$Lever = @($Lever | ForEach-Object { $_ -split "," } | Where-Object { $_ })   # -File passes "a,b" as one string
$Here = $PSScriptRoot
$App = Split-Path -Parent (Split-Path -Parent $Here)
. (Join-Path $App "tools\toolchain.ps1")
$adb = Join-Path $TC "android-sdk\platform-tools\adb.exe"
$pkg = "com.underarmcape.bardroid"
$HM = Join-Path (Split-Path $TC) "hailmary-work"
. (Join-Path $Here "levers.ps1")
function Adb { & $adb -s $Device @args }
function AppSh([string]$script, [string[]]$a = @()) {
  $script | & $adb -s $Device exec-in run-as $pkg sh -c "tr -d '\r' > files/hm-x.sh" | Out-Null
  & $adb -s $Device exec-out run-as $pkg sh files/hm-x.sh @a
}
function PushFile([string]$local, [string]$remote) {   # binary-safe, as the app (cmd's redirection, not PowerShell's pipe)
  cmd /c "`"$adb`" -s $Device exec-in run-as $pkg sh -c `"mkdir -p `$(dirname $remote) && cat > $remote`" < `"$local`""
  if ($LASTEXITCODE) { throw "push failed: $local" }
}
function PushText([string]$text, [string]$remote) {
  # through a file, not a pipe: Windows PowerShell puts a UTF-8 BOM in front of text piped into adb; Android's sh skips
  # it, but the container's bash does not (dev-env.sh failed on line 1 and no lever was applied, 2026-10-27)
  $tmp = Join-Path $HM "tmp\push.txt"
  New-Item -ItemType Directory -Force (Split-Path $tmp) | Out-Null
  [IO.File]::WriteAllText($tmp, $text.Replace("`r", ""), (New-Object System.Text.UTF8Encoding $false))
  PushFile $tmp $remote
}

# Kailil's phone: no run while he uses it (2026-10-27 a call was in front while benchmarks kept being started). In use =
# screen on with another app in front than this app or the home screen. Waits, checking every 2 minutes.
function WaitPhoneFree {
  while ($true) {
    # off the network or adb dropped (phone away): wait for it
    cmd /c "`"$adb`" connect $Device >nul 2>nul"
    if ("$(cmd /c "`"$adb`" -s $Device get-state 2>nul")".Trim() -ne "device") {
      Write-Host "[research] phone not reachable over adb: waiting"
      Start-Sleep 120; continue
    }
    $o = cmd /c "`"$adb`" -s $Device shell `"dumpsys power | grep -m1 mWakefulness=; dumpsys activity activities | grep -m1 topResumedActivity`" 2>nul"
    $awake = "$o" -match 'mWakefulness=Awake'
    $top = if ("$o" -match 'u0 ([\w.]+)/') { $Matches[1] } else { "" }
    if (-not $awake -or $top -eq "" -or $top -match 'bardroid|launcher') { return }
    Write-Host "[research] phone in use ($top in front): waiting"
    Start-Sleep 120
  }
}
function Thermal {
  $t = Adb shell "dumpsys thermalservice"
  $status = [int](($t | Select-String 'Thermal Status: (\d)' | Select-Object -First 1).Matches[0].Groups[1].Value)
  $skin = ($t | Select-String "mValue=([\d.]+), mType=\d+, mName=SKIN," | ForEach-Object { [double]$_.Matches[0].Groups[1].Value } | Measure-Object -Maximum).Maximum
  [pscustomobject]@{ Status = $status; Skin = $skin }
}

# phone-bench.ps1's arguments: this script does the warm-up itself (hot, throttled runs: Kailil, 2026-10-27), so
# phone-bench.ps1 neither warms (-NoWarm) nor waits for a cool phone (-NoCool), whichever of the two its version has
function BenchArgs([hashtable]$a) {
  $p = (Get-Command (Join-Path $App "tools\phone-bench.ps1")).Parameters
  $a["Device"] = $Device
  foreach ($s in "NoWarm", "NoCool") { if ($p.ContainsKey($s)) { $a[$s] = $true } }
  $out = @{}; foreach ($k in $a.Keys) { if ($p.ContainsKey($k)) { $out[$k] = $a[$k] } }
  $out
}

$lock = Join-Path (Split-Path $TC) "phone-bench.lock"
function TakeLock {
  while (Test-Path $lock) {
    $holder = (Get-Content $lock -ErrorAction SilentlyContinue | Select-Object -First 1)
    if (-not $holder -or [int]$holder -eq $PID -or -not (Get-Process -Id ([int]$holder) -ErrorAction SilentlyContinue)) { break }
    Write-Host "[research] phone busy (lock held by process $holder): waiting"
    Start-Sleep 30
  }
  Set-Content -Path $lock -Value $PID -Encoding ascii
}

function Restore {
  Write-Host "[research] restoring the phone: no lever, no research dev-env.sh, Game Mode standard, saved prefs"
  AppSh @'
B=files/bar
rm -f $B/research/lever.conf $B/research/springsettings.cfg
[ -f $B/research/BYAR.lua.backup ] && mv $B/research/BYAR.lua.backup $B/LuaUI/Config/BYAR.lua
rm -rf $B/games/BAR-hailmary.sdd
if grep -q 'hail-mary research hook' $B/dev-env.sh 2>/dev/null; then
  rm -f $B/dev-env.sh
  [ -f $B/research/dev-env.orig.sh ] && mv $B/research/dev-env.orig.sh $B/dev-env.sh
fi
if [ -f $B/research/prefs.saved ]; then
  while read -r k v; do
    sed -i "/name=\"$k\"/d" shared_prefs/bardroid.xml
    [ -n "$v" ] && sed -i "s|</map>|    <int name=\"$k\" value=\"$v\" />\n</map>|" shared_prefs/bardroid.xml
  done < $B/research/prefs.saved
  rm -f $B/research/prefs.saved
fi
# Kailil's hard 30 fps lock (2026-10-27): the frame cap stays 30 when no saved value came back
grep -q 'name="frameCap"' shared_prefs/bardroid.xml || sed -i 's|</map>|    <int name="frameCap" value="30" />\n</map>|' shared_prefs/bardroid.xml
ls $B/dev-env.sh $B/research 2>&1 | tr '\n' ' '; echo
'@
  if ($Purge) { AppSh 'rm -rf files/bar/research files/hm-x.sh; echo purged' }
  Adb shell "cmd game mode standard $pkg" 2>$null | Out-Null
}

# The phone is Kailil's: no adb at all (not even reading its state) unless it has been handed over for research runs
# (hailmary-work\phone-ok, created by hand when Kailil or the main session says the phone is free, deleted when not)
if (-not (Test-Path (Join-Path $HM "phone-ok"))) { Write-Host "[research] the phone has not been handed over (no $HM\phone-ok): no phone access"; exit 2 }
WaitPhoneFree   # before the lock: a phone that is away or in use does not hold up other sessions' runs
TakeLock
try {
  & $adb connect $Device | Out-Null
  if ($Cleanup -or $Purge) { Adb shell "am force-stop $pkg"; Restore; return }
  Adb shell "am force-stop $pkg"
  # the user's prefs that phone-bench.ps1 changes, put back afterwards
  AppSh @'
mkdir -p files/bar/research
[ -f files/bar/research/prefs.saved ] || for k in renderScale frameCap fpsCap; do
  echo "$k $(grep -o "name=\"$k\" value=\"[0-9]*\"" shared_prefs/bardroid.xml | sed 's/.*value="\([0-9]*\)"/\1/')"
done > files/bar/research/prefs.saved
cat files/bar/research/prefs.saved | tr '\n' ' '; echo
'@
  # the hook, keeping a developer's own dev-env.sh
  AppSh 'B=files/bar; if [ -f $B/dev-env.sh ] && ! grep -q "hail-mary research hook" $B/dev-env.sh; then mv $B/dev-env.sh $B/research/dev-env.orig.sh; fi'
  PushText (Get-Content (Join-Path $Here "dev-env.sh") -Raw) "files/bar/dev-env.sh"
  PushText (Get-Content (Join-Path $Here "wrap-spring.sh") -Raw) "files/bar/research/wrap/spring"
  AppSh 'chmod 755 files/bar/research/wrap/spring'

  # warm-up into the throttled state (as phone-bench.ps1 does, but each run guarded by WaitPhoneFree): recorded
  # baseline runs until the skin is at 40 C and the thermal status at 1, at most 3
  if (-not $NoWarm -and -not $Train) {
    PushText "# lever baseline (warm-up)`n" "files/bar/research/lever.conf"
    for ($w = 1; $w -le 3; $w++) {
      $h = Thermal
      if ($h.Status -ge 1 -and $h.Skin -ge 40) { break }
      Write-Host "[research] warming up ($w): status $($h.Status), skin $($h.Skin) C"
      WaitPhoneFree
      $pb = Join-Path $App "tools\phone-bench.ps1"; $pbArgs = BenchArgs @{ Scale = $Scale; Cap = $Cap; Label = "hm:warmup-baseline" }
      & $pb @pbArgs
      Set-Content -Path $lock -Value $PID -Encoding ascii
    }
  }

  foreach ($name in $Lever) {
    $L = $Levers[$name]
    if (-not $L) { throw "unknown lever $name (tools/research/levers.ps1)" }
    if ($Culled -contains $name) { throw "lever $name is culled: online-safe levers only (levers.ps1 `$Culled)" }
    if ($L.Prepare) { & $L.Prepare }
    PushText ("# lever $name`n" + $L.Conf) "files/bar/research/lever.conf"
    for ($i = 1; $i -le $Runs; $i++) {
      Write-Host "[research] lever $name, run $i of $Runs"
      WaitPhoneFree
      if ($L.Before) { & $L.Before }
      $perfJob = $null
      if ($Perf -gt 0) { $perfJob = Start-PerfJob $name $Perf }
      if ($Train) {   # a PGO training run: the instrumented engine writes its profile when it exits by itself
        $n = [int](AppSh "grep -c 'spring exited with' files/logs/launcher.log")
        Adb shell "input keyevent KEYCODE_WAKEUP" | Out-Null
        Adb shell "am start -n $pkg/.LauncherActivity --es start bench" | Out-Null
        $deadline = (Get-Date).AddMinutes(20)
        while ((Get-Date) -lt $deadline -and [int](AppSh "grep -c 'spring exited with' files/logs/launcher.log") -le $n) { Start-Sleep 15 }
        Adb shell "am force-stop $pkg"
        $dir = Join-Path $HM "pgo"; New-Item -ItemType Directory -Force $dir | Out-Null
        foreach ($f in @(AppSh "ls files/bar/research/pgo/ 2>/dev/null")) {
          if (-not $f.Trim()) { continue }
          cmd /c "`"$adb`" -s $Device exec-out run-as $pkg cat files/bar/research/pgo/$($f.Trim()) > `"$dir\$($f.Trim())`""
          Write-Host "[research] PGO profile: $dir\$($f.Trim())"
        }
        AppSh "rm -rf files/bar/research/pgo; grep -E 'Sim [0-9]+ frames|spring exited' files/logs/launcher.log | tail -n 2"
        continue
      }
      $pbArgs = BenchArgs @{ Scale = $(if ($L.Scale) { $L.Scale } else { $Scale }); Cap = $(if ($L.Cap) { $L.Cap } else { $Cap }); Profile = $Profile; Label = "hm:$name$(if ($Profile) { " profile $Profile" })" }
      & (Join-Path $App "tools\phone-bench.ps1") @pbArgs
      Set-Content -Path $lock -Value $PID -Encoding ascii   # phone-bench.ps1 drops the lock on an error
      if ($perfJob) { Finish-PerfJob $perfJob $name }
      if ($L.After) { & $L.After }
      AppSh '[ -f files/bar/research/BYAR.lua.backup ] && mv files/bar/research/BYAR.lua.backup files/bar/LuaUI/Config/BYAR.lua; true' | Out-Null
      # the run's infolog (launch-bar.sh keeps a copy per run): the engine timers, thread setup
      $il = (AppSh 'ls -t files/bar/logs/infolog-*.txt | head -n 1').Trim()
      $dir = Join-Path $App "build\research-infolog"; New-Item -ItemType Directory -Force $dir | Out-Null
      if ($il) { cmd /c "`"$adb`" -s $Device exec-out run-as $pkg cat $il > `"$dir\$((Get-Date).ToString('HHmm'))-$name.txt`"" }
      AppSh 'grep -E "\[research\]|research lever" files/logs/launcher.log | tail -n 4'
    }
  }
} finally {
  try { Restore } catch { Write-Host "[research] RESTORE FAILED: $_" }
  Remove-Item $lock -ErrorAction SilentlyContinue
}
