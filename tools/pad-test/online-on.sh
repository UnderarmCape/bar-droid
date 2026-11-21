# tools/pad-test.ps1 -Online, in the app's folder: the next skirmish plays BAR's released game with user widgets' orders
# forbidden, as a host can forbid them online (the modoption allowunitcontrolwidgets).
printf '%s\n' "sed -i 's/deathmode=com;/deathmode=com;allowunitcontrolwidgets=0;/' \"\$BAR/skirmish.txt\"" > files/bar/dev-env.sh
