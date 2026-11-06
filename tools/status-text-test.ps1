# StatusText.java (the game service's status in players' words: the notification and the launcher's status line) on
# the toolchain's JDK.
#   powershell -ExecutionPolicy Bypass -File tools\status-text-test.ps1
$ErrorActionPreference = "Stop"
$App = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot "toolchain.ps1")
$Work = Join-Path $App "build\status-text-test"
$classes = Join-Path $Work "classes"
Remove-Item -Recurse -Force $classes -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $classes | Out-Null
$javac = (Get-ChildItem (Join-Path $TC "jdk") -Recurse -Filter javac.exe | Select-Object -First 1).FullName
$java = Join-Path (Split-Path $javac) "java.exe"
$env:JAVA_TOOL_OPTIONS = "-Duser.home=$(Join-Path $TC 'home') -Djava.io.tmpdir=$Work"
& $javac -nowarn -d $classes (Join-Path $PSScriptRoot "status-text-test\StatusTextTest.java") `
  (Join-Path $App "app\src\main\java\com\underarmcape\bardroid\StatusText.java") `
  (Join-Path $App "app\src\main\java\com\underarmcape\bardroid\DriverWatch.java")
if ($LASTEXITCODE -ne 0) { throw "javac failed" }
& $java -cp $classes com.underarmcape.bardroid.StatusTextTest
exit $LASTEXITCODE
