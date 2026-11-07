# The dev phone, shared by sessions working side by side (2026-11-06): one at a time runs games or changes on it, in
# the order they asked (a queue), so nobody waits forever.
#   devphone-lock.ps1 take <who> [-Minutes 60]   joins the queue, waits until the phone is free and it is first in line
#                                                (a hold older than its minutes is stale), then takes it
#   devphone-lock.ps1 free <who>                 gives it back (only the holder's); the next in line takes it
#   devphone-lock.ps1 show                       the holder and the queue
# Keep holds under ~45 min and free between chunks: the queue gives the phone to the others in between. replay-memory.ps1
# runs keep their own replay-memory.lock as well; reading the phone (dumpsys, logs) needs no lock.
param([ValidateSet("take", "free", "show")][string]$Do = "show", [string]$Who = "", [int]$Minutes = 60)
$lock = "C:\Tools\BARANDROID\devphone-busy.lock"
$queue = "C:\Tools\BARANDROID\devphone-queue.txt"
function Holder { if (Test-Path $lock) { (Get-Content $lock -Raw).Trim() } else { "" } }
function Queue { if (Test-Path $queue) { @(Get-Content $queue | Where-Object { $_ -match '\S' }) } else { @() } }
# (a queue line: "<who> <yyyy-MM-dd HH:mm:ss>"; one waiting longer than 3 hours without taking is dropped as gone)
function CleanQueue {
  # (and the holder's own line: a session that took the phone without the script leaves it behind, blocking the rest)
  $holder = ((Holder) -split ' ')[0]
  $keep = @(Queue | Where-Object {
    $p = $_ -split ' ', 2
    $p[0] -ne $holder -and $(try { ((Get-Date) - [datetime]::Parse($p[1])).TotalHours -lt 3 } catch { $false })
  })
  Set-Content -LiteralPath $queue -Value $keep
}
switch ($Do) {
  "show" {
    $h = Holder; if ($h) { "busy: $h" } else { "free" }
    $q = Queue; if ($q.Count) { "queue: " + (($q | ForEach-Object { ($_ -split ' ')[0] }) -join ', ') }
  }
  "take" {
    if (-not $Who) { throw "who takes it?" }
    if (-not (Queue | Where-Object { ($_ -split ' ')[0] -eq $Who })) { Add-Content -LiteralPath $queue -Value "$Who $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" }
    while ($true) {
      CleanQueue
      $first = @(Queue)[0]
      $h = Holder
      $stale = $false
      if ($h) {
        $age = ((Get-Date) - (Get-Item $lock).LastWriteTime).TotalMinutes
        $max = if ($h -match 'for (\d+) min') { [int]$Matches[1] } else { 60 }
        $stale = $age -gt $max
      }
      if ((-not $h -or $stale) -and $first -and ($first -split ' ')[0] -eq $Who) {
        if ($stale) { "stale hold ($h): taking it" }
        break
      }
      Start-Sleep 5
    }
    Set-Content -LiteralPath $lock -Value "$Who since $(Get-Date -Format 'HH:mm') for $Minutes min"
    Set-Content -LiteralPath $queue -Value @(Queue | Where-Object { ($_ -split ' ')[0] -ne $Who })
    "taken by $Who"
  }
  "free" {
    $h = Holder
    if ($h -and $h -notmatch "^$([regex]::Escape($Who)) ") { "held by someone else: $h"; exit 1 }
    Remove-Item -LiteralPath $lock -ErrorAction SilentlyContinue
    "free"
  }
}
