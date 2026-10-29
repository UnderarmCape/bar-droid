"""The app's resizable build menu (app/src/main/assets/bardroid/bardroid_buildmenu.lua) from BAR's own Build menu.

Kailil, 2026-10-28: "the vaniallal build menu works fine for touch. just rebuild the exact same one with the ability for
us to resize it freely". BAR's widgets take no size from another widget and BAR's sandbox ignores patched copies of its
widgets under their own name, so the app runs a copy of BAR's Build menu under its own name: the same code, with its
place and size from the app's layout editor (bardroid_layout.lua) and the few widget-handler calls a user widget makes
through BAR's stand-in for the handler. Each change is marked "BAR Droid:" in the copy.

Takes BAR's luaui/Widgets/gui_buildmenu.lua from the byar:test release in a BAR data folder's rapid pool (BAR's Windows
install, as the laptop checks use it) and records its pool md5: launch-bar.sh runs the copy only while the phone's BAR
release has that same file (Installer writes its md5 to .bardroid-buildmenu), so a BAR update to its build menu brings
BAR's own back until this is run again. A patch that no longer finds its place stops the tool.
    python -I tools/make-buildmenu.py [--bar-data <BAR data folder>]
"""
import argparse
import gzip
import os
import sys

APP = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(APP, "app", "src", "main", "assets", "bardroid", "bardroid_buildmenu.lua")
FILE = "luaui/widgets/gui_buildmenu.lua"


def bar_file(bar):
    """(release name, pool md5, bytes) of FILE in the byar:test release of the BAR data folder bar."""
    tag = None
    for root, _, files in os.walk(os.path.join(bar, "rapid")):
        if "versions.gz" in files and root.replace("\\", "/").endswith("/byar"):
            for line in gzip.open(os.path.join(root, "versions.gz")).read().decode().splitlines():
                parts = line.split(",", 3)
                if parts[0] == "byar:test":
                    tag = parts
    if not tag:
        sys.exit("byar:test is not in " + bar)
    data = gzip.open(os.path.join(bar, "packages", tag[1] + ".sdp")).read()
    i = 0
    while i < len(data):
        n = data[i]
        name = data[i + 1:i + 1 + n].decode().lower()
        md5 = data[i + 1 + n:i + 17 + n].hex()
        i += 1 + n + 16 + 8
        if name == FILE:
            with gzip.open(os.path.join(bar, "pool", md5[:2], md5[2:] + ".gz")) as f:
                return tag[3], md5, f.read()
    sys.exit(FILE + " is not in " + tag[3])


HEADER = """\
-- BAR Droid build menu: BAR's own Build menu (luaui/Widgets/gui_buildmenu.lua, by Floris, GPL v2 or later), from
-- {release}, unchanged except where marked "BAR Droid:" (Kailil, 2026-10-28: "the vaniallal build menu works fine for
-- touch. just rebuild the exact same one with the ability for us to resize it freely"): its place and size come from
-- the app's layout editor (bardroid_layout.lua), and the widget-handler calls go through BAR's stand-in for the handler
-- that user widgets get. Made by tools/make-buildmenu.py; do not edit by hand, run it again.
-- launch-bar.sh runs it instead of BAR's Build menu only while the BAR release on the phone has the same file as the
-- line below (Installer writes the md5 of BAR's file to .bardroid-buildmenu); in the controller game, which keeps its
-- own ("Build menu (controller)", the gamepad drives it), this one stands down.
-- BARDROID_BUILDMENU_FROM {md5}
"""

# (what to find, exactly once; what goes in its place)
PATCHES = [
    ('''		name = "Build menu",
		desc = "",
		author = "Floris",''',
     '''		name = "BAR Droid build menu", -- BAR Droid: its own name (BAR ignores copies under BAR's)
		desc = "BAR's Build menu, its size and place set with the BAR Droid layout editor",
		author = "Floris (BAR's Build menu), BAR Droid",'''),
    ('''		layer = 0,
		enabled = false,
		handler = true,
	}''',
     '''		layer = 0,
		enabled = false, -- BAR Droid: launch-bar.sh switches it on in place of BAR's Build menu (no handler: a user widget)
	}'''),
    ('''function widget:ViewResize()
	tracy.ZoneBeginN("W:BuildMenu:ViewResize")''',
     '''-- BAR Droid: the layout editor's settings for the menu (moved by dx, dy of the screen; size)
local function droidEdits()
	local editor = WG.BarDroidLayout
	return editor and editor.get("buildmenu") or { dx = 0, dy = 0, size = 1 }
end

-- BAR Droid: the menu for the layout editor, once it is there (BAR's own shows in it as fixed)
local droidRegistered = false
local function droidRegister()
	local editor = WG.BarDroidLayout
	if droidRegistered or not (editor and editor.register) then
		return
	end
	droidRegistered = true
	editor.register("buildmenu", {
		label = "Build menu",
		can = { move = true, size = true },
		rect = function()
			return backgroundRect[1], backgroundRect[2], backgroundRect[3], backgroundRect[4]
		end,
		relayout = function()
			widget:ViewResize()
		end,
	})
end

function widget:ViewResize()
	tracy.ZoneBeginN("W:BuildMenu:ViewResize")'''),
    ('''function widget:Update(dt)
''',
     '''function widget:Update(dt)
	droidRegister() -- BAR Droid
'''),
    ('''	backgroundRect = { posX, (posY - height) * vsy, posX2, posY * vsy }

	checkGuishader(true)''',
     '''	-- BAR Droid: the layout editor's size (width and height from the menu's bottom left corner) and place
	local droid = droidEdits()
	if droid.size ~= 1 or droid.dx ~= 0 or droid.dy ~= 0 then
		local bottom = posY - height
		width, height = width * droid.size, height * droid.size
		local w = math_floor(width * vsx)
		posX = math.clamp(posX + math_floor(droid.dx * vsx), 0, math.max(0, vsx - w))
		posX2 = posX + w
		bottom = math.clamp(bottom + droid.dy, 0, math.max(0, 1 - height))
		posY, posY2 = bottom + height, bottom
	end
	backgroundRect = { posX, (posY - height) * vsy, posX2, posY * vsy }

	checkGuishader(true)'''),
    ('''		widgetHandler:RemoveWidgetCallIn("DrawWorld", self)''',
     '''		widgetHandler:RemoveCallIn("DrawWorld") -- BAR Droid: the handler's stand-in for user widgets'''),
    ('''function widget:Initialize()
	widgetHandler:RegisterUnitCommand(widget, CMD.BUILD)
	widgetHandler:RegisterUnitCommand(widget, CMD_STOP_PRODUCTION)''',
     '''function widget:Initialize()
	-- BAR Droid: the controller game keeps its own build menu (the gamepad drives it)
	if (Game.gameVersion or ""):find("$VERSION", 1, true) or (WG.buildmenu and WG.buildmenu.controllerApiVersion) then
		Spring.Echo("[bardroid-buildmenu] the controller game: its own build menu")
		widgetHandler:RemoveWidget()
		return
	end
	widgetHandler:RegisterUnitCommand(CMD.BUILD) -- BAR Droid: the handler's stand-in for user widgets
	widgetHandler:RegisterUnitCommand(CMD_STOP_PRODUCTION)'''),
    ('''	if widgetHandler:IsWidgetKnown("Grid menu") then
		-- Grid menu needs to be disabled right now and before we recreate
		-- WG['buildmenu'] since its Shutdown will destroy it.
		widgetHandler:DisableWidgetRaw("Grid menu")
	end
''',
     '''	-- BAR Droid: BAR's Grid menu is off by launch-bar.sh (a user widget cannot switch widgets)
'''),
    ('''	widget:ViewResize()
	widget:SelectionChanged(spGetSelectedUnits())

	WG.buildmenu = {}''',
     '''	widget:ViewResize()
	widget:SelectionChanged(spGetSelectedUnits())

	droidRegister() -- BAR Droid
	WG.buildmenu = {}'''),
    ('''	WG.buildmenu = nil
end

function widget:GetConfigData()''',
     '''	if WG.buildmenu and WG.buildmenu.getSize and not WG.buildmenu.controllerApiVersion then
		WG.buildmenu = nil
	end
	if WG.BarDroidLayout and WG.BarDroidLayout.unregister then -- BAR Droid
		WG.BarDroidLayout.unregister("buildmenu")
	end
end

function widget:GetConfigData()'''),
]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--bar-data", default=os.path.join(os.environ.get("LOCALAPPDATA_REAL") or
                    os.path.expandvars(r"%USERPROFILE%\AppData\Local"), "Programs", "Beyond-All-Reason", "data"))
    args = ap.parse_args()
    release, md5, raw = bar_file(args.bar_data)
    text = raw.decode("utf-8").replace("\r\n", "\n")
    for find, repl in PATCHES:
        n = text.count(find)
        if n != 1:
            sys.exit(f"BAR's build menu changed: a patch finds its place {n} times (not once):\n{find}")
        text = text.replace(find, repl)
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write(HEADER.format(release=release, md5=md5) + text)
    print(f"{OUT}: {release}, {FILE} {md5}, {len(PATCHES)} patches")


if __name__ == "__main__":
    main()
