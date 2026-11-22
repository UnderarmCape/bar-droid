# The touch playtest (README.md here): the running game stopped from the launcher, the lobby opened, its register
# window closed, the quick Skirmish opened, a screenshot taken. The skirmish's pages (map, faction, difficulty, start)
# are then gone through by hand: play.py look all / tap. The dev phone upright (play.py setup), held by
# devphone-lock.ps1 take playtest.
. "$PSScriptRoot\..\toolchain.ps1"
$env:ANDROID_USER_HOME = Join-Path $TC "home\.android"
$adb = Join-Path $TC "android-sdk\platform-tools\adb.exe"
$py = Join-Path $TC "android-sdk\ndk\29.0.14206865\toolchains\llvm\prebuilt\windows-x86_64\python3\python.exe"
$play = Join-Path $PSScriptRoot "play.py"
$dev = Get-PhoneDevice $adb
if (-not $dev) { throw "no dev phone (BARDROID_DEVICE, or ..\phone-device.txt)" }
& $adb -s $dev shell am start -n com.underarmcape.bardroid/.LauncherActivity | Out-Null
Start-Sleep 2
& $adb -s $dev shell input tap 946 674          # Stop
Start-Sleep 12
& $adb -s $dev shell input tap 878 530          # Lobby
Start-Sleep 50
& $py -I $play tap 874 1688 Cancel register
Start-Sleep 1.5
& $py -I $play tap 540 2120 Skirmish
Start-Sleep 3
& $py -I $play look all skirmish-1
