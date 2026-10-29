-- Blackthornes Equipment -- Logic/QuestLog.lua
-- The character's quest log, read for the Quest log tab on the upgrade quest
-- panel (UI/QuestLogTab.lua). The owner asked (2026-10-10) for the game's
-- quest tracker inside the panel, with the same clicks: track, show on the
-- map, open the quest, share it, abandon it, and the quest item buttons.
--
-- The game's own tracker is never moved or taken over; this reads the log
-- and draws its own list. Two ways of reading the log are tried, newest
-- first, since Forever is a retail client running Classic's world:
--
--   * C_QuestLog.GetNumQuestLogEntries / GetInfo / GetQuestObjectives,
--     tracking with C_QuestLog.AddQuestWatch (by quest ID).
--   * GetNumQuestLogEntries / GetQuestLogTitle / GetQuestLogLeaderBoard,
--     tracking with AddQuestWatch (by log index).
--
-- Neither has been seen on Forever yet; /beq probe lists which are there.
-- Every value the client hands back is copied inside a pcall, because
-- instances hand out secret values that raise when touched.
--
-- Reading the whole log is cheap (25 quests at most), but it only happens
-- when something changed and the tab is on screen: the quest events arrive
-- in bursts, so they mark the log stale and the tab reads it once, a moment
-- later (QuestLogUI:RefreshSoon).

local _, ns = ...
local L = ns.L

local QuestLog = ns.NewModule("QuestLog")

local function Read(fn, ...)
    if type(fn) ~= "function" then return nil end
    local result = { pcall(fn, ...) }
    if not result[1] then return nil end
    return unpack(result, 2)
end

local function Plain(value)
    local ok, copy = pcall(function()
        if type(value) == "string" and value ~= "" then return value .. "" end
    end)
    return ok and copy or nil
end

local function Number(value)
    local ok, copy = pcall(function()
        local number = tonumber(value)
        if number and number == number then return number + 0 end
    end)
    return ok and copy or nil
end

--- True, false or nil, copied: 1 counts as true, as the old calls say it.
local function Flag(value)
    local ok, copy = pcall(function()
        if value == nil then return nil end
        return value == true or value == 1
    end)
    if not ok then return nil end
    return copy
end

--- A field of a table the client handed back, or nil.
local function Field(info, key)
    local ok, value = pcall(function() return info[key] end)
    return ok and value or nil
end

local function Log() return type(_G.C_QuestLog) == "table" and _G.C_QuestLog or nil end

--------------------------------------------------------------------------------
-- Reading
--------------------------------------------------------------------------------

--- How many lines the log has (zone headings and quests), and the way to
--- read them: "new" (C_QuestLog) or "old".
function QuestLog.Size()
    local log = Log()
    local count = Number(Read(log and log.GetNumQuestLogEntries))
    if count and log and type(log.GetInfo) == "function" then return count, "new" end
    count = Number(Read(_G.GetNumQuestLogEntries))
    if count and type(_G.GetQuestLogTitle) == "function" then return count, "old" end
    return 0, nil
end

--- One line of the log: { header = true, title, collapsed } or a quest
--- { questID, index, title, level, group, complete, failed }.
local function Line(index, how)
    if how == "new" then
        local info = Read(Log().GetInfo, index)
        if type(info) ~= "table" then return nil end
        if Flag(Field(info, "isHidden")) then return nil end
        local title = Plain(Field(info, "title"))
        if not title then return nil end
        if Flag(Field(info, "isHeader")) then
            return { header = true, title = title, collapsed = Flag(Field(info, "isCollapsed")) == true }
        end
        return {
            index = index, title = title, questID = Number(Field(info, "questID")),
            level = Number(Field(info, "level")), group = Number(Field(info, "suggestedGroup")),
        }
    end
    local title, level, group, isHeader, collapsed, complete, _, questID = Read(_G.GetQuestLogTitle, index)
    title = Plain(title)
    if not title then return nil end
    if Flag(isHeader) then return { header = true, title = title, collapsed = Flag(collapsed) == true } end
    complete = Number(complete)
    return {
        index = index, title = title, questID = Number(questID), level = Number(level),
        group = Number(group), complete = complete == 1 or nil, failed = complete == -1 or nil,
    }
end

--- A quest's objectives: { text, done } each, in the log's order.
function QuestLog.Objectives(quest, how)
    local list = {}
    local log = Log()
    if how == "new" and quest.questID and log and type(log.GetQuestObjectives) == "function" then
        local objectives = Read(log.GetQuestObjectives, quest.questID)
        if type(objectives) == "table" then
            for _, objective in ipairs(objectives) do
                local text = Plain(Field(objective, "text"))
                if text then list[#list + 1] = { text = text, done = Flag(Field(objective, "finished")) == true } end
            end
            return list
        end
    end
    local count = Number(Read(_G.GetNumQuestLeaderBoards, quest.index)) or 0
    for which = 1, math.min(count, 20) do
        local text, _, finished = Read(_G.GetQuestLogLeaderBoard, which, quest.index)
        text = Plain(text)
        if text then list[#list + 1] = { text = text, done = Flag(finished) == true } end
    end
    return list
end

--- Is the quest tracked (watched)?
function QuestLog.Tracked(quest)
    local log = Log()
    if quest.questID and log and type(log.GetQuestWatchType) == "function" then
        local ok, kind = pcall(log.GetQuestWatchType, quest.questID)
        if ok then return kind ~= nil end
    end
    if quest.questID and log and type(log.IsQuestWatched) == "function" then
        local watched = Flag(Read(log.IsQuestWatched, quest.questID))
        if watched ~= nil then return watched end
    end
    return Flag(Read(_G.IsQuestWatched, quest.index)) == true
end

--- The item a quest hands out to use (a quest item button), or nil:
--- { link, itemID, texture, charges }.
function QuestLog.Item(quest)
    local link, texture, charges = Read(_G.GetQuestLogSpecialItemInfo, quest.index)
    link = Plain(link)
    if not link then return nil end
    return { link = link, itemID = tonumber(link:match("item:(%d+)")), texture = texture,
        charges = Number(charges) }
end

--- Done, failed, or neither, asked the newer way where the line did not say.
local function State(quest)
    local log = Log()
    if quest.questID and log then
        if quest.complete == nil then
            local ready = Flag(Read(log.ReadyForTurnIn, quest.questID))
            if ready == nil or ready == false then ready = Flag(Read(log.IsComplete, quest.questID)) end
            quest.complete = ready == true or nil
        end
        if quest.failed == nil and Flag(Read(log.IsFailed, quest.questID)) then quest.failed = true end
    end
end

--- "Dungeon", "Elite", "Group" and the like, or nil.
local function Tag(quest)
    local log = Log()
    if quest.questID and log and type(log.GetQuestTagInfo) == "function" then
        local info = Read(log.GetQuestTagInfo, quest.questID)
        local name = type(info) == "table" and Plain(Field(info, "tagName"))
        if name then return name end
    end
    if quest.questID and type(_G.GetQuestTagInfo) == "function" then
        local _, name = Read(_G.GetQuestTagInfo, quest.questID)
        name = Plain(name)
        if name then return name end
    end
    if (quest.group or 0) > 1 then return L.Format("Group (%d)", quest.group) end
    return nil
end

QuestLog.Line = Line

--- The whole log, in its order: { zones = { { title, collapsed, quests } },
--- count, tracked }. A heading folded in the game's own quest log hides its
--- quests from addons too, so it comes back with `collapsed` and no quests.
function QuestLog:Read()
    local size, how = QuestLog.Size()
    local zones, count, tracked = {}, 0, 0
    local zone
    for index = 1, math.min(size, 80) do
        local line = Line(index, how)
        if line and line.header then
            zone = { title = line.title, collapsed = line.collapsed, quests = {} }
            zones[#zones + 1] = zone
        elseif line then
            if not zone then
                -- `title` stays English: it keys the saved folds. `label` is
                -- what a list shows for it.
                zone = { title = "Other", label = L["Other"], quests = {} }
                zones[#zones + 1] = zone
            end
            State(line)
            line.zone = zone.title
            line.objectives = QuestLog.Objectives(line, how)
            line.tracked = QuestLog.Tracked(line)
            line.item = QuestLog.Item(line)
            line.tag = Tag(line)
            zone.quests[#zone.quests + 1] = line
            count = count + 1
            if line.tracked then tracked = tracked + 1 end
        end
    end
    self.how = how
    return { zones = zones, count = count, tracked = tracked, how = how }
end

--- One quest of the log by its ID, read the way QuestLog:Read reads each:
--- { questID, index, title, level, complete, failed, objectives, tracked },
--- or nil when it is not in the log (or sits under a heading folded in the
--- game's log, which hides it from addons). For the upgrade quest's step to
--- do now (UpgradeQuest:Steps), so only that one quest is read.
function QuestLog:Find(questID)
    questID = Number(questID)
    if not questID then return nil end
    local size, how = QuestLog.Size()
    if not how then return nil end
    self.how = how
    local log = Log()
    local line
    if how == "new" and type(log.GetLogIndexForQuestID) == "function" then
        local index = Number(Read(log.GetLogIndexForQuestID, questID))
        local found = index and index > 0 and Line(index, how)
        if found and not found.header and found.questID == questID then line = found end
    end
    if not line then
        for index = 1, math.min(size, 80) do
            local found = Line(index, how)
            if found and not found.header and found.questID == questID then
                line = found
                break
            end
        end
    end
    if not line then return nil end
    State(line)
    line.objectives = QuestLog.Objectives(line, how)
    line.tracked = QuestLog.Tracked(line)
    return line
end

--------------------------------------------------------------------------------
-- What a quest's row says
--------------------------------------------------------------------------------

--- The colour the game gives a quest of `level` for this character:
--- red, orange, yellow, green or grey.
function QuestLog.Difficulty(level)
    level = tonumber(level)
    if not level or level <= 0 then return "yellow" end
    local player = Number(Read(_G.UnitLevel, "player")) or level
    local gap = level - player
    if gap >= 5 then return "red" end
    if gap >= 3 then return "orange" end
    if gap >= -2 then return "yellow" end
    local green = Number(Read(_G.GetQuestGreenRange)) or (player <= 30 and 8 or 9)
    if -gap <= green then return "green" end
    return "grey"
end

-- The tick the log's done objectives wear.
QuestLog.DONE_MARK = "|TInterface\\RaidFrame\\ReadyCheck-Ready:11|t "

--- A quest's lines under its title, as the game's tracker words them:
--- "Failed", "Ready to hand in" once done, else each objective with its
--- count, ticked green when done. A list of { text, color }.
function QuestLog.ObjectiveLines(quest)
    local lines = {}
    if quest.failed then
        lines[1] = { text = L["- Failed"], color = "loss" }
    elseif quest.complete then
        local who = QuestLog.HandIn(quest)
        lines[1] = { text = who and L.Format("- Ready to hand in to %s", who) or L["- Ready to hand in"], color = "accent" }
    else
        for _, objective in ipairs(quest.objectives or {}) do
            lines[#lines + 1] = objective.done and { text = QuestLog.DONE_MARK .. objective.text, color = "good" }
                or { text = "- " .. objective.text, color = "text" }
        end
    end
    return lines
end

--- The quest's title line: "[23] Seasoned Wolf Kabobs" in the game's
--- colour for its level.
function QuestLog.TitleText(quest)
    local level = quest.level and quest.level > 0 and ("[%d] "):format(quest.level) or ""
    local rgb = QuestLog.DIFFICULTY[QuestLog.Difficulty(quest.level)]
    return ("|cff%02x%02x%02x%s|r"):format(math.floor(rgb[1] * 255 + 0.5), math.floor(rgb[2] * 255 + 0.5),
        math.floor(rgb[3] * 255 + 0.5), level .. (quest.title or ""))
end

QuestLog.DIFFICULTY = {
    red = { 1, 0.1, 0.1 },
    orange = { 1, 0.5, 0.25 },
    yellow = { 1, 0.82, 0 },
    green = { 0.25, 0.75, 0.25 },
    grey = { 0.55, 0.55, 0.55 },
}

--- Where to go for a quest, from Data/QuestEnds.lua: the hand-in once
--- it is done, else the place of the first objective not done yet, else
--- the hand-in. Nil when the
--- data has nothing; a place is { zone, x, y, name }.
function QuestLog.Place(quest)
    local upgrade = ns.UpgradeQuest
    local ends = quest.questID and upgrade and upgrade.Ender and upgrade.Ender(quest.questID)
    if not ends then return nil end
    local goal = upgrade.OpenGoal and upgrade.OpenGoal(ends, quest.objectives) or ends.goal
    local pick = quest.complete and ends.hand or goal or ends.hand
    if not (pick and pick.zone) then return nil end
    return { zone = pick.zone, x = pick.x, y = pick.y, name = pick.dungeon or pick.name }
end

--- Who to hand a finished quest to, "Chef Grual", or nil.
function QuestLog.HandIn(quest)
    local upgrade = ns.UpgradeQuest
    local ends = quest.questID and upgrade and upgrade.Ender and upgrade.Ender(quest.questID)
    return ends and ends.hand and ends.hand.name or nil
end

--- Quests the upgrade quests lead through: { [questID] = item link } for
--- every tab's quest reward and the quests before it in its chain.
function QuestLog.ForUpgrades()
    local found = {}
    local upgrade = ns.UpgradeQuest
    if not (upgrade and upgrade:IsEnabled()) then return found end
    for _, quest in pairs(upgrade:Quests()) do
        local source = type(quest) == "table" and quest.source
        if type(source) == "table" and source.kind == "quest" and source.questID then
            found[source.questID] = quest.link or true
            local ok, chain = pcall(ns.Finder.Chain, ns.Finder, source.questID)
            if ok and type(chain) == "table" then
                for _, before in ipairs(chain) do
                    if before.questID then found[before.questID] = quest.link or true end
                end
            end
        end
    end
    return found
end

--------------------------------------------------------------------------------
-- Doing things with a quest
--------------------------------------------------------------------------------

--- Track or stop tracking a quest. True when the client took it.
function QuestLog:SetTracked(quest, on)
    local log = Log()
    local ok = false
    if quest.questID and log and type(log.AddQuestWatch) == "function" and self.how == "new" then
        ok = pcall(on and log.AddQuestWatch or log.RemoveQuestWatch, quest.questID)
    elseif quest.index then
        local fn = on and _G.AddQuestWatch or _G.RemoveQuestWatch
        ok = type(fn) == "function" and pcall(fn, quest.index)
    end
    -- The old way has no event of its own for this.
    if ok and type(_G.QuestWatch_Update) == "function" then pcall(_G.QuestWatch_Update) end
    return ok
end

--- Pick a quest in the game's log, as a click there does, for the calls
--- that act on the picked quest. Returns a function that puts the old pick
--- back.
local function Pick(quest)
    local log = Log()
    if quest.questID and log and type(log.SetSelectedQuest) == "function" then
        local before = Read(log.GetSelectedQuest)
        pcall(log.SetSelectedQuest, quest.questID)
        return function() if before then pcall(log.SetSelectedQuest, before) end end
    end
    if quest.index and type(_G.SelectQuestLogEntry) == "function" then
        local before = Read(_G.GetQuestLogSelection)
        pcall(_G.SelectQuestLogEntry, quest.index)
        return function() if before then pcall(_G.SelectQuestLogEntry, before) end end
    end
    return nil
end
QuestLog.Pick = Pick

--- Can the quest be shared with the group right now?
function QuestLog:CanShare(quest)
    local members = Number(Read(_G.GetNumGroupMembers)) or Number(Read(_G.GetNumPartyMembers)) or 0
    if members <= 0 then return false end
    local log = Log()
    if quest.questID and log and type(log.IsPushableQuest) == "function" then
        return Flag(Read(log.IsPushableQuest, quest.questID)) == true
    end
    local restore = Pick(quest)
    local pushable = Flag(Read(_G.GetQuestLogPushable))
    if restore then restore() end
    return pushable == true
end

--- Share the quest with the group, as the quest log's Share button does.
function QuestLog:Share(quest)
    if type(_G.QuestLogPushQuest) ~= "function" then return false end
    -- Unpicked, the game would share whichever quest its log has picked.
    local restore = Pick(quest)
    if not restore then return false end
    local ok = pcall(_G.QuestLogPushQuest)
    restore()
    return ok
end

--- Abandon the quest, through the game's own "Abandon this quest?" box:
--- nothing is dropped until the player says yes there.
function QuestLog:Abandon(quest)
    local log = Log()
    -- Unpicked, the game would abandon whichever quest its log has picked.
    local restore = Pick(quest)
    local set = (log and log.SetAbandonQuest) or _G.SetAbandonQuest
    local ok = restore ~= nil and type(set) == "function" and pcall(set)
    if restore then restore() end
    if not ok or type(_G.StaticPopup_Show) ~= "function" then
        ns.Print(L.Format("open your quest log to abandon %s.", quest.title or L["that quest"]))
        return false
    end
    pcall(_G.StaticPopup_Show, "ABANDON_QUEST", quest.title)
    return true
end

--- Open the quest in the game's quest log (or map, on a client that keeps
--- quests there). Without a quest, opens or closes the log.
function QuestLog:Open(quest)
    if quest then
        if quest.questID and type(_G.QuestMapFrame_OpenToQuestDetails) == "function"
            and pcall(_G.QuestMapFrame_OpenToQuestDetails, quest.questID) then
            return true
        end
        if quest.index and type(_G.QuestLog_OpenToQuest) == "function"
            and pcall(_G.QuestLog_OpenToQuest, quest.index) then
            return true
        end
        if quest.index and type(_G.SelectQuestLogEntry) == "function" then
            pcall(_G.SelectQuestLogEntry, quest.index)
        end
    end
    for _, name in ipairs({ "ToggleQuestLog", "ToggleQuestLogFrame" }) do
        local fn = _G[name]
        if type(fn) == "function" and pcall(fn) then return true end
    end
    return false
end

--- Put the game's map pin on where to go for the quest, or open the map on
--- its zone. False when there is nowhere to show.
function QuestLog:ShowOnMap(quest)
    local place = QuestLog.Place(quest)
    local waypoints = ns.Waypoints
    -- A spot, or only a zone ("Somewhere in ZONE"): the marker and the arrow.
    local zone = place and place.zone or quest.zone
    if waypoints and zone and waypoints:MapFor(zone) then
        local shown = place and place.zone and place or { zone = zone }
        return waypoints:Show(shown, shown.name or quest.title)
    end
    -- The client's own way to a quest on the map.
    if quest.questID and type(_G.QuestMapFrame_OpenToQuestDetails) == "function"
        and pcall(_G.QuestMapFrame_OpenToQuestDetails, quest.questID) then
        return true
    end
    ns.Print(L.Format("no spot is known for %s.", quest.title or L["that quest"]))
    return false
end

--- Point the quest arrow at where to go for the quest. False when there is
--- nowhere known.
function QuestLog:Aim(quest)
    local place = QuestLog.Place(quest)
    if not place then
        local mapID = ns.Waypoints and quest.zone and ns.Waypoints:MapFor(quest.zone)
        if mapID then place = { zone = quest.zone, name = quest.zone } end
    end
    if not (place and ns.QuestArrow and ns.QuestArrow.AimAtQuest) then
        ns.Print(L.Format("no spot is known for %s, so the arrow can't point at it.", quest.title or L["that quest"]))
        return false
    end
    return ns.QuestArrow:AimAtQuest(quest.questID, quest.title, place)
end

--------------------------------------------------------------------------------
-- Checking what the client allows
--------------------------------------------------------------------------------

QuestLog.CALLS = {
    "C_QuestLog.GetNumQuestLogEntries", "C_QuestLog.GetInfo", "C_QuestLog.GetLogIndexForQuestID", "C_QuestLog.GetQuestObjectives",
    "C_QuestLog.GetQuestWatchType", "C_QuestLog.AddQuestWatch", "C_QuestLog.RemoveQuestWatch",
    "C_QuestLog.GetQuestTagInfo", "C_QuestLog.SetSelectedQuest", "C_QuestLog.IsPushableQuest",
    "C_QuestLog.SetAbandonQuest", "GetNumQuestLogEntries", "GetQuestLogTitle",
    "GetNumQuestLeaderBoards", "GetQuestLogLeaderBoard", "IsQuestWatched", "AddQuestWatch",
    "RemoveQuestWatch", "GetQuestLogSpecialItemInfo", "SelectQuestLogEntry", "QuestLogPushQuest",
    "SetAbandonQuest", "StaticPopup_Show", "QuestMapFrame_OpenToQuestDetails", "QuestLog_OpenToQuest",
    "ToggleQuestLog", "GetQuestDifficultyColor", "ObjectiveTrackerFrame", "QuestWatchFrame",
}

--- The probe's lines about the log: which way it reads, and what it found.
function QuestLog:Describe()
    local size, how = QuestLog.Size()
    if not how then return "no way to read the quest log found" end
    local data = self:Read()
    local items = 0
    for _, zone in ipairs(data.zones) do
        for _, quest in ipairs(zone.quests) do
            if quest.item then items = items + 1 end
        end
    end
    return ("read the %s way: %d lines, %d quests in %d headings, %d tracked, %d with an item button"):format(
        how == "new" and "C_QuestLog" or "classic", size, data.count, #data.zones, data.tracked, items)
end
