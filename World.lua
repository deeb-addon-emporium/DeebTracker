-- world: zone changes, instance enter/leave, deaths, gold
local DT = DeebTracker

local lastMoney = nil
local lastDamageSource = nil

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
	if LootFrame and LootFrame:IsShown() then return "loot" end
	if DT.lastTurnIn and GetTime() - DT.lastTurnIn < 1.5 then return "quest" end
	if MailFrame and MailFrame:IsShown() then return "mail" end
	if AuctionHouseFrame and AuctionHouseFrame:IsShown() then return "auction" end
	if TradeFrame and TradeFrame:IsShown() then return "trade" end
	return "other"
end

local f = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "PLAYER_DEAD", "PLAYER_MONEY", "COMBAT_LOG_EVENT_UNFILTERED" }) do pcall(f.RegisterEvent, f, e) end
f:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_ENTERING_WORLD" then
		C_Timer.After(1, function() checkZone(true); checkInstance(); local m = DT.plain(GetMoney()); lastMoney = m end)
	elseif event == "ZONE_CHANGED_NEW_AREA" then
		checkZone(false); checkInstance()
	elseif event == "ZONE_CHANGED" or event == "ZONE_CHANGED_INDOORS" then
		local z, sz = zone(); DT.lastZone, DT.lastSub = z, sz
	elseif event == "PLAYER_DEAD" then
		DT.log("dead", { killer = lastDamageSource })
	elseif event == "PLAYER_MONEY" then
		local m = DT.plain(GetMoney())
		if m and lastMoney then
			local delta = m - lastMoney
			if delta ~= 0 then DT.log("gold", { delta = delta, reason = moneyReason() }) end
		end
		lastMoney = m
	elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
		local ok, _, sub, _, _, srcName, _, _, destGUID = pcall(CombatLogGetCurrentEventInfo)
		if ok and sub and destGUID == UnitGUID("player") and (string.find(sub, "_DAMAGE", 1, true)) and srcName then
			local n = DT.plain(srcName)
			if n then lastDamageSource = n end
		end
	end
end)
