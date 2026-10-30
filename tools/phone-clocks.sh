# The phone's clocks every 5 s while a benchmark runs (tools/phone-bench.ps1 runs it through adb shell, Android's shell
# user): CPU clusters' clock and cap (MHz), GPU clock, cap and busy %, Android's thermal status and the AP/skin
# temperatures. Ends after $1 seconds or when /data/local/tmp/bardroid-clocks.stop exists.
end=$(( $(date +%s) + ${1:-900} ))
rm -f /data/local/tmp/bardroid-clocks.stop
k=/sys/class/kgsl/kgsl-3d0
# the fastest cluster's first core (the last cpufreq policy): the Fold7's cpu6, the S23 Ultra's prime cpu7 (its cpu6 is
# a middle core); phone-bench.ps1 reads the 4th and 5th columns as the prime core's clock and cap
p=$(ls /sys/devices/system/cpu/cpufreq | sed -n 's/^policy//p' | sort -n | tail -n 1)
p=${p:-6}
echo "time cpu0 cap0 cpu$p cap$p gpu gpucap busy status temps"
n=0
rm -f /data/local/tmp/bardroid-threads.txt
while [ "$(date +%s)" -lt "$end" ] && [ ! -e /data/local/tmp/bardroid-clocks.stop ]; do
  n=$((n + 1))
  # ~70 s in (the battle at its biggest): the busiest threads over 3 s, every one of them heat
  [ $n -eq 14 ] && top -H -b -n 2 -d 3 -m 30 -s 3 -o TID,USER,%CPU,CPU,NAME,CMD |
    awk '/^ *TID/ { block++ } block == 2' > /data/local/tmp/bardroid-threads.txt
  c0=$(( $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq) / 1000 ))
  m0=$(( $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq) / 1000 ))
  c6=$(( $(cat /sys/devices/system/cpu/cpu$p/cpufreq/scaling_cur_freq) / 1000 ))
  m6=$(( $(cat /sys/devices/system/cpu/cpu$p/cpufreq/scaling_max_freq) / 1000 ))
  g=$(( $(cat $k/devfreq/cur_freq) / 1000000 )); gm=$(( $(cat $k/devfreq/max_freq) / 1000000 ))
  b=$(cat $k/gpu_busy_percentage | tr -d ' %')
  t=$(dumpsys thermalservice | sed -n '/Current temperatures from HAL/,/Current cooling/p' |
    grep -E 'mName=(AP|SKIN|BAT|PA)[^,]*,' | sed 's/.*mValue=\([0-9.]*\).*mName=\([A-Z_]*\).*/\2=\1/' | tr '\n' ' ')
  s=$(dumpsys thermalservice | grep -m1 'Thermal Status' | sed 's/[^0-9]//g')
  echo "$(date +%H:%M:%S) $c0 $m0 $c6 $m6 $g $gm $b $s $t"
  sleep 5
done
