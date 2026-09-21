-- XP: kills from the combat XP chat line, level ups, and the PLAYER_XP_UPDATE delta matcher.
-- The matcher attributes each XP delta to the quest turn-in or kill line seen within 1 s;
-- anything unmatched is logged as "ox" (exploration, discovery, and whatever else the beta adds).
local DT = DeebTracker

local lastXP, lastMax, lastLevel = nil, nil, nil
local recentKill = nil          -- { xp=, mob=, at= }

local function snapshot()
	local x = DT.plain(UnitXP("player")); local m = DT.plain(UnitXPMax("player"))
	lastXP, lastMax, lastLevel = x, m, UnitLevel("player")
end

-- "Slime dies, you gain 42 experience." / "You gain 42 experience." / "(+21 Rested bonus)" / "(+10 group bonus)"
local function parseKill(text)
	local mob, xp = string.match(text, "^(.-) dies, you gain (%d+) experience")
	if not mob then xp = string.match(text, "^You gain (%d+) experience") end
	local rested = string.match(text, "%+(%d+) [Rr]ested")
	local group = string.match(text, "%+(%d+) [Gg]roup")
	return mob, tonumber(xp), tonumber(rested), tonumber(group)
end

local f = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "CHAT_MSG_COMBAT_XP_GAIN", "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP" }) do pcall(f.RegisterEvent, f, e) end
f:SetScript("OnEvent", function(_, event, a1, a2)
	if event == "PLAYER_ENTERING_WORLD" then
		snapshot()
	elseif event == "CHAT_MSG_COMBAT_XP_GAIN" then
		local mob, xp, rested, group = parseKill(a1 or "")
		if xp then
			recentKill = { xp = xp, mob = mob, at = GetTime() }
			DT.sessionXP = DT.sessionXP + xp
			DT.log("kx", { mob = mob, xp = xp, rested = rested, group = group, raw = a1 })
		end
	elseif event == "PLAYER_LEVEL_UP" then
		local to = a1
		DT.log("lvl", { from = lastLevel, to = to })
		pcall(RequestTimePlayed)
		C_Timer.After(0.5, snapshot)
	elseif event == "PLAYER_XP_UPDATE" then
		local x = DT.plain(UnitXP("player")); local m = DT.plain(UnitXPMax("player"))
		local lvl = UnitLevel("player")
		if x and lastXP and lvl == lastLevel then
			local delta = x - lastXP
			if delta > 0 then
				local now = GetTime()
				local q = DT.recentQuestXP
				if q and now - q.at < 1.5 then
					DT.sessionXP = DT.sessionXP + delta
					if q.xp and q.xp ~= delta then DT.log("qx", { id = q.id, xp = delta, reported = q.xp }) end
					DT.recentQuestXP = nil
				elseif recentKill and now - recentKill.at < 1.5 then
					recentKill = nil                  -- already counted from the chat line
				else
					DT.sessionXP = DT.sessionXP + delta
					DT.log("ox", { xp = delta })
				end
			end
		elseif x and lastXP and lvl ~= lastLevel and lastMax then
			-- crossed a level: the part of the gain before the ding
			local delta = (lastMax - lastXP) + x
			local q = DT.recentQuestXP
			if q and GetTime() - q.at < 1.5 then DT.recentQuestXP = nil
			elseif recentKill and GetTime() - recentKill.at < 1.5 then recentKill = nil
			else DT.sessionXP = DT.sessionXP + delta; DT.log("ox", { xp = delta, ding = true }) end
		end
		snapshot()
	end
end)
