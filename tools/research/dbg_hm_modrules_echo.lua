function widget:GetInfo() return { name = "HM modrules echo", layer = 0, enabled = true } end
function widget:Initialize()
	Spring.Echo(string.format("[hm-modrules] losMipLevel %s airMipLevel %s radarMipLevel %s", tostring(Game.losMipLevel), tostring(Game.airMipLevel), tostring(Game.radarMipLevel)))
	widgetHandler:RemoveWidget()
end