# PadGame (the gamepad in BAR's game: v0.8.5's controls on a mouse and keys) on the toolchain's JDK: the real
# PadGame.java, PadMouse.java and PadButtons.java with a made-up pointer, keyboard, game and clock.
#   powershell -ExecutionPolicy Bypass -File tools\padgame-test.ps1
$ErrorActionPreference = "Stop"
$App = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot "toolchain.ps1")
$Work = Join-Path $App "build\padgame-test"
Remove-Item -Recurse -Force $Work -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $Work | Out-Null
$javac = (Get-ChildItem (Join-Path $TC "jdk") -Recurse -Filter javac.exe | Select-Object -First 1).FullName
$java = Join-Path (Split-Path $javac) "java.exe"
$env:JAVA_TOOL_OPTIONS = "-Duser.home=$(Join-Path $TC 'home') -Djava.io.tmpdir=$Work"
$src = Join-Path $App "app\src\main\java\com\underarmcape\bardroid"
$sources = @(Get-ChildItem (Join-Path $PSScriptRoot "padgame-test\src") -Recurse -Filter *.java | ForEach-Object FullName) +
  (Join-Path $src "PadGame.java") + (Join-Path $src "PadMouse.java") + (Join-Path $src "PadButtons.java") + (Join-Path $src "BuildMenuPatches.java")
& $javac -nowarn -d $Work $sources
if ($LASTEXITCODE -ne 0) { throw "javac failed" }
& $java -cp $Work com.underarmcape.bardroid.PadGameTest
exit $LASTEXITCODE
