# The hail-mary levers (dot-sourced by research-bench.ps1). Each: Conf = research/lever.conf (wrap-spring.sh reads it);
# optional Prepare (once, before its runs: push files), Before/After (around each run), Scale (resolution %).
$Eng = "/root/bar/engine/recoil_2026.07.04"
$RA = "/root/bar/research"
function PushEngine([string]$name) {
  # a research engine dir: our spring binary, everything else linked to the official engine dir
  $bin = Join-Path $HM "out\$name\spring"
  if (-not (Test-Path $bin)) { throw "no research engine build at $bin" }
  $have = AppSh "md5sum files/bar/research/engine-$name/spring 2>/dev/null | cut -c1-32"
  $want = (Get-FileHash -Algorithm MD5 $bin).Hash.ToLower()
  if ("$have".Trim() -ne $want) {
    Write-Host "[research] pushing engine build $name ($([int]((Get-Item $bin).Length / 1MB)) MB)"
    PushFile $bin "files/bar/research/engine-$name/spring"
  }
  AppSh @"
d=files/bar/research/engine-$name; chmod 755 `$d/spring
for f in files/bar/engine/recoil_2026.07.04/*; do n=`$(basename "`$f"); case "`$n" in spring) ;; *) [ -e "`$d/`$n" ] || ln -s "$Eng/`$n" "`$d/`$n" ;; esac; done
ls `$d | tr '\n' ' '; echo
"@
}
# The gadget-trim overlay game "BAR Hail Mary 1" (files/bar/games/BAR-hailmary.sdd): depends on the game the benchmark
# runs and replaces gadget files with a one-line stub that declines to load (a chunk returning false). Only our own
# stubs: no BAR content. The gadgets: every synced one that ran on damage/explosion events in the laptop profile
# (tools/research/dbg_hm_synced_profile.lua) and the costliest unsynced effects (tools/profile/dbg_bardroid_gadget_profile.lua),
# APIs other gadgets and widgets read (Unit Attributes API, Stats, Team stats, Widget Events) kept.
$TrimGadgets = @("unit_explosion_spawner", "unit_juno_damage", "gfx_explosion_lights", "unit_paralyze_damage_limit",
  "gfx_watersplash", "gfx_emp_lightning", "unit_airunitsturnradius", "unit_evolution", "unit_shield_behaviour",
  "unit_jammed_fix", "unit_commando_watch", "unit_collision_damage_behavior", "game_energy_conversion", "unit_objectify",
  "gfx_reclaim_fx", "unit_crashing_aircraft", "unit_respawning", "unit_stun_script", "unit_hats", "unit_paralyze_on_off",
  "unit_paralyze_damage_multiplier", "gfx_tree_feller", "unit_death_animations", "gfx_fire_gl4", "gfx_beam_laser_gl4",
  "gfx_fire_smoke_gl4", "snd_notifications", "gfx_nano_particles_gl4", "snd_battle_volume_controller", "gui_display_dps")
function PushOverlay([switch]$Trim, [string]$Modrules = "", [string]$depend = "Beyond All Reason `$VERSION") {
  $g = "files/bar/games/BAR-hailmary.sdd"
  AppSh "rm -rf $g" | Out-Null
  PushText "-- BAR Droid hail-mary research overlay (never shipped): $depend$(if ($Trim) { ', gadgets switched off' })$(if ($Modrules) { ", modrules $Modrules" })`nreturn { name = `"BAR Hail Mary`", shortName = `"BYAR`", version = `"1`", game = `"Beyond All Reason`", shortGame = `"BYAR`", modtype = 1, depend = { `"$depend`" } }`n" "$g/modinfo.lua"
  if ($Trim) {
    $sh = ($TrimGadgets | ForEach-Object { "echo 'return false -- hail-mary: off' > $g/luarules/gadgets/$_.lua" }) -join "`n"
    AppSh "mkdir -p $g/luarules/gadgets`n$sh`nls $g/luarules/gadgets | wc -l"
  }
  if ($Modrules) {
    # BAR's own modrules.lua of the release the phone's benchmark game depends on, from the laptop's BAR install,
    # edited at run time (modrules-override.py); never kept: it lives only in the overlay, removed after the session
    $relScript = @'
sed -n 's/.*depend = { "\([^"]*\)".*/\1/p' files/bar/games/BAR-gamepad.sdd/modinfo.lua
'@
    $rel = "$(AppSh $relScript)".Trim()
    $tmp = Join-Path $HM "tmp\modrules.lua"
    & (Join-Path $TC "hosttools\python\python.exe") -I (Join-Path $Here "modrules-override.py") $BarData $rel $Modrules $tmp
    if ($LASTEXITCODE) { throw "modrules override for '$rel' failed (is that release in the laptop's BAR install?)" }
    PushFile $tmp "$g/gamedata/modrules.lua"
    Remove-Item $tmp
    PushFile (Join-Path $Here "dbg_hm_modrules_echo.lua") "$g/luaui/Widgets/dbg_hm_modrules_echo.lua"
  }
}
function PushAlloc {
  foreach ($f in "libmimalloc.so.3", "libjemalloc.so.2", "libtcmalloc_minimal.so.4") {
    $have = AppSh "[ -f files/bar/research/lib/$f ] && echo yes"
    if ("$have".Trim() -ne "yes") { PushFile (Join-Path $HM "alloc\usr\lib\aarch64-linux-gnu\$f") "files/bar/research/lib/$f" }
  }
}

# ONLINE-SAFE ONLY since 2026-10-27 ~20:00 (Kailil: "we MUST have online play enabled. so only do online safe
# adjustments"): online play needs the official engine binary and BAR's own game archive, so every R_ENGINE build, the
# overlay games (gadget trim, modrules) and the start-script hacks are culled from the queue (kept below as the record of
# round 1-2). Online-safe = the engine and game unchanged, only client-side settings, the OS and local widgets.
$Culled = @("eng-clang-o3", "eng-oryon", "eng-oryon-lto", "eng-pgo-gen", "eng-oryon-lto-pgo", "eng-oryon-lto-fast",
  "eng-oryon-lto-nosync", "eng-max-nopgo", "eng-max", "eng-sw", "eng-animdfs", "eng-nohash-rt", "eng-dmgsync", "eng-sw-all",
  "eng-gs20", "eng-syslibm", "everything", "gadgets-trim", "lua-min", "no-luaui", "no-luaui-min", "mr-los", "mr-avoid6",
  "mr-quadpos6", "mr-quad256", "mr-quad64", "mr-path", "mr-overlap", "mr-all")
$Levers = [ordered]@{
  # the official engine through the research wrapper with nothing changed: the harness costs nothing
  "baseline"        = @{ Conf = "" }
  # thread pool size (WorkerThreadCount counts the main thread): the engine found no cache topology on the phone and
  # runs main + 3 workers (infolog: "affinity not set"); the Fold7 has 8 big cores
  "workers7"        = @{ Conf = 'R_SETTINGS="WorkerThreadCount=7"' }
  "workers8"        = @{ Conf = 'R_SETTINGS="WorkerThreadCount=8"' }
  "workers6"        = @{ Conf = 'R_SETTINGS="WorkerThreadCount=6"' }
  "workers5"        = @{ Conf = 'R_SETTINGS="WorkerThreadCount=5"' }
  # Lua garbage collection: the least the engine allows per cycle and the slowest growth-driven rate
  "lua-gc-lazy"     = @{ Conf = 'R_SETTINGS="LuaGarbageCollectionMemLoadMult=1 LuaGarbageCollectionRunTimeMult=1"' }
  # the fewest effects particles BAR allows (MaxParticles >= 10000, CLAUDE.md), no nano-spray particles
  "particles-min"   = @{ Conf = 'R_SETTINGS="MaxParticles=10000 MaxNanoParticles=0"' }
  # the whole engine on the two prime cores (4.47 GHz max) / on the six others
  "taskset-prime"   = @{ Conf = 'R_TASKSET=6-7' }
  "taskset-perf"    = @{ Conf = 'R_TASKSET=0-5' }
  # main thread alone on prime core 7, every other engine thread on 0-6 (wrap-spring.sh re-pins every 10 s)
  "pin-main7"       = @{ Conf = "R_PIN_MAIN=7`nR_PIN_OTHERS=0-6" }
  "pin-main7-w6"    = @{ Conf = "R_PIN_MAIN=7`nR_PIN_OTHERS=0-6`nR_SETTINGS=`"WorkerThreadCount=6`"" }
  # other allocators for malloc/free (the engine's own operator new is mimalloc already, USE_MIMALLOC)
  "mimalloc"        = @{ Conf = "R_PRELOAD=$RA/lib/libmimalloc.so.3"; Prepare = { PushAlloc } }
  "jemalloc"        = @{ Conf = "R_PRELOAD=$RA/lib/libjemalloc.so.2"; Prepare = { PushAlloc } }
  "tcmalloc"        = @{ Conf = "R_PRELOAD=$RA/lib/libtcmalloc_minimal.so.4"; Prepare = { PushAlloc } }
  # LuaUI off for the whole run (no widgets: no BAR interface, no bardroid widgets; the benchmark gadget still reports)
  "no-luaui"        = @{ Conf = 'R_DEBUGCMDS="16:luaui disable"' }
  # the least drawing the engine can do: interface hidden, no sky/water/trees detail, smallest ground mesh, 70%
  "min-render"      = @{ Conf = 'R_SETTINGS="AdvMapShading=0 AdvUnitShading=0 BumpWaterReflection=0 BumpWaterRefraction=0 ReflectiveWater=0 Water=0 DynamicSky=0 GroundDetail=20 MaxDynamicMapLights=0 MaxDynamicModelLights=0 MaxNanoParticles=0 3DTrees=0 TreeRadius=0 GrassDetail=0 MaxParticles=10000"
'; Scale = 70 }
  "no-luaui-min"    = @{ Conf = 'R_SETTINGS="AdvMapShading=0 AdvUnitShading=0 BumpWaterReflection=0 BumpWaterRefraction=0 ReflectiveWater=0 Water=0 DynamicSky=0 GroundDetail=20 MaxDynamicMapLights=0 MaxDynamicModelLights=0 MaxNanoParticles=0 3DTrees=0 TreeRadius=0 GrassDetail=0 MaxParticles=10000"
R_DEBUGCMDS="16:luaui disable|17:hideinterface 1"'; Scale = 70 }
  # the gadget-trim overlay (PushOverlay): game logic and effects on damage/explosion events off
  "gadgets-trim"    = @{ Conf = 'R_GAME="BAR Hail Mary 1"'; Prepare = { PushOverlay -Trim } }
  # LuaUI widgets that cost the most in the laptop's widget profile with the phone's set (tools/research/laptop-bench.ps1
  # -Widgets), off for the run (wrap-spring.sh R_WIDGETS_OFF; BYAR.lua is put back after the run)
  "widgets-trim"    = @{ Conf = 'R_WIDGETS_OFF="Sensor Ranges LOS;Unit Repeat Icons;Notifications;Attack Range GL4;Unit Stencil GL4;AdvPlayersList Music Player New;Unit Wait Icons;Attack and Move Notification;Auto Repair Idle Builders;Commander Hurt Vignette;NoDuplicateOrders;Sensor Ranges Radar;Sensor Ranges Jammer Preview;Sensor Ranges Sonar;Projectile Target AoE"' }
  # everything Lua that is not needed to run the fight: LuaUI off and the gadget trim
  "lua-min"         = @{ Conf = "R_GAME=`"BAR Hail Mary 1`"`nR_DEBUGCMDS=`"17:luaui disable`""; Prepare = { PushOverlay -Trim } }
  # --- second round (2026-10-27, "Research again. More ways") ---
  # Recoil's large-army knobs in BAR's modrules (overlay, generated from BAR's file at run time): one level coarser LOS,
  # air-LOS and radar maps; ground-unit collision avoidance and quad position updates every 6th frame instead of 3rd;
  # quadfield cells 256 / 64 elmos instead of 128; slower path updates and half the QTPFS search budget; overlapping units
  "mr-los"          = @{ Conf = 'R_GAME="BAR Hail Mary 1"'; Prepare = { PushOverlay -Modrules "sensors.los.losMipLevel=4;sensors.los.airMipLevel=5;sensors.los.radarMipLevel=3" } }
  "mr-avoid6"       = @{ Conf = 'R_GAME="BAR Hail Mary 1"'; Prepare = { PushOverlay -Modrules "movement.groundUnitCollisionAvoidanceUpdateRate=6" } }
  "mr-quadpos6"     = @{ Conf = 'R_GAME="BAR Hail Mary 1"'; Prepare = { PushOverlay -Modrules "movement.unitQuadPositionUpdateRate=6" } }
  "mr-quad256"      = @{ Conf = 'R_GAME="BAR Hail Mary 1"'; Prepare = { PushOverlay -Modrules "system.quadFieldQuadSizeInElmos=256" } }
  "mr-quad64"       = @{ Conf = 'R_GAME="BAR Hail Mary 1"'; Prepare = { PushOverlay -Modrules "system.quadFieldQuadSizeInElmos=64" } }
  "mr-path"         = @{ Conf = 'R_GAME="BAR Hail Mary 1"'; Prepare = { PushOverlay -Modrules "system.pathFinderUpdateRateScale=0.5;system.qtMaxNodesSearched=4096" } }
  "mr-overlap"      = @{ Conf = 'R_GAME="BAR Hail Mary 1"'; Prepare = { PushOverlay -Modrules "movement.allowUnitCollisionOverlap=true" } }
  "mr-all"          = @{ Conf = 'R_GAME="BAR Hail Mary 1"'; Prepare = { PushOverlay -Modrules "sensors.los.losMipLevel=4;sensors.los.airMipLevel=5;sensors.los.radarMipLevel=3;movement.groundUnitCollisionAvoidanceUpdateRate=6;movement.unitQuadPositionUpdateRate=6;system.pathFinderUpdateRateScale=0.5;system.qtMaxNodesSearched=4096" } }
  # the main thread's split: sim may take more of it when behind (engine defaults 0.15 and 2)
  "draw-balance05"  = @{ Conf = 'R_SETTINGS="MinSimDrawBalance=0.05"' }
  "draw-balance0"   = @{ Conf = 'R_SETTINGS="MinSimDrawBalance=0 MinDrawFPS=1"' }
  # frame caps (libbardroid_pace.so): fewer draw frames, less heat; compare game speed
  "cap20"           = @{ Conf = ""; Cap = 20 }
  "cap30"           = @{ Conf = ""; Cap = 30 }
  # heat: no OpenAL mixing (the openal thread was ~10 % in the main session's capture)
  "sound-off"       = @{ Conf = 'R_SETTINGS="Sound=0"' }
  # huge pages for the heap (check /sys/kernel/mm/transparent_hugepage first: the profile job prints it)
  "thp-glibc"       = @{ Conf = 'R_ENV="GLIBC_TUNABLES=glibc.malloc.hugetlb=1"' }
  "thp-mimalloc"    = @{ Conf = 'R_ENV="MIMALLOC_ALLOW_LARGE_OS_PAGES=1"' }
  # the cool setup for soak pairs (research-bench.ps1 -Runs 6 against baseline -Runs 6): 30 fps, no sound
  "cool"            = @{ Conf = 'R_SETTINGS="Sound=0"'; Cap = 30 }
  # engine patches (hailmary-work\recoil-src, tools/research/engine-build/recoil-research.patch): one arm64 build
  # oryon-lto-sw with runtime switches (-DHM_RESEARCH_SWITCHES; off unless their environment variable is set), and two
  # builds of their own (GAME_SPEED 20; ENABLE_STREFLOP=OFF = the system libm)
  "eng-sw"          = @{ Conf = "R_ENGINE=$RA/engine-oryon-lto-sw"; Prepare = { PushEngine "oryon-lto-sw" } }
  "eng-animdfs"     = @{ Conf = "R_ENGINE=$RA/engine-oryon-lto-sw`nR_ENV=`"HM_ANIM_DFS=1`""; Prepare = { PushEngine "oryon-lto-sw" } }
  "eng-nohash-rt"   = @{ Conf = "R_ENGINE=$RA/engine-oryon-lto-sw`nR_ENV=`"HM_NO_SYNC_HASH=1`""; Prepare = { PushEngine "oryon-lto-sw" } }
  "eng-dmgsync"     = @{ Conf = "R_ENGINE=$RA/engine-oryon-lto-sw`nR_ENV=`"HM_DMG_SYNCED_ONLY=1`""; Prepare = { PushEngine "oryon-lto-sw" } }
  "eng-sw-all"      = @{ Conf = "R_ENGINE=$RA/engine-oryon-lto-sw`nR_ENV=`"HM_ANIM_DFS=1 HM_NO_SYNC_HASH=1 HM_DMG_SYNCED_ONLY=1`""; Prepare = { PushEngine "oryon-lto-sw" } }
  "eng-gs20"        = @{ Conf = "R_ENGINE=$RA/engine-oryon-lto-gs20"; Prepare = { PushEngine "oryon-lto-gs20" } }
  "eng-syslibm"     = @{ Conf = "R_ENGINE=$RA/engine-oryon-lto-syslibm"; Prepare = { PushEngine "oryon-lto-syslibm" } }
  # the hail-mary ceiling: every engine lever in one build (max-all: oryon, ThinLTO, fast-math, system libm, GAME_SPEED
  # 20, switches on), LuaUI off, the gadget trim, 8 threads, the least drawing, 70 % resolution. Sim at GAME_SPEED 20:
  # compare Sim ms x 20 with baseline's x 30 (per game second)
  "everything"      = @{ Conf = "R_ENGINE=$RA/engine-max-all`nR_ENV=`"HM_ANIM_DFS=1 HM_NO_SYNC_HASH=1 HM_DMG_SYNCED_ONLY=1`"`nR_GAME=`"BAR Hail Mary 1`"`nR_DEBUGCMDS=`"17:luaui disable|18:hideinterface 1`"`nR_SETTINGS=`"WorkerThreadCount=8 AdvMapShading=0 AdvUnitShading=0 Water=0 DynamicSky=0 GroundDetail=20 MaxDynamicMapLights=0 MaxDynamicModelLights=0 MaxNanoParticles=0 MaxParticles=10000`""; Scale = 70; Prepare = { PushEngine "max-all"; PushOverlay -Trim } }
  "gamemode-perf"   = @{ Conf = ""; Before = { Adb shell "cmd game mode performance $pkg" }; After = { Adb shell "cmd game mode standard $pkg" } }
  # research engine builds (tools/research/build-engine.ps1 -> hailmary-work\out\<name>\spring)
  "eng-clang-o3"    = @{ Conf = "R_ENGINE=$RA/engine-clang-o3"; Prepare = { PushEngine "clang-o3" } }
  "eng-oryon"       = @{ Conf = "R_ENGINE=$RA/engine-oryon"; Prepare = { PushEngine "oryon" } }
  "eng-oryon-lto"   = @{ Conf = "R_ENGINE=$RA/engine-oryon-lto"; Prepare = { PushEngine "oryon-lto" } }
  "eng-pgo-gen"     = @{ Conf = "R_ENGINE=$RA/engine-pgo-gen`nR_ENV=`"LLVM_PROFILE_FILE=/root/bar/research/pgo/bench-%p.profraw`""; Prepare = { PushEngine "pgo-gen" } }
  "eng-oryon-lto-pgo" = @{ Conf = "R_ENGINE=$RA/engine-oryon-lto-pgo"; Prepare = { PushEngine "oryon-lto-pgo" } }
  # not sync-safe: FMA contraction, reassociation, reciprocals (NaN/Inf checks kept: no -ffinite-math-only)
  "eng-oryon-lto-fast" = @{ Conf = "R_ENGINE=$RA/engine-oryon-lto-fast"; Prepare = { PushEngine "oryon-lto-fast" } }
  # SYNCCHECK off (no checksum of synced state: desyncs go undetected; online play refused/unsafe)
  "eng-oryon-lto-nosync" = @{ Conf = "R_ENGINE=$RA/engine-oryon-lto-nosync"; Prepare = { PushEngine "oryon-lto-nosync" } }
  # every compile-time lever without a phone profile: oryon + ThinLTO + fast-math + no sync hashing
  "eng-max-nopgo"   = @{ Conf = "R_ENGINE=$RA/engine-max-nopgo"; Prepare = { PushEngine "max-nopgo" } }
  "eng-max"         = @{ Conf = "R_ENGINE=$RA/engine-max"; Prepare = { PushEngine "max" } }
}

# simpleperf on the engine during a run: waits for the benchmark's start, lets the fight build up, records
function Start-PerfJob([string]$name, [int]$secs) {
  $sp = Join-Path $TC "android-sdk\ndk\29.0.14206865\simpleperf\bin\android\arm64\simpleperf"
  $have = AppSh "[ -x files/simpleperf ] && echo yes"
  if ("$have".Trim() -ne "yes") { PushFile $sp "files/simpleperf"; AppSh "chmod 755 files/simpleperf" | Out-Null }
  Adb shell "setprop security.perf_harden 0" | Out-Null
  $before = [int](AppSh "grep -c 'Starting Benchmark' files/logs/launcher.log")
  Start-Job -ArgumentList $adb, $Device, $pkg, $before, $secs, $name -ScriptBlock {
    param($adb, $dev, $pkg, $before, $secs, $name)
    function S([string]$s) { $s | & $adb -s $dev exec-in run-as $pkg sh -c "tr -d '\r' > files/hm-perf.sh" | Out-Null; & $adb -s $dev exec-out run-as $pkg sh files/hm-perf.sh }
    $deadline = (Get-Date).AddMinutes(30)
    while ((Get-Date) -lt $deadline) {
      Start-Sleep 5
      if ([int](S "grep -c 'Starting Benchmark' files/logs/launcher.log") -gt $before) { break }
    }
    Start-Sleep 20
    S @"
pid=`$(pidof recoil-main || pidof spring)
pp=`$(for p in `$(pidof libproot.so proot 2>/dev/null); do echo -n "`$p,"; done)
echo "engine `$pid proot `$pp"
for p in `$pid `$(echo `$pp | tr ',' ' '); do echo "stat0 `$p `$(cut -d' ' -f2,14,15 /proc/`$p/stat)"; done
files/simpleperf record -p `$pid -e cpu-clock -f 2000 --duration $secs -o files/perf-$name.data 2>&1 | tail -n 3
for p in `$pid `$(echo `$pp | tr ',' ' '); do echo "stat1 `$p `$(cut -d' ' -f2,14,15 /proc/`$p/stat)"; done
ls /proc/`$pid/task | while read t; do echo "thread `$t `$(cat /proc/`$pid/task/`$t/comm) `$(cut -d' ' -f14,15,39 /proc/`$pid/task/`$t/stat)"; done
# Android scheduling of the engine (read only): cgroups, allowed CPUs, uclamp of its cgroup, huge pages, the threads'
# last CPU (stat field 39) and voluntary/involuntary switches
echo "cgroup `$(tr '\n' ' ' < /proc/`$pid/cgroup)"
grep -E 'Cpus_allowed_list|voluntary_ctxt' /proc/`$pid/status | tr '\n' ' '; echo
for c in top-app foreground background system-background; do echo "cpuset `$c `$(cat /dev/cpuset/`$c/cpus 2>/dev/null) uclamp `$(cat /dev/cpuctl/`$c/cpu.uclamp.min 2>/dev/null)/`$(cat /dev/cpuctl/`$c/cpu.uclamp.max 2>/dev/null)"; done
echo "thp `$(cat /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null) defrag `$(cat /sys/kernel/mm/transparent_hugepage/defrag 2>/dev/null)"
ls /proc/`$pid/task | while read t; do echo "sched `$t `$(cat /proc/`$pid/task/`$t/comm) `$(grep -E '^(nr_voluntary_switches|nr_involuntary_switches)' /proc/`$pid/task/`$t/sched 2>/dev/null | tr -s ' ' | tr '\n' ' ')"; done
"@
  }
}
function Finish-PerfJob($job, [string]$name) {
  $out = Receive-Job -Job $job -Wait -AutoRemoveJob
  $out | ForEach-Object { Write-Host "  [perf] $_" }
  $dir = Join-Path $App "build\research-perf"; New-Item -ItemType Directory -Force $dir | Out-Null
  $out | Set-Content (Join-Path $dir "perf-$name.txt")
  cmd /c "`"$adb`" -s $Device exec-out run-as $pkg cat files/perf-$name.data > `"$dir\perf-$name.data`""
  AppSh "rm -f files/perf-$name.data" | Out-Null
  Adb shell "setprop security.perf_harden 1" | Out-Null
  Write-Host "[research] profile: $dir\perf-$name.data"
}
