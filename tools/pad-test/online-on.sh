# tools/pad-test.ps1 -Online, in the app's folder: the next skirmish plays BAR's released game with user widgets' orders
# forbidden, as a host can forbid them online (the modoption allowunitcontrolwidgets). The controller game is switched
# off only if it was on, and files/padtest-gamepad-was-on says so for online-off.sh (a player who had it off keeps it off).
if grep -q 'name="gamepadGame" value="true"' shared_prefs/*.xml; then
  sed -i 's/name="gamepadGame" value="true"/name="gamepadGame" value="false"/' shared_prefs/*.xml
  touch files/padtest-gamepad-was-on
fi
printf '%s\n' "sed -i 's/deathmode=com;/deathmode=com;allowunitcontrolwidgets=0;/' \"\$BAR/skirmish.txt\"" > files/bar/dev-env.sh
