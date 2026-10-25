function widget:GetInfo()
	return { name = "BAR Droid fps log", desc = "Logs the frame rate to infolog every 10 s (developer)", layer = 0, enabled = true }
end

local frames, t0 = 0, nil

function widget:DrawScreen()
	frames = frames + 1
	if not t0 then
		t0 = Spring.GetTimer()
		return
	end
	local dt = Spring.DiffTimers(Spring.GetTimer(), t0)
	if dt >= 10 then
		Spring.Echo(string.format("[bardroid-fps] %.2f fps over %.1f s, game frame %d", frames / dt, dt, Spring.GetGameFrame()))
		frames, t0 = 0, Spring.GetTimer()
	end
end
