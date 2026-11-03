#!/bin/sh
# The Java checks of tools/laptop-tests.ps1 that need no BAR install, for Linux and CI (.github/workflows/build.yml):
# Downloader.java against a local HTTP server, SettingsMerge.java on the app's springsettings.cfg, Updater.java's
# rollback on made-up files dirs, PadGame.java's gamepad controls with a made-up pointer and game, StatusText.java's
# words for players. javac and java from JAVA_HOME, else PATH. Prints each check's result; exit 1 on a failure.
#   sh tools/java-checks.sh
set -eu
cd "$(dirname "$0")/.."
bin=${JAVA_HOME:+$JAVA_HOME/bin/}
src=app/src/main/java/com/underarmcape/bardroid
work=build/java-checks
rm -rf "$work"
mkdir -p "$work"
failed=0

# check <name> <main class> <sources...>: compile into its own folder and run (the class prints "ALL PASS")
check() {
  name=$1; main=$2; shift 2
  classes=$work/$name
  mkdir -p "$classes"
  "${bin}javac" -nowarn -d "$classes" "$@"
  if out=$(JAVA_TOOL_OPTIONS="-Djava.io.tmpdir=$work" "${bin}java" -cp "$classes" "$main" $args 2>&1) &&
     printf '%s\n' "$out" | grep -q "ALL PASS"; then
    echo "PASS  $name"
  else
    printf '%s\n' "$out" | tail -n 20
    echo "FAIL  $name"
    failed=1
  fi
}

args=""
check downloader com.underarmcape.bardroid.DlTest $(find tools/downloader-test/src -name '*.java') "$src/Downloader.java"
args="app/src/main/assets/bardroid/springsettings.cfg"
check settings-merge com.underarmcape.bardroid.MergeTest tools/settings-merge-test/MergeTest.java "$src/SettingsMerge.java"
args=""
check updater com.underarmcape.bardroid.UpdaterTest $(find tools/updater-test/src tools/lobby-bridge-test/src/org -name '*.java') \
  "$src/Updater.java" "$src/Downloader.java"
rm -rf "$work"/updater-*
# (the same sources as tools/padgame-test.ps1: PadGameTest also checks BuildMenuPatches, the phone's remake of the
# menu copies)
check padgame com.underarmcape.bardroid.PadGameTest $(find tools/padgame-test/src -name '*.java') \
  "$src/PadGame.java" "$src/PadMouse.java" "$src/PadButtons.java" "$src/BuildMenuPatches.java"
check status-text com.underarmcape.bardroid.StatusTextTest tools/status-text-test/StatusTextTest.java "$src/StatusText.java"
exit $failed
