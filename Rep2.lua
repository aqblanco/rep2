-- change frame to what chatframe output is desired
local frame = 1
--
local f = CreateFrame("FRAME",nil,UIParent)

local factionVars = {}

local cwhite, cyellow, corange, cresume = "|cffffffff","|cffffff78","|cffff7831","|r"
local fmt = string.format
local C_Reputation = C_Reputation or {}
-- Classic clients lack C_Reputation's faction list; adapt the legacy globals to its data shape.
local getfactioninfo = C_Reputation.GetFactionDataByIndex or function(index)
	local name, description, standingID, barMin, barMax, barValue, atWarWith, canToggleAtWar, isHeader, isCollapsed, hasRep, isWatched, isChild, factionID = GetFactionInfo(index)
	if not name then return nil end
	return { name = name, description = description, reaction = standingID, currentReactionThreshold = barMin, nextReactionThreshold = barMax,
		currentStanding = barValue, isHeader = isHeader, isHeaderWithRep = hasRep, isChild = isChild, factionID = factionID }
end
local getnumfactions = C_Reputation.GetNumFactions or GetNumFactions
local expandallheaders = C_Reputation.ExpandAllFactionHeaders or function() ExpandFactionHeader(0) end
local getmajorfactiondata = C_MajorFactions and C_MajorFactions.GetMajorFactionData
local isMajorFaction = C_Reputation.IsMajorFaction or (C_MajorFactions and C_MajorFactions.IsMajorFaction)
	or (getmajorfactiondata and function(factionID) return getmajorfactiondata(factionID) ~= nil end)
local hasmaxrenown = C_MajorFactions and C_MajorFactions.HasMaximumRenown
local isParagon = C_Reputation.IsFactionParagon or function() return false end
local getparagoninfo = C_Reputation.GetFactionParagonInfo
local getfriendship = C_GossipInfo and C_GossipInfo.GetFriendshipReputation
local getfriendshipranks = C_GossipInfo and C_GossipInfo.GetFriendshipReputationRanks
if not getfriendship and GetFriendshipReputation then
	getfriendship = function(factionID)
		local friendID, standing, maxRep, name, text, texture, reaction, threshold, nextThreshold = GetFriendshipReputation(factionID)
		if not friendID or friendID == 0 then return nil end
		return { friendshipFactionID = friendID, standing = standing, maxRep = maxRep, name = name, text = text, texture = texture,
			reaction = reaction, reactionThreshold = threshold, nextThreshold = nextThreshold }
	end
	getfriendshipranks = GetFriendshipReputationRanks and function(factionID)
		local currentLevel, maxLevel = GetFriendshipReputationRanks(factionID)
		return currentLevel and { currentLevel = currentLevel, maxLevel = maxLevel } or nil
	end
end
local math_abs = math.abs
local math_ceil = math.ceil
local math_fmod = math.fmod
local standingmax = 8
local standingmin = 1
local init = 0
local headersExpanded = false
local chatframe = _G["ChatFrame" .. frame]
f:RegisterEvent("UPDATE_FACTION")
if C_MajorFactions then
	f:RegisterEvent("MAJOR_FACTION_RENOWN_LEVEL_CHANGED")
	f:RegisterEvent("MAJOR_FACTION_UNLOCKED")
end

-- Renown bars reset each level, so values combine level and progress to stay monotonic; Paragon currentValue is already cumulative.
local function GetTrackedData(data)
	if isMajorFaction and isMajorFaction(data.factionID) then
		local major = getmajorfactiondata(data.factionID)
		if major and major.isUnlocked then
			local capped = hasmaxrenown(data.factionID)
			if capped and isParagon(data.factionID) then
				local currentValue, threshold = getparagoninfo(data.factionID)
				if currentValue and threshold and threshold > 0 then
					return { kind = "renown", standing = "Paragon", label = "Paragon", min = 0, max = threshold, value = currentValue, capped = true, paragon = true }
				end
			end
			local level = major.renownLevel
			local bottom = major.renownLevelThreshold * (level - 1)
			local top = bottom + major.renownLevelThreshold
			local value = capped and top or (bottom + major.renownReputationEarned)
			return { kind = "renown", standing = level, label = "Renown " .. level, min = bottom, max = top, value = value, capped = capped, paragon = false }
		end
	end
	-- Friendship standing and thresholds are cumulative.
	if getfriendship then
		local friend = getfriendship(data.factionID)
		if friend and friend.friendshipFactionID and friend.friendshipFactionID > 0 then
			local ranks = getfriendshipranks and getfriendshipranks(data.factionID)
			local level = ranks and ranks.currentLevel or friend.reactionThreshold
			local capped = friend.nextThreshold == nil
			return { kind = "friendship", standing = level, label = friend.reaction, maxLevel = ranks and ranks.maxLevel,
				min = friend.reactionThreshold, max = friend.nextThreshold or friend.standing, value = friend.standing, capped = capped, paragon = false }
		end
	end
	if data.reaction == standingmax and isParagon(data.factionID) then
		local currentValue, threshold = getparagoninfo(data.factionID)
		if currentValue and threshold and threshold > 0 then
			return { kind = "standard", standing = "Paragon", label = "Paragon", min = 0, max = threshold, value = currentValue, capped = true, paragon = true }
		end
	end
	return { kind = "standard", standing = data.reaction, label = _G["FACTION_STANDING_LABEL" .. data.reaction],
		min = data.currentReactionThreshold, max = data.nextReactionThreshold, value = data.currentStanding, capped = (data.reaction == standingmax), paragon = false }
end

local function IsTrackable(data)
	return data and (not data.isHeader or data.isHeaderWithRep) and data.name and data.factionID
end

local function TrackFaction(data)
	local t = GetTrackedData(data)
	factionVars[data.factionID] = {
		Name = data.name,
		Standing = t.standing,
		Value = t.value,
		Paragon = t.paragon,
		Kind = t.kind,
	}
end

local function ScanFaction()
if not headersExpanded then
	headersExpanded = true
	expandallheaders()
end
if (getnumfactions() == 0) then DEFAULT_CHAT_FRAME:AddMessage("Factions not yet available") end
	for i = 1, getnumfactions() do
		local data = getfactioninfo(i)
		if IsTrackable(data) then
			TrackFaction(data)
		end
	end

end

local function Report()
local tempfactions = getnumfactions()
if (tempfactions ~= 0 and init == 0) then
	ScanFaction()
	init = 1
	return
	end
	for factionIndex = 1, getnumfactions() do
		local data = getfactioninfo(factionIndex)

		if IsTrackable(data) and not factionVars[data.factionID] then
			TrackFaction(data)
		elseif IsTrackable(data) then
			local factionID = data.factionID
			local name = data.name
			local t = GetTrackedData(data)
			local standingID, barMin, barMax, barValue = t.standing, t.min, t.max, t.value
			local tracked = factionVars[factionID]

			if t.paragon ~= tracked.Paragon or t.kind ~= tracked.Kind then
				-- Values on different scales aren't comparable; rebaseline.
				tracked.Value = barValue
				tracked.Standing = standingID
				tracked.Paragon = t.paragon
				tracked.Kind = t.kind
			else
			local diff = barValue - tracked.Value
			if diff ~= 0 then
				if standingID ~= tracked.Standing then
					local newstandingtext =
						"New standing with " .. cyellow .. name .. cresume ..
						" is " .. cyellow .. tostring(t.label) .. cresume .. "!"

					chatframe:AddMessage(newstandingtext)
				end

				local remaining, nextstanding
				if t.paragon then
					local intoCycle = math_fmod(barValue, barMax)
					if diff > 0 then
						remaining = barMax - intoCycle
						nextstanding = "next Paragon reward"
					else
						remaining = intoCycle
						nextstanding = "start of this Paragon cycle"
					end
				elseif diff > 0 then
					remaining = barMax - barValue
					if t.kind == "renown" then
						nextstanding = t.capped and "Max Renown" or ("Renown " .. (standingID + 1))
					elseif t.kind == "friendship" then
						if t.capped then
							nextstanding = "End of " .. tostring(t.label)
						else
							nextstanding = t.maxLevel and fmt("rank %d/%d", standingID + 1, t.maxLevel) or "next rank"
						end
					elseif standingID < standingmax then
						nextstanding = _G["FACTION_STANDING_LABEL" .. standingID + 1]
					else
						nextstanding = "End of " .. _G["FACTION_STANDING_LABEL" .. standingmax]
					end
				else
					remaining = barValue - barMin
					if t.kind == "renown" then
						nextstanding = standingID > 1 and ("Renown " .. (standingID - 1)) or "Beginning of Renown"
					elseif t.kind == "friendship" then
						if standingID > 1 then
							nextstanding = t.maxLevel and fmt("rank %d/%d", standingID - 1, t.maxLevel) or "previous rank"
						else
							nextstanding = "Beginning of " .. tostring(t.label)
						end
					elseif standingID > standingmin then
						nextstanding = _G["FACTION_STANDING_LABEL" .. standingID - 1]
					else
						nextstanding = "Beginning of " .. _G["FACTION_STANDING_LABEL" .. standingmin]
					end
				end

				local change = math_abs(diff)
				local repetitions = math_ceil(remaining / change)

				local newvaluetext
				if remaining <= 0 then
					newvaluetext = fmt("%s%+d%s %s%s (%s%s%s).",
					corange,diff,cyellow,name,cresume,cyellow,tostring(t.label),cresume )
				else
					newvaluetext = fmt("%s%+d%s %s%s, %s%d%s more to %s%s%s (%s%d%s Repetitions).",
					corange,diff,cyellow,name,cresume,corange,remaining,cresume,
					cyellow,nextstanding,cresume,corange,repetitions,cresume )
				end

				chatframe:AddMessage(newvaluetext)

				tracked.Value = barValue
				tracked.Standing = standingID
			end
			end
		end
	end
end

local pendingReport = false

local function eventHandler(self, event, ...)
	if not pendingReport then
		pendingReport = true
		C_Timer.After(0, function()
			pendingReport = false
			Report()
		end)
	end
end
f:SetScript("OnEvent", eventHandler);
