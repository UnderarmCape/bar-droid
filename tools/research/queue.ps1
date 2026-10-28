# The hail-mary phone queue, ONLINE-SAFE levers only (Kailil, 2026-10-27: online play needs the official engine and
# BAR's own game; tools/research/levers.ps1 $Culled lists what was dropped). Each research-bench.ps1 call takes and
# releases the phone lock and does nothing without hailmary-work\phone-ok. Hot, throttled runs, every lever next to a
# baseline. Afterwards: python -I tools\research\summary.py --markdown
#   powershell -ExecutionPolicy Bypass -File tools\research\queue.ps1 [-From 1] [-To 3]
param([int]$From = 1, [int]$To = 99)
$rb = Join-Path $PSScriptRoot "research-bench.ps1"
function RB { powershell -NoProfile -ExecutionPolicy Bypass -File $rb @args 2>&1 | ForEach-Object { "$(Get-Date -Format HH:mm:ss) $_" } }
$steps = @(
  # 1: threads (Tracy: the animation pass is for_mt; the phone runs main + 3), pinning, the allocator, the main
  #    thread's draw/sim split (warms the phone first)
  { RB -Lever "baseline,workers8,baseline,workers6,pin-main7,baseline,mimalloc,draw-balance0,baseline" },
  # 2: client settings: sound, effects particles, local widgets, Lua GC, the frame cap
  { RB -Lever "sound-off,particles-min,baseline,widgets-trim,lua-gc-lazy,baseline,cap30,baseline" -NoWarm },
  # 3: where the phone's time goes: simpleperf (official engine, its debug symbols), proot's CPU share, the engine's
  #    cgroup/uclamp, huge pages, worker threads spinning or not
  { RB -Lever "baseline,workers8" -Perf 30 -NoWarm },
  # 4 (if 1-2 left room): the remaining client-side levers
  { RB -Lever "workers7,workers5,baseline,taskset-prime,jemalloc,baseline,thp-glibc,min-render,baseline,gamemode-perf,draw-balance05,baseline" -NoWarm },
  # 5: soak pair, ~15 min each: the steady-state CPU cap of a cooler setup (30 fps, no sound) against the default
  { RB -Lever "baseline" -Runs 6 -NoWarm },
  { RB -Lever "cool" -Runs 6 -NoWarm }
)
for ($i = $From; $i -le [Math]::Min($To, $steps.Count); $i++) {
  Write-Host "=== queue step $i"
  & $steps[$i - 1]
  if (-not (Test-Path (Join-Path (Split-Path (Split-Path (Split-Path $PSScriptRoot))) "hailmary-work\phone-ok"))) { Write-Host "phone no longer handed over: stop"; break }
}