# tools/pad-test.ps1 -Online: as online-on.sh found it.
sed -i 's/name="gamepadGame" value="false"/name="gamepadGame" value="true"/' shared_prefs/*.xml
rm -f files/bar/dev-env.sh
