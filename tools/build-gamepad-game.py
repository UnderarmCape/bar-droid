"""Packages Kailil's controller support (BAR Controller Support v0.8.5, the BARGAMEPAD project's branch
controller/codex-v085-perf: controller/codex-v085-release plus performance work that keeps its behaviour) for the
phone: app/src/main/assets/gamepad/gamepad.zip plus gamepad.properties.

v0.8.5 is BAR's own game with the controller added (new widgets, edits inside ten of BAR's widgets), ported onto one
BAR release. On the phone it runs as BAR's developer game ("Beyond All Reason $VERSION", what the lobby's
"Beyond All Reason Dev" setting plays): games/BAR-gamepad.sdd holds only the files v0.8.5 added or changed, and its
modinfo.lua depends on that BAR release, which the app downloads from BAR's servers. The engine loads an archive's own
files before its dependencies', so v0.8.5's files win.

Not packaged: BAR artwork v0.8.5 copied under new names (LICENSE.md next to them names the originals), and BAR files
the lobby reads from the game's own archive (modoptions.lua); the app copies those from the downloaded release
(gamepad.properties "copy.N = <destination> <source>"). Changed on the way, for
Android: the controller's "companion status" panel is off (the app is the companion and always runs).

Stripped for the phone (Kailil, 2026-10-26: "we can get rid of the debug stuff and the hints menu all together. and
remove bindings menu and UI and all that bloat ... its too clunky to use on mobile"): the button hints are off, and
the bindings menu, the UI layout editor, the SmartX mouse audit, v0.8.5's tests and its test-runner change are left
out (MOBILE_LEFT_OUT). The game keeps everything that plays: the camera widget, its radials and the pad bridge.

  python -I tools/build-gamepad-game.py [--repo DIR] [--branch NAME] [--out DIR] [--unpack SDD --bar-data DIR]
  python -I tools/build-gamepad-game.py --unpack-only --unpack SDD --bar-data DIR   # the committed package, as installed
"""
import argparse, gzip, hashlib, io, json, os, re, subprocess, sys, urllib.request, zipfile

ap = argparse.ArgumentParser()
ap.add_argument("--repo", default=r"C:\Tools\BARGAMEPAD\src\bar-codex", help="any checkout of the BAR game repository")
# v0.8.5 with the performance work (same behaviour, ~92% less Lua garbage; HANDOFF.md "Gamepad")
ap.add_argument("--branch", default="controller/codex-v085-perf")
ap.add_argument("--out", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "app", "src", "main", "assets", "gamepad"))
ap.add_argument("--unpack", metavar="SDD", help="also unpack the package there, as the app does (needs --bar-data)")
ap.add_argument("--bar-data", metavar="DIR", help="a BAR data folder with the base release's packages/ and pool/")
ap.add_argument("--unpack-only", action="store_true",
                help="with --unpack: unpack the package already in --out, no rebuild (no git, no network)")
ARGS = ap.parse_args()
REPO, BRANCH, OUT = ARGS.repo, ARGS.branch, ARGS.out
BASE_COMMIT = "a61703336e586233f242376ec3b7855d00855ff5"   # BAR Release 2026.10.20-1, what v0.8.5 was ported to
BASE_TAG = "byar:git:" + BASE_COMMIT
VERSIONS = "https://repos-cdn.beyondallreason.dev/byar/versions.gz"
# Left out of the phone's game: menus and tools too clunky on a phone, and test code (the widgets that use them check
# for them first). A left-out change to one of BAR's own files means BAR's file plays.
MOBILE_LEFT_OUT = (
    "luaui/Widgets/gui_controller_bindings_ui.lua",
    "luaui/Widgets/gui_controller_ui_layout.lua",
    "luaui/Include/controller_ui_editor_input.lua",
    "luaui/Include/controller_ui_editor_workspace.lua",
    "luaui/Widgets/gui_controller_smartx_mouse_audit.lua",
    "luaui/Widgets/dbg_test_runner.lua",
    "luaui/Tests/",
)
# Copies of BAR artwork in v0.8.5 (luaui/images/controller/stat-icons/LICENSE.md): destination <- BAR's file
BAR_COPIES = {
    "luaui/images/controller/stat-icons/metal.png": "luaui/images/metal.png",
    "luaui/images/controller/stat-icons/energy.png": "luaui/images/energy.png",
    "luaui/images/controller/stat-icons/health.png": "luaui/images/info_health.png",
}
# BAR files the lobby reads from the game's own archive, without its dependencies (Chobby's modoptions panel:
# VFS.UseArchive(game) then modoptions.lua; without it the Skirmish screen stays empty). The release's own copy.
LOBBY_COPIES = {
    "modoptions.lua": "modoptions.lua",
}


def git(*args):
    return subprocess.run(["git", "-C", REPO, *args], capture_output=True, check=True).stdout


def base_package():
    """The rapid name and package md5 of the BAR release, from BAR's own index (it must be downloadable)."""
    req = urllib.request.Request(VERSIONS, headers={"User-Agent": "BARDroid-build-gamepad-game"})
    for line in gzip.decompress(urllib.request.urlopen(req, timeout=60).read()).decode("utf-8", "replace").splitlines():
        f = line.split(",", 3)
        if f[0] == BASE_TAG and len(f) == 4:
            return f[3], f[1]
    sys.exit(f"{BASE_TAG} is not in {VERSIONS}")


def main():
    commit = git("rev-parse", BRANCH).decode().strip()
    if git("merge-base", BASE_COMMIT, commit).decode().strip() != BASE_COMMIT:
        sys.exit(f"{BRANCH} is not based on {BASE_COMMIT}")
    names = git("diff", "--name-only", "--diff-filter=AM", BASE_COMMIT, commit, "--", "luaui", "controller-ui").decode().split("\n")
    names = sorted(n for n in names if n and not n.startswith(MOBILE_LEFT_OUT))
    if git("diff", "--name-only", "--diff-filter=DR", BASE_COMMIT, commit, "--", "luaui", "controller-ui").strip():
        sys.exit("v0.8.5 deletes or renames BAR files: an overlay cannot express that")
    base_name, base_md5 = base_package()

    os.makedirs(OUT, exist_ok=True)
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w") as z:
        def put(name, data):   # fixed timestamps: the same commit gives the same zip (and version)
            z.writestr(zipfile.ZipInfo(name, (2026, 1, 1, 0, 0, 0)), data, zipfile.ZIP_DEFLATED, 9)

        for n in names:
            data = git("show", f"{commit}:{n}")
            if n.lower() in BAR_COPIES:
                if data != git("show", f"{BASE_COMMIT}:{BAR_COPIES[n.lower()]}"):
                    sys.exit(f"{n} is no longer a copy of BAR's {BAR_COPIES[n.lower()]}")
                continue
            if n == "controller-ui/shipping-defaults.json":
                doc = json.loads(data)
                doc["settings"]["components"]["companionStatus"]["enabled"] = False
                doc["settings"]["components"]["hints"]["enabled"] = False
                data = (json.dumps(doc, indent=2) + "\n").encode()
            put(n, data)
        put("modinfo.lua", MODINFO.format(commit=commit, base=base_name).encode())
    copies = sorted(BAR_COPIES)
    missing = [c for c in copies if c not in [n.lower() for n in names]]
    if missing:
        sys.exit(f"not in v0.8.5 any more: {missing}")
    zbytes = buf.getvalue()
    with open(os.path.join(OUT, "gamepad.zip"), "wb") as f:
        f.write(zbytes)
    all_copies = {**BAR_COPIES, **LOBBY_COPIES}
    copy_lines = [f"{dst} {all_copies[dst]}" for dst in sorted(all_copies)]
    # (the version covers the copies too: a phone with the same zip but fewer copies installs it again)
    digest = hashlib.sha256(zbytes + "\n".join(copy_lines).encode()).hexdigest()[:10]
    props = [
        "# written by tools/build-gamepad-game.py",
        f"version = v0.8.5-{commit[:10]}-{digest}",
        f"branch = {BRANCH}",
        f"commit = {commit}",
        f"base.tag = {BASE_TAG}",
        f"base.name = {base_name}",
        f"base.md5 = {base_md5}",
    ] + [f"copy.{i} = {line}" for i, line in enumerate(copy_lines)]
    with open(os.path.join(OUT, "gamepad.properties"), "w", newline="\n") as f:
        f.write("\n".join(props) + "\n")
    print(f"{len(names) - len(copies)} files from {commit[:10]} on {base_name} ({base_md5}): "
          f"gamepad.zip {len(zbytes) // 1024} KB")
    if ARGS.unpack:
        unpack(ARGS.unpack, ARGS.bar_data)


def unpack(sdd, bar_data):
    """What Installer.installGamepadGame does on the phone, from gamepad.zip and gamepad.properties in --out: the zip,
    then the copies (BAR's icons, modoptions.lua) from the base release's pool."""
    import shutil
    props = {}
    for line in open(os.path.join(OUT, "gamepad.properties"), encoding="utf-8"):
        if "=" in line and not line.startswith("#"):
            k, v = line.split("=", 1)
            props[k.strip()] = v.strip()
    shutil.rmtree(sdd, ignore_errors=True)
    zipfile.ZipFile(os.path.join(OUT, "gamepad.zip")).extractall(sdd)
    data = gzip.open(os.path.join(bar_data, "packages", props["base.md5"] + ".sdp")).read()
    pool, i = {}, 0
    while i < len(data):
        n = data[i]
        name = data[i + 1:i + 1 + n].decode().lower()
        pool[name] = data[i + 1 + n:i + 17 + n].hex()
        i += 1 + n + 16 + 8
    for key, value in props.items():
        if not key.startswith("copy."):
            continue
        dst, src = value.split()
        md5 = pool[src.lower()]
        os.makedirs(os.path.dirname(os.path.join(sdd, dst)), exist_ok=True)
        with gzip.open(os.path.join(bar_data, "pool", md5[:2], md5[2:] + ".gz")) as f, open(os.path.join(sdd, dst), "wb") as o:
            o.write(f.read())
    print("unpacked to", sdd)


MODINFO = """-- BAR Droid: Kailil's BAR Controller Support v0.8.5 ({commit}) as BAR's developer game.
-- Only v0.8.5's own files are here; the rest of the game is the BAR release it was ported to (depend).
return {{
	name = "Beyond All Reason",
	description = "Beyond All Reason",
	shortName = "BYAR",
	version = "$VERSION",
	mutator = "Official",
	game = "Beyond All Reason",
	shortGame = "BYAR",
	modtype = 1,
	url = "https://www.beyondallreason.info",
	depend = {{ "{base}" }},
}}
"""

if __name__ == "__main__":
    if ARGS.unpack_only:
        if not (ARGS.unpack and ARGS.bar_data):
            sys.exit("--unpack-only needs --unpack and --bar-data")
        unpack(ARGS.unpack, ARGS.bar_data)
    else:
        main()
