# LogRedact.java ("Share logs" keeps an online game's join password out of the logs it hands on), on the toolchain's
# JDK.
#   powershell -ExecutionPolicy Bypass -File tools\log-redact-test.ps1
$ErrorActionPreference = "Stop"
$App = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot "toolchain.ps1")
$Work = Join-Path $App "build\log-redact-test"
$classes = Join-Path $Work "classes"
Remove-Item -Recurse -Force $classes -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $classes | Out-Null
$javac = (Get-ChildItem (Join-Path $TC "jdk") -Recurse -Filter javac.exe | Select-Object -First 1).FullName
$java = Join-Path (Split-Path $javac) "java.exe"
$env:JAVA_TOOL_OPTIONS = "-Duser.home=$(Join-Path $TC 'home') -Djava.io.tmpdir=$Work"
& $javac -nowarn -encoding UTF-8 -d $classes (Join-Path $PSScriptRoot "log-redact-test\LogRedactTest.java") `
  (Join-Path $App "app\src\main\java\com\underarmcape\bardroid\LogRedact.java")
if ($LASTEXITCODE -ne 0) { throw "javac failed" }
& $java -cp $classes com.underarmcape.bardroid.LogRedactTest
exit $LASTEXITCODE
