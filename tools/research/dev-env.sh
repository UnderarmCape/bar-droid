# BAR Droid hail-mary research hook (branch research/hail-mary): tools/research/research-bench.ps1 puts this at
# files/bar/dev-env.sh for its runs and takes it away afterwards (a developer's own dev-env.sh is kept in
# research/dev-env.orig.sh meanwhile and still applied). launch-bar.sh sources it right before the engine starts.
# Only a benchmark start (MODE=bench) with research/lever.conf present changes: the engine is started through
# research/wrap/spring (research/wrap-spring.sh), which applies the lever. Any other start is mainline.
[ -f "$BAR/research/dev-env.orig.sh" ] && . "$BAR/research/dev-env.orig.sh"
if [ "$MODE" = bench ] && [ -f "$BAR/research/lever.conf" ]; then
  ENGINE="$BAR/research/wrap"
  log "research lever: $(grep -v '^#' "$BAR/research/lever.conf" | tr '\n' ' ')"
fi
