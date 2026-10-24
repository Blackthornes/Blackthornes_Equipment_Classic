-- Blackthornes Equipment -- Logic/QuestLearn.lua
-- Quests and their rewards, learned as they are met.
--
-- The finder and the upgrade quest read quests from Classic data
-- (Sources.QUESTS), and Forever has added and changed some. So whenever a
-- quest is offered or handed in, the quest's ID, title, level, who gave it
-- and where, and the gear it rewards are kept, account wide, in
-- `BlackthornesEquipmentDB.learnedQuests[questID]` (never rename it):
--
--   { title =, level =, min =, giver =, zone =, x =, y =, side =,
--     rewards = { { itemID, req, ilvl, given }, ... },
--     items = { { itemID, count, given }, ... }, money =, xp =, at = }
--
-- `side` is who was offered it: "A" (Alliance), "H" (Horde) or "AH" once
-- both have been. A quest seen by one side only is offered to that side
-- only; an older record without it is offered to both.
--
-- `given` is true for a reward handed over outright, false for one of the
-- choices. Gear goes in `rewards`, and only when it says something new: a
-- quest or reward the data already has is not saved again.
--
-- For a quest the data does not have, everything else it gives is kept too
-- (the owner asked 2026-10-20, so players can share every quest and its
-- rewards): `items` for rewards that are not gear (potions, bags, reagents),
-- with how many and `given` as above, and the copper (`money`) and XP
-- (`xp`) the window shows, as first read. Only gear is laid over the data;
-- the rest is kept for the shipped data and the other addons.
--
-- What is learned (and what ships in Data/ForeverQuests.lua, folded in from
-- the owner's save by tools/forever_quests.py before a release) is laid over
-- Sources.QUESTS and Sources.ITEMS as the addon loads and as each quest is
-- learned: a new quest gets a row, and a reward gets the quest in its `q`
-- list. Nothing Classic says is replaced.
--
-- Quests already in the log are read the same way from the quest log, once
-- after login and as each is accepted, so a quest picked up before its
-- window could be read is learned too (with no giver).
--
-- Every client value is read inside a pcall and copied: in an instance the
-- game hands out secret values that raise when touched. A quest window is
-- one read, so nothing here runs on bag events.

local _, ns = ...

local QuestLearn = ns.NewModule("QuestLearn")

local REWARDS_MOST = 12

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

--------------------------------------------------------------------------------
-- Laying learned quests over the data
--------------------------------------------------------------------------------

--- The data's number for a zone name, adding the zone when the data lacks it.
local function ZoneID(name)
    local zones = ns.Sources and ns.Sources.ZONES
    if type(zones) ~= "table" or type(name) ~= "string" or name == "" then return 0 end
    local top = 0
    for id, zone in pairs(zones) do
        if zone == name then return id end
        if type(id) == "number" and id > top then top = id end
    end
    zones[top + 1] = name
    return top + 1
end

QuestLearn.ZoneID = ZoneID

local function Has(list, value)
    for _, v in ipairs(list or {}) do
        if v == value then return true end
    end
    return false
end

--- Classic's race bits for the side that was offered a quest, or 0 for both.
local function SideRaces(side)
    local F = ns.Finder
    local alliance = F and F.ALLIANCE_RACES or (1 + 4 + 8 + 64)
    local horde = F and F.HORDE_RACES or (2 + 16 + 32 + 128)
    if side == "A" then return alliance end
    if side == "H" then return horde end
    return 0
end
QuestLearn.SideRaces = SideRaces

--- Both sides' letters together, once each: "A" and "H" make "AH".
function QuestLearn.JoinSides(a, b)
    if a == nil or a == b then return b end
    if b == nil then return a end
    return "AH"
end

--- Lay one quest record over the data. Returns true when it added anything.
function QuestLearn:Lay(questID, rec)
    local S = ns.Sources
    if type(S) ~= "table" or type(S.QUESTS) ~= "table" or type(S.ITEMS) ~= "table" then return false end
    if type(questID) ~= "number" or type(rec) ~= "table" or type(rec.title) ~= "string" then return false end
    local added = false

    if not S.QUESTS[questID] then
        local level = tonumber(rec.level) or tonumber(rec.min) or 1
        local min = tonumber(rec.min) or level
        S.QUESTS[questID] = {
            rec.title, min, level, 0, 0, type(rec.giver) == "string" and rec.giver or "",
            ZoneID(rec.zone), tonumber(rec.x) or 0, tonumber(rec.y) or 0, "",
            learned = true,
        }
        added = true
    end
    -- A learned quest is kept to the side that was offered it.
    local row = S.QUESTS[questID]
    if row.learned and rec.side then
        local races = SideRaces(rec.side)
        if row[4] ~= races then row[4] = races; added = true end
    end

    for _, reward in ipairs(type(rec.rewards) == "table" and rec.rewards or {}) do
        local itemID = type(reward) == "table" and tonumber(reward[1])
        -- A reward kept before non-gear was turned away stays saved, but is
        -- not laid over the data.
        if itemID and not QuestLearn.NotWorn(itemID) then
            local item = S.ITEMS[itemID]
            if not item then
                local level = tonumber(rec.level) or tonumber(rec.min) or 1
                local ilvl = tonumber(reward[3]) or 0
                item = { tonumber(reward[2]) or 0, ilvl > 0 and ilvl or level, 0, 0, 0, learned = true }
                S.ITEMS[itemID] = item
            end
            if not Has(item.q, questID) then
                item.q = item.q or {}
                item.q[#item.q + 1] = questID
                added = true
            end
            if reward[4] and not Has(item.g, questID) then
                item.g = item.g or {}
                item.g[#item.g + 1] = questID
                added = true
            end
        end
    end
    return added
end

--- Lay everything shipped and everything learned. Done at login, once.
function QuestLearn:LayAll()
    -- A false stands in for a missing shipped list, so ipairs still reaches the
    -- learned ones (on Classic Era the shipped list is left out).
    local added = false
    for _, source in ipairs({ ns.ForeverQuests or false, type(ns.db) == "table" and ns.db.learnedQuests or nil }) do
        if type(source) == "table" then
            for questID, rec in pairs(source) do
                if self:Lay(questID, rec) then added = true end
            end
        end
    end
    if added and ns.Finder and ns.Finder.MarkStale then pcall(ns.Finder.MarkStale, ns.Finder) end
    return added
end

--- How many quests this account has learned.
function QuestLearn:Count()
    local n = 0
    for _ in pairs(type(ns.db) == "table" and type(ns.db.learnedQuests) == "table" and ns.db.learnedQuests or {}) do
        n = n + 1
    end
    return n
end

--------------------------------------------------------------------------------
-- Reading the quest window
--------------------------------------------------------------------------------

local function ItemIDFromLink(link)
    local ok, id = pcall(function()
        if type(link) ~= "string" then return nil end
        return tonumber(link:match("item:(%d+)"))
    end)
    return ok and id or nil
end

QuestLearn.ItemIDFromLink = ItemIDFromLink

-- Equip slots that are not something to wear. This client gives every
-- item that cannot be worn INVTYPE_NON_EQUIP_IGNORE, so potions and other
-- goods a vendor or quest hands out are not taken for gear.
local NOT_WORN = { [""] = true, INVTYPE_BAG = true, INVTYPE_NON_EQUIP = true,
    INVTYPE_NON_EQUIP_IGNORE = true }

--- The item's equip slot from GetItemInfoInstant, or nil when unknown.
local function EquipLoc(itemID)
    local C = _G.C_Item
    local instant = (type(C) == "table" and C.GetItemInfoInstant) or _G.GetItemInfoInstant
    if type(instant) ~= "function" then return nil end
    local result = { pcall(instant, itemID) }
    if not result[1] then return nil end
    local ok, loc = pcall(function()
        if type(result[5]) == "string" then return result[5] .. "" end
    end)
    return ok and loc or nil
end

--- True only when the client says the item cannot be worn. Unknown items
--- are not turned away, so nothing learned is dropped on a guess.
function QuestLearn.NotWorn(itemID)
    local equipLoc = EquipLoc(itemID)
    return equipLoc ~= nil and NOT_WORN[equipLoc] == true
end

--- Is an item gear, and its required level and item level (0 while the
--- client has not loaded it). Nil for anything that is not gear.
function QuestLearn.Gear(itemID)
    local C = _G.C_Item
    local equipLoc = EquipLoc(itemID)
    if type(equipLoc) ~= "string" or NOT_WORN[equipLoc] then return nil end
    local getInfo = (type(C) == "table" and C.GetItemInfo) or _G.GetItemInfo
    local info = { pcall(getInfo or error, itemID) }
    local ilvl, req
    if info[1] then ilvl, req = Number(info[5]), Number(info[6]) end
    return req or 0, ilvl or 0
end

--- One reward. Gear comes back as { itemID, required level, item level,
--- given }; anything else as nil and { itemID, count, given }. `kind` is
--- "choice" or "reward"; `linkOf` gives the reward's link and `countOf` how
--- many (the quest window's, or the quest log's).
local function ReadReward(kind, index, linkOf, countOf)
    local itemID = ItemIDFromLink(Plain(Read(linkOf or _G.GetQuestItemLink, kind, index)))
    if not itemID then return nil end
    local req, ilvl = QuestLearn.Gear(itemID)
    if req then return { itemID, req, ilvl, kind == "reward" } end
    local count = countOf and Number(countOf(kind, index))
    count = count and math.floor(count) or 0
    return nil, { itemID, count >= 1 and count or 1, kind == "reward" }
end

--- The third thing a client call answers (how many, from the reward info
--- calls), or nil.
local function Third(fn, ...)
    local _, _, third = Read(fn, ...)
    return third
end

--- Copper and XP a quest gives, kept on `rec` when above 0.
local function NoteMoneyAndXP(rec, money, xp)
    money, xp = Number(money), Number(xp)
    if money and money > 0 then rec.money = math.floor(money) end
    if xp and xp > 0 then rec.xp = math.floor(xp) end
end

--- What the open quest window says, without keeping it: the quest's ID,
--- title, and the gear it rewards. Nil when the quest cannot be told.
function QuestLearn:Read(offer)
    local questID = Number(Read(_G.GetQuestID))
    local title = Plain(Read(_G.GetTitleText))
    if not questID or questID <= 0 or not title then return nil end
    local rewards, items = {}, {}
    local function CountOf(k, i) return Third(_G.GetQuestItemInfo, k, i) end
    for _, kind in ipairs({ "choice", "reward" }) do
        local count = Number(Read(kind == "choice" and _G.GetNumQuestChoices or _G.GetNumQuestRewards)) or 0
        for index = 1, math.min(count, REWARDS_MOST) do
            local reward, other = ReadReward(kind, index, nil, CountOf)
            if reward then rewards[#rewards + 1] = reward end
            if other then items[#items + 1] = other end
        end
    end
    local rec = { title = title, rewards = rewards, items = items }
    NoteMoneyAndXP(rec, Read(_G.GetRewardMoney), Read(_G.GetRewardXP))
    local level
    local log = _G.C_QuestLog
    if type(log) == "table" then
        level = Number(Read(log.GetQuestDifficultyLevel, questID))
    end
    if level and level > 0 then rec.level = level end
    rec.playerLevel = Number(Read(_G.UnitLevel, "player"))
    local side = ns.Finder and ns.Finder.Side and ns.Finder.Side()
    if side == "Alliance" or side == "Horde" then rec.side = side == "Alliance" and "A" or "H" end
    if offer then
        -- The one who offers it stands in front of the player.
        local name = Plain(Read(_G.UnitName, "npc"))
        if name and ns.NPCSpots then
            local zone, x, y = ns.NPCSpots:Here()
            if zone then rec.giver, rec.zone, rec.x, rec.y = name, zone, x, y end
        end
    end
    return questID, rec
end

local function ItemIn(list, itemID)
    for _, have in ipairs(type(list) == "table" and list or {}) do
        if type(have) == "table" and have[1] == itemID then return have end
    end
    return nil
end

--- Does a reading add rewards that are not gear, or copper or XP, to what
--- is kept?
function QuestLearn.AddsExtras(rec, seen)
    rec = rec or {}
    for _, item in ipairs(seen.items or {}) do
        local have = ItemIn(rec.items, item[1])
        if not have or (item[3] and not have[3]) then return true end
    end
    return (seen.money and not rec.money) or (seen.xp and not rec.xp) or false
end

--- Put a reading's rewards that are not gear, copper and XP on the record.
--- Copper and XP are kept as first read.
function QuestLearn.KeepExtras(rec, seen)
    for _, item in ipairs(seen.items or {}) do
        if type(rec.items) ~= "table" then rec.items = {} end
        local have = ItemIn(rec.items, item[1])
        if have then
            have[3] = have[3] or item[3]
        elseif #rec.items < REWARDS_MOST then
            rec.items[#rec.items + 1] = { item[1], item[2], item[3] }
        end
    end
    rec.money = rec.money or seen.money
    rec.xp = rec.xp or seen.xp
end

--- Keep what is new about a quest. Returns true when anything was saved.
function QuestLearn:Learn(questID, seen)
    local db = ns.db
    local S = ns.Sources
    if type(db) ~= "table" or type(S) ~= "table" or type(S.QUESTS) ~= "table" then return false end
    if type(db.learnedQuests) ~= "table" then db.learnedQuests = {} end
    local rec = db.learnedQuests[questID]
    local known = S.QUESTS[questID]

    -- Rewards the data does not link to this quest yet.
    local fresh = {}
    for _, reward in ipairs(seen.rewards or {}) do
        local item = S.ITEMS and S.ITEMS[reward[1]]
        if not (item and Has(item.q, questID) and (not reward[4] or Has(item.g, questID))) then
            fresh[#fresh + 1] = reward
        end
    end
    -- A quest Classic's data has keeps only gear it lacks.
    local classic = known and not known.learned
    if classic and #fresh == 0 then return false end
    -- A record kept before sides were noted stays offered to both.
    local side = seen.side
    if rec then side = rec.side and QuestLearn.JoinSides(rec.side, seen.side) end
    local extras = not classic and QuestLearn.AddsExtras(rec, seen)
    if known and known.learned and rec and #fresh == 0 and not (seen.giver and not rec.giver)
        and side == rec.side and not extras then return false end

    if not rec then
        rec = { title = seen.title, rewards = {}, at = Number(Read(_G.time)) or 0 }
        db.learnedQuests[questID] = rec
    end
    rec.level = seen.level or rec.level
    rec.side = side
    -- Offered to the player at this level, so it opens at or below it.
    local at = seen.playerLevel
    if at and (not rec.min or at < rec.min) then rec.min = at end
    if seen.giver and not rec.giver then rec.giver, rec.zone, rec.x, rec.y = seen.giver, seen.zone, seen.x, seen.y end
    if not classic then QuestLearn.KeepExtras(rec, seen) end
    for _, reward in ipairs(fresh) do
        local match
        for _, have in ipairs(rec.rewards) do
            if have[1] == reward[1] then match = have end
        end
        if match then
            match[4] = match[4] or reward[4]
            if (match[2] or 0) == 0 then match[2] = reward[2] end
            if (match[3] or 0) == 0 then match[3] = reward[3] end
        else
            rec.rewards[#rec.rewards + 1] = reward
        end
    end
    if self:Lay(questID, rec) and ns.Finder and ns.Finder.MarkStale then
        pcall(ns.Finder.MarkStale, ns.Finder)
    end
    return true
end

--------------------------------------------------------------------------------
-- Reading the quest log
--------------------------------------------------------------------------------

--- What the quest log says about one quest in it, without keeping it: the
--- same as a quest window's reading, with no giver. The quest is picked in
--- the log for the reward calls and the old pick put back. Nil when the
--- quest cannot be told.
function QuestLearn:ReadLogQuest(line)
    local questID = line and Number(line.questID)
    local title = line and Plain(line.title)
    if not questID or questID <= 0 or not title then return nil end
    local QL = ns.QuestLog
    local restore = QL and QL.Pick and QL.Pick(line)
    local rewards, items = {}, {}
    local money, xp
    pcall(function()
        for _, kind in ipairs({ "choice", "reward" }) do
            local counter = kind == "choice" and _G.GetNumQuestLogChoices or _G.GetNumQuestLogRewards
            local count = Number(Read(counter, questID)) or 0
            for index = 1, math.min(count, REWARDS_MOST) do
                local reward, other = ReadReward(kind, index, function(k, i)
                    return _G.GetQuestLogItemLink(k, i, questID)
                end, function(k, i)
                    return Third(k == "choice" and _G.GetQuestLogChoiceInfo or _G.GetQuestLogRewardInfo,
                        i, questID)
                end)
                if reward then rewards[#rewards + 1] = reward end
                if other then items[#items + 1] = other end
            end
        end
        money = Read(_G.GetQuestLogRewardMoney, questID)
        xp = Read(_G.GetQuestLogRewardXP, questID)
    end)
    if restore then pcall(restore) end
    local rec = { title = title, rewards = rewards, items = items }
    NoteMoneyAndXP(rec, money, xp)
    -- In the log, so it opens at or below the character's level.
    rec.playerLevel = Number(Read(_G.UnitLevel, "player"))
    local level = Number(line.level)
    if level and level > 0 then rec.level = level end
    local side = ns.Finder and ns.Finder.Side and ns.Finder.Side()
    if side == "Alliance" or side == "Horde" then rec.side = side == "Alliance" and "A" or "H" end
    return questID, rec
end

--- Learn from every quest in the log: quests picked up before this addon
--- learned, or whose window it missed. Reads a few quests a frame.
QuestLearn.LOG_PER_STEP = 4

function QuestLearn:LearnLog(only)
    local QL = ns.QuestLog
    if not (QL and QL.Size and QL.Line) then return end
    local size, how = QL.Size()
    if not how then return end
    local lines = {}
    for index = 1, math.min(size, 80) do
        local line = QL.Line(index, how)
        if line and not line.header and line.questID and (not only or line.questID == only) then
            lines[#lines + 1] = line
        end
    end
    local at = 1
    local function Step()
        if _G.InCombatLockdown and Read(_G.InCombatLockdown) then
            if _G.C_Timer then _G.C_Timer.After(2, Step) end
            return
        end
        for _ = 1, QuestLearn.LOG_PER_STEP do
            local line = lines[at]
            if not line then return end
            at = at + 1
            local questID, seen = QuestLearn:ReadLogQuest(line)
            if questID then QuestLearn:Learn(questID, seen) end
        end
        if lines[at] and _G.C_Timer then _G.C_Timer.After(0, Step) end
    end
    Step()
end

function QuestLearn:OnQuestWindow(offer)
    local questID, seen = self:Read(offer)
    if questID then self:Learn(questID, seen) end
end

function QuestLearn:OnEnable()
    pcall(self.LayAll, self)
    ns.RegisterEvent(self, "QUEST_DETAIL", function() QuestLearn:OnQuestWindow(true) end)
    ns.RegisterEvent(self, "QUEST_COMPLETE", function() QuestLearn:OnQuestWindow(false) end)
    -- The log: once after login (and again, for rewards the client loads
    -- late), and each quest as it is accepted.
    if _G.C_Timer then
        _G.C_Timer.After(6, function() QuestLearn:LearnLog() end)
        _G.C_Timer.After(30, function() QuestLearn:LearnLog() end)
    end
    ns.RegisterEvent(self, "QUEST_ACCEPTED", function(_, _, a, b)
        -- Retail passes the quest ID first; older clients the log index, then the ID.
        local questID = Number(b) or Number(a)
        if questID and _G.C_Timer then
            _G.C_Timer.After(1, function() QuestLearn:LearnLog(questID) end)
        end
    end)
end
