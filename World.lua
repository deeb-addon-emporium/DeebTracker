-- world: zone changes, instance enter/leave, deaths, gold
local DT = DeebTracker

local lastMoney = nil
local lastLootOpen = 0
local lastDeath = 0
local crumbM, crumbX, crumbY = nil, nil, nil

local function zone()
	local z = GetRealZoneText and GetRealZoneText() or nil
	local sz = GetSubZoneText and GetSubZoneText() or nil
	if sz == "" then sz = nil end
	return z, sz
end

local function checkZone(force)
	local z, sz = zone()
	if force or z ~= DT.lastZone or sz ~= DT.lastSub then
		local changed = z ~= DT.lastZone
		DT.lastZone, DT.lastSub = z, sz
		if changed or force then DT.log("zone", { name = z }) end
	end
end

local function checkInstance()
	local inInst, kind = IsInInstance()
	local name, itype, diff, _, _, _, _, mapID = GetInstanceInfo()
	if inInst and DT.instID ~= mapID then
		DT.instID = mapID
		DT.log("inst", { mapID = mapID, name = name, kind = kind or itype, difficulty = diff })
	elseif not inInst and DT.instID then
		local was = DT.instID
		DT.instID = nil
		DT.log("instx", { mapID = was })
	end
end

local function moneyReason()
	if MerchantFrame and MerchantFrame:IsShown() then return "vendor" end
	if (LootFrame and LootFrame:IsShown()) or GetTime() - lastLootOpen < 2 then return "loot" end
	if DT.lastTurnIn and GetTime() - DT.lastTurnIn < 1.5 then return "quest" end
	if MailFrame and MailFrame:IsShown() then return "mail" end
	if AuctionHouseFrame and AuctionHouseFrame:IsShown() then return "auction" end
	if TradeFrame and TradeFrame:IsShown() then return "trade" end
	return "other"
end

local f = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "PLAYER_DEAD", "PLAYER_MONEY", "LOOT_OPENED" }) do pcall(f.RegisterEvent, f, e) end
f:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_ENTERING_WORLD" then
		C_Timer.After(1, function() checkZone(true); checkInstance(); local m = DT.plain(GetMoney()); lastMoney = m end)
	elseif event == "ZONE_CHANGED_NEW_AREA" then
		checkZone(false); checkInstance()
	elseif event == "ZONE_CHANGED" or event == "ZONE_CHANGED_INDOORS" then
		local z, sz = zone(); DT.lastZone, DT.lastSub = z, sz
	elseif event == "LOOT_OPENED" then
		lastLootOpen = GetTime()
	elseif event == "PLAYER_DEAD" then
		if GetTime() - lastDeath > 5 then
			lastDeath = GetTime()
			-- the combat log is forbidden to addons on this client; best available: your target
			local killer
			if UnitExists("target") and UnitCanAttack("player", "target") then killer = DT.plain(UnitName("target")) end
			DT.log("dead", { killer = killer })
		end
	elseif event == "PLAYER_MONEY" then
		local m = DT.plain(GetMoney())
		if m and lastMoney then
			local delta = m - lastMoney
			if delta ~= 0 then DT.log("gold", { delta = delta, reason = moneyReason() }) end
		end
		lastMoney = m
	end
end)

-- breadcrumbs: a "pos" event every 15 s while you have moved at least 1% of the map
C_Timer.NewTicker(15, function()
	if DT.paused then return end
	local m, x, y = DT.pos()
	if not m or not x then return end
	if crumbM == m and crumbX and math.abs(x - crumbX) < 1 and math.abs(y - crumbY) < 1 then return end
	crumbM, crumbX, crumbY = m, x, y
	DT.log("pos", {})
end)
