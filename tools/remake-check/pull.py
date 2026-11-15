"""BAR's gui_buildmenu.lua, gui_ordermenu.lua, gui_mission_info.lua, gui_teamstats.lua and gui_options.lua from the
phone's BAR release, read as the make-*.py tools read them (tools/remake-check.ps1):
    python -I pull.py <repository> <adb> <outdir>   -> <outdir>/<buildmenu|ordermenu|missioninfo|teamstats|options>.bar and .info
ANDROID_SERIAL names the phone."""
import importlib.util, os, sys

repo, adb, out = sys.argv[1:4]
for tool, name in (("make-buildmenu.py", "buildmenu"), ("make-ordermenu.py", "ordermenu"),
                   ("make-missioninfo.py", "missioninfo"), ("make-teamstats.py", "teamstats"),
                   ("make-options.py", "options")):
    spec = importlib.util.spec_from_file_location(name, os.path.join(repo, "tools", tool))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    release, md5, raw = mod.bar_file(None, adb)
    with open(os.path.join(out, name + ".bar"), "wb") as f:
        f.write(raw)
    with open(os.path.join(out, name + ".info"), "w", encoding="utf-8", newline="\n") as f:
        f.write(release + "\n" + md5 + "\n")
    print(name, release, md5)

# The files the phone engine patches (assets/bardroid/phone-*.lua.patch), as BAR's release has them, for
# tools/phone-lua-check.py: <outdir>/barlua/luaui/widgets/... and luarules/gadgets/... (one BAR no longer has is left
# out: phone-lua-check names it)
import glob
assets = os.path.join(repo, "app", "src", "main", "assets", "bardroid")
kinds = {"phone-widget-": "luaui/widgets/", "phone-gadget-": "luarules/gadgets/"}
spec = importlib.util.spec_from_file_location("phone_files", os.path.join(repo, "tools", "make-buildmenu.py"))
mb = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mb)
for path in sorted(glob.glob(os.path.join(assets, "phone-*.lua.patch"))):
    base = os.path.basename(path)
    for prefix, folder in kinds.items():
        if not base.startswith(prefix):
            continue
        name = base[len(prefix):-len(".patch")]
        mb.FILE = folder + name
        try:
            release, md5, raw = mb.bar_file(None, adb)
        except SystemExit:
            print("phone", folder + name, "not in BAR's release")
            continue
        dest = os.path.join(out, "barlua", *folder.strip("/").split("/"), name)
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        with open(dest, "wb") as f:
            f.write(raw)
        print("phone", folder + name, md5)
