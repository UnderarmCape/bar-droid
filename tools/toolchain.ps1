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
