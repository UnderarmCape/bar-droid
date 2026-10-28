# The hail-mary phone queue, in order of expected payoff (each research-bench.ps1 call takes and releases the phone
# lock; it does nothing without hailmary-work\phone-ok, see research-bench.ps1). Engine builds must exist in
# hailmary-work\out (hailmary-work\scripts\build-engine.ps1). Afterwards: python -I tools\research\summary.py --markdown
#   powershell -ExecutionPolicy Bypass -File tools\research\queue.ps1 [-From 1]
param([int]$From = 1)
$rb = Join-Path $PSScriptRoot "research-bench.ps1"
function RB { powershell -NoProfile -ExecutionPolicy Bypass -File $rb @args 2>&1 | ForEach-Object { "$(Get-Date -Format HH:mm:ss) $_" } }
$steps = @(
  # 1: the biggest compile-time levers against baselines (warms the phone first)
  { RB -Lever "baseline,eng-oryon-lto,baseline,eng-max-nopgo,workers8,baseline" },
  # 2: where the phone's time goes (simpleperf, official engine with its debug symbols, and our build)
  { RB -Lever "baseline,eng-oryon-lto" -Perf 30 -NoWarm },
  # 3: PGO training run (instrumented engine; profiles to hailmary-work\pgo, then build oryon-lto-pgo and max)
  { RB -Lever "eng-pgo-gen" -Train -NoWarm },
  # 4: Lua: LuaUI off, gadget trim, widget trim, both
  { RB -Lever "no-luaui,gadgets-trim,baseline,widgets-trim,lua-min,baseline" -NoWarm },
  # 5: the rest of the engine builds and the CPU levers
  { RB -Lever "eng-oryon-lto-nosync,eng-oryon-lto-fast,eng-oryon,eng-clang-o3,baseline,pin-main7,taskset-prime,mimalloc,baseline" -NoWarm },
  # 6 (round 2): modrules knobs, the main thread's draw/sim split, frame caps, sound, huge pages
  { RB -Lever "mr-los,mr-avoid6,mr-quadpos6,baseline,mr-quad256,mr-quad64,mr-path,mr-overlap,mr-all,baseline" -NoWarm },
  { RB -Lever "draw-balance05,draw-balance0,cap30,cap20,baseline,sound-off,thp-glibc,thp-mimalloc,baseline" -NoWarm },
  # 7 (round 2): engine patches (GAME_SPEED 20, damage events to synced Lua only, system libm) and worker counts
  { RB -Lever "eng-sw,eng-animdfs,eng-nohash-rt,eng-dmgsync,eng-sw-all,baseline,eng-gs20,eng-syslibm,baseline,workers5,workers7,workers8,baseline" -NoWarm },
  # 8 (round 2): soak pair, ~15 min each: steady-state CPU cap of the cool setup against the default
  { RB -Lever "baseline" -Runs 6 -NoWarm },
  { RB -Lever "cool" -Runs 6 -NoWarm },
  # 9: the ceiling: every lever at once, against baselines
  { RB -Lever "everything,baseline,everything" -NoWarm }
)
for ($i = $From; $i -le $steps.Count; $i++) {
  Write-Host "=== queue step $i"
  & $steps[$i - 1]
  if (-not (Test-Path (Join-Path (Split-Path (Split-Path (Split-Path $PSScriptRoot))) "hailmary-work\phone-ok"))) { Write-Host "phone no longer handed over: stop"; break }
}
