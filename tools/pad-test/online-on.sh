# tools/pad-test.ps1 -Online, in the app's folder: the next skirmish plays BAR's released game with user widgets' orders
# forbidden, as a host can forbid them online (the modoption allowunitcontrolwidgets).
sed -i 's/name="gamepadGame" value="true"/name="gamepadGame" value="false"/' shared_prefs/*.xml
printf '%s\n' "sed -i 's/deathmode=com;/deathmode=com;allowunitcontrolwidgets=0;/' \"\$BAR/skirmish.txt\"" > files/bar/dev-env.sh
