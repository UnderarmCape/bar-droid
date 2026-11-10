"""BAR's gui_buildmenu.lua, gui_ordermenu.lua and gui_mission_info.lua from the phone's BAR release, read as
make-buildmenu.py, make-ordermenu.py and make-missioninfo.py read them (tools/remake-check.ps1):
    python -I pull.py <repository> <adb> <outdir>   -> <outdir>/<buildmenu|ordermenu|missioninfo>.bar and .info
ANDROID_SERIAL names the phone."""
import importlib.util, os, sys

repo, adb, out = sys.argv[1:4]
for tool, name in (("make-buildmenu.py", "buildmenu"), ("make-ordermenu.py", "ordermenu"),
                   ("make-missioninfo.py", "missioninfo")):
    spec = importlib.util.spec_from_file_location(name, os.path.join(repo, "tools", tool))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    release, md5, raw = mod.bar_file(None, adb)
    with open(os.path.join(out, name + ".bar"), "wb") as f:
        f.write(raw)
    with open(os.path.join(out, name + ".info"), "w", encoding="utf-8", newline="\n") as f:
        f.write(release + "\n" + md5 + "\n")
    print(name, release, md5)
