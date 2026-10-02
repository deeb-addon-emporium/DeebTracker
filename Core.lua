-- DeebTracker core: the account-wide event log.
-- Every event carries four clocks:
--   t  = wall clock (epoch seconds, local machine)
--   st = server time (epoch seconds, GetServerTime)
--   s  = seconds since this login (GetTime based, sub-second)
--   p  = played time on this character in seconds (TIME_PLAYED_MSG + elapsed since)
-- plus c (char key), L (level), x (XP into the level), z/sz (zone, subzone), inst (instance
-- map id or nil), e (event type) and the event's own fields.
-- Numbers go through plain(): a secret value is stored as nil and the event gets secret=true.
DeebTracker = DeebTracker or {}
local DT = DeebTracker
DT.VERSION = "1.6"
DT.SCHEMA = 1
DT.MAX_EVENTS = 40000

function DT.msg(t) print("|cff80d0ffDeebTracker|r: " .. t) end

function DT.plain(v)
	if v == nil then return nil, false end
	if issecretvalue and issecretvalue(v) then return nil, true end
	return v, false
end

DT.paused = false
DT.loginAt = nil           -- GetTime() at login
DT.playedBase = nil        -- played seconds reported by the server
DT.playedAt = nil          -- GetTime() when playedBase arrived
DT.charKey = nil
DT.sessionXP = 0
DT.lastZone, DT.lastSub, DT.instID = nil, nil, nil

local function db()
	if type(DeebTrackerDB) ~= "table" then DeebTrackerDB = {} end
	local d = DeebTrackerDB
	d.schema = DT.SCHEMA; d.addonVersion = DT.VERSION
	d.chars = d.chars or {}; d.events = d.events or {}
	return d
end
DT.db = db

function DT.played()
	if not DT.playedBase then return nil end
	return math.floor(DT.playedBase + (GetTime() - DT.playedAt))
end

-- where you are: ui map id and x/y as 0-100 with one decimal (blank inside instances)
function DT.pos()
	if not C_Map or not C_Map.GetBestMapForUnit then return nil end
	local ok, m = pcall(C_Map.GetBestMapForUnit, "player")
	if not ok or not m then return nil end
	local ok2, v = pcall(C_Map.GetPlayerMapPosition, m, "player")
	if not ok2 or not v then return m end
	local x, y = DT.plain(v.x), DT.plain(v.y)
	if not x or not y then return m end
	return m, math.floor(x * 1000 + 0.5) / 10, math.floor(y * 1000 + 0.5) / 10
end

function DT.char()
	if DT.charKey then return DT.charKey end
	local name, realm = UnitName("player"), GetRealmName()
	DT.charKey = (name or "?") .. "-" .. (realm or "?")
	return DT.charKey
end

-- events that carry XP get wr = Well-Rested stacks (see XP.lua)
local XP_KINDS = { qt = true, kx = true, ox = true, qx = true }

-- append one event. fields is a table of the event's own data; secret numbers are nil'd.
function DT.log(kind, fields)
	if DT.paused then return end
	local d = db()
	local ev = { e = kind, t = time(), st = GetServerTime and GetServerTime() or nil,
		s = DT.loginAt and (math.floor((GetTime() - DT.loginAt) * 10) / 10) or nil,
		p = DT.played(), c = DT.char(), L = UnitLevel("player"),
		z = DT.lastZone, sz = DT.lastSub, inst = DT.instID }
	local m, px, py = DT.pos(); ev.m = m; ev.px = px; ev.py = py
	if XP_KINDS[kind] and DT.refreshWR then ev.wr = DT.refreshWR() end
	local xp, sec = DT.plain(UnitXP("player")); ev.x = xp; if sec then ev.secret = true end
	if fields then
		for k, v in pairs(fields) do
			if type(v) == "number" then
				local pv, s2 = DT.plain(v); ev[k] = pv; if s2 then ev.secret = true end
			else
				ev[k] = v
			end
		end
	end
	local n = #d.events + 1
	d.events[n] = ev
	-- cap: only drop events already uploaded. The Emporium app writes uploadedThrough (the newest
	-- uploaded event time) into this file while WoW is closed; events at or before it are safe.
	if n > DT.MAX_EVENTS then
		local through = d.uploadedThrough
		local drop = 0
		if through then
			while drop < n - DT.MAX_EVENTS and d.events[drop + 1] and (d.events[drop + 1].t or 0) <= through do drop = drop + 1 end
		end
		if drop > 0 then
			local kept = {}
			for i = drop + 1, n do kept[#kept + 1] = d.events[i] end
			d.events = kept
		elseif not DT.warnedCap then
			DT.warnedCap = true
			DT.msg("over " .. DT.MAX_EVENTS .. " events and nothing uploaded yet - still logging. Turn on sharing in Deeb's Addon Emporium so old events can be trimmed.")
		end
	end
	return ev
end

-- character record
local function touchChar()
	local d = db()
	local key = DT.char()
	local _, class = UnitClass("player"); local _, race = UnitRace("player")
	local rec = d.chars[key] or { firstSeen = time() }
	rec.class = class; rec.race = race; rec.faction = UnitFactionGroup("player")
	rec.level = UnitLevel("player"); rec.lastSeen = time()
	d.chars[key] = rec
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("TIME_PLAYED_MSG")
f:RegisterEvent("PLAYER_LEVEL_UP")
f:SetScript("OnEvent", function(_, event, a1, a2)
	if event == "PLAYER_LOGIN" then
		DT.loginAt = GetTime()
		db(); touchChar()
		local _, class = UnitClass("player"); local _, race = UnitRace("player")
		DT.log("login", { class = class, race = race, faction = UnitFactionGroup("player"), addon = DT.VERSION })
		pcall(RequestTimePlayed)
		C_Timer.After(3, function() DT.msg("logging - /dt for status. Data is saved on logout or /reload.") end)
	elseif event == "TIME_PLAYED_MSG" then
		local total, lvl = DT.plain(a1), DT.plain(a2)
		if total then DT.playedBase = total; DT.playedAt = GetTime() end
		if not DT.lastPlayedLog or GetTime() - DT.lastPlayedLog > 5 then
			DT.lastPlayedLog = GetTime()
			DT.log("played", { total = total, atLevel = lvl })
		end
	elseif event == "PLAYER_LEVEL_UP" then
		touchChar()
	end
end)
