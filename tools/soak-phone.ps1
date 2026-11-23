# The overnight soak on the dev phone (RC 0.2.0 item 10, docs/DELIVERY.md): long games at 1x, one chunk of at most
# 40 minutes each (the dev phone's lock freed 20 s between chunks, as tools\phone-round.ps1). Two kinds of chunk:
# - a server replay through the launcher's bench mode (files/bar/.bardroid-bench-replay "0 <seconds> <replay>":
#   bardroid_bench.lua plays it and quits after), for each replay in files/bar/demos the phone can play as it is: its
#   engine the phone's, its game the one installed (skirmish.txt's), its map in maps/ (tools/demo-info.py reads them; the
#   bench mode downloads nothing, and the container's downloads need the app's own process: adb's run-as has no network;
#   tools\soak-fetch.ps1 copies BAR's newest online games of the phone's engine and game in, with their maps);
# - then, to fill the chunks, a long game of BARb against BARb that the phone watches as a spectator: the launcher's
#   skirmish (its map, BAR's game as installed), the start script made AI against AI by a dev-env.sh for the run
#   (removed after; a developer's own put back), until one side's commander dies or the chunk's time is up.
# Each chunk counts, from launcher.log and Android's exit records: the GPU driver's refusals (DriverWatch), low-memory
# kills, the engine's error exits, the thermal status's steps (PerfLog's "[perf]" lines once a minute), the frame rate
# ("[bardroid-perf]" in the infolog) and which engine played. One line a chunk in build\phone-round\<stamp>-soak.txt; a
# chunk ended by a fault not in that list, or the phone engine set aside, is a FAIL.
#   powershell -ExecutionPolicy Bypass -File tools\soak-phone.ps1 [-Chunks 6] [-ChunkMinutes 40] [-Replays "a.sdfz"] [-NoReplays]
# The dev phone only.
param([int]$Chunks = 6, [int]$ChunkMinutes = 40, [string[]]$Replays = @(), [switch]$NoReplays, [string]$Device = "",
  [string]$Who = "soak")
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "toolchain.ps1")
$env:ANDROID_USER_HOME = Join-Path $TC "home\.android"
$adb = Join-Path $TC "android-sdk\platform-tools\adb.exe"
if (-not $Device) { $Device = Get-PhoneDevice $adb }
if (-not $Device) { throw "no dev phone (BARDROID_DEVICE, or ..\phone-device.txt)" }
$pkg = "com.underarmcape.bardroid"
$lockTool = "C:\Tools\BARANDROID\bar-droid-engine\tools\engine-sim\devphone-lock.ps1"
$ChunkMinutes = [math]::Min($ChunkMinutes, 40)
$resultDir = Join-Path (Split-Path -Parent $PSScriptRoot) "build\phone-round"
New-Item -ItemType Directory -Force $resultDir | Out-Null
$result = Join-Path $resultDir "$(Get-Date -Format 'yyyyMMdd-HHmm')-soak.txt"

function Say([string]$line) { Write-Host $line; Add-Content -Encoding utf8 $result $line }
function InApp([string]$command) { & $adb -s $Device exec-out run-as $pkg sh -c $command }
function Lines([string]$file) { $n = 0; [void][int]::TryParse("$(InApp "wc -l < $file 2>/dev/null")".Trim(), [ref]$n); $n }
# launcher.log's lines since the chunk's start ($from lines then, its first line $head0), [-E filter]: the app puts a
# full log aside as launcher.old.log at its start and every 2000 lines, so a chunk's start can be in that one (2026-11-23
# chunk 4 read a log begun mid-game: "official engine, the AI start script not applied" for a game the phone engine
# played as BARb against BARb)
function SinceStart([string]$filter = "") {
  $rotated = "$(InApp "head -1 files/logs/launcher.log 2>/dev/null")".Trim() -ne $head0
  $cmd = if ($rotated) { "{ tail -n +$($from + 1) files/logs/launcher.old.log; cat files/logs/launcher.log; }" } else { "tail -n +$($from + 1) files/logs/launcher.log" }
  if ($filter) { $cmd += " | grep -a -E '$filter'" }
  @(InApp "$cmd 2>/dev/null")
}
function LowMemorySince([string]$since) {   # (Android's exit records, newest first; as tools\phone-round.ps1)
  $ts = ""; $n = 0
  foreach ($l in (& $adb -s $Device shell dumpsys activity exit-info $pkg)) {
    if ($l -match 'timestamp=(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d)') { $ts = $Matches[1] }
    elseif ($l -match 'reason=3 \(LOW_MEMORY\)' -and $ts -and $ts -ge $since) { $n++ }
  }
  $n
}

# ---- what the phone can play as it is ----------------------------------------------------------------------------
$ver = @(InApp "ls -1 files/bar/engine" | ForEach-Object { "$_".Trim() } | Where-Object { $_ -match '^recoil_([\d.]+)$' } |
  ForEach-Object { $_ -replace '^recoil_', '' }) | Select-Object -Last 1
$game = "$(InApp "sed -n 's/^[[:space:]]*GameType=\(.*\);/\1/p' files/bar/skirmish.txt | head -1")".Trim()
$maps = @(InApp "ls -1 files/bar/maps" | ForEach-Object { "$_".Trim().ToLower() })
$skirmishMap = "$(InApp "sed -n 's/^[[:space:]]*MapName=\(.*\);/\1/p' files/bar/skirmish.txt | head -1")".Trim()
$playable = New-Object System.Collections.Generic.List[string]
if (-not $NoReplays) {
  if (-not $Replays) { $Replays = @(InApp "cd files/bar/demos 2>/dev/null && ls -1S *.sdfz 2>/dev/null | head -20" | ForEach-Object { "$_".Trim() } | Where-Object { $_ }) }
  $py = Join-Path $TC "android-sdk\ndk\29.0.14206865\toolchains\llvm\prebuilt\windows-x86_64\python3\python.exe"
  $local = Join-Path $TC "tmp\soak-replay.sdfz"
  foreach ($r in $Replays) {
    # (through a copy with a plain name: adb split a replay's name at its spaces, BAR's own names have them)
    InApp "cp 'files/bar/demos/$r' files/bar/.soak-pull.sdfz" | Out-Null
    cmd /c "$adb -s $Device exec-out run-as $pkg cat files/bar/.soak-pull.sdfz > `"$local`""
    $kv = @{}; foreach ($l in (& $py -I (Join-Path $PSScriptRoot "demo-info.py") $local)) { if ($l -match '^(\w+)=(.*)$') { $kv[$Matches[1]] = $Matches[2] } }
    $mapFile = ($kv.map -replace ' ', '_').ToLower()
    $why = if ($kv.error) { $kv.error } elseif ($kv.engine -notlike "$ver*") { "engine $($kv.engine), the phone's $ver" } `
      elseif ($kv.game -ne $game) { "game $($kv.game), the phone's $game" } `
      elseif (-not ($maps | Where-Object { $_ -like "$mapFile.sd?" })) { "map $($kv.map) not on the phone" } `
      elseif ([int]$kv.seconds -lt 900) { "$($kv.seconds) s long" } else { "" }
    if ($why) { Write-Host "  $r skipped: $why" } else { $playable.Add($r) }
  }
  InApp "rm -f files/bar/.soak-pull.sdfz" | Out-Null
  Remove-Item -Force $local -ErrorAction SilentlyContinue
}
$plan = @(for ($i = 0; $i -lt $Chunks; $i++) { if ($i -lt $playable.Count) { $playable[$i] } else { "ai" } })
Say ("soak on the dev phone: {0} chunks of {1} min at 1x (engine {2}, {3}): {4}" -f $Chunks, $ChunkMinutes, $ver, $game,
  (($plan | ForEach-Object { if ($_ -eq "ai") { "BARb against BARb on $skirmishMap, watched" } else { $_ } }) -join ' | '))

# A dev-env.sh for the AI chunks: launch-bar.sh runs it (a developer's build) just before the engine starts the skirmish
$devEnv = Join-Path $TC "tmp\soak-dev-env.sh"
[IO.File]::WriteAllText($devEnv, ((@'
# tools/soak-phone.ps1's (removed after its run): the skirmish as BARb against BARb, the phone a spectator
f="$BAR/skirmish.txt"
if [ -f "$f" ]; then
  map=$(sed -n 's/^[[:space:]]*MapName=\(.*\);/\1/p' "$f" | head -1)
  game=$(sed -n 's/^[[:space:]]*GameType=\(.*\);/\1/p' "$f" | head -1)
  cat > "$f" <<EOF
// tools/soak-phone.ps1: BARb against BARb, the phone a spectator
[GAME]
{
	MapName=$map;
	GameType=$game;
	GameStartDelay=3;
	StartPosType=1;
	RecordDemo=1;
	MyPlayerName=Phone;
	IsHost=1;
	NumPlayers=1;
	NumUsers=1;
	HostIP=127.0.0.1;
	HostPort=0;
	NoHelperAIs=0;
	[MODOPTIONS]
	{
		deathmode=com;
	}
	[ALLYTEAM0]
	{
		NumAllies=0;
	}
	[ALLYTEAM1]
	{
		NumAllies=0;
	}
	[TEAM0]
	{
		Side=Armada;
		Handicap=0;
		AllyTeam=0;
		TeamLeader=0;
	}
	[TEAM1]
	{
		Side=Cortex;
		Handicap=0;
		AllyTeam=1;
		TeamLeader=0;
	}
	[AI0]
	{
		Host=0;
		IsFromDemo=0;
		Name=BARb(1);
		ShortName=BARb;
		Team=0;
		Version=stable;
	}
	[AI1]
	{
		Host=0;
		IsFromDemo=0;
		Name=BARb(2);
		ShortName=BARb;
		Team=1;
		Version=stable;
	}
	[PLAYER0]
	{
		IsFromDemo=0;
		Name=Phone;
		Spectator=1;
		Rank=0;
	}
}
EOF
  log "soak: the skirmish as BARb against BARb on $map, watched"
fi
'@) -replace "`r`n", "`n"))
# (and a widget that says the game's end in the infolog: the engine writes no line of its own for it)
$overWidget = Join-Path $TC "tmp\soak_gameover.lua"
[IO.File]::WriteAllText($overWidget, ("function widget:GetInfo()`n`treturn { name = `"soak game over`", desc = `"tools/soak-phone.ps1's (removed after its run)`", layer = 0, enabled = true }`nend`n" +
  "function widget:GameOver()`n`tSpring.Echo(`"[soak] game over`")`nend`n"))
$hadDevEnv = "$(InApp "[ -f files/bar/dev-env.sh ] && echo yes")".Trim() -eq "yes"
if ($hadDevEnv) { InApp "cp files/bar/dev-env.sh files/bar/.soak-dev-env.sh.keep" | Out-Null }

$total = @{ fault = 0; lowmem = 0; errors = 0; fails = 0 }
try {
for ($i = 0; $i -lt $Chunks; $i++) {
  $kind = $plan[$i]
  $bat0 = Wait-PhoneCharge $adb $Device   # (the battery: a night of chunks emptied it, 2026-11-23 07:10)
  $taken = & $lockTool take $Who -Minutes ($ChunkMinutes + 5)
  if ("$(& $adb -s $Device get-state 2>$null)".Trim() -ne "device") {
    $total.fails++; Say "FAIL  chunk $($i + 1): the phone not on adb, $(Get-Date -Format 'HH:mm'): the soak stopped"
    & $lockTool free $Who | Out-Null; break
  }
  if ("$taken" -notmatch '^taken') { Say "chunk $($i + 1): the dev phone busy ($taken): waiting 5 min"; Start-Sleep 300; $i--; continue }
  try {
    & $adb -s $Device shell am force-stop $pkg
    $since = "$(& $adb -s $Device shell "date '+%Y-%m-%d %H:%M:%S'")".Trim()   # (one string: adb split the format at its space)
    $from = Lines "files/logs/launcher.log"
    $head0 = "$(InApp "head -1 files/logs/launcher.log 2>/dev/null")".Trim()
    InApp "rm -f files/bar/infolog.txt files/bar/.bardroid-bench-settings files/bar/.bardroid-bench-replay" | Out-Null
    if ($kind -eq "ai") {
      Send-AppFile $adb $devEnv "files/bar/dev-env.sh" $Device
      InApp "mkdir -p files/bar/LuaUI/Widgets" | Out-Null
      Send-AppFile $adb $overWidget "files/bar/LuaUI/Widgets/soak_gameover.lua" $Device
      $start = "skirmish"; $label = "BARb against BARb"
    } else {
      InApp "rm -f files/bar/dev-env.sh; echo '0 $($ChunkMinutes * 60 - 120) $kind' > files/bar/.bardroid-bench-replay" | Out-Null
      # (background apps closed first, as tools\engine-gate.ps1: an 8v8 replay on the 8 GB dev phone was taken by
      # Android's low-memory killer while loading with either engine, and played to its end after "am kill-all")
      & $adb -s $Device shell "am kill-all" | Out-Null
      $start = "bench"; $label = $kind
    }
    & $adb -s $Device shell "input keyevent KEYCODE_WAKEUP" | Out-Null
    & $adb -s $Device shell "am start -n $pkg/.LauncherActivity --es start $start" | Out-Null
    $t0 = Get-Date; $ended = "time"; $gone = $false
    while (((Get-Date) - $t0).TotalMinutes -lt $ChunkMinutes) {
      Start-Sleep 20
      # (the phone gone from adb: every read below comes back empty, and an empty count once read as "replay done",
      # 2026-11-23 07:12: two chunks written down as PASS with no engine, fps or thermal line)
      if ("$(& $adb -s $Device get-state 2>$null)".Trim() -ne "device") { $ended = "the phone gone from adb"; $gone = $true; break }
      $new = "$(@(SinceStart 'engine exited|game ended|lack of memory|no map') | Select-Object -Last 1)".Trim()
      if ("$(InApp "grep -a -c 'replaybench\] done' files/bar/infolog.txt 2>/dev/null")".Trim() -match '^[1-9]') { $ended = "replay done"; break }
      if ($kind -eq "ai" -and "$(InApp "grep -a -c '\[soak\] game over' files/bar/infolog.txt 2>/dev/null")".Trim() -match '^[1-9]') { $ended = "game over"; break }
      if ($new -match 'lack of memory') { $ended = "Android ended the app for memory"; break }
      if ($new -match 'engine exited \(([1-9]\d*)\)|game ended with an error|no map') { $ended = "the engine's error exit: $new"; break }
      if (-not "$(& $adb -s $Device shell pidof $pkg)".Trim()) { $ended = "the app gone"; break }
    }
    $minutes = [math]::Round(((Get-Date) - $t0).TotalMinutes, 1)
    if ($gone) {   # (nothing to read: the chunk a FAIL, the soak over)
      $total.fails++
      Say ("FAIL  chunk {0} ({1}): the phone gone from adb after {2} min, {3} (unplugged, or the phone reset: its uptime says which once back)" -f
        ($i + 1), $label, $minutes, (Get-Date -Format 'HH:mm'))
      break
    }
    $log = @(SinceStart)
    # (which engine played: the phone engine unless launch-bar.sh set it aside, which is a fault of its own)
    $setAside = @($log | Where-Object { $_ -match '\[launch\] !!! phone engine' }).Count
    $engine = if ($setAside) { "the phone engine SET ASIDE" } elseif (@($log | Where-Object { $_ -match '\[launch\] phone engine:' })) { "phone engine" } else { "official engine" }
    $aiOn = $kind -ne "ai" -or @($log | Where-Object { $_ -match 'soak: the skirmish as BARb against BARb' }).Count -gt 0
    $faults = @($log | Where-Object { $_ -match 'GPU driver refused' }).Count
    $errors = @($log | Where-Object { $_ -match 'engine exited \([1-9]|game ended with an error' }).Count
    $thermal = @($log | ForEach-Object { if ($_ -match '\[perf\] thermal (\d+)') { [int]$Matches[1] } })
    $steps = 0; for ($k = 1; $k -lt $thermal.Count; $k++) { if ($thermal[$k] -ne $thermal[$k - 1]) { $steps++ } }
    $tmax = if ($thermal) { ($thermal | Measure-Object -Maximum).Maximum } else { "?" }
    $fps = @(InApp "grep -a -o '\[bardroid-perf\] [0-9.]* fps' files/bar/infolog.txt 2>/dev/null" |
      ForEach-Object { if ("$_" -match '\] ([0-9.]+) fps') { [double]$Matches[1] } })
    if (-not $fps) {   # (the bench's own lines, every few seconds: "[replaybench] 12:30 x1.00 (...), 812 units, 29 fps")
      $fps = @(InApp "grep -a -o 'units, [0-9]* fps' files/bar/infolog.txt 2>/dev/null" |
        ForEach-Object { if ("$_" -match ', (\d+) fps') { [double]$Matches[1] } })
    }
    $fpsText = if ($fps) { "fps min $([math]::Round(($fps | Measure-Object -Minimum).Minimum, 1)), mean $([math]::Round(($fps | Measure-Object -Average).Average, 1)) over $($fps.Count) lines" } else { "no fps lines" }
    # (a replay's: whether the phone kept up with the game at 1x, bardroid_bench.lua's summary at its end)
    $keptUp = "$(InApp "grep -a -o 'speed min x[0-9.]*, median x[0-9.]*; below x0.95 [0-9]*%' files/bar/infolog.txt 2>/dev/null | tail -1")".Trim()
    if ($keptUp) { $fpsText += "; $keptUp of the time" }
    $fpsText += "; battery $bat0 -> $(Wait-PhoneCharge $adb $Device -Low 0) %"
    $lowmem = LowMemorySince $since
    $total.fault += $faults; $total.lowmem += $lowmem; $total.errors += $errors
    # (known classes: the driver's refusal, a low-memory kill; anything else that ended a chunk early is new)
    $known = $ended -in @("time", "replay done", "game over") -or $ended -match 'for memory' -or ($ended -eq "the app gone" -and $lowmem -gt 0) -or
      ($ended -match 'error exit' -and $faults -gt 0)
    $verdict = if ($known -and -not $setAside -and $aiOn) { "PASS" } else { $total.fails++; "FAIL" }
    $note = if (-not $aiOn) { " (the AI start script not applied)" } else { "" }
    Say ("{0}  chunk {1} ({2}, {11}){12}: {3} min, {4}; driver refusals {5}, low-memory kills {6}, engine errors {7}; thermal max {8}, {9} steps; {10}" -f
      $verdict, ($i + 1), $label, $minutes, $ended, $faults, $lowmem, $errors, $tmax, $steps, $fpsText, $engine, $note)
  } finally {
    & $adb -s $Device shell am force-stop $pkg
    InApp "rm -f files/bar/.bardroid-bench-replay files/bar/dev-env.sh files/bar/LuaUI/Widgets/soak_gameover.lua" | Out-Null
    & $lockTool free $Who | Out-Null
  }
  Start-Sleep 20
}
} finally {
  # (a developer's own dev-env.sh back as it was)
  if ($hadDevEnv) { InApp "mv -f files/bar/.soak-dev-env.sh.keep files/bar/dev-env.sh" | Out-Null } else { InApp "rm -f files/bar/dev-env.sh" | Out-Null }
  InApp "rm -f files/bar/LuaUI/Widgets/soak_gameover.lua" | Out-Null
  Remove-Item -Force $devEnv, $overWidget -ErrorAction SilentlyContinue
  & (Join-Path $PSScriptRoot "devphone.ps1") dark | Out-Null
}
Say ("soak: {0} chunks, {1} failing; driver refusals {2}, low-memory kills {3}, engine errors {4}" -f $Chunks,
  $total.fails, $total.fault, $total.lowmem, $total.errors)
Say "results: $result"
exit $total.fails
