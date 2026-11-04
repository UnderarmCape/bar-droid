# engine branch (docs/ENGINE-SIM.md), "+allcpu": every CPU for the engine. It starts with a CPU mask that leaves out the
# dev phone's prime core 7 (0x3f, 0x5f, 0x3b... from its first log line on, while the shell that starts it has all 8:
# set from outside as it starts), and Android's side may not change it (SELinux: Permission denied from run-as); the
# app's own shell can. So, from here, every 3 s: each engine thread allowed on every CPU of its cpuset again.
(
  for i in $(seq 1 1200); do
    sleep 3
    p=$(pidof spring 2>/dev/null)
    [ -n "$p" ] || continue
    for t in /proc/$p/task/*; do taskset -p ff "${t##*/}" >/dev/null 2>&1; done
  done
) &
log "engine-sim: the engine's threads allowed on every CPU, every 3 s"
