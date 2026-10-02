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
	if cmd == "splits" then DT.splits.command(rest); return end
	if cmd == "mapdump" then
		-- the explored-area art for a map: what the world map paints over the base parchment.
		-- Saved to DeebTrackerDB.mapArt[mapID] so the route page can draw the explored map.
		local id = tonumber(rest) or (C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player"))
		if not id or not (C_MapExplorationInfo and C_MapExplorationInfo.GetExploredMapTextures) then DT.msg("no map / no exploration API"); return end
		local ok, list = pcall(C_MapExplorationInfo.GetExploredMapTextures, id)
		if not ok or type(list) ~= "table" then DT.msg("could not read map " .. tostring(id)); return end
		local out = {}
		for i, tex in ipairs(list) do
			local ids = {}
			for j, fid in ipairs(tex.fileDataIDs or {}) do ids[j] = fid end
			out[i] = { w = tex.textureWidth, h = tex.textureHeight, x = tex.offsetX, y = tex.offsetY,
				top = tex.isDrawOnTopLayer or nil, ids = ids }
		end
		d.mapArt = d.mapArt or {}
		d.mapArt[id] = { t = time(), layers = out, name = C_Map.GetMapInfo and (C_Map.GetMapInfo(id) or {}).name }
		DT.msg(string.format("saved %d explored map layers for map %d - /reload to write them to disk", #out, id))
		return
	end
	if cmd == "flush" then DT.msg("the file only writes on logout or /reload - do a /reload to flush now"); return end
	if cmd == "wipe" and rest == "yes" then d.events = {}; DT.msg("event log wiped"); return end
	local since = DT.loginAt and (GetTime() - DT.loginAt) or 0
	local perHour = since > 60 and math.floor(DT.sessionXP / (since / 3600)) or 0
	local chars = 0; for _ in pairs(d.chars) do chars = chars + 1 end
	local pending = 0
	for _, e in ipairs(d.events) do if not d.uploadedThrough or (e.t or 0) > d.uploadedThrough then pending = pending + 1 end end
	DT.msg(string.format("%s | %d events (%d not yet uploaded) across %d chars | ~%d KB on disk",
		DT.paused and "PAUSED" or "logging", #d.events, pending, chars, math.floor(#d.events * 300 / 1024)))
	DT.msg(string.format("this session: %s in, %d XP, %d XP/hour | played %s | last: %s",
		fmtTime(since), DT.sessionXP, perHour, fmtTime(DT.played()), d.events[#d.events] and d.events[#d.events].e or "-"))
	local wr = DT.refreshWR and DT.refreshWR()
	if wr == nil then
		DT.msg("Well-Rested: unknown (buffs are hidden in combat) | spell " .. tostring(d.wellRestedSpell))
	elseif wr == 0 then
		DT.msg("Well-Rested: none | spell " .. tostring(d.wellRestedSpell))
	else
		DT.msg(string.format("Well-Rested: x%d (+%d%% XP)%s | spell %s", wr, wr * 3,
			DT.wrLeft and string.format(", %dm left", math.floor(DT.wrLeft / 60)) or "", tostring(d.wellRestedSpell)))
	end
	DT.msg("/dt tail [n]  /dt off  /dt on  /dt splits  /dt mapdump [mapID]  /dt wipe yes")
end
