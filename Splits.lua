-- DeebTracker live splits: a speedrun split timer for the 1-10 route.
--
-- Everything is compared against your own history in DeebTrackerDB, worked out at login:
--   * level splits: each level's /played time against your personal-best run to 10 (PB)
--   * phase splits: the route's recurring chunks against the best you've ever done each one
--     ("gold"). Kill phases run first -> last kill of the target mobs while the quest is open,
--     quest phases run accept -> turn-in: the same rules as the route dashboard.
-- A run is one character from level 1; a recreated character of the same name starts a new
-- run (the played clock or level resets). The run you're on is left out of the comparisons.
--
--   /dt splits         show / hide the window (it shows itself on characters below level 11)
--   /dt splits reset   put the window back in the middle of the screen
local DT = DeebTracker
local S = {}
DT.splits = S

local PHASES = {
	{ key = "young",   name = "Young boars & sabers", kind = "kills", mobs = { ["Young Thistle Boar"] = true, ["Young Nightsaber"] = true }, within = { 456 } },
	{ key = "grell",   name = "Grellkin",             kind = "kills", mobs = { ["Grellkin"] = true }, within = { 459 } },
	{ key = "venom",   name = "Webwood venom",        kind = "kills", mobs = { ["Webwood Spider"] = true }, within = { 916 } },
	{ key = "egg",     name = "Egg run",              kind = "quest", ids = { 917 } },
	{ key = "timber",  name = "Timberling kills",     kind = "kills", mobs = { ["Timberling"] = true }, within = { 918 } },
	{ key = "seeds",   name = "Seeds + Sprouts",      kind = "quest", ids = { 918, 919 } },
	{ key = "corrupt", name = "Gnarlpine Corruption", kind = "quest", ids = { 476 } },
	{ key = "mystic",  name = "7 Mystics",            kind = "kills", mobs = { ["Gnarlpine Mystic"] = true }, within = { 2459 } },
	{ key = "mist",    name = "Mist escort",          kind = "quest", ids = { 938 } },
}
local FIRST_L, LAST_L = 2, 10

-- ---------------------------------------------------------------------------
-- Runs and what happened in them
-- ---------------------------------------------------------------------------
-- A character's events split into runs wherever the played clock jumps back or the level drops.
local function segments(events, charKey)
	local segs, cur, lastP, lastL = {}, nil, nil, nil
	for _, e in ipairs(events) do
		if e.c == charKey then
			local p, L = e.p, e.L
			if cur and ((p and lastP and p < lastP - 600) or (L and lastL and L < lastL - 1)) then cur = nil end
			if not cur then cur = {}; segs[#segs + 1] = cur end
			cur[#cur + 1] = e
			if p then lastP = p end
			if L then lastL = L end
		end
	end
	return segs
end

local function inList(list, v) for _, x in ipairs(list) do if x == v then return true end end return false end

-- quest window: earliest accept to latest turn-in of the ids; open = accepted, not turned in yet
local function questWindow(seg, ids)
	local a, b
	for _, e in ipairs(seg) do
		if e.p and e.id and inList(ids, e.id) then
			if e.e == "qa" and (not a or e.p < a) then a = e.p end
			if e.e == "qt" and (not b or e.p > b) then b = e.p end
		end
	end
	if a and b and b < a then b = nil end
	return a, b
end

-- each phase in a run: { d = seconds, a = start, b = end, n = kills, open = still running }
local function phasesOf(seg)
	local out = {}
	for _, ph in ipairs(PHASES) do
		if ph.kind == "quest" then
			local a, b = questWindow(seg, ph.ids)
			if a then out[ph.key] = { a = a, b = b, d = b and (b - a) or nil, open = not b } end
		else
			local a, b = questWindow(seg, ph.within)
			if a then
				local first, last, n = nil, nil, 0
				for _, e in ipairs(seg) do
					if e.e == "kx" and e.p and e.mob and ph.mobs[e.mob] and e.p >= a and (not b or e.p <= b + 5) then
						n = n + 1; first = first or e.p; last = e.p
					end
				end
				if first then out[ph.key] = { a = first, b = b and last or nil, d = b and (last - first) or nil, n = n, open = not b } end
			end
		end
	end
	return out
end

-- level -> played seconds when it was reached (level 1 = 0 for runs that began at 1)
local function levelsOf(seg)
	local lv, minL = {}, nil
	for _, e in ipairs(seg) do
		if e.L then minL = math.min(minL or e.L, e.L) end
		if e.e == "lvl" and e.to and e.p then lv[e.to] = e.p end
	end
	if minL == 1 then lv[1] = 0 end
	return lv
end

-- ---------------------------------------------------------------------------
-- History: golds and the PB, from every run except the one being played
-- ---------------------------------------------------------------------------
local hist = { gold = {}, goldLv = {}, pb = nil, pbTo10 = nil, runs = 0 }

local function currentSegment()
	local d = DT.db()
	local segs = segments(d.events, DT.char())
	return segs[#segs]
end

local function buildHistory()
	local d = DT.db()
	local cur = currentSegment()
	hist = { gold = {}, goldLv = {}, pb = nil, pbTo10 = nil, runs = 0 }
	local keys = {}
	for _, e in ipairs(d.events) do if e.c then keys[e.c] = true end end
	for key in pairs(keys) do
		for _, seg in ipairs(segments(d.events, key)) do
			if seg ~= cur and (key ~= DT.char() or seg[1] ~= (cur and cur[1])) then
				local lv = levelsOf(seg)
				if lv[1] and lv[FIRST_L] then hist.runs = hist.runs + 1 end
				for L = FIRST_L, LAST_L do
					if lv[L] and lv[L - 1] then
						local s = lv[L] - lv[L - 1]
						if not hist.goldLv[L] or s < hist.goldLv[L] then hist.goldLv[L] = s end
					end
				end
				if lv[1] and lv[LAST_L] and (not hist.pbTo10 or lv[LAST_L] < hist.pbTo10) then hist.pbTo10 = lv[LAST_L]; hist.pb = lv end
				for k, v in pairs(phasesOf(seg)) do
					if v.d and (not hist.gold[k] or v.d < hist.gold[k]) then hist.gold[k] = v.d end
				end
			end
		end
	end
end

-- ---------------------------------------------------------------------------
-- Window
-- ---------------------------------------------------------------------------
local ROW_H, W = 14, 236
local GREEN, RED, GOLD, GREY, WHITE = "|cff5fd35f", "|cffff6060", "|cffffc83d", "|cff8a8a8a", "|cffffffff"

local function clock(s)
	if not s then return "-" end
	s = math.floor(s + 0.5)
	local h, m, ss = math.floor(s / 3600), math.floor(s % 3600 / 60), s % 60
	if h > 0 then return string.format("%d:%02d:%02d", h, m, ss) end
	return string.format("%d:%02d", m, ss)
end
local function delta(s)
	if not s then return "" end
	local sign = s < 0 and "-" or "+"
	return sign .. clock(math.abs(s))
end

local frame, rows, title, runLine = nil, {}, nil, nil

local function makeRow(i)
	local r = {}
	r.name = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	r.name:SetPoint("TOPLEFT", 8, -36 - (i - 1) * ROW_H); r.name:SetWidth(120); r.name:SetJustifyH("LEFT")
	r.time = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	r.time:SetPoint("TOPLEFT", 128, -36 - (i - 1) * ROW_H); r.time:SetWidth(52); r.time:SetJustifyH("RIGHT")
	r.delta = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	r.delta:SetPoint("TOPLEFT", 180, -36 - (i - 1) * ROW_H); r.delta:SetWidth(50); r.delta:SetJustifyH("RIGHT")
	rows[i] = r
	return r
end

local function setRow(i, name, time, dtext)
	local r = rows[i] or makeRow(i)
	r.name:SetText(name or ""); r.time:SetText(time or ""); r.delta:SetText(dtext or "")
end

local function ensureFrame()
	if frame then return frame end
	local d = DT.db()
	frame = CreateFrame("Frame", "DeebTrackerSplits", UIParent, "BackdropTemplate")
	frame:SetSize(W, 60)
	frame:SetFrameStrata("MEDIUM")
	frame:SetClampedToScreen(true)
	frame:SetMovable(true); frame:EnableMouse(true); frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, rel, x, y = self:GetPoint()
		DT.db().splitsPos = { point, rel, x, y }
	end)
	if frame.SetBackdrop then
		frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
		frame:SetBackdropColor(0.05, 0.06, 0.05, 0.82)
		frame:SetBackdropBorderColor(0.3, 0.33, 0.3, 0.9)
	end
	local pos = d.splitsPos
	if pos then frame:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4]) else frame:SetPoint("RIGHT", UIParent, "RIGHT", -40, 60) end
	title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOPLEFT", 8, -6); title:SetJustifyH("LEFT")
	runLine = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	runLine:SetPoint("TOPRIGHT", -8, -6); runLine:SetJustifyH("RIGHT")
	local sub = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	sub:SetPoint("TOPLEFT", 8, -21); sub:SetText("vs PB (levels) / gold (phases)")
	return frame
end

-- ---------------------------------------------------------------------------
-- Refresh: the current run against history
-- ---------------------------------------------------------------------------
local lastSummaryFor = nil

function S.refresh()
	if not frame or not frame:IsShown() then return end
	local now = DT.played()
	local seg = currentSegment() or {}
	local lv = levelsOf(seg)
	local ph = phasesOf(seg)
	local level = UnitLevel("player")
	local i = 0

	title:SetText(string.format("Splits  %s", hist.pbTo10 and (GREY .. "PB " .. clock(hist.pbTo10) .. "|r") or (GREY .. "no PB yet|r")))
	local runDelta = ""
	if now and hist.pb and hist.pb[level] and lv[level] then
		-- ahead/behind: how your current level was reached compared with the PB
		local dd = lv[level] - hist.pb[level]
		runDelta = "  " .. (dd <= 0 and GREEN or RED) .. delta(dd) .. "|r"
	end
	runLine:SetText((now and clock(now) or GREY .. "waiting for /played|r") .. runDelta)

	-- level splits: done ones show split time and the delta at that level vs the PB; the next one runs live
	for L = FIRST_L, LAST_L do
		local reached, prev = lv[L], lv[L - 1]
		local name, t, dt = "Level " .. L, "", ""
		if reached then
			local seg_s = prev and (reached - prev)
			local isGold = seg_s and (not hist.goldLv[L] or seg_s < hist.goldLv[L])
			t = clock(reached)
			if hist.pb and hist.pb[L] then local dd = reached - hist.pb[L]; dt = (dd <= 0 and GREEN or RED) .. delta(dd) .. "|r" end
			if isGold then name = GOLD .. name .. "|r" end
		elseif L == level + 1 and now then
			name = WHITE .. name .. "|r"; t = GREY .. clock(now) .. "|r"
			if hist.pb and hist.pb[L] then local dd = now - hist.pb[L]; if dd > 0 then dt = RED .. delta(dd) .. "|r" end end
		else
			name = GREY .. name .. "|r"
			if hist.pb and hist.pb[L] then t = GREY .. clock(hist.pb[L]) .. "|r" end
		end
		i = i + 1; setRow(i, name, t, dt)
	end
	i = i + 1; setRow(i, GREY .. "-- phases --|r", "", "")

	-- phases: finished ones against gold, a running one ticks live, untouched ones show the gold to beat
	for _, def in ipairs(PHASES) do
		local p, gold = ph[def.key], hist.gold[def.key]
		local name, t, dt = def.name, "", ""
		if p and p.d then
			t = clock(p.d)
			if gold then local dd = p.d - gold; dt = (dd <= 0 and GOLD or RED) .. delta(dd) .. "|r" else dt = GOLD .. "new|r" end
			if not gold or p.d < gold then name = GOLD .. name .. "|r" end
		elseif p and p.open and now then
			local run = now - p.a
			name = WHITE .. name .. "|r"; t = WHITE .. clock(run) .. "|r"
			if gold then local dd = run - gold; dt = (dd <= 0 and GREY or RED) .. delta(dd) .. "|r" end
		else
			name = GREY .. name .. "|r"; t = gold and (GREY .. clock(gold) .. "|r") or ""
		end
		i = i + 1; setRow(i, name, t, dt)
	end
	for j = i + 1, #rows do setRow(j) end
	frame:SetHeight(40 + i * ROW_H)

	-- reached 10: one summary in chat per run
	if lv[LAST_L] and lastSummaryFor ~= (seg[1] and seg[1].t) then
		lastSummaryFor = seg[1] and seg[1].t
		S.summary(lv, ph)
	end
end

function S.summary(lv, ph)
	local parts = {}
	for _, def in ipairs(PHASES) do
		local p, gold = ph[def.key], hist.gold[def.key]
		if p and p.d and gold then parts[#parts + 1] = { name = def.name, dd = p.d - gold } end
	end
	table.sort(parts, function(a, b) return a.dd > b.dd end)
	local total = lv[LAST_L]
	local pbText = hist.pbTo10 and ((total <= hist.pbTo10 and GREEN .. "NEW PB|r " or "") .. "vs PB " .. ((total - hist.pbTo10) <= 0 and GREEN or RED) .. delta(total - hist.pbTo10) .. "|r") or "first full run"
	DT.msg(string.format("level 10 in %s - %s", clock(total), pbText))
	local lost = {}
	for k = 1, math.min(3, #parts) do
		if parts[k].dd > 0 then lost[#lost + 1] = parts[k].name .. " " .. RED .. delta(parts[k].dd) .. "|r" end
	end
	if #lost > 0 then DT.msg("most time lost vs gold: " .. table.concat(lost, ", ")) end
	local golds = {}
	for _, p in ipairs(parts) do if p.dd < 0 then golds[#golds + 1] = p.name .. " " .. GOLD .. delta(p.dd) .. "|r" end end
	if #golds > 0 then DT.msg("new golds: " .. table.concat(golds, ", ")) end
end

-- ---------------------------------------------------------------------------
-- Wiring: watch the log for the events that move splits, tick once a second while shown
-- ---------------------------------------------------------------------------
local MOVES = { qa = true, qt = true, kx = true, lvl = true, played = true }
local origLog = DT.log
DT.log = function(kind, fields)
	local ev = origLog(kind, fields)
	if MOVES[kind] and frame and frame:IsShown() then
		-- a phase finishing on this event: announce a gold as it happens
		if kind == "qt" then
			local before = S.lastPhases or {}
			local ph = phasesOf(currentSegment() or {})
			for _, def in ipairs(PHASES) do
				local p, old = ph[def.key], before[def.key]
				if p and p.d and not (old and old.d) then
					local gold = hist.gold[def.key]
					if gold then DT.msg(string.format("%s %s (%s)", def.name, clock(p.d), (p.d <= gold and GOLD .. "gold " or RED) .. delta(p.d - gold) .. "|r")) end
				end
			end
			S.lastPhases = ph
		end
		pcall(S.refresh)
	end
	return ev
end

local function wanted()
	local d = DT.db()
	if d.splitsHidden then return false end
	return UnitLevel("player") <= LAST_L
end

function S.setShown(show)
	ensureFrame()
	frame:SetShown(show)
	if show then pcall(S.refresh) end
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
	C_Timer.After(2, function()
		pcall(buildHistory)
		S.lastPhases = phasesOf(currentSegment() or {})
		if wanted() then S.setShown(true) end
	end)
end)
C_Timer.NewTicker(1, function() if frame and frame:IsShown() then pcall(S.refresh) end end)

function S.command(rest)
	local d = DT.db()
	if rest == "reset" then
		d.splitsPos = nil
		ensureFrame(); frame:ClearAllPoints(); frame:SetPoint("CENTER")
		S.setShown(true); d.splitsHidden = nil
		return
	end
	local show = not (frame and frame:IsShown())
	d.splitsHidden = not show
	if show then pcall(buildHistory) end
	S.setShown(show)
	DT.msg("splits " .. (show and "shown" or "hidden") .. string.format(" (%d past run(s), PB %s)", hist.runs, clock(hist.pbTo10)))
end
