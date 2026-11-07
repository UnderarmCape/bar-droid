# The dev phone (Kailil, 2026-10-29: a phone always on USB adb for the agents' dev work, tests and benchmarks, "You can
# use this phone 24/7"; his Fold7 only for his own tests of builds): its adb links and its screen. Its USB serial and
# Wi-Fi address are the lines of ..\phone-device.txt (outside the repository; toolchain.ps1 Get-PhoneDevices).
#   powershell -ExecutionPolicy Bypass -File tools\devphone.ps1 [status|connect|dark|bench|watch]
#   status   the links (USB, Wi-Fi), the screen, the battery (the default)
#   connect  adb over Wi-Fi as a backup to USB: adb tcpip 5555 over USB when the phone does not listen yet (after each
#            restart of the phone), then adb connect to its current address
#   dark     the screen as dark as it goes, kept on (toolchain.ps1 $PhoneScreen.dark): what it is between benchmarks
#   bench    the normal minimum brightness, Extra dim off: for benchmarks (tools\phone-bench.ps1 switches by itself)
#   watch    connect and dark again every minute (a phone restart, a lost Wi-Fi link, a setting changed), except while a
#            benchmark holds ..\phone-bench.lock; tools\devphone-watch.bat runs it in a window of its own
#   view     half brightness, Extra dim off, for Kailil to watch its games; held (watch leaves it) until "dark" runs
param([ValidateSet("status", "connect", "dark", "bench", "watch", "view")][string]$Do = "status")
. (Join-Path $PSScriptRoot "toolchain.ps1")
$adb = Join-Path $TC "android-sdk\platform-tools\adb.exe"
$mine = Get-PhoneDevices
if (-not $mine.Count) { throw "no dev phone: put its USB serial and Wi-Fi address (ip:5555) in $(Join-Path (Split-Path $TC) 'phone-device.txt')" }
$usb = @($mine | Where-Object { $_ -notmatch ":" })[0]
$wifi = @($mine | Where-Object { $_ -match ":\d+$" })[0]
$lock = Join-Path (Split-Path $TC) "phone-bench.lock"
$hold = Join-Path (Split-Path $TC) "devphone-view.hold"

function Listed { @(& $adb devices | Select-Object -Skip 1 | Where-Object { $_ -match "^(\S+)\s+device$" } | ForEach-Object { $Matches[1] }) }
function Target { $l = Listed; foreach ($d in @($usb, $wifi)) { if ($d -and $l -contains $d) { return $d } }; "" }

function Connect {
  $l = Listed
  if ($usb -and $l -contains $usb) {
    $ip = (& $adb -s $usb shell "ip -4 addr show wlan0" | Select-String "inet (\d+\.\d+\.\d+\.\d+)" | ForEach-Object { $_.Matches[0].Groups[1].Value }) | Select-Object -First 1
    if (-not $ip) { Write-Host "[devphone] no Wi-Fi address on the phone: USB only"; return }
    $addr = "${ip}:5555"
    if ($wifi -and $addr -ne $wifi) { Write-Host "[devphone] the phone's Wi-Fi address is now $addr (phone-device.txt: $wifi)" }
    if ($l -contains $addr) { return }
    if ((& $adb -s $usb shell getprop service.adb.tcp.port) -ne "5555") {
      & $adb -s $usb tcpip 5555 | Out-Null
      Start-Sleep 4
      & $adb wait-for-usb-device 2>$null
    }
    $out = & $adb connect $addr
    Write-Host "[devphone] $out"
  } elseif ($wifi -and $l -notcontains $wifi) {
    $out = & $adb connect $wifi
    Write-Host "[devphone] no USB link; $out"
  }
}

function Status {
  $l = Listed
  Write-Host ("[devphone] USB {0}: {1}; Wi-Fi {2}: {3}" -f $usb, $(if ($l -contains $usb) { "connected" } else { "not connected" }),
    $wifi, $(if ($l -contains $wifi) { "connected" } else { "not connected" }))
  $t = Target
  if (-not $t) { Write-Host "[devphone] the phone is not reachable"; return }
  $s = @'
echo "screen: $(dumpsys power 2>/dev/null | grep -o 'mWakefulness=[A-Za-z]*' | sed -n 1p), brightness $(settings get system screen_brightness) (mode $(settings get system screen_brightness_mode)), Extra dim $(settings get secure reduce_bright_colors_activated) at $(settings get secure reduce_bright_colors_level)%, wallpaper dim $(cmd wallpaper get-dim-amount | grep -o '[0-9.]*$'), awake while powered $(settings get global stay_on_while_plugged_in)"
echo "battery: $(dumpsys battery | grep -E '^  level' | grep -o '[0-9]*')%, $(($(dumpsys battery | grep -E '^  temperature' | grep -o '[0-9]*') / 10)) C, protection $(settings get global protect_battery) (to $(settings get global battery_protection_threshold)%)"
'@
  Invoke-PhoneScript $adb $t $s "bardroid-status.sh" | ForEach-Object { "[devphone] $_" }
}

function Screen([string]$mode) {
  $t = Target
  if (-not $t) { Write-Host "[devphone] the phone is not reachable"; return }
  Set-PhoneScreen $adb $t $mode | ForEach-Object { Write-Host "[devphone] $mode`: $_" }
}

switch ($Do) {
  "status" { Status }
  "connect" { Connect; Status }
  "dark" { Remove-Item -LiteralPath $hold -ErrorAction SilentlyContinue; Screen "dark" }
  "bench" { Screen "bench" }
  "view" { Set-Content -LiteralPath $hold -Value "Kailil watches the dev phone's games ($(Get-Date -Format 'yyyy-MM-dd HH:mm')); devphone.ps1 dark ends it"; Screen "view" }
  "watch" {
    Write-Host "[devphone] watching the dev phone every minute (Ctrl+C stops)"
    while ($true) {
      try {
        Connect
        if (Test-Path $lock) { Write-Host "[devphone] $(Get-Date -Format HH:mm) a benchmark runs: the screen left to it" }
        elseif (Test-Path $hold) { Screen "view" }
        else { Screen "dark" }
      } catch { Write-Host "[devphone] $(Get-Date -Format HH:mm) $_" }
      Start-Sleep 60
    }
  }
}
