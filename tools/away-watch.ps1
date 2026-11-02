# Kailil back at the laptop (a key, the mouse) while a laptop check runs BAR: the check's engine is ended at once and a
# flag file says so, for the next check not to start. BAR's launch guard looks only at the start, and twice a run begun
# after his 10 idle minutes went on with him back (2026-11-01, 2026-11-02). Dot-source it, then:
#   $watch = Start-AwayWatch <flag file>   ...   Stop-AwayWatch $watch
# Not for checks that move the pointer themselves (-Pointer: nobody at the laptop then).
function Start-AwayWatch([string]$flag) {
  Remove-Item $flag -ErrorAction SilentlyContinue
  Start-Job -ArgumentList $flag -ScriptBlock {
    param($flag)
    Add-Type -Name Input -Namespace BarDroid -MemberDefinition @'
[StructLayout(LayoutKind.Sequential)] public struct LastInput { public uint cbSize; public uint dwTime; }
[DllImport("user32.dll")] static extern bool GetLastInputInfo(ref LastInput l);
public static uint Last() { var l = new LastInput(); l.cbSize = 8; GetLastInputInfo(ref l); return l.dwTime; }
'@
    $start = [BarDroid.Input]::Last()
    while ([BarDroid.Input]::Last() -eq $start) { Start-Sleep -Milliseconds 500 }
    Set-Content $flag "back"
    Get-CimInstance Win32_Process -Filter "Name='spring.exe' OR Name='spring-headless.exe'" |
      Where-Object { $_.CommandLine -match 'bar-droid-app\\build' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
  }
}

function Stop-AwayWatch($job) {
  if ($job) { Stop-Job $job; Remove-Job $job -Force }
}
