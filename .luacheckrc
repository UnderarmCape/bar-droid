-- luacheck for the app's Lua widgets (app/src/main/assets/bardroid/*.lua) and the test widgets (tools/**/*.lua):
--   luacheck app/src/main/assets/bardroid tools
-- tools/laptop-tests.ps1 runs it with the toolchain's luacheck 1.2.0 (Install Toolchain.bat), else LUACHECK or PATH.
std = "lua51"
max_line_length = false
self = false -- widget:Callin(...) methods that do not use self
globals = { "widget", "gadget", "WG" } -- WG: the table widgets share
read_globals = {
	"widgetHandler", "gadgetHandler", "Spring", "gl", "GL", "VFS", "UnitDefs", "UnitDefNames", "WeaponDefs",
	"WeaponDefNames", "FeatureDefs", "Game", "CMD", "CMDTYPE", "Script", "BAR", "LOG", "Platform", "Engine",
	"SendToUnsynced", "tracy",
}
-- BAR's own Build and Order menus and Mission Info copied by tools/make-buildmenu.py, make-ordermenu.py and
-- make-missioninfo.py (BAR's code and style; their changes are checked in a game)
exclude_files = { "app/src/main/assets/bardroid/bardroid_buildmenu.lua", "app/src/main/assets/bardroid/bardroid_ordermenu.lua",
	"app/src/main/assets/bardroid/bardroid_missioninfo.lua" }
-- the test widgets that stand in for Spring's calls (a teammate's share recorded, speak to chat's sends): on purpose
files["tools/pad-test/bardroid_pad_share_test.lua"] = { ignore = { "122" } }
files["tools/pad-test/bardroid_chat_voice_test.lua"] = { ignore = { "122" } }
