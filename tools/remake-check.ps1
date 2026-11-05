# The phone's remake of the app's menu copies (Installer.remakeBarCopy, BuildMenuPatches), checked byte for byte: BAR's
# gui_buildmenu.lua and gui_ordermenu.lua from the phone's BAR release, the shipped .patches applied by the app's own
# BuildMenuPatches.java (the toolchain's JDK), the result against the shipped bardroid_buildmenu.lua and
# bardroid_ordermenu.lua. Run it after make-buildmenu.py or make-ordermenu.py made the copies from that phone's release
# (--adb): a difference means a phone would make a different copy after BAR's next update than the one tested.
#   powershell -ExecutionPolicy Bypass -File tools\remake-check.ps1 [-Device <serial>]   (the dev phone by default)
param([string]$Device = "")
$ErrorActionPreference = "Stop"
$App = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot "toolchain.ps1")
$adb = Join-Path $TC "android-sdk\platform-tools\adb.exe"
if (-not $Device) { $Device = Get-PhoneDevice $adb }
$Work = Join-Path $App "build\remake-check"
Remove-Item -Recurse -Force $Work -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path (Join-Path $Work "classes") | Out-Null
$env:ANDROID_SERIAL = $Device
$python = Join-Path $TC "hosttools\python\python.exe"
if (-not (Test-Path $python)) { $python = "python" }
& $python -I (Join-Path $PSScriptRoot "remake-check\pull.py") $App $adb $Work
if ($LASTEXITCODE -ne 0) { throw "BAR's files not read from the phone" }
$javac = (Get-ChildItem (Join-Path $TC "jdk") -Recurse -Filter javac.exe | Select-Object -First 1).FullName
$java = Join-Path (Split-Path $javac) "java.exe"
$env:JAVA_TOOL_OPTIONS = "-Duser.home=$(Join-Path $TC 'home') -Djava.io.tmpdir=$Work"
& $javac -nowarn -d (Join-Path $Work "classes") (Join-Path $PSScriptRoot "remake-check\src\com\underarmcape\bardroid\RemakeCheck.java") `
  (Join-Path $App "app\src\main\java\com\underarmcape\bardroid\BuildMenuPatches.java")
if ($LASTEXITCODE -ne 0) { throw "javac failed" }
& $java -cp (Join-Path $Work "classes") com.underarmcape.bardroid.RemakeCheck $Work (Join-Path $App "app\src\main\assets\bardroid") buildmenu ordermenu
exit $LASTEXITCODE
