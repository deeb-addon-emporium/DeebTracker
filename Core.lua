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
DT.VERSION = "1.0"
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
	d.chars = d.chars or {}; d.events = d.events or {}; d.cursor = d.cursor or 0
	return d
end
DT.db = db

function DT.played()
	if not DT.playedBase then return nil end
	return math.floor(DT.playedBase + (GetTime() - DT.playedAt))
end

function DT.char()
	if DT.charKey then return DT.charKey end
	local name, realm = UnitName("player"), GetRealmName()
	DT.charKey = (name or "?") .. "-" .. (realm or "?")
	return DT.charKey
end

-- append one event. fields is a table of the event's own data; secret numbers are nil'd.
function DT.log(kind, fields)
	if DT.paused then return end
	local d = db()
	local ev = { e = kind, t = time(), st = GetServerTime and GetServerTime() or nil,
		s = DT.loginAt and (math.floor((GetTime() - DT.loginAt) * 10) / 10) or nil,
		p = DT.played(), c = DT.char(), L = UnitLevel("player"),
		z = DT.lastZone, sz = DT.lastSub, inst = DT.instID }
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
	-- cap: only drop events the app already uploaded
	if n > DT.MAX_EVENTS and d.cursor > 0 then
		local drop = math.min(d.cursor, n - DT.MAX_EVENTS)
		for _ = 1, drop do table.remove(d.events, 1) end
		d.cursor = d.cursor - drop
	elseif n > DT.MAX_EVENTS and not DT.warnedCap then
		DT.warnedCap = true
		DT.msg("over " .. DT.MAX_EVENTS .. " events and nothing uploaded yet - still logging, but let the app sync")
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
		DT.log("played", { total = total, atLevel = lvl })
	elseif event == "PLAYER_LEVEL_UP" then
		touchChar()
	end
end)
