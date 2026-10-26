# Downloader.java (install and update downloads) against a local HTTP server on the toolchain's JDK, with stand-ins for
# the app's Log/BuildConfig/Installer: fresh, whole .part (416), resume, range ignored, body cut short, resume after.
#   powershell -ExecutionPolicy Bypass -File tools\downloader-test.ps1
$ErrorActionPreference = "Stop"
$App = Split-Path -Parent $PSScriptRoot
$Work = Join-Path $App "build\downloader-test"
$classes = Join-Path $Work "classes"
Remove-Item -Recurse -Force $classes -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $classes | Out-Null
$javac = (Get-ChildItem (Join-Path $App "..\toolchain\jdk") -Recurse -Filter javac.exe | Select-Object -First 1).FullName
$java = Join-Path (Split-Path $javac) "java.exe"
$env:JAVA_TOOL_OPTIONS = "-Duser.home=$(Join-Path $App '..\toolchain\home') -Djava.io.tmpdir=$Work"
$sources = @(Get-ChildItem (Join-Path $PSScriptRoot "downloader-test\src") -Recurse -Filter *.java | ForEach-Object FullName) +
  (Join-Path $App "app\src\main\java\com\underarmcape\bardroid\Downloader.java")
& $javac -nowarn -d $classes $sources
if ($LASTEXITCODE -ne 0) { throw "javac failed" }
& $java -cp $classes com.underarmcape.bardroid.DlTest
exit $LASTEXITCODE
