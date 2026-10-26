-- User widget for tools/ui-screenshot.ps1: once the game runs, a screenshot (screenshots/ in the write dir), then quit.
function widget:GetInfo()
	return { name = "BAR Droid screenshot", desc = "Screenshot after the game started, then quit", author = "BAR Droid",
		layer = 0, enabled = true }
end

local shotAt, quitAt
function widget:GameFrame(f)
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
