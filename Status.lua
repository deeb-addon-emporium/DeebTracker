-- /dt status, on/off, tail
local DT = DeebTracker

local function fmtTime(s)
	if not s then return "?" end
	local h = math.floor(s / 3600); local m = math.floor((s % 3600) / 60)
	return string.format("%dh %02dm", h, m)
end

SLASH_DEEBTRACKER1 = "/dt"
SlashCmdList.DEEBTRACKER = function(input)
	local cmd, rest = string.match(strtrim(input or ""), "^(%S+)%s*(.*)$")
	local d = DT.db()
	if cmd == "off" then DT.paused = true; DT.msg("paused for this session"); return end
	if cmd == "on" then DT.paused = false; DT.msg("logging"); return end
	if cmd == "tail" then
		local n = tonumber(rest) or 8
		for i = math.max(1, #d.events - n + 1), #d.events do
			local ev = d.events[i]
			local parts = {}
			for k, v in pairs(ev) do
				if k ~= "e" and k ~= "t" and k ~= "st" and k ~= "c" and k ~= "z" and k ~= "sz" and k ~= "raw" then parts[#parts + 1] = k .. "=" .. tostring(v) end
			end
			DT.msg(string.format("%s  %s  %s", date("%H:%M:%S", ev.t), ev.e, table.concat(parts, " ")))
		end
		return
	end
	if cmd == "flush" then DT.msg("the file only writes on logout or /reload - do a /reload to flush now"); return end
	if cmd == "wipe" and rest == "yes" then d.events = {}; d.cursor = 0; DT.msg("event log wiped"); return end
	local since = DT.loginAt and (GetTime() - DT.loginAt) or 0
	local perHour = since > 60 and math.floor(DT.sessionXP / (since / 3600)) or 0
	local chars = 0; for _ in pairs(d.chars) do chars = chars + 1 end
	DT.msg(string.format("%s | %d events (%d not yet uploaded) across %d chars | ~%d KB on disk",
		DT.paused and "PAUSED" or "logging", #d.events, #d.events - (d.cursor or 0), chars, math.floor(#d.events * 120 / 1024)))
	DT.msg(string.format("this session: %s in, %d XP, %d XP/hour | played %s | last: %s",
		fmtTime(since), DT.sessionXP, perHour, fmtTime(DT.played()), d.events[#d.events] and d.events[#d.events].e or "-"))
	DT.msg("/dt tail [n]  /dt off  /dt on  /dt wipe yes")
end
