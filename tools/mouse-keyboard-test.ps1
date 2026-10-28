# CtrlAltRelease.java (MouseKeyboard: a lone Ctrl+Alt gives the captured mouse back to Android) on the toolchain's
# JDK. The rest of MouseKeyboard is Android input handling: checked on the phone (HANDOFF "Mouse and keyboard").
#   powershell -ExecutionPolicy Bypass -File tools\mouse-keyboard-test.ps1
$ErrorActionPreference = "Stop"
$App = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot "toolchain.ps1")
$Work = Join-Path $App "build\mouse-keyboard-test"
$classes = Join-Path $Work "classes"
Remove-Item -Recurse -Force $classes -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $classes | Out-Null
$javac = (Get-ChildItem (Join-Path $TC "jdk") -Recurse -Filter javac.exe | Select-Object -First 1).FullName
$java = Join-Path (Split-Path $javac) "java.exe"
$env:JAVA_TOOL_OPTIONS = "-Duser.home=$(Join-Path $TC 'home') -Djava.io.tmpdir=$Work"
& $javac -nowarn -d $classes (Join-Path $PSScriptRoot "mouse-keyboard-test\ReleaseTest.java") `
  (Join-Path $App "app\src\main\java\com\underarmcape\bardroid\CtrlAltRelease.java")
if ($LASTEXITCODE -ne 0) { throw "javac failed" }
& $java -cp $classes com.underarmcape.bardroid.ReleaseTest
exit $LASTEXITCODE
