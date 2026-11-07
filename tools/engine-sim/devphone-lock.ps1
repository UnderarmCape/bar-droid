# The dev phone, shared by sessions working side by side (2026-11-06): one at a time runs games or changes on it.
#   devphone-lock.ps1 take <who> [-Minutes 60]   waits until free (a lock older than its minutes is stale), then takes it
#   devphone-lock.ps1 free <who>                 gives it back (only the holder's)
#   devphone-lock.ps1 show
# replay-memory.ps1 runs keep their own replay-memory.lock as well; reading the phone (dumpsys, logs) needs no lock.
param([ValidateSet("take", "free", "show")][string]$Do = "show", [string]$Who = "", [int]$Minutes = 60)
$lock = "C:\Tools\BARANDROID\devphone-busy.lock"
function Holder { if (Test-Path $lock) { Get-Content $lock -Raw } else { "" } }
switch ($Do) {
  "show" { $h = Holder; if ($h) { "busy: $h" } else { "free" } }
  "take" {
    if (-not $Who) { throw "who takes it?" }
    while ($true) {
      $h = Holder
      if (-not $h) { break }
      $age = ((Get-Date) - (Get-Item $lock).LastWriteTime).TotalMinutes
      $max = if ($h -match 'for (\d+) min') { [int]$Matches[1] } else { 60 }
      if ($age -gt $max) { "stale lock ($h, $([int]$age) min): taking it"; break }
      Start-Sleep 30
    }
    Set-Content -LiteralPath $lock -Value "$Who since $(Get-Date -Format 'HH:mm') for $Minutes min"
    "taken by $Who"
  }
  "free" {
    $h = Holder
    if ($h -and $h -notmatch "^$([regex]::Escape($Who)) ") { "held by someone else: $h"; exit 1 }
    Remove-Item -LiteralPath $lock -ErrorAction SilentlyContinue
    "free"
  }
}
