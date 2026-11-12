# MapStore.java (the map storage limit: a map's last use from the engine's lines, the pruning order) on made-up map
# folders, on the toolchain's JDK.
#   powershell -ExecutionPolicy Bypass -File tools\map-store-test.ps1
$ErrorActionPreference = "Stop"
$App = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot "toolchain.ps1")
$Work = Join-Path $App "build\map-store-test"
$classes = Join-Path $Work "classes"
Remove-Item -Recurse -Force $classes -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $classes | Out-Null
$javac = (Get-ChildItem (Join-Path $TC "jdk") -Recurse -Filter javac.exe | Select-Object -First 1).FullName
$java = Join-Path (Split-Path $javac) "java.exe"
$env:JAVA_TOOL_OPTIONS = "-Duser.home=$(Join-Path $TC 'home') -Djava.io.tmpdir=$Work"
& $javac -nowarn -d $classes (Join-Path $PSScriptRoot "map-store-test\MapStoreTest.java") `
  (Join-Path $App "app\src\main\java\com\underarmcape\bardroid\MapStore.java")
if ($LASTEXITCODE -ne 0) { throw "javac failed" }
& $java -cp $classes com.underarmcape.bardroid.MapStoreTest
exit $LASTEXITCODE
