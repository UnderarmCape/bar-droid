#!/bin/bash
# The engine as a research benchmark starts it (installed as files/bar/research/wrap/spring; dev-env.sh points
# launch-bar.sh's ENGINE here). launch-bar.sh runs: ./spring --isolation --write-dir /root/bar /root/bar/bench.txt
# research/lever.conf (shell variables, all optional):
#   R_ENGINE     engine dir to run (default: the official one, /root/bar/engine/recoil_$ENGINE_VER)
#   R_PRELOAD    libraries put in front of LD_PRELOAD (an allocator)
#   R_ENV        VAR=value words exported before the engine starts
#   R_TASKSET    CPU list for taskset (the engine's threads inherit it)
#   R_SETTINGS   Key=value words for springsettings: a copy of the real file with them, given to the engine with
#                --config (the real springsettings.cfg is never changed)
#   R_DEBUGCMDS  frame:command entries put into the start script's debugcommands (after "20:vsync 0")
#   R_GAME       the start script's gametype (an overlay game)
R=/root/bar/research
. "$R/lever.conf"
E="${R_ENGINE:-/root/bar/engine/recoil_${ENGINE_VER:?}}"
script="${@: -1}"
cfg="$R/springsettings.cfg"
cp /root/bar/springsettings.cfg "$cfg"
for kv in ${R_SETTINGS:-}; do
  k=${kv%%=*}; v=${kv#*=}
  sed -i "/^$k *=/d" "$cfg"; echo "$k = $v" >> "$cfg"
done
# every run: the engine's own timers (cumulative ms per part) at the benchmark's start and end, in infolog
R_DEBUGCMDS="16:debuginfo profiling|2010:debuginfo profiling${R_DEBUGCMDS:+|$R_DEBUGCMDS}"
sed -i "s/|20:vsync 0|/|20:vsync 0|$R_DEBUGCMDS|/" "$script"
[ -n "${R_GAME:-}" ] && sed -i "s/^gametype=.*;/gametype=$R_GAME;/" "$script"
# R_WIDGETS_OFF: BAR widgets (names, ;-separated) off for this run in LuaUI/Config/BYAR.lua; research-bench.ps1 puts the
# file back from research/BYAR.lua.backup after the run (BAR also saves the file when the game ends)
if [ -n "${R_WIDGETS_OFF:-}" ]; then
  f=/root/bar/LuaUI/Config/BYAR.lua
  [ -f "$R/BYAR.lua.backup" ] || cp "$f" "$R/BYAR.lua.backup"
  IFS=';' read -ra ws <<< "$R_WIDGETS_OFF"
  for w in "${ws[@]}"; do
    re=$(printf '%s' "$w" | sed 's/[][\/.*^$]/\\&/g'); rep=$(printf '%s' "$w" | sed 's/[\/&]/\\&/g')
    if grep -q "\[\"$re\"\] *= *-\?[0-9][0-9]*" "$f"; then sed -i "s/\[\"$re\"\] *= *-\?[0-9][0-9]*/[\"$rep\"] = 0/" "$f"
    else sed -i "0,/^\torder *= *{/s//\torder = {\n\t\t[\"$rep\"] = 0,/" "$f"; fi
  done
  echo "[research] widgets off: $(grep -c '\] = 0,' "$f") entries at 0 in BYAR.lua"
fi
[ -n "${R_PRELOAD:-}" ] && export LD_PRELOAD="$R_PRELOAD${LD_PRELOAD:+:$LD_PRELOAD}"
for e in ${R_ENV:-}; do export "$e"; done
pre=""; [ -n "${R_TASKSET:-}" ] && pre="taskset -c $R_TASKSET"
echo "[research] engine $E; LD_PRELOAD=${LD_PRELOAD:-}; taskset ${R_TASKSET:-none}; settings ${R_SETTINGS:-none}; debugcommands ${R_DEBUGCMDS:-none}; game ${R_GAME:-unchanged}; env ${R_ENV:-none}"
grep -E '^(debugcommands|gametype)=' "$script" | cut -c1-200 | sed 's/^/[research] /'
cd "$E" || exit 11
if [ -z "${R_PIN_MAIN:-}" ]; then exec $pre "$E/spring" --config "$cfg" "$@"; fi
# R_PIN_MAIN / R_PIN_OTHERS: the main thread (the process's first thread) on its own CPUs, every other engine thread
# on the rest; re-applied every 10 s for threads started later
$pre "$E/spring" --config "$cfg" "$@" &
pid=$!
(
  while kill -0 $pid 2>/dev/null; do
    sleep 10
    for t in /proc/$pid/task/*; do
      t=${t##*/}
      if [ "$t" = "$pid" ]; then taskset -p -c "$R_PIN_MAIN" "$t"; else taskset -p -c "${R_PIN_OTHERS:-0-7}" "$t"; fi
    done > /dev/null 2>&1
    [ -f "$R/pinned" ] || { touch "$R/pinned"; echo "[research] pinned: main thread $pid on $R_PIN_MAIN, $(ls /proc/$pid/task | wc -l) threads; others on ${R_PIN_OTHERS:-0-7}"; }
  done
  rm -f "$R/pinned"
) &
wait $pid
