# Memory pacer for big replays on 8 GB phones (docs/ENGINE-SIM.md; a developer file: replay-memory.ps1 -Pacer appends
# it to files/bar/dev-env.sh, which launch-bar.sh sources before the engine starts). An 8v8's load allocates faster
# than Android swaps the engine's cold memory out, and its low-memory killer ends the game with 1 GB or more still
# "available". While Android's available memory is under PACER_LOW the engine is paused (SIGSTOP), until it is over
# PACER_HIGH again or PACER_MAX tenths of a second have passed; each pause is logged to launcher.log.
PACER_LOW=${PACER_LOW:-1200000}    # kB
PACER_HIGH=${PACER_HIGH:-1500000}  # kB
PACER_MAX=${PACER_MAX:-30}         # tenths of a second
(
  avail() { sed -n 's/^MemAvailable: *\([0-9]*\).*/\1/p' /proc/meminfo; }
  seen=0
  while :; do
    p=$(pidof spring)
    if [ -z "$p" ]; then
      [ "$seen" = 1 ] && exit 0
      sleep 0.5
      continue
    fi
    seen=1
    a=$(avail)
    if [ "${a:-99999999}" -lt "$PACER_LOW" ]; then
      kill -STOP $p 2>/dev/null
      n=0
      while [ "$n" -lt "$PACER_MAX" ]; do
        sleep 0.1
        n=$((n + 1))
        a=$(avail)
        [ "${a:-0}" -gt "$PACER_HIGH" ] && break
      done
      kill -CONT $p 2>/dev/null
      echo "[pacer] engine paused $((n * 100)) ms, memory available then $((a / 1024)) MB" >&2
    fi
    sleep 0.1
  done
) &
