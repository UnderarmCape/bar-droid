# SettingsMerge.java (springsettings.cfg at every start: BAR's and the player's settings kept, the Android keys set) on
# the toolchain's JDK, with the app's template; -Phone <file> adds a real springsettings.cfg from the phone.
#   powershell -ExecutionPolicy Bypass -File tools\settings-merge-test.ps1 [-Phone <springsettings.cfg>]
param([string]$Phone = "")
$ErrorActionPreference = "Stop"
$App = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot "toolchain.ps1")
$Work = Join-Path $App "build\settings-merge-test"
$classes = Join-Path $Work "classes"
Remove-Item -Recurse -Force $classes -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $classes | Out-Null
$javac = (Get-ChildItem (Join-Path $TC "jdk") -Recurse -Filter javac.exe | Select-Object -First 1).FullName
$java = Join-Path (Split-Path $javac) "java.exe"
$env:JAVA_TOOL_OPTIONS = "-Duser.home=$(Join-Path $TC 'home') -Djava.io.tmpdir=$Work"
& $javac -nowarn -d $classes (Join-Path $PSScriptRoot "settings-merge-test\MergeTest.java") `
  (Join-Path $App "app\src\main\java\com\underarmcape\bardroid\SettingsMerge.java")
if ($LASTEXITCODE -ne 0) { throw "javac failed" }
$args2 = @((Join-Path $App "app\src\main\assets\bardroid\springsettings.cfg"))
if ($Phone) { $args2 += $Phone }
& $java -cp $classes com.underarmcape.bardroid.MergeTest @args2
exit $LASTEXITCODE
