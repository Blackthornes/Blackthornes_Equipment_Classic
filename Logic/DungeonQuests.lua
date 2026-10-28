-- Blackthornes Equipment -- Logic/DungeonQuests.lua
-- Every dungeon and raid quest, and which this character has done (the
-- owner said build it, 2026-10-20, from a mockup).
--
-- Classic's dungeon quests that the Forever client still has come from
-- Data/DungeonQuests.lua (tools/make_dungeon_quests.py, never by hand).
-- Forever's own are learned in game, since its tables hold quest IDs only
-- (folded into Data/ForeverDungeonQuests.lua at each release by
-- tools/forever_dungeon_quests.py, so every player gets them):
-- a quest in the log under a heading that names a dungeon, or accepted
-- while inside one, is kept account wide in
-- `BlackthornesEquipmentDB.learnedDungeonQuests[questID]` (never rename
-- it):
--
--   { dungeon =, title =, level =, min =, side =, giver =, zone =, x =, y =,
--     reward =, at = }
--
-- `dungeon` is a Sources.DUNGEONS or FOREVER_DUNGEON_PLACES key (the map
-- ID as a string). A quest Classic's data already has is never kept again.
--
-- Status: "done" when Finder:QuestDone says so, "log" while it is in the
-- quest log, else "todo". The log is read once per QUEST_LOG_UPDATE burst,
-- only while the window shows. Nothing here runs on bag events.

local _, ns = ...
local L = ns.L

local DQ = ns.NewModule("DungeonQuests")

DQ.SETTLE = 0.3
-- A quest this many levels under the character counts as past it.
DQ.BELOW = 6
-- City doors: these zones are named alone, not "Door in".
DQ.CITIES = {
    ["Orgrimmar"] = true, ["Stormwind City"] = true, ["Undercity"] = true,
    ["Ironforge"] = true, ["Darnassus"] = true, ["Thunder Bluff"] = true,
}

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
        local n = tonumber(value)
        if n and n == n then return n + 0 end
    end)
    return ok and copy or nil
end

local function Band(a, b)
    if bit and bit.band then return bit.band(a, b) end
    local result, place = 0, 1
    while a > 0 and b > 0 do
        if a % 2 == 1 and b % 2 == 1 then result = result + place end
        a, b, place = math.floor(a / 2), math.floor(b / 2), place * 2
    end
    return result
end

--------------------------------------------------------------------------------
-- Dungeons
--------------------------------------------------------------------------------

--- A dungeon by key: { key, name, low, high, door, raid, forever }, or nil.
function DQ.Dungeon(key)
    local row = ns.Sources and ns.Sources.DUNGEONS and ns.Sources.DUNGEONS[key]
    local place = ns.FOREVER_DUNGEON_PLACES and ns.FOREVER_DUNGEON_PLACES[key]
    if place then
        -- Levels, and a door the place lacks, from the row ForeverDrops.lua
        -- laid in Sources.DUNGEONS (a door that only repeats the name is none).
        local door = place[2] ~= "" and place[2] or nil
        local low, high
        if type(row) == "table" then
            low, high = row[2], row[3]
            if not door and row[4] ~= "" and row[4] ~= place[1] then door = row[4] end
        end
        return { key = key, name = place[1], low = low, high = high, door = door,
            raid = place[3] == true, forever = true }
    end
    if type(row) ~= "table" then return nil end
    return { key = key, name = row[1], low = row[2], high = row[3],
        door = row[4] ~= "" and row[4] or nil, raid = row[6] == true }
end

--- The key of the dungeon a name means (a log heading), or nil.
function DQ.KeyForName(name)
    name = Plain(name)
    if not name then return nil end
    if ns.Waypoints and ns.Waypoints.DataZone then
        local ok, english = pcall(ns.Waypoints.DataZone, ns.Waypoints, name)
        if ok and type(english) == "string" then name = english end
    end
    local lower = name:lower()
    for key, place in pairs(ns.FOREVER_DUNGEON_PLACES or {}) do
        if place[1]:lower() == lower then return key end
    end
    for key, row in pairs(ns.Sources and ns.Sources.DUNGEONS or {}) do
        -- Scarlet Monastery's wings share its quests.
        if type(row) == "table" and row[1]:lower() == lower and not key:find("%a") then return key end
    end
    return nil
end

--- The dungeon the character stands in now, by the map ID the game gives.
function DQ.Inside()
    local _, kind, _, _, _, _, _, mapID = Read(_G.GetInstanceInfo)
    kind = Plain(kind)
    if kind ~= "party" and kind ~= "raid" then return nil end
    local key = Number(mapID) and tostring(Number(mapID))
    if key and DQ.Dungeon(key) then return key end
    return nil
end

--- For /beq probe: what GetInstanceInfo says, "outside" when not in one.
function DQ.InstanceText()
    local name, kind, _, _, _, _, _, mapID = Read(_G.GetInstanceInfo)
    kind = Plain(kind)
    if kind ~= "party" and kind ~= "raid" then return "outside" end
    return ("%s %s map %s"):format(tostring(Plain(name)), tostring(kind), tostring(Number(mapID)))
end

--------------------------------------------------------------------------------
-- The quests
--------------------------------------------------------------------------------

--- Every dungeon quest, data and learned: [questID] = { questID, dungeon,
--- title, min, level, side, classes, giver, zone, x, y, reward, prev,
--- learned }. Laid out again only when a quest is learned.
function DQ:All()
    if self.all and self.allVersion == (self.version or 0) then return self.all end
    local all = {}
    -- Classic's, then Forever's own as met in game and shipped at a release.
    for _, data in ipairs({ ns.DUNGEON_QUESTS or {}, ns.FOREVER_DUNGEON_QUESTS or {} }) do
        for questID, q in pairs(data) do
            if not all[questID] then
                all[questID] = { questID = questID, dungeon = q[1], title = q[2], min = q[3],
                    level = q[4], side = q[5], classes = q[6],
                    giver = q[7] ~= "" and q[7] or nil, zone = q[8] ~= "" and q[8] or nil,
                    x = q[9], y = q[10], reward = q[11], prev = q[12] }
            end
        end
    end
    local learned = type(ns.db) == "table" and ns.db.learnedDungeonQuests
    for questID, rec in pairs(type(learned) == "table" and learned or {}) do
        questID = Number(questID)
        local have = questID and all[questID]
        if have and type(rec) == "table" and not have.giver and type(rec.giver) == "string" then
            -- A shipped Forever quest whose giver the cache could not say.
            have.giver, have.zone = rec.giver, rec.zone
            have.x, have.y = Number(rec.x) or 0, Number(rec.y) or 0
            if have.side == "" and (rec.side == "A" or rec.side == "H") then have.side = rec.side end
        elseif questID and not have and type(rec) == "table" and type(rec.dungeon) == "string"
            and type(rec.title) == "string" then
            all[questID] = { questID = questID, dungeon = rec.dungeon, title = rec.title,
                min = Number(rec.min) or Number(rec.level) or 0, level = Number(rec.level) or 0,
                side = rec.side == "AH" and "" or rec.side or "", classes = 0,
                giver = rec.giver, zone = rec.zone, x = Number(rec.x) or 0, y = Number(rec.y) or 0,
                reward = Number(rec.reward) or 0, prev = 0, learned = true }
        end
    end
    self.all, self.allVersion = all, self.version or 0
    return all
end

--- Can this character take the quest at all (its side and class)?
function DQ.ForMe(quest, player)
    if not player then return true end
    if quest.side == "A" and player.faction ~= "A" then return false end
    if quest.side == "H" and player.faction ~= "H" then return false end
    local classes = quest.classes or 0
    if classes ~= 0 and (player.classBit or 0) ~= 0 and Band(classes, player.classBit) == 0 then
        return false
    end
    return true
end

--- Near the character's level: it can take it now, and it is not far past.
function DQ.AtLevel(quest, level)
    if not level then return true end
    if (quest.min or 0) > level then return false end
    local questLevel = quest.level or 0
    return questLevel <= 0 or questLevel + DQ.BELOW >= level
end

--- The quest IDs in the log now, read once per burst of log events.
function DQ:InLog()
    if self.log and not self.logStale then return self.log end
    local log = {}
    local QL = ns.QuestLog
    if QL and QL.Size and QL.Line then
        local size, how = QL.Size()
        for index = 1, math.min(size or 0, 80) do
            local line = how and QL.Line(index, how)
            if line and not line.header and line.questID then log[line.questID] = true end
        end
    end
    self.log, self.logStale = log, false
    return log
end

function DQ:Status(quest)
    local finder = ns.Finder
    if finder and finder.QuestDone and finder:QuestDone(quest.questID) then return "done" end
    if self:InLog()[quest.questID] then return "log" end
    return "todo"
end

DQ.Settings = {}

function DQ.HideDone()
    return type(ns.db) == "table" and ns.db.dungeonQuestsHideDone == true
end

--- On unless unticked, as the mockup has it.
function DQ.MyLevelOnly()
    return not (type(ns.db) == "table" and ns.db.dungeonQuestsMyLevel == false)
end

function DQ:SetHideDone(on)
    if type(ns.db) == "table" then ns.db.dungeonQuestsHideDone = on and true or nil end
    self:Changed()
end

function DQ:SetMyLevelOnly(on)
    if type(ns.db) ~= "table" then return end
    if on then ns.db.dungeonQuestsMyLevel = nil else ns.db.dungeonQuestsMyLevel = false end
    self:Changed()
end

--- What the window shows: { dungeons = { { key, name, low, high, door,
--- raid, forever, done, all, quests = { quest + status } } }, done, all }.
--- Counts follow My Level Only; Hide Done only takes rows out.
function DQ:Build()
    local player = ns.Finder and ns.Finder.Player and ns.Finder:Player()
    local level = player and player.level
    local myLevel, hideDone = DQ.MyLevelOnly(), DQ.HideDone()
    local byKey, done, all = {}, 0, 0
    for _, quest in pairs(self:All()) do
        if DQ.ForMe(quest, player) and (not myLevel or DQ.AtLevel(quest, level)) then
            local dungeon = byKey[quest.dungeon]
            if not dungeon then
                dungeon = DQ.Dungeon(quest.dungeon)
                if dungeon then
                    dungeon.quests, dungeon.done, dungeon.all = {}, 0, 0
                    byKey[quest.dungeon] = dungeon
                end
            end
            if dungeon then
                local row = setmetatable({ status = self:Status(quest) }, { __index = quest })
                dungeon.all, all = dungeon.all + 1, all + 1
                if row.status == "done" then dungeon.done, done = dungeon.done + 1, done + 1 end
                if not (hideDone and row.status == "done") then dungeon.quests[#dungeon.quests + 1] = row end
                if dungeon.forever then
                    local lvl = quest.level or 0
                    if lvl > 0 then
                        dungeon.low = math.min(dungeon.low or lvl, quest.min or lvl)
                        dungeon.high = math.max(dungeon.high or lvl, lvl)
                    end
                end
            end
        end
    end
    local list = {}
    for _, dungeon in pairs(byKey) do
        table.sort(dungeon.quests, function(a, b)
            if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) < (b.level or 0) end
            return a.title < b.title
        end)
        list[#list + 1] = dungeon
    end
    -- Classic's by their levels, raids after dungeons, Forever's own last.
    table.sort(list, function(a, b)
        if (a.forever or false) ~= (b.forever or false) then return not a.forever end
        if (a.raid or false) ~= (b.raid or false) then return not a.raid end
        if (a.low or 0) ~= (b.low or 0) then return (a.low or 0) < (b.low or 0) end
        return a.name < b.name
    end)
    return { dungeons = list, done = done, all = all }
end

--- Where a quest starts, as the row's second line says it.
function DQ.From(quest)
    -- In the game's own words (Logic/Names.lua).
    local names = ns.Names
    local giver = quest.giver and names and names:NPC(quest.giver) or quest.giver
    if giver and quest.zone and quest.zone ~= "" then
        return L.Format("%s, %s", giver, names and names:Zone(quest.zone) or quest.zone)
    end
    return giver or ""
end

--- The place it starts, for the arrow and the map pin, or nil.
function DQ.Place(quest)
    if not (quest.zone and quest.zone ~= "" and (quest.x or 0) > 0) then return nil end
    return { zone = quest.zone, x = quest.x, y = quest.y, name = quest.giver }
end

--- The quest arrow to where it is worked on: its objective when it is in
--- the log (QuestLog.Place reads that), else where it starts.
function DQ:Follow(quest)
    local arrow = ns.QuestArrow
    local place = DQ.Place(quest)
    if not (arrow and arrow.AimAtQuest and place) then return false end
    -- A quest not in the log goes in with no ID, or the quest log tab lets
    -- it go as gone from the log.
    local id = self:InLog()[quest.questID] and quest.questID or nil
    local ok, aimed = pcall(arrow.AimAtQuest, arrow, id, DQ:TitleOf(quest), place)
    return ok and aimed == true
end

--- The game's map pin where it starts.
function DQ:ShowTheWay(quest)
    local place = DQ.Place(quest)
    if not (place and ns.Waypoints) then return false end
    local ok, shown = pcall(ns.Waypoints.Show, ns.Waypoints, place, quest.giver or quest.title)
    return ok and shown == true
end

--------------------------------------------------------------------------------
-- Names from the game
--------------------------------------------------------------------------------

-- The game's own title for each quest, kept for the session (it is in the
-- client's language, and Forever's wording wins over the data's).
DQ.titles = {}
DQ.asked = {}

--- The quest's name as the game gives it, else the data's. A quest the
--- game has not loaded is asked for once; QUEST_DATA_LOAD_RESULT redraws.
function DQ:TitleOf(quest)
    local id = quest and Number(quest.questID)
    if not id then return quest and quest.title or "" end
    local kept = self.titles[id]
    if kept then return kept end
    local log = _G.C_QuestLog
    local title = Plain(Read(log and log.GetTitleForQuestID, id))
    if title then
        self.titles[id] = title
        return title
    end
    if not self.asked[id] and log and type(log.RequestLoadQuestByID) == "function" then
        self.asked[id] = true
        pcall(log.RequestLoadQuestByID, id)
    end
    return quest.title or ""
end

--- A quest the game just loaded: redraw once, a moment later, if shown.
function DQ:TitleLoaded(questID, success)
    questID = Number(questID)
    if not (questID and self.asked[questID] and success) then return end
    if self.titleRedraw then return end
    local after = _G.C_Timer and _G.C_Timer.After
    if type(after) ~= "function" then
        self:Changed()
        return
    end
    self.titleRedraw = true
    after(DQ.SETTLE, function()
        DQ.titleRedraw = false
        local ui = ns.DungeonQuestsUI
        if ui and ui.Showing and ui:Showing() then DQ:Changed() end
    end)
end

--- For /beq probe: whether the game names quests by ID, and quest 166's.
function DQ:DescribeTitles()
    local log = _G.C_QuestLog
    local has = log and type(log.GetTitleForQuestID) == "function"
    local load = log and type(log.RequestLoadQuestByID) == "function"
    local title = Plain(Read(log and log.GetTitleForQuestID, 166))
    return ("title call %s, load call %s, quest 166 %s"):format(
        has and "found" or "missing", load and "found" or "missing", title or "not loaded")
end

--------------------------------------------------------------------------------
-- Learning Forever's own
--------------------------------------------------------------------------------

--- Keep a quest met in a dungeon, unless the data has it.
function DQ:Learn(questID, dungeon, line)
    questID = Number(questID)
    if not (questID and dungeon and type(ns.db) == "table") then return false end
    if ns.DUNGEON_QUESTS and ns.DUNGEON_QUESTS[questID] then return false end
    local title = Plain(line and line.title)
    if not title then return false end
    if type(ns.db.learnedDungeonQuests) ~= "table" then ns.db.learnedDungeonQuests = {} end
    local store = ns.db.learnedDungeonQuests
    if store[questID] then return false end
    -- What the quest learner knows of it: its giver, level and rewards.
    local known = type(ns.db.learnedQuests) == "table" and ns.db.learnedQuests[questID] or {}
    local reward = 0
    if type(known.rewards) == "table" and type(known.rewards[1]) == "table" then
        reward = Number(known.rewards[1][1]) or 0
    end
    local faction = ns.Finder and ns.Finder.Side and ns.Finder.Side()
    store[questID] = {
        dungeon = dungeon, title = title,
        level = Number(line.level) or Number(known.level) or 0,
        min = Number(known.min),
        side = known.side or (faction == "Alliance" and "A" or faction == "Horde" and "H" or nil),
        giver = Plain(known.giver), zone = Plain(known.zone),
        x = Number(known.x), y = Number(known.y), reward = reward, at = Read(_G.time),
    }
    self.version = (self.version or 0) + 1
    return true
end

--- Read the log for quests under a dungeon's heading. `inside` is the
--- dungeon the character stands in, for a quest just accepted there.
function DQ:LearnLog(acceptedID)
    local QL = ns.QuestLog
    if not (QL and QL.Size and QL.Line) then return end
    local size, how = QL.Size()
    if not how then return end
    local inside = acceptedID and DQ.Inside()
    local heading
    local learned = false
    for index = 1, math.min(size or 0, 80) do
        local line = QL.Line(index, how)
        if line and line.header then
            heading = DQ.KeyForName(line.title)
        elseif line and line.questID then
            local key = heading or (line.questID == acceptedID and inside) or nil
            if key and self:Learn(line.questID, key, line) then learned = true end
        end
    end
    if learned then self:Changed() end
end

--------------------------------------------------------------------------------
-- Keeping the window up to date
--------------------------------------------------------------------------------

function DQ:Changed()
    local ui = ns.DungeonQuestsUI
    if ui and ui.Refresh then pcall(ui.Refresh, ui) end
end

function DQ:LogMoved()
    self.logStale = true
    if self.pending then return end
    local after = _G.C_Timer and _G.C_Timer.After
    if type(after) ~= "function" then
        self:Changed()
        return
    end
    self.pending = true
    after(DQ.SETTLE, function()
        DQ.pending = false
        local ui = ns.DungeonQuestsUI
        if ui and ui.Showing and ui:Showing() then DQ:Changed() end
    end)
end

--- For /beq probe: what the completed quest calls answer here.
function DQ:Describe()
    local log = _G.C_QuestLog
    local done = Read(log and log.IsQuestFlaggedCompleted, 166)
    if done == nil then done = Read(_G.IsQuestFlaggedCompleted, 166) end
    local count = 0
    for _ in pairs(ns.DUNGEON_QUESTS or {}) do count = count + 1 end
    local learned = 0
    for _ in pairs(type(ns.db) == "table" and type(ns.db.learnedDungeonQuests) == "table"
        and ns.db.learnedDungeonQuests or {}) do learned = learned + 1 end
    -- Quest 166 is an Alliance quest: "works, 166 not done" on a Horde
    -- character means the call answers.
    return ("%d in data, %d learned, done call %s, inside %s"):format(
        count, learned, done == nil and "missing" or ("works, 166 " .. (done and "done" or "not done")),
        tostring(DQ.Inside()))
end

function DQ:OnEnable()
    for _, event in ipairs({ "QUEST_LOG_UPDATE", "QUEST_TURNED_IN", "QUEST_REMOVED" }) do
        ns.RegisterEvent(self, event, function() DQ:LogMoved() end)
    end
    ns.RegisterEvent(self, "QUEST_ACCEPTED", function(_, _, a, b)
        local questID = Number(b) or Number(a)
        DQ:LogMoved()
        if _G.C_Timer then _G.C_Timer.After(1, function() DQ:LearnLog(questID) end) end
    end)
    ns.RegisterEvent(self, "QUEST_DATA_LOAD_RESULT", function(_, _, questID, success)
        DQ:TitleLoaded(questID, success)
    end)
    if _G.C_Timer then _G.C_Timer.After(8, function() DQ:LearnLog() end) end
end

ns.RegisterCommand("dungeons", L["your dungeon quests and which ones you've done"], function()
    if ns.DungeonQuestsUI then ns.DungeonQuestsUI:Toggle() end
end)
