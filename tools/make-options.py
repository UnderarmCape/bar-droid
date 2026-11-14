"""The app's Settings (app/src/main/assets/bardroid/bardroid_options.lua) from BAR's own Options window.

Kailil, 2026-11-13: "Fully rebuild the settings menu to fit mobile. Our vertical and horizontal aspect ratio", and of the
three ways asked about, "The engine rebuild/patch method". BAR's Options (luaui/Widgets/gui_options.lua) is a window
950 x 610 times the screen's height over 1080: upright on a phone about 1770 pixels wide on a 936 wide screen, its
values cut off. The app cannot change it from a user widget: BAR's sandbox keeps the widget handler from user widgets,
and Options needs it for most of its settings (a switch that turns a widget on or off, the saved config, the order
list), and `/option` is a command BAR drops from them. The engine branch loads the app's widgets as the game's
(BarDroidGameWidgetsDir, launch-bar.sh BARDROID_GAME_WIDGETS=1), where a widget has the real handler: there this copy runs
in BAR's place (GetInfo replaces), the same code laid out for a phone:
  - upright: the window the screen's width under BAR's top bar down to its foot; a header of two rows (the title, the
    search and a close button; then BAR's two switches, the note that changes wait for a restart at their left), BAR's
    tabs as a grid of buttons three across under it, the list and the description strip the window's width;
  - sideways: BAR's layout as large as the screen allows, a close button at the header's right end;
  - both: rows and words larger, for fingers; BAR's Options' saved state (its first time setup done, the open tab)
    taken over the first time; with BAR's official engine (a user widget) it gives way to BAR's own.
Each change is marked "BAR Droid:" in the copy.

Takes BAR's file from the byar:test release (BAR's Windows install, or --adb a phone's) and records its pool md5; it also
writes the patches beside the copy, and the phone makes the copy again itself when an update changes BAR's file
(Installer, BuildMenuPatches). A patch that no longer finds its place stops the tool.
    python -I tools/make-options.py [--bar-data <BAR data folder> | --adb <adb.exe>] [--check]   (ANDROID_SERIAL names the phone)
"""
import argparse
import importlib.util
import os
import sys

APP = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(APP, "app", "src", "main", "assets", "bardroid", "bardroid_options.lua")
PATCHES_OUT = os.path.join(APP, "app", "src", "main", "assets", "bardroid", "bardroid_options.patches")
FILE = "luaui/widgets/gui_options.lua"


def bar_file(bar, adb):
    """(release name, pool md5, bytes) of FILE, read as tools/make-buildmenu.py reads BAR's Build menu."""
    spec = importlib.util.spec_from_file_location("make_buildmenu", os.path.join(APP, "tools", "make-buildmenu.py"))
    mb = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mb)
    mb.FILE = FILE
    return mb.bar_file(bar, adb)


HEADER = """\
-- BAR Droid settings: BAR's own Options (luaui/Widgets/gui_options.lua, by Floris, GPL v2 or later), from {release},
-- unchanged except where marked "BAR Droid:" (Kailil, 2026-11-13: "Fully rebuild the settings menu to fit mobile. Our
-- vertical and horizontal aspect ratio"): upright the window the screen's size, the tabs a grid of buttons over the
-- list; sideways as large as the screen allows; larger rows for fingers; a close button. Runs only as one of the game's
-- widgets (the engine branch, launch-bar.sh BARDROID_GAME_WIDGETS), where it has BAR's widget handler. Made by
-- tools/make-options.py; do not edit by hand, run it again. When an update changes BAR's file the phone makes it again
-- from the new file (the line below names the one it was made from; Installer, BuildMenuPatches).
-- BARDROID_OPTIONS_FROM {md5}
"""

# (what to find, exactly once; what goes in its place)
PATCHES = [
    ('''		name = "Options",
		desc = "",
''',
     '''		name = "BAR Droid settings", -- BAR Droid: its own name (two widgets of one name: one of them is not loaded)
		desc = "BAR's Options laid out for a phone, upright and sideways (BAR Droid)",
		-- BAR Droid: BAR's own off while this runs (BAR's widget handler: GetInfo replaces; back on if this one is not
		-- running, as with BAR's official engine, where this is a user widget and gives way: Initialize)
		replaces = "Options",
'''),
    ('''	rowHighlight = true, -- light up the row under the mouse (what folds a family always lights up)
}
''',
     '''	rowHighlight = true, -- light up the row under the mouse (what folds a family always lights up)
}
-- BAR Droid: a phone's rows, tabs and words larger, for fingers (BAR's: 25, 14, 12.5, 12.5, 14, 29, 14, 25, 14)
tuning.rowHeight, tuning.fontSize, tuning.controlFontSize, tuning.dropdownFontSize = 34, 16, 14, 15
tuning.headingFontSize, tuning.categoryHeight, tuning.categoryFontSize = 16, 40, 16
tuning.subcategoryHeight, tuning.subcategoryFontSize = 32, 15
-- BAR Droid: upright (the screen taller than wide), the close button's rect, BAR's Options' state taken over (Initialize)
local droid = { upright = false, close = nil, configLoaded = false }
'''),
    ('''	widgetScale = (vsy / 1080)

	screenHeight = math.floor(screenHeightOrg * widgetScale)
	screenWidth = math.floor(screenWidthOrg * widgetScale)
	screenX = math.floor((vsx * centerPosX) - (screenWidth / 2))
	screenY = math.floor((vsy * centerPosY) + (screenHeight / 2))
''',
     '''	widgetScale = (vsy / 1080)

	-- BAR Droid: on a phone's screen under BAR's top bar: upright the screen's width down to its foot, the scale by the
	-- width (by the height alone the window was ~1770 pixels wide on a 936 wide screen); sideways as large as fits
	local droidTop = math.floor(vsy * (vsy > vsx and 0.045 or 0.085)) -- (BAR's top bar)
	local droidM = math.max(4, math.floor(math.min(vsx, vsy) * 0.012))
	droid.upright = vsy > vsx * 1.05
	if droid.upright then
		widgetScale = math.min(vsx / 500, vsy / 950)
		screenWidth, screenHeight = vsx - 2 * droidM, vsy - droidTop - 2 * droidM
		screenX, screenY = droidM, vsy - droidTop - droidM
	else
		widgetScale = math.min((vsx - 2 * droidM) / screenWidthOrg, (vsy - droidTop - 2 * droidM) / screenHeightOrg)
		screenHeight = math.floor(screenHeightOrg * widgetScale)
		screenWidth = math.floor(screenWidthOrg * widgetScale)
		screenX = math.floor((vsx - screenWidth) / 2)
		screenY = vsy - droidTop - droidM
	end
'''),
    ('''	searchBox:setRect(
		layout.listX1,
		rowBottom,
		layout.unfoldSwitchHit[1] - math.floor(28 * s),
		rowTop,
		math.floor((rowTop - rowBottom) * 0.5)
	)
end
''',
     '''	searchBox:setRect(
		layout.listX1,
		rowBottom,
		layout.unfoldSwitchHit[1] - math.floor(28 * s),
		rowTop,
		math.floor((rowTop - rowBottom) * 0.5)
	)

	-- BAR Droid: a close button at the header's right end (a phone has no Escape at hand, and upright no room around the
	-- window to tap). Sideways the switches and the search left of it. Upright a header of two rows (the title, the
	-- search, close; then the switches from the right), BAR's tabs a grid three across under it (droid.tabs), the list
	-- the window's width
	local closeW = math.floor(metrics.headerH * 1.5)
	if not droid.upright then
		droid.close = { a[3] - closeW, rowBottom, a[3], rowTop }
		local dx = closeW + metrics.gap
		for _, r in ipairs({ layout.switch, layout.switchHit, layout.unfoldSwitch, layout.unfoldSwitchHit }) do
			r[1], r[3] = r[1] - dx, r[3] - dx
		end
		searchBox:setRect(
			layout.listX1,
			rowBottom,
			layout.unfoldSwitchHit[1] - math.floor(28 * s),
			rowTop,
			math.floor((rowTop - rowBottom) * 0.5)
		)
		return
	end
	droid.close = { a[3] - closeW, rowBottom, a[3], rowTop }
	local titleW = math.floor(font:GetTextWidth(BAR.I18N("ui.topbar.button.settings")) * metrics.titleFs)
		+ metrics.sidePad * 2
	searchBox:setRect(
		a[1] + titleW,
		rowBottom,
		droid.close[1] - metrics.gap,
		rowTop,
		math.floor((rowTop - rowBottom) * 0.5)
	)
	local row2Top, row2Bottom = rowBottom - math.floor(4 * s), rowBottom - metrics.headerH
	local tH = math.floor((row2Top - row2Bottom) * 0.62)
	local tY1 = math.floor((row2Top + row2Bottom) * 0.5) - math.floor(tH * 0.5)
	local function hit2(switch, caption) -- (as hitArea, on the second row)
		local captionW = math.floor(font:GetTextWidth(caption) * metrics.captionFs)
		return { switch[1] - metrics.rowPad * 2 - captionW, row2Bottom, switch[3] + metrics.rowPad, row2Top }
	end
	layout.switch = { x2 - togW, tY1, x2, tY1 + tH }
	layout.switchHit = hit2(layout.switch, view.switchCaption())
	local uX2 = math.floor(layout.switchHit[1] - 16 * s)
	layout.unfoldSwitch = { uX2 - togW, tY1, uX2, tY1 + tH }
	layout.unfoldSwitchHit = hit2(layout.unfoldSwitch, BAR.I18N("ui.settings.unfoldall"))
	layout.sidebarTop = row2Bottom - metrics.inset
	layout.listX1 = a[1]
	layout.listTop = layout.sidebarTop - 3 * metrics.groupHeight - metrics.inset * 2
	-- (the controls' column narrower, the names wider: "Build menu  bottom positi..", "Windows hide the interfa.." were
	-- cut short, dev phone 2026-11-13; "Window 936 x 2013" still fits its dropdown)
	metrics.controlW = math.floor(tuning.controlsWidth * 0.85 * s)
end
'''),
    ('''function draw.sidebar()
	local a = layout.area
	local x1, x2 = a[1], a[1] + metrics.sidebarW
''',
     '''-- BAR Droid: upright, the title in the header's first row and BAR's tabs as a grid of buttons three across under the
-- header (the open one lit, under a search the tabs with matches and how many); the open tab's sections are the
-- list's own headings. The note that changes wait for a restart on the header's second row, left of the switches.
function droid.tabs()
	local a = layout.area
	font:Print(look.title .. BAR.I18N("ui.topbar.button.settings"), a[1] + metrics.sidePad, a[4] - metrics.titleY,
		metrics.titleFs, "ov")
	if changesRequireRestart then
		local w = layout.unfoldSwitchHit[1] - a[1] - metrics.sidePad * 2
		font:Print(look.restart .. text.fit(font, BAR.I18N("ui.settings.madechanges"), w, metrics.sectionFs),
			a[1] + metrics.sidePad, math.floor((layout.switchHit[2] + layout.switchHit[4]) * 0.5), metrics.sectionFs, "ov")
	end
	layout.sidebar = {}
	local searching = view.searching()
	local lit = view.litLine(searching)
	local litGroup = searching and lit and view.lines[lit].group
	local cols, gap = 3, metrics.inset
	local w = math.floor((a[3] - a[1] - (cols - 1) * gap) / cols)
	local n = 0
	for _, group in ipairs(optionGroups) do
		if
			group.numOptions > 0
			and (devMode or devUI or group.id ~= "dev")
			and (not searching or view.matches[group])
			and n < 3 * cols
		then
			local x = a[1] + (n % cols) * (w + gap)
			local top = layout.sidebarTop - math.floor(n / cols) * metrics.groupHeight
			local r = { x, top - metrics.groupHeight + gap, x + w, top }
			local selected = (not searching and group.id == currentGroupTab) or group == litGroup
			RectRound(r[1], r[2], r[3], r[4], metrics.csSmall, 1, 1, 1, 1,
				selected and look.selectedFill or look.sidebarFill, selected and look.selectedFill or look.sidebarFillTop)
			if selected then -- (a gold line along its foot, as the column marks its section)
				RectRound(r[1] + metrics.sidePad, r[2] + metrics.inset, r[3] - metrics.sidePad,
					r[2] + metrics.inset + metrics.accentW, 0, 0, 0, 0, 0, look.sectionAccent)
			end
			local count = searching and (look.count .. "  " .. view.matches[group]) or ""
			local room = w - metrics.sidePad * 2 - (searching and metrics.groupFs * 2 or 0)
			font:Print((selected and look.groupSelected or look.group) .. text.fit(font, group.name, room, metrics.groupFs)
				.. count, math.floor((r[1] + r[3]) * 0.5), math.floor((r[2] + r[4]) * 0.5), metrics.groupFs, "cov")
			layout.sidebar[#layout.sidebar + 1] = { rect = r, group = group, line = view.headingOf[group] }
			n = n + 1
		end
	end
end

-- BAR Droid: the close button (setLayout's droid.close): red, as the app's dock draws one, a white cross
function droid.drawClose(mx, my)
	local c = droid.close
	if not c then
		return
	end
	local over = math_isInRect(mx, my, c[1], c[2], c[3], c[4])
	RectRound(c[1], c[2], c[3], c[4], metrics.csSmall, 1, 1, 1, 1,
		over and { 0.55, 0.13, 0.1, 0.95 } or { 0.42, 0.08, 0.06, 0.9 }, { 0.62, 0.16, 0.12, 0.95 })
	local cx, cy = (c[1] + c[3]) * 0.5, (c[2] + c[4]) * 0.5
	local h = math.floor((c[4] - c[2]) * 0.2)
	local t = math.max(1.5, h * 0.17)
	local function bar(dx, dy) -- (a bar through the middle, t thick either side)
		local len = math.sqrt(dx * dx + dy * dy)
		local nx, ny = -dy / len * t, dx / len * t
		gl.Vertex(cx - dx + nx, cy - dy + ny)
		gl.Vertex(cx + dx + nx, cy + dy + ny)
		gl.Vertex(cx + dx - nx, cy + dy - ny)
		gl.Vertex(cx - dx - nx, cy - dy - ny)
	end
	gl.Texture(false)
	gl.Color(0.95, 0.95, 0.95, 1)
	gl.BeginEnd(GL.QUADS, function()
		bar(h, h)
		bar(h, -h)
	end)
	gl.Color(1, 1, 1, 1)
end

function draw.sidebar()
	if droid.upright then -- BAR Droid: the tabs over the list (droid.tabs)
		return droid.tabs()
	end
	local a = layout.area
	local x1, x2 = a[1], a[1] + metrics.sidebarW
'''),
    ('''	UiElement(w[1], w[2], w[3], w[4], 1, 1, 1, 1, 1, 1, 1, 1, WG.FlowUI.clampedOpacity)
''',
     '''	-- BAR Droid: nearly opaque: without the GUI shader's blur (off on phones) the map, the chat and BAR's panels under it
	-- showed through its rows (dev phone, upright, 2026-11-13)
	UiElement(w[1], w[2], w[3], w[4], 1, 1, 1, 1, 1, 1, 1, 1, math.max(0.94, WG.FlowUI.clampedOpacity or 0))
'''),
    ('''function draw.header(mx, my)
	local unfold = view.unfoldAll
''',
     '''function draw.header(mx, my)
	droid.drawClose(mx, my) -- BAR Droid: the close button
	local unfold = view.unfoldAll
'''),
    ('''	local inWindow = inRect(layout.window, mx, my)
	local pressedInside = view.pressedInside
''',
     '''	-- BAR Droid: the close button closes it as its release
	if button == 1 and droid.close and inRect(droid.close, mx, my) and not openSelect and not view.picker then
		if release then
			view.pressedInside = nil
			view.close()
		end
		return true
	end
	local inWindow = inRect(layout.window, mx, my)
	local pressedInside = view.pressedInside
'''),
    ('''function widget:Initialize()
	-- Restart-with-state restore:''',
     '''function widget:Initialize()
	-- BAR Droid: only as one of the game's widgets (the engine branch's BarDroidGameWidgetsDir), where it has the widget
	-- handler Options needs; a user widget (BAR's official engine) gives way to BAR's own (GetInfo replaces: back on
	-- while this one is not running)
	if not widgetHandler.orderList or not widgetHandler.configData then
		Spring.Echo("[bardroid-settings] not one of the game's widgets: BAR's own Options instead")
		if widgetHandler.RemoveWidget then
			widgetHandler:RemoveWidget(self)
		end
		return
	end
	-- BAR Droid: BAR's Options' saved state (its first time setup done, its version, the open tab, folded families) the
	-- first time this runs: without it the first time setup ran again (water 4, BAR's defaults over the app's) and a
	-- "newer version" turned widgets to BAR's defaults
	if not droid.configLoaded and type(widgetHandler.configData["Options"]) == "table" then
		widget:SetConfigData(widgetHandler.configData["Options"])
	end
	-- Restart-with-state restore:'''),
    ('''function widget:SetConfigData(data)
	if data.version ~= nil then''',
     '''function widget:SetConfigData(data)
	droid.configLoaded = true -- BAR Droid: its own saved state (Initialize takes BAR's Options' without one)
	if data.version ~= nil then'''),
]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--bar-data", default=os.path.join(os.environ.get("LOCALAPPDATA_REAL") or
                    os.path.expandvars(r"%USERPROFILE%\AppData\Local"), "Programs", "Beyond-All-Reason", "data"))
    ap.add_argument("--adb", help="read BAR's file off the phone with this adb, not from a BAR data folder")
    ap.add_argument("--check", action="store_true", help="only see that every patch finds its place; write nothing")
    args = ap.parse_args()
    release, md5, raw = bar_file(args.bar_data, args.adb)
    text = raw.decode("utf-8").replace("\r\n", "\n")
    for find, repl in PATCHES:
        n = text.count(find)
        if n != 1:
            sys.exit(f"BAR's Options changed: a patch finds its place {n} times (not once):\n{find}")
        text = text.replace(find, repl)
    if args.check:
        print(f"patches apply: {release}, {FILE} {md5}, {len(PATCHES)} patches")
        return
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write(HEADER.format(release=release, md5=md5) + text)
    # (the same patches for the phone: Installer makes the copy again when an update changes BAR's file, BuildMenuPatches)
    with open(PATCHES_OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write("\x1e".join([HEADER] + [part for patch in PATCHES for part in patch]))
    print(f"{OUT}: {release}, {FILE} {md5}, {len(PATCHES)} patches")


if __name__ == "__main__":
    main()
