# The engine's memory every 5 s while it runs (tools/phone-memory.ps1): seconds since the start, Android's GL mtrack
# (the engine's GPU memory: RAM on a phone, never swapped), its resident memory (the GPU memory included: it is mapped
# into the engine) and swapped memory, the phone's available memory, all in kB; "gone" when the engine ended before
# the time was up.
#   sh phone-memory.sh <seconds> <output file>
secs=${1:-150}; out=${2:-/data/local/tmp/bardroid-mem.txt}
: > "$out"
t=0; seen=0
while [ $t -lt "$secs" ]; do
  p=$(pidof spring)
  if [ -n "$p" ]; then
    seen=1
    m=$(dumpsys meminfo "$p" 2>/dev/null)
    gl=$(echo "$m" | sed -n 's/^ *GL mtrack *\([0-9][0-9]*\).*/\1/p' | head -n 1)
    rss=$(echo "$m" | sed -n 's/.*TOTAL RSS: *\([0-9][0-9]*\).*/\1/p' | head -n 1)
    swp=$(echo "$m" | sed -n 's/.*TOTAL SWAP[^:]*: *\([0-9][0-9]*\).*/\1/p' | head -n 1)
    av=$(sed -n 's/^MemAvailable: *\([0-9][0-9]*\).*/\1/p' /proc/meminfo)
    echo "$t ${gl:-0} ${rss:-0} ${swp:-0} ${av:-0}" >> "$out"
  elif [ $seen = 1 ]; then
    echo "$t gone" >> "$out"
    break
  fi
  sleep 5
  t=$((t + 5))
done
echo done >> "$out"
