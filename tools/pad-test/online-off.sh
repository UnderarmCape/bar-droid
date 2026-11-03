# tools/pad-test.ps1 -Online: as online-on.sh found it. The controller game back on only if online-on.sh switched it off;
# its marker goes once the setting reads on again (pad-test.ps1 runs this again while the marker is there: a restore
# right after the app was stopped was lost twice on the dev phone, 2026-11-03).
if [ -f files/padtest-gamepad-was-on ]; then
  sed -i 's/name="gamepadGame" value="false"/name="gamepadGame" value="true"/' shared_prefs/*.xml
  grep -q 'name="gamepadGame" value="true"' shared_prefs/*.xml && rm -f files/padtest-gamepad-was-on
fi
rm -f files/bar/dev-env.sh
