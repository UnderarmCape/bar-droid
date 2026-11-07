# The app's processes thread by thread (docs/CONTAINER-COST.md): CPU ticks and context switches, twice, $1 seconds
# apart, each process's block stamped with /proc/uptime. Run as the app (run-as) or the shell; tools/container-cost/
# thrdiff.ps1 turns the two snapshots into % of a core per thread.
snap() {
  for p in $(pidof com.underarmcape.bardroid) $(pidof bardroid-x11) $(pidof libproot.so) $(pidof spring) $(pidof recoil-main); do
    echo "U $p $(cut -d' ' -f1 /proc/uptime)"
    for t in /proc/$p/task/*; do
      s=$(cat $t/stat 2>/dev/null) || continue
      c=$(grep ctxt_switches $t/status 2>/dev/null | tr -s ' \t' ' ' | cut -d' ' -f2 | tr '\n' ' ')
      comm=${s#*(}; comm=${comm%%)*}
      rest=${s##*) }
      set -- $rest
      echo "T $p ${t##*/} $(echo $comm | tr ' ' '_') $1 ${12} ${13} $c"
    done
  done
}
snap
echo ===
sleep $1
snap
