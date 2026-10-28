# The hail-mary phone queue, ONLINE-SAFE levers only (Kailil, 2026-10-27: online play needs the official engine and
# BAR's own game; tools/research/levers.ps1 $Culled lists what was dropped). Each research-bench.ps1 call takes and
# releases the phone lock and does nothing without hailmary-work\phone-ok. Hot, throttled runs, every lever next to a
# baseline. Afterwards: python -I tools\research\summary.py --markdown
#   powershell -ExecutionPolicy Bypass -File tools\research\queue.ps1 [-From 1] [-To 3]
param([int]$From = 1, [int]$To = 99)
$rb = Join-Path $PSScriptRoot "research-bench.ps1"
function RB { powershell -NoProfile -ExecutionPolicy Bypass -File $rb @args 2>&1 | ForEach-Object { "$(Get-Date -Format HH:mm:ss) $_" } }
$steps = @(
  # 1: thread pool size against alternating baselines (Tracy: the animation pass is for_mt; the phone runs main + 3);
  #    warms the phone first
  { RB -Lever "baseline,workers5,baseline,workers7,workers8,baseline" },
  # 2: OS-side levers: main thread on the prime core, whole engine on the prime cores, other allocators for malloc,
  #    huge pages, the local widget trim
  { RB -Lever "pin-main7,taskset-prime,baseline,mimalloc,jemalloc,baseline,thp-glibc,thp-mimalloc,widgets-trim,baseline" -NoWarm },
  # 3: frame caps as game speed (Kailil's hard lock is 30)
  { RB -Lever "cap20,cap30,baseline" -NoWarm },
  # 4: soak pair, ~20 min each: steady-state CPU cap and game speed with sound on vs Sound=0
  { RB -Lever "baseline" -Runs 6 -NoWarm },
  { RB -Lever "sound-off" -Runs 6 -NoWarm },
  # 5: simpleperf (official engine with its debug symbols): proot's CPU share, worker threads spinning, the engine's
  #    cgroup/uclamp, huge pages
  { RB -Lever "baseline" -Perf 30 -NoWarm }
)
for ($i = $From; $i -le [Math]::Min($To, $steps.Count); $i++) {
  Write-Host "=== queue step $i"
  & $steps[$i - 1]
  if (-not (Test-Path (Join-Path (Split-Path (Split-Path (Split-Path $PSScriptRoot))) "hailmary-work\phone-ok"))) { Write-Host "phone no longer handed over: stop"; break }
}