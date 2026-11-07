# The dev phone, shared by sessions working side by side (2026-11-06): one at a time runs games or changes on it, in
# the order they asked (a queue), so nobody waits forever.
#   devphone-lock.ps1 take <who> [-Minutes 60]   joins the queue, waits until the phone is free and it is first in line
#                                                (a hold older than its minutes is stale), then takes it
#   devphone-lock.ps1 free <who>                 gives it back (only the holder's); the next in line takes it
#   devphone-lock.ps1 show                       the holder and the queue
# Keep holds under ~45 min and free between chunks: the queue gives the phone to the others in between. replay-memory.ps1
# runs keep their own replay-memory.lock as well; reading the phone (dumpsys, logs) needs no lock.
# The queue is one file per waiter (devphone-queue\<who>.wait, the time it joined): 2026-11-07 the one shared queue
# file was held open by a waiting process (a failed write in PowerShell's file cmdlets), and every take behind it saw an
# empty queue forever. Files are read and written only through .NET calls that close them, never the cmdlets.
param([ValidateSet("take", "free", "show")][string]$Do = "show", [string]$Who = "", [int]$Minutes = 60)
$lock = "C:\Tools\BARANDROID\devphone-busy.lock"
$qdir = "C:\Tools\BARANDROID\devphone-queue"
[void][IO.Directory]::CreateDirectory($qdir)
function ReadText([string]$path) {   # (any sharing: a writer elsewhere never makes a read fail)
  for ($i = 0; $i -lt 20; $i++) {
    try {
      $fs = [IO.File]::Open($path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete)
      try { return (New-Object IO.StreamReader($fs)).ReadToEnd().Trim() } finally { $fs.Dispose() }
    } catch [IO.FileNotFoundException] { return $null } catch [IO.DirectoryNotFoundException] { return $null } catch { Start-Sleep -Milliseconds 100 }
  }
  return "?"
}
function WriteText([string]$path, [string]$text) {
  for ($i = 0; $i -lt 20; $i++) { try { [IO.File]::WriteAllText($path, $text); return } catch { Start-Sleep -Milliseconds 100 } }
  throw "cannot write $path"
}
function Holder { if ([IO.File]::Exists($lock)) { $h = ReadText $lock; if ($null -eq $h) { "" } else { $h } } else { "" } }
function Waiters {   # in the order they joined; one waiting longer than 3 hours without taking is dropped as gone
  $holder = ((Holder) -split ' ')[0]
  $list = foreach ($f in [IO.Directory]::GetFiles($qdir, "*.wait")) {
    $name = [IO.Path]::GetFileNameWithoutExtension($f)
    $since = [IO.File]::GetCreationTime($f)
    $t = ReadText $f; $p = [datetime]::MinValue
    if ($t -and [datetime]::TryParse($t, [ref]$p)) { $since = $p }
    # (and the holder's own entry: a session that took the phone without the script leaves it behind, blocking the rest)
    if ($name -eq $holder -or ((Get-Date) - $since).TotalHours -ge 3) { try { [IO.File]::Delete($f) } catch {}; continue }
    [pscustomobject]@{ Who = $name; Since = $since }
  }
  @($list | Sort-Object Since)
}
switch ($Do) {
  "show" {
    $h = Holder; if ($h) { "busy: $h" } else { "free" }
    $q = Waiters; if ($q.Count) { "queue: " + (($q | ForEach-Object { $_.Who }) -join ', ') }
  }
  "take" {
    if (-not $Who -or $Who -match '[^\w.-]') { throw "who takes it? (letters, digits, . - _)" }
    $mine = Join-Path $qdir "$Who.wait"
    if (-not [IO.File]::Exists($mine)) { WriteText $mine (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') }
    while ($true) {
      $first = @(Waiters)[0]
      $h = Holder
      $stale = $false
      if ($h) {
        $age = ((Get-Date) - [IO.File]::GetLastWriteTime($lock)).TotalMinutes
        $max = if ($h -match 'for (\d+) min') { [int]$Matches[1] } else { 60 }
        $stale = $age -gt $max
      }
      if ((-not $h -or $stale) -and $first -and $first.Who -eq $Who) {
        if ($stale) { "stale hold ($h): taking it" }
        break
      }
      if (-not [IO.File]::Exists($mine)) { WriteText $mine (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') }   # (dropped: in again, last)
      Start-Sleep 5
    }
    WriteText $lock "$Who since $(Get-Date -Format 'HH:mm') for $Minutes min"
    try { [IO.File]::Delete($mine) } catch {}
    "taken by $Who"
  }
  "free" {
    $h = Holder
    if ($h -and $h -notmatch "^$([regex]::Escape($Who)) ") { "held by someone else: $h"; exit 1 }
    for ($i = 0; $i -lt 20 -and [IO.File]::Exists($lock); $i++) { try { [IO.File]::Delete($lock) } catch { Start-Sleep -Milliseconds 100 } }
    "free"
  }
}
