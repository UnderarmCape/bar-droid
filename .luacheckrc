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
-- BAR's own Build and Order menus, Mission Info, TeamStats and Settings copied by tools/make-buildmenu.py,
-- make-ordermenu.py, make-missioninfo.py, make-teamstats.py and make-options.py (BAR's code and style; their changes are
-- checked in a game; the Settings copy came after this list and failed laptop-tests' lint with BAR's 34 warnings)
exclude_files = { "app/src/main/assets/bardroid/bardroid_buildmenu.lua", "app/src/main/assets/bardroid/bardroid_ordermenu.lua",
	"app/src/main/assets/bardroid/bardroid_missioninfo.lua", "app/src/main/assets/bardroid/bardroid_teamstats.lua",
	"app/src/main/assets/bardroid/bardroid_options.lua" }
-- the lobby's widget runs in Chobby's LuaMenu, which gives its widgets i18n (its words in the player's language)
files["app/src/main/assets/bardroid/bardroid_lobby_touch.lua"] = { read_globals = { "i18n" } }
-- the test widgets that stand in for Spring's calls (a teammate's share recorded, speak to chat's sends): on purpose
files["tools/pad-test/bardroid_pad_share_test.lua"] = { ignore = { "122" } }
files["tools/pad-test/bardroid_chat_voice_test.lua"] = { ignore = { "122" } }
