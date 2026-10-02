-- XP: kills from the combat XP chat line, level ups, and the PLAYER_XP_UPDATE delta matcher.
-- The matcher attributes each XP delta to the quest turn-in or kill line seen within 1 s;
-- anything unmatched is logged as "ox" (exploration, discovery, and whatever else the beta adds).
local DT = DeebTracker

local lastXP, lastMax, lastLevel = nil, nil, nil
local recentKill = nil          -- { xp=, mob=, at= }

-- Mob facts for "is this mob worth it": max HP and level, read when you target it. Those can be
-- secret in combat on this client, so they're taken whenever readable (usually before the pull)
-- and kept per mob name in DeebTrackerDB.mobs. Kills also carry the fight time: seconds from
-- entering combat (or the previous kill in the same fight) to this kill.
local fightStart = nil
local function noteTarget()
	if not UnitExists("target") or UnitIsPlayer("target") or not UnitCanAttack("player", "target") then return end
	local name = DT.plain(UnitName("target"))
	local hp = DT.plain(UnitHealthMax("target"))
	local lvl = DT.plain(UnitLevel("target"))
	if not name or not hp or hp <= 0 then return end
	local d = DT.db(); d.mobs = d.mobs or {}
	local m = d.mobs[name] or {}
	m.hp = math.max(m.hp or 0, hp)                  -- rares/elites of the same name never shrink it
	if lvl and lvl > 0 then m.lo = math.min(m.lo or lvl, lvl); m.hi = math.max(m.hi or lvl, lvl) end
	m.seen = time()
	d.mobs[name] = m
end

local function snapshot()
	local x = DT.plain(UnitXP("player")); local m = DT.plain(UnitXPMax("player"))
	lastXP, lastMax, lastLevel = x, m, UnitLevel("player")
end

-- Well-Rested: Forever's Cozy Sleeping Bag buff, +3% XP per stack, up to 3 stacks (player report;
-- Silvara's quest XP ran at exactly 1.03x Wowhead's numbers with one stack). DT.log stamps every
-- XP event with wr = stacks (0 = none) so base XP is xp / (1 + 0.03 * wr). Aura reads throw while
-- auras are secret (combat), so the count is read whenever allowed and the cached value stamps
-- combat kills. Matched by name until the spell id has been seen once, then by id.
DT.WR_NAME = "well.?rested"     -- "Well-Rested", or the same without the hyphen
DT.wr, DT.wrLeft = nil, nil      -- nil = not read yet
local function readWellRested()
	if C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret() then return nil end
	if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return nil end
	local d = DT.db()
	for i = 1, 40 do
		local a = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
		if not a then return 0 end
		local sid = DT.plain(a.spellId)
		local name = DT.plain(a.name)
		if (sid and sid == d.wellRestedSpell) or (type(name) == "string" and string.find(string.lower(name), DT.WR_NAME)) then
			if sid then d.wellRestedSpell = sid end
			local n = DT.plain(a.applications) or 0
			local exp = DT.plain(a.expirationTime)
			return math.max(n, 1), sid, (exp and exp > 0) and math.floor(exp - GetTime()) or nil
		end
	end
	return 0
end

function DT.refreshWR()
	local ok, n, sid, left = pcall(readWellRested)
	if not ok then
		if not DT.wrWarned then DT.wrWarned = true; DT.msg("could not read your buffs: " .. tostring(n)) end
		return DT.wr
	end
	if n == nil then return DT.wr end
	local old = DT.wr
	DT.wr, DT.wrLeft = n, left
	if (old ~= nil and n ~= old) or (old == nil and n > 0) then
		DT.log("wr", { stacks = n, from = old, spell = sid, left = left })
	end
	return n
end

local wrQueued = false
local function queueWR()
	if wrQueued then return end
	wrQueued = true
	C_Timer.After(0.3, function() wrQueued = false; DT.refreshWR() end)
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
for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "CHAT_MSG_COMBAT_XP_GAIN", "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP",
	"PLAYER_TARGET_CHANGED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }) do pcall(f.RegisterEvent, f, e) end
pcall(f.RegisterUnitEvent, f, "UNIT_AURA", "player")
f:SetScript("OnEvent", function(_, event, a1, a2)
	if event == "UNIT_AURA" then
		queueWR()
	elseif event == "PLAYER_TARGET_CHANGED" then
		pcall(noteTarget)
	elseif event == "PLAYER_REGEN_DISABLED" then
		fightStart = GetTime()
	elseif event == "PLAYER_REGEN_ENABLED" then
		fightStart = nil
		queueWR()
	elseif event == "PLAYER_ENTERING_WORLD" then
		snapshot()
		queueWR()
	elseif event == "CHAT_MSG_COMBAT_XP_GAIN" then
		local mob, xp, rested, group = parseKill(a1 or "")
		-- "You gain N experience." with no mob is a quest turn-in (the quest module logs those);
		-- counting it here made every turn-in a fake kill. Only "<mob> dies, you gain" is a kill.
		if xp and mob then
			recentKill = { xp = xp, mob = mob, at = GetTime() }
			DT.sessionXP = DT.sessionXP + xp
			local ft = fightStart and (math.floor((GetTime() - fightStart) * 10) / 10) or nil
			if fightStart then fightStart = GetTime() end          -- a second mob in the same fight times from here
			DT.log("kx", { mob = mob, xp = xp, rested = rested, group = group, ft = ft, raw = a1 })
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
