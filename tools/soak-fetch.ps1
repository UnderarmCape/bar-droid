# Server replays for the soak (RC 0.2.0 item 10): BAR's newest online games the dev phone can play as it is (its engine,
# BAR's game as installed), with their maps, copied into the app's files/bar/demos and files/bar/maps; the soak
# (tools\soak-phone.ps1) then plays them at 1x before its AI chunks.
#   powershell -ExecutionPolicy Bypass -File tools\soak-fetch.ps1 [-Count 2] [-MinMinutes 30] [-Players 16]
#                [-Engine <ver> -Game <name>] [-NoPush] [-Who soak-fetch] [-Device <serial>]
# api.bar-rts.com/replays lists BAR's games (here: ended normally, no AIs, -Players people in all, -MinMinutes or longer,
# a different map each); maps-metadata.beyondallreason.dev names each map's file. Both are downloaded on the laptop
# (toolchain\tmp\soak-fetch, kept for the next run) and copied in under plain names (adb splits a name at its spaces):
# the phone's own downloads need the app's process (adb's run-as has no network), and the bench mode downloads nothing.
# -Engine and -Game stand in for the phone's (read from it otherwise); -NoPush only downloads. The dev phone only,
# through its lock (taken twice, briefly: to read the phone, then to copy the files in).
param([int]$Count = 2, [int]$MinMinutes = 30, [int]$Players = 16, [string]$Engine = "", [string]$Game = "",
  [switch]$NoPush, [string]$Device = "", [string]$Who = "soak-fetch")
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"   # (Invoke-WebRequest's progress bar slows a download many times over)
. (Join-Path $PSScriptRoot "toolchain.ps1")
$env:ANDROID_USER_HOME = Join-Path $TC "home\.android"
$adb = Join-Path $TC "android-sdk\platform-tools\adb.exe"
$pkg = "com.underarmcape.bardroid"
$lockTool = "C:\Tools\BARANDROID\bar-droid-engine\tools\engine-sim\devphone-lock.ps1"
$store = Join-Path $TC "tmp\soak-fetch"
New-Item -ItemType Directory -Force $store | Out-Null
$demoUrl = "https://storage.uk.cloud.ovh.net/v1/AUTH_10286efc0d334efd917d476d7183232e/BAR/demos/"
function InApp([string]$command) { & $adb -s $Device exec-out run-as $pkg sh -c $command }
function Take { & powershell -ExecutionPolicy Bypass -File $lockTool take $Who -Minutes 20 | Out-Host }
function Free { & powershell -ExecutionPolicy Bypass -File $lockTool free $Who | Out-Host }
$needPhone = -not $NoPush -or -not ($Engine -and $Game)
if ($needPhone) {
  if (-not $Device) { $Device = Get-PhoneDevice $adb }
  if (-not $Device) { throw "no dev phone (BARDROID_DEVICE, or ..\phone-device.txt)" }
}

# ---- the phone's engine, game and maps (as soak-phone.ps1 reads them) ---------------------------------------------
$maps = @(); $have = @()
if ($needPhone) {
  Take
  try {
    if (-not $Engine) {
      $Engine = @(InApp "ls -1 files/bar/engine" | ForEach-Object { "$_".Trim() } | Where-Object { $_ -match '^recoil_([\d.]+)$' } |
        ForEach-Object { $_ -replace '^recoil_', '' }) | Select-Object -Last 1
    }
    if (-not $Game) { $Game = "$(InApp "sed -n 's/^[[:space:]]*GameType=\(.*\);/\1/p' files/bar/skirmish.txt | head -1")".Trim() }
    $maps = @(InApp "ls -1 files/bar/maps" | ForEach-Object { "$_".Trim().ToLower() })
    $have = @(InApp "ls -1 files/bar/demos" | ForEach-Object { "$_".Trim() })
  } finally { Free }
}
if (-not $Engine -or -not $Game) { throw "the phone's engine or game not found (files/bar/engine, files/bar/skirmish.txt)" }
Write-Host "the phone's engine $Engine, game $Game"

# ---- BAR's newest games of that engine and game -------------------------------------------------------------------
# (PowerShell 5.1 hands a JSON array on as one object: @() of it was one item, every map's fileName in one; unrolled here)
$mapList = @(Invoke-RestMethod "https://maps-metadata.beyondallreason.dev/latest/live_maps.validated.json" | ForEach-Object { $_ })
$picked = New-Object System.Collections.Generic.List[object]
$usedMaps = @{}
for ($page = 1; $page -le 10 -and $picked.Count -lt $Count; $page++) {
  $list = Invoke-RestMethod "https://api.bar-rts.com/replays?page=$page&limit=50&endedNormally=true&hasBots=false"
  foreach ($r in @($list.data)) {
    if ($picked.Count -ge $Count) { break }
    if ($r.durationMs -lt $MinMinutes * 60000 -or $usedMaps[$r.Map.scriptName]) { continue }
    $people = 0; $ais = 0
    foreach ($a in @($r.AllyTeams)) { $people += @($a.Players).Count; $ais += @($a.AIs).Count }
    if ($people -ne $Players -or $ais) { continue }
    $d = Invoke-RestMethod "https://api.bar-rts.com/replays/$($r.id)"
    if ($d.engineVersion -ne $Engine -or $d.gameVersion -ne $Game) { continue }
    $m = $mapList | Where-Object { $_.springName -eq $r.Map.scriptName } | Select-Object -First 1
    if (-not $m -or -not $m.downloadURL) { continue }
    $usedMaps[$r.Map.scriptName] = $true
    $stamp = ([datetime]$r.startTime).ToUniversalTime().ToString("yyyyMMdd-HHmm")
    $plain = (($m.fileName -replace '\.sd[7z]$', '') -replace '[^A-Za-z0-9._-]', '_').ToLower()
    $picked.Add([pscustomobject]@{ File = $d.fileName; Name = "server-$stamp-$plain.sdfz"; Map = $r.Map.scriptName;
      MapFile = $m.fileName.ToLower(); MapUrl = $m.downloadURL; Minutes = [math]::Round($r.durationMs / 60000, 1) })
  }
}
if (-not $picked.Count) { throw "no game of engine $Engine and $Game among BAR's newest 500 ($Players people, $MinMinutes min or longer)" }

# ---- downloaded on the laptop -------------------------------------------------------------------------------------
foreach ($p in $picked) {
  $local = Join-Path $store $p.Name
  if (-not (Test-Path $local)) { Invoke-WebRequest -UseBasicParsing ($demoUrl + [uri]::EscapeDataString($p.File)) -OutFile $local }
  $mapLocal = Join-Path $store $p.MapFile
  if (-not (Test-Path $mapLocal) -and -not ($maps -contains $p.MapFile)) { Invoke-WebRequest -UseBasicParsing $p.MapUrl -OutFile $mapLocal }
  Write-Host ("  {0}: {1}, {2} min ({3:N1} MB; the map {4})" -f $p.Name, $p.Map, $p.Minutes, ((Get-Item $local).Length / 1MB),
    $(if ($maps -contains $p.MapFile) { "on the phone" } else { "{0:N0} MB" -f ((Get-Item $mapLocal).Length / 1MB) }))
}
if ($NoPush) { Write-Host "[soakfetch] done: $($picked.Count) downloaded, not copied to the phone (-NoPush)"; exit 0 }

# ---- copied into the app ------------------------------------------------------------------------------------------
Take
try {
  InApp "mkdir -p files/bar/demos files/bar/maps" | Out-Null
  foreach ($p in $picked) {
    if (-not ($maps -contains $p.MapFile)) { Send-AppFile $adb (Join-Path $store $p.MapFile) "files/bar/maps/$($p.MapFile)" $Device }
    if (-not ($have -contains $p.Name)) { Send-AppFile $adb (Join-Path $store $p.Name) "files/bar/demos/$($p.Name)" $Device }
    $size = 0; [void][long]::TryParse("$(InApp "wc -c < files/bar/demos/$($p.Name)")".Trim(), [ref]$size)
    $want = (Get-Item (Join-Path $store $p.Name)).Length
    if ($size -ne $want) { throw "files/bar/demos/$($p.Name): $size bytes on the phone, $want here" }
  }
} finally { Free }
Write-Host "[soakfetch] done: $($picked.Count) on the phone ($(($picked | ForEach-Object { $_.Name }) -join ', '))"
