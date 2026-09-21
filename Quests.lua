-- quests: accepted, turned in (with the XP and money the server reports), abandoned
local DT = DeebTracker

local pendingTurnIn = {}      -- questID -> GetTime() of the turn-in, for the XP matcher
DT.lastTurnIn = 0

local function questName(id)
	if C_QuestLog and C_QuestLog.GetTitleForQuestID then
		local ok, n = pcall(C_QuestLog.GetTitleForQuestID, id); if ok and n then return n end
	end
	return nil
end

local f = CreateFrame("Frame")
for _, e in ipairs({ "QUEST_ACCEPTED", "QUEST_TURNED_IN", "QUEST_REMOVED" }) do pcall(f.RegisterEvent, f, e) end
f:SetScript("OnEvent", function(_, event, a1, a2, a3)
	if event == "QUEST_ACCEPTED" then
		local id = a1
		if type(id) ~= "number" then id = a2 end       -- older signature: (questLogIndex, questID)
		if not id then return end
		local xpShown = 0
		local ok, xp = pcall(GetQuestLogRewardXP, id); if ok then xpShown = xp end
		local qlvl
		if C_QuestLog and C_QuestLog.GetQuestDifficultyLevel then
			local ok2, l = pcall(C_QuestLog.GetQuestDifficultyLevel, id); if ok2 then qlvl = l end
		end
		DT.log("qa", { id = id, name = questName(id), qlvl = qlvl, xpShown = xpShown })
	elseif event == "QUEST_TURNED_IN" then
		local id, xp, money = a1, a2, a3
		pendingTurnIn[id] = GetTime(); DT.lastTurnIn = GetTime()
		DT.recentQuestXP = { id = id, xp = xp, at = GetTime() }
		DT.log("qt", { id = id, name = questName(id), xp = xp, money = money })
	elseif event == "QUEST_REMOVED" then
		local id = a1
		if id and not pendingTurnIn[id] then DT.log("qab", { id = id, name = questName(id) }) end
		if id then C_Timer.After(5, function() pendingTurnIn[id] = nil end) end
	end
end)
