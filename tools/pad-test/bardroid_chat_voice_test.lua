-- LuaUI widget for tools/pad-test.ps1 -Chat: what speak to chat sends (bardroid_chat.lua's WG.bardroidChat.voice, as
-- bardroid_touch.lua hands it the app's VoiceChat words), in a skirmish: BAR's chat sends recorded here instead of
-- sent. A message is cut to BAR's 127 bytes, never inside a character (a long sentence in Chinese, Japanese, or with
-- accents), and never a command. Logs "[padtest] PASS|FAIL <case>" and "[padtest] done".
function widget:GetInfo()
	return { name = "BAR Droid chat voice test", desc = "What speak to chat sends", author = "BAR Droid", layer = 0, enabled = true }
end

local READY_FRAME = 420
local fails, ran = 0, false
local sent, real = {}, {}
local SENDS = { "SendAllyChat", "SendPublicChat", "SendSpectatorChat" }

local function check(case, ok, detail)
	if not ok then
		fails = fails + 1
	end
	Spring.Echo("[padtest] " .. (ok and "PASS " or "FAIL ") .. case .. (detail ~= nil and (": " .. tostring(detail)) or ""))
end

-- whole UTF-8 characters only: each lead byte followed by as many continuation bytes as it says
local function wholeUtf8(s)
	local i, n = 1, #s
	while i <= n do
		local b = s:byte(i)
		local more = b < 128 and 0 or (b >= 194 and b < 224) and 1 or (b >= 224 and b < 240) and 2 or (b >= 240 and b < 245) and 3
		if not more or i + more > n then
			return false
		end
		for k = i + 1, i + more do
			local c = s:byte(k)
			if c < 128 or c >= 192 then
				return false
			end
		end
		i = i + more + 1
	end
	return true
end

local function say(text)
	local before = #sent
	WG.bardroidChat.voice(text)
	return #sent == before + 1 and sent[#sent] or nil
end

local function cases()
	local got = say("hello there")
	check("words said: sent as they are", got == "hello there", got)
	got = say("/quit now")
	check("never a command: the slash goes", got == "quit now", got)
	local cjk = string.rep("\228\184\173", 60) -- (中, 3 bytes: 180 bytes)
	got = say(cjk)
	check("a long sentence in Chinese: cut at a character, 127 bytes at most", got ~= nil and #got <= 127 and wholeUtf8(got)
		and got == string.rep("\228\184\173", 42), got and (#got .. " bytes, whole: " .. tostring(wholeUtf8(got))))
	local accents = string.rep("\195\169", 70) -- (é, 2 bytes: 140 bytes)
	got = say(accents)
	check("accents: cut at a character", got ~= nil and got == string.rep("\195\169", 63),
		got and (#got .. " bytes, whole: " .. tostring(wholeUtf8(got))))
	local exact = "a" .. string.rep("\195\169", 63) -- (127 bytes, the next character after it)
	got = say(exact .. "\195\169")
	check("a cut that falls between characters keeps all 127 bytes", got == exact, got and #got)
end

function widget:GameFrame(f)
	if f ~= READY_FRAME or ran then
		return
	end
	ran = true
	Spring.Echo("[padtest] ready")
	if not (WG.bardroidChat and WG.bardroidChat.voice) then
		check("BAR Droid chat runs", false, "no WG.bardroidChat")
	else
		for _, name in ipairs(SENDS) do
			real[name] = Spring[name]
			Spring[name] = function(text)
				sent[#sent + 1] = text
			end
		end
		local ok, err = pcall(cases)
		if not ok then
			check("the cases ran", false, err)
		end
		for _, name in ipairs(SENDS) do
			Spring[name] = real[name]
		end
	end
	Spring.Echo("[padtest] done: " .. (fails == 0 and "ALL PASS" or (fails .. " FAILED")))
end

function widget:Shutdown()
	for name, f in pairs(real) do
		Spring[name] = f
	end
end
