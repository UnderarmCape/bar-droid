# The portable toolchain's folder, found as scripts\env.bat finds it: BARDROID_TOOLCHAIN if set, else a "toolchain"
# folder beside this checkout with a JDK in it, else toolchain\ inside the checkout. Dot-source it: sets $TC.
$TC = if ($env:BARDROID_TOOLCHAIN) {
  [IO.Path]::GetFullPath($env:BARDROID_TOOLCHAIN)
} elseif (Test-Path (Join-Path $PSScriptRoot "..\..\toolchain\jdk\bin\java.exe")) {
  [IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\..\toolchain"))
} else {
  [IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\toolchain"))
}

# BAR's Windows install (the laptop checks read its engines, packages and pool, never change them): BAR_DATA if set,
# else the BAR launcher's default place. The real Local AppData folder, not $env:LOCALAPPDATA, which scripts\env.bat
# points into the toolchain.
$BarData = if ($env:BAR_DATA) { $env:BAR_DATA } else {
  Join-Path ([Environment]::GetFolderPath("LocalApplicationData")) "Programs\Beyond-All-Reason\data"
}
function Assert-BarData {
  if (-not (Test-Path (Join-Path $BarData "engine"))) {
    throw "BAR's Windows install was not found at $BarData (install BAR, or set BAR_DATA to its data folder)"
  }
}

# Replays for the laptop tools that play one (spectate-test, fp-tuner), newest first: BAR's own demos and the copies the
# tools keep in build\<tool>\data\demos, where a replay recorded on the phone stays once a tool has played it (BAR's
# newest replay need not play: one from 2026-10-13 never left its first frame on the laptop). Larger than 500 KB (a
# real game), each name once.
function Get-ReplayFiles {
  $dirs = @(Join-Path $BarData "demos") + @(Get-ChildItem (Join-Path (Split-Path -Parent $PSScriptRoot) "build") -Directory -ErrorAction SilentlyContinue |
    ForEach-Object { Join-Path $_.FullName "data\demos" })
  $seen = @{}
  $dirs | Where-Object { Test-Path $_ } | ForEach-Object { Get-ChildItem $_ -Filter *.sdfz } | Where-Object { $_.Length -gt 500000 } |
    Sort-Object LastWriteTime -Descending | Where-Object { -not $seen[$_.Name] -and ($seen[$_.Name] = $true) }
}

# The phone's adb serial for tools that drive it: BARDROID_DEVICE if set, else the first line of phone-device.txt
# beside the toolchain folder (the player's phone, e.g. its Wi-Fi address 192.168.x.y:5555; outside the
# repository), else the one device adb lists. "" when there is none.
function Get-PhoneDevice([string]$adb) {
  if ($env:BARDROID_DEVICE) { return $env:BARDROID_DEVICE }
  $file = Join-Path (Split-Path $TC) "phone-device.txt"
  if (Test-Path $file) {
    $d = Get-Content $file | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith("#") } |
      Select-Object -First 1
    if ($d) { return $d }
  }
  $listed = @(& $adb devices | Select-Object -Skip 1 | Where-Object { $_ -match "^(\S+)\s+device$" } |
    ForEach-Object { $Matches[1] })
  if ($listed.Count -eq 1) { return $listed[0] }
  return ""
}

# The lobby tests never log in (Kailil, 2026-10-28: "i cant have two accounts. so instead dont login and disable
# autologin on the laptop when you run the tests"): BAR's server allows one session per account, and a test that logged
# in with his ended the game he was spectating on the phone. Their lobby starts with no login saved, automatic login
# and the remembered password off, and no login window (firstLoginEver = false); bardroid_login_wait.lua says when the
# lobby is ready instead. (They ran logged in from 2026-10-27 to 10-28, from bar-lobby-login.txt beside the toolchain
# folder; nothing reads that file now.)
$LoginWaitWidget = Join-Path $PSScriptRoot "lobby-login\bardroid_login_wait.lua"
# A lobby test's LuaMenu/Config/IGL_data.lua: the "Chili lobby" fields (UTF-8 without a byte-order mark, which Lua
# would not read).
function Write-LobbyConfig([string]$data, [string]$fields) {
  $offline = "autoLogin = false, rememberPassword = false, wantAuthenticateWithSteam = false, firstLoginEver = false,"
  Write-Host "[lobby-login] offline: the test lobby does not log in"
  [IO.File]::WriteAllText((Join-Path $data "LuaMenu\Config\IGL_data.lua"),
    "return { [`"Chili lobby`"] = { $offline $fields }, }", (New-Object Text.UTF8Encoding($false)))
  Copy-Item $LoginWaitWidget (Join-Path $data "LuaMenu\Widgets\") -Force
}
# The test lobby's saved settings removed again at the end.
function Remove-LobbyLogin([string]$data) {
  Remove-Item (Join-Path $data "LuaMenu\Config\IGL_data.lua") -ErrorAction SilentlyContinue
}
# A lobby test's engine until its widget logs $done: up to 2 minutes for the lobby ("[lobbylogin] ready"), then 90 s
# for the test. Returns "done", "lobby not ready", "timed out" or "exited".
function Wait-LobbyTest($proc, [string]$log, [string]$done) {
  $readyBy = (Get-Date).AddMinutes(2); $testBy = $null
  while (-not $proc.HasExited) {
    Start-Sleep 1
    if (-not (Test-Path $log)) { continue }
    if (Select-String -Path $log -Pattern $done -Quiet) { return "done" }
    if (-not $testBy -and (Select-String -Path $log -Pattern '\[lobbylogin\] ready' -Quiet)) { $testBy = (Get-Date).AddSeconds(90) }
    if ($testBy -and (Get-Date) -gt $testBy) { return "timed out" }
    if (-not $testBy -and (Get-Date) -gt $readyBy) { return "lobby not ready" }
  }
  "exited"
}

# The engine folder the laptop checks start spring from: BAR's engine without anything else put beside spring.exe.
# Kailil's BAR install has ReShade there (an opengl32.dll proxy, add-ons, DLSS files): every engine started in that
# folder draws through ReShade (timings, screenshots) and writes ReShade's logs into BAR's install.
# build\engine\<engine> holds copies of the engine's files and junctions to its folders, without those files.
$EngineCopies = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\build\engine"))
$NotEngine = '^(opengl32\.dll|dxgi\.dll|d3d\d+\.dll|reshade.*|.*\.addon(32|64)?|nvngx_.*|dlss.*|verify-dlss.*|.*\.dmp|.*\.log|.*\.png|infolog.*)$'
function Get-EngineDir([string]$Engine) {
  $src = Join-Path $BarData "engine\$Engine"
  if (-not (Test-Path (Join-Path $src "spring.exe"))) { throw "engine $Engine was not found in BAR's install ($src)" }
  $dst = Join-Path $EngineCopies $Engine
  New-Item -ItemType Directory -Force $dst | Out-Null
  $want = @{}
  foreach ($i in Get-ChildItem $src -Force | Where-Object { $_.Name -notmatch $NotEngine }) {
    $want[$i.Name] = $true
    $d = Join-Path $dst $i.Name
    $have = Get-Item -LiteralPath $d -Force -ErrorAction SilentlyContinue
    if ($i.PSIsContainer) {
      if ($have -and $have.LinkType -eq "Junction" -and "$($have.Target)" -eq $i.FullName) { continue }
      if ($have -and $have.LinkType -ne "Junction") { throw "$d is a folder, not BAR's $($i.Name): remove it by hand" }
      if ($have) { [IO.Directory]::Delete($d) }   # the junction itself, never what it points to
      New-Item -ItemType Junction -Path $d -Target $i.FullName | Out-Null
    } elseif (-not ($have -and $have.Length -eq $i.Length -and $have.LastWriteTimeUtc -eq $i.LastWriteTimeUtc)) {
      Copy-Item -LiteralPath $i.FullName $d -Force
    }
  }
  foreach ($h in Get-ChildItem $dst -Force | Where-Object { -not $want[$_.Name] }) {
    if ($h.LinkType -eq "Junction") { [IO.Directory]::Delete($h.FullName) }
    elseif (-not $h.PSIsContainer) { Remove-Item -LiteralPath $h.FullName -Force }
  }
  $dst
}
