# Profile-guided optimization for the engine branch (docs/ENGINE-SIM.md): runs the instrumented build (built with
# -fprofile-generate=/root/bar/pgo/; installed as engine-sim/<-Engine>) through BAR's benchmark scenario on the dev
# phone, every CPU allowed as in play, then pulls the profile files into C:\Tools\BARANDROID\engine-sim\pgo-data.
# Their names carry the object paths with Windows backslashes and '#' ("\rts#...#File.cpp.gcda", -fprofile-prefix-path
# set to the build folder); on the phone that is one file name each in files/bar/pgo/, on the laptop a plain file in
# pgo-data (the rebuild with -fprofile-use=pgo-data looks for "pgo-data\rts#...gcda").
#   pgo-train.ps1 [-Engine gcc-pgogen] [-Runs 1] [-Keep]   (-Keep: add to pgo-data, else it starts empty)
param([string]$Engine = "gcc-pgogen", [int]$Runs = 1, [switch]$Keep, [string]$Device = "R5CW22GVC3D")
$ErrorActionPreference = "Continue"
$tools = Split-Path $PSScriptRoot
. (Join-Path $tools "toolchain.ps1")
$adb = Join-Path $TC "android-sdk\platform-tools\adb.exe"
$tmp = Join-Path $TC "tmp"
function AppRun([string]$text, [string]$name) {
  $f = Join-Path $tmp $name
  [IO.File]::WriteAllText($f, ($text -replace "`r", ""), (New-Object Text.ASCIIEncoding))
  Invoke-AppScript $adb $f $Device
}
$data = "C:\Tools\BARANDROID\engine-sim\pgo-data"
if (-not $Keep -and (Test-Path $data)) { Get-ChildItem $data -File | Remove-Item -Confirm:$false }
New-Item -ItemType Directory -Force $data | Out-Null
foreach ($n in 1..$Runs) {
  & powershell -ExecutionPolicy Bypass -File "$PSScriptRoot\phone-engine.ps1" -Use $Engine -Device $Device | Out-Null
  Send-AppFile $adb "$PSScriptRoot\dev-env-allcpu.sh" "files/bar/es-allcpu.txt" $Device
  AppRun "cat files/bar/es-allcpu.txt >> files/bar/dev-env.sh; rm -f files/bar/es-allcpu.txt files/bar/.bardroid-bench-replay files/bar/infolog.txt; mkdir -p files/bar/pgo" "es-p0.sh" | Out-Null
  $count = "grep -c 'svc\] engine exited' files/logs/launcher.log"
  $before = [int](AppRun $count "es-p1.sh")
  & $adb -s $Device shell "am force-stop com.underarmcape.bardroid; sleep 1; input keyevent KEYCODE_WAKEUP; am start -n com.underarmcape.bardroid/.LauncherActivity --es start bench" | Out-Null
  $start = Get-Date
  do { Start-Sleep 20; $now = [int](AppRun $count "es-p1.sh") } while ($now -le $before -and ((Get-Date) - $start).TotalMinutes -lt 30)
  "run $n : $([int]((Get-Date) - $start).TotalSeconds) s; $(AppRun "grep -E 'svc\] (engine exited|Benchmark)' files/logs/launcher.log | tail -2; ls files/bar/pgo | wc -l" 'es-p2.sh')"
}
& powershell -ExecutionPolicy Bypass -File "$PSScriptRoot\phone-engine.ps1" -Off -Device $Device | Out-Null
# pull: one tar of the folder (names with backslashes and '#' would not survive adb pull on Windows)
& cmd /c "`"$adb`" -s $Device exec-out run-as com.underarmcape.bardroid sh -c `"cd files/bar/pgo && tar cf - .`" > `"$data\pgo.tar`""
# ("./\rts#...#X.cpp.gcda": the part after the last backslash is the file the rebuild looks for; -Keep: counts of a
# file already here are kept, a later run's replace them (merging would need gcov-tool))
$py = @"
import sys, tarfile, os
data = sys.argv[1]
n = 0
with tarfile.open(os.path.join(data, 'pgo.tar')) as t:
    for m in t.getmembers():
        if m.isfile() and m.name.endswith('.gcda'):
            leaf = m.name.split('\\')[-1].split('/')[-1]
            with open(os.path.join(data, leaf), 'wb') as f:
                f.write(t.extractfile(m).read())
            n += 1
print(n, 'profile files')
"@
$pyf = Join-Path $tmp "es-pgo-x.py"
[IO.File]::WriteAllText($pyf, $py)
& cmd /c "call C:\Tools\BARANDROID\toolchain\env.bat >nul && python -I `"$pyf`" `"$data`""
Remove-Item "$data\pgo.tar" -Confirm:$false
