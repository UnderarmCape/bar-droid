-- User widget for tools/ui-screenshot.ps1: once the game runs, a screenshot (screenshots/ in the write dir), then quit.
-- bardroid_shot_chat = 1: a few chat lines first (the chat's layout on the phone's screens).
function widget:GetInfo()
	return { name = "BAR Droid screenshot", desc = "Screenshot after the game started, then quit", author = "BAR Droid",
		layer = 0, enabled = true }
end

local CHAT = {
	"gg",
	"anyone have a spare con for the front? my left side is collapsing fast and I need help over here",
	"push mid now, their t2 air is coming",
	"nice!",
}
local chat = Spring.GetConfigInt("bardroid_shot_chat", 0) == 1
local shotAt, quitAt
function widget:GameFrame(f)
	if chat and f >= 40 and f < 40 + #CHAT * 15 and (f - 40) % 15 == 0 then
		Spring.SendCommands("say " .. CHAT[(f - 40) / 15 + 1])
	end
	if not shotAt and f >= 150 then
		shotAt = f
		Spring.SendCommands("screenshot png")
		Spring.Echo("[uishot] screenshot at frame " .. f)
	elseif shotAt and not quitAt and f >= shotAt + 30 then
		quitAt = f
		Spring.Echo("[uishot] done")
		Spring.SendCommands("quitforce")
	end
end
