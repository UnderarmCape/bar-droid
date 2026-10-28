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

# The lobby tests run logged in (Kailil, 2026-10-27: "Make the lobby tests wait for me to log in before they run";
# then "create a local file for me to keep on my laptop ... use that to log me in from now on"). The player's BAR
# login in bar-lobby-login.txt beside the toolchain folder, outside the repository, written by the player alone; the
# tests put it into their own lobby's saved settings (Chobby's remembered password and automatic login) and delete
# that copy again at the end. Never printed. Get-LobbyLoginLua: the "Chili lobby" fields, or "" while the file is not
# filled in (the test lobby then waits on its login screen for the player).
$LobbyLoginFile = Join-Path (Split-Path $TC) "bar-lobby-login.txt"
$LoginWaitWidget = Join-Path $PSScriptRoot "lobby-login\bardroid_login_wait.lua"
function Get-LobbyLoginLua {
  if (-not (Test-Path $LobbyLoginFile)) {
    @(
      "# Your BAR lobby login for the laptop lobby tests (bar-droid-app\tools\lobby-*-test.ps1): fill in both lines, save.",
      "# This file stays on this laptop: outside the repository, never committed or printed. The tests copy it into",
      "# their own test lobby's settings for the run only. Note: the test lobby logging in may end your other lobby",
      "# session on the same account (BAR's server allows one).",
      "username = ",
      "password = "
    ) | Set-Content $LobbyLoginFile -Encoding utf8
  }
  $kv = @{}
  foreach ($l in Get-Content $LobbyLoginFile -Encoding utf8) {
    if ($l -match '^\s*(username|password)\s*=\s?(.*?)\s*$') { $kv[$Matches[1]] = $Matches[2] }
  }
  if (-not $kv.username -or -not $kv.password) { return "" }
  $q = { param($s) '"' + $s.Replace('\', '\\').Replace('"', '\"') + '"' }
  "userName = $(& $q $kv.username), password = $(& $q $kv.password), rememberPassword = true, autoLogin = true, " +
    "wantAuthenticateWithSteam = false, firstLoginEver = false,"
}
# A lobby test's LuaMenu/Config/IGL_data.lua: the "Chili lobby" fields with the login (UTF-8 without a byte-order mark,
# which Lua would not read). Prints where the login comes from.
function Write-LobbyConfig([string]$data, [string]$fields) {
  $login = Get-LobbyLoginLua
  if ($login) { Write-Host "[lobby-login] logging in from $LobbyLoginFile" }
  else { Write-Host "[lobby-login] $LobbyLoginFile is not filled in: log in on the test lobby's login screen (up to 5 minutes)" }
  [IO.File]::WriteAllText((Join-Path $data "LuaMenu\Config\IGL_data.lua"),
    "return { [`"Chili lobby`"] = { $login $fields }, }", (New-Object Text.UTF8Encoding($false)))
  Copy-Item $LoginWaitWidget (Join-Path $data "LuaMenu\Widgets\") -Force
}
# The login's copy out of the test lobby's settings again (Chobby saves the remembered password there at exit).
function Remove-LobbyLogin([string]$data) {
  Remove-Item (Join-Path $data "LuaMenu\Config\IGL_data.lua") -ErrorAction SilentlyContinue
}
# A lobby test's engine until its widget logs $done: up to 5 minutes for the login ("[lobbylogin] logged in"), then 90 s
# for the test. Returns "done", "not logged in", "timed out" or "exited".
function Wait-LobbyTest($proc, [string]$log, [string]$done) {
  $loginBy = (Get-Date).AddMinutes(5); $testBy = $null
  while (-not $proc.HasExited) {
    Start-Sleep 1
    if (-not (Test-Path $log)) { continue }
    if (Select-String -Path $log -Pattern $done -Quiet) { return "done" }
    if (-not $testBy -and (Select-String -Path $log -Pattern '\[lobbylogin\] logged in' -Quiet)) { $testBy = (Get-Date).AddSeconds(90) }
    if ($testBy -and (Get-Date) -gt $testBy) { return "timed out" }
    if (-not $testBy -and (Get-Date) -gt $loginBy) { return "not logged in" }
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
