# Updater.launchEnded (keep or roll back a BAR update after the engine exits) on the toolchain's JDK: the real
# Updater.java and Downloader.java with stand-ins for Paths/Proot/Proc/Prefs/Log, on made-up files dirs.
#   powershell -ExecutionPolicy Bypass -File tools\updater-test.ps1 [-Verbose]
param([switch]$Verbose)
$ErrorActionPreference = "Stop"
$App = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot "toolchain.ps1")
$Work = Join-Path $App "build\updater-test"
$classes = Join-Path $Work "classes"
Remove-Item -Recurse -Force $classes -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $classes | Out-Null
$javac = (Get-ChildItem (Join-Path $TC "jdk") -Recurse -Filter javac.exe | Select-Object -First 1).FullName
$java = Join-Path (Split-Path $javac) "java.exe"
$env:JAVA_TOOL_OPTIONS = "-Duser.home=$(Join-Path $TC 'home') -Djava.io.tmpdir=$Work"
$src = Join-Path $App "app\src\main\java\com\underarmcape\bardroid"
$sources = @(Get-ChildItem (Join-Path $PSScriptRoot "updater-test\src") -Recurse -Filter *.java | ForEach-Object FullName) +
  @(Get-ChildItem (Join-Path $PSScriptRoot "lobby-bridge-test\src\org") -Recurse -Filter *.java | ForEach-Object FullName) +
  (Join-Path $src "Updater.java") + (Join-Path $src "Downloader.java")
& $javac -nowarn -d $classes $sources
if ($LASTEXITCODE -ne 0) { throw "javac failed" }
$a = @(); if ($Verbose) { $a += "-v" }
& $java -cp $classes com.underarmcape.bardroid.UpdaterTest @a
$rc = $LASTEXITCODE
Get-ChildItem $Work -Directory -Filter "updater-*" | Remove-Item -Recurse -Force   # the made-up files dirs (no links in them)
exit $rc
