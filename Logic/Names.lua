-- Blackthornes Equipment -- Logic/Names.lua
-- The game's own names for what the data names in English: zones,
-- dungeons, quests, creatures, items and professions. Only on a client in
-- another language; an English client shows the data's names as before.
--
-- Everything here is for showing only. The data, the saved quests and every
-- check keep the English names (a zone is compared as "The Barrens"), so a
-- caller turns a name into the client's just before it puts it in words.
--
-- Where each name comes from, all read inside a pcall and kept:
--   zones       the map's own name (Waypoints.ZONE_MAPS, Classic's map IDs)
--   dungeons    GetRealZoneText for the instance (Sources.DUNGEONS keys)
--   quests      the quest's title as the client has it, else the quest log
--   creatures   a hidden tooltip on the creature (Data/NameIDs.lua gives
--               the ID), as the game names it once it has met it
--   items       item info (Data/NameIDs.lua, or the ID the caller has)
--   professions the profession's spell name
-- A name the game does not have yet stays English. A creature or quest the
-- client has not loaded is asked for again at most every Names.RETRY
-- seconds, and the upgrade quest panel is drawn again once one comes in.

local _, ns = ...

local Names = ns.NewModule("Names")

-- Seconds before the game is asked again for a name it did not have.
Names.RETRY = 10
-- Seconds after a miss before looking again, to redraw what came in.
Names.LOOK_AGAIN = 1.5

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

local function Now()
    return Read(_G.GetTime) or 0
end

-- The professions' spells, by the data's English name (Crafts.PROFESSIONS).
Names.PROFESSION_SPELLS = {
    ["Alchemy"] = 2259, ["Blacksmithing"] = 2018, ["Enchanting"] = 7411,
    ["Engineering"] = 4036, ["Leatherworking"] = 2108, ["Tailoring"] = 3908,
    ["Mining"] = 2575, ["Herbalism"] = 2366, ["Skinning"] = 8613,
    ["Cooking"] = 2550, ["First Aid"] = 3273, ["Fishing"] = 7620,
}

--- Does this client name things in another language than the data?
function Names.Local()
    local Waypoints = ns.Waypoints
    if Waypoints and Waypoints.English then return not Waypoints.English() end
    local locale = Plain(Read(_G.GetLocale))
    return locale ~= nil and locale:sub(1, 2) ~= "en"
end

local zones, quests, creatures, items, professions = {}, {}, {}, {}, {}
local tried = { quest = {}, npc = {} }

--- Forget every kept name (the tests, or a change of language).
function Names:Forget()
    zones, quests, creatures, items, professions = {}, {}, {}, {}, {}
    tried = { quest = {}, npc = {} }
    self.waiting = false
end

-- A miss: look again a moment later, and redraw once a name came in.
function Names:Missed(kind, key)
    tried[kind][key] = Now()
    if self.waiting then return end
    local after = _G.C_Timer and _G.C_Timer.After
    if type(after) ~= "function" then return end
    self.waiting = true
    after(Names.LOOK_AGAIN, function()
        Names.waiting = false
        if Names:Arrived() then Names:Redraw() end
    end)
end

--- Did a name the game lacked come in since? Looks only at the misses.
function Names:Arrived()
    local any = false
    for id in pairs(tried.npc) do
        if self:CreatureName(id) then
            tried.npc[id] = nil
            any = true
        end
    end
    for id in pairs(tried.quest) do
        if self:QuestTitle(id) then
            tried.quest[id] = nil
            any = true
        end
    end
    return any
end

--- Draw the upgrade quest panel again, where names show.
function Names:Redraw()
    local panel = ns.QuestPanel
    if panel and panel.RefreshSoon then pcall(panel.RefreshSoon, panel) end
end

--------------------------------------------------------------------------------
-- Zones and dungeons
--------------------------------------------------------------------------------

local function MapName(mapID)
    local map = _G.C_Map
    local info = map and Read(map.GetMapInfo, mapID)
    if type(info) ~= "table" then return nil end
    local ok, name = pcall(function() return info.name end)
    return ok and Plain(name) or nil
end

local function DungeonName(name)
    local dungeons = ns.Sources and ns.Sources.DUNGEONS
    if type(dungeons) ~= "table" then return nil end
    for key, dungeon in pairs(dungeons) do
        -- A wing ("189Graveyard") has no instance of its own to name it.
        local id = type(key) == "string" and key:match("^%d+$") and tonumber(key)
        if id and dungeon[1] == name then
            local here = Plain(Read(_G.GetRealZoneText))
            local found = Plain(Read(_G.GetRealZoneText, id))
            -- A client that ignores the ID answers where the player is.
            if found and found ~= here then return found end
            return nil
        end
    end
    return nil
end

--- A zone or dungeon the data names in English, as the client names it.
function Names:Zone(name)
    if type(name) ~= "string" or name == "" or not Names.Local() then return name end
    local kept = zones[name]
    if kept ~= nil then return kept or name end
    local mapID = ns.Waypoints and ns.Waypoints.ZONE_MAPS and ns.Waypoints.ZONE_MAPS[name]
    local found = (mapID and MapName(mapID)) or DungeonName(name)
    zones[name] = found or false
    return found or name
end

--------------------------------------------------------------------------------
-- Quests
--------------------------------------------------------------------------------

--- The client's title for a quest, or nil while it has none.
function Names:QuestTitle(questID)
    questID = tonumber(questID)
    if not questID then return nil end
    if quests[questID] then return quests[questID] end
    local log = _G.C_QuestLog
    local title = log and (Plain(Read(log.GetTitleForQuestID, questID))
        or Plain(Read(log.GetQuestInfo, questID)))
    if not title and ns.QuestLog and ns.QuestLog.Find then
        local ok, found = pcall(ns.QuestLog.Find, ns.QuestLog, questID)
        title = ok and type(found) == "table" and Plain(found.title) or nil
    end
    if title then quests[questID] = title end
    return title
end

--- A quest's title in the client's language, else `english`.
function Names:Quest(questID, english)
    if not Names.Local() then return english end
    questID = tonumber(questID)
    if not questID then return english end
    local title = self:QuestTitle(questID)
    if title then return title end
    local last = tried.quest[questID]
    if not last or Now() - last >= Names.RETRY then
        local log = _G.C_QuestLog
        if log and type(log.RequestLoadQuestByID) == "function" then
            pcall(log.RequestLoadQuestByID, questID)
        end
        self:Missed("quest", questID)
    end
    return english
end

--------------------------------------------------------------------------------
-- Creatures
--------------------------------------------------------------------------------

local TIP_NAME = "BlackthornesEquipmentNameTip"

local function Tip()
    if Names.tip ~= nil then return Names.tip or nil end
    local ok, tip = pcall(_G.CreateFrame, "GameTooltip", TIP_NAME, nil, "GameTooltipTemplate")
    Names.tip = ok and tip or false
    return Names.tip or nil
end

--- The client's name for a creature by its ID, or nil while it has none.
function Names:CreatureName(id)
    id = tonumber(id)
    if not id then return nil end
    if creatures[id] then return creatures[id] end
    local link = ("unit:Creature-0-0-0-0-%d-0000000000"):format(id)
    local name
    local info = _G.C_TooltipInfo
    if info and type(info.GetHyperlink) == "function" then
        local data = Read(info.GetHyperlink, link)
        local ok, text = pcall(function() return data.lines[1].leftText end)
        name = ok and Plain(text) or nil
    end
    if not name then
        local tip = Tip()
        if tip then
            pcall(tip.SetOwner, tip, _G.WorldFrame, "ANCHOR_NONE")
            pcall(tip.ClearLines, tip)
            if pcall(tip.SetHyperlink, tip, link) then
                local line = _G[TIP_NAME .. "TextLeft1"]
                name = line and Plain(Read(line.GetText, line)) or nil
            end
            pcall(tip.Hide, tip)
        end
    end
    if name then creatures[id] = name end
    return name
end

--- A creature the data names in English ("Apothecary Helbrim"), as the
--- client names it. `id` when the caller has one, else from the data.
function Names:NPC(english, id)
    if type(english) ~= "string" or english == "" or not Names.Local() then return english end
    local ids = ns.NAME_IDS and ns.NAME_IDS.npc
    id = tonumber(id) or (ids and ids[english])
    if not id then return english end
    if creatures[id] then return creatures[id] end
    local last = tried.npc[id]
    if last and Now() - last < Names.RETRY then return english end
    local name = self:CreatureName(id)
    if name then return name end
    self:Missed("npc", id)
    return english
end

--------------------------------------------------------------------------------
-- Items and professions
--------------------------------------------------------------------------------

--- An item the data names in English, as the client names it. `id` when
--- the caller has one, else from the data. An item not loaded yet is asked
--- for, and the windows that showed it draw again when it comes.
function Names:Item(english, id)
    if type(english) ~= "string" or english == "" or not Names.Local() then return english end
    local ids = ns.NAME_IDS and ns.NAME_IDS.item
    id = tonumber(id) or (ids and ids[english])
    if not id then return english end
    if items[id] then return items[id] end
    local item = _G.C_Item
    local name = Plain(Read(item and item.GetItemNameByID, id)) or Plain(Read(_G.GetItemInfo, id))
    if name then
        items[id] = name
        return name
    end
    -- Asking for its quality asks the client for the item, and the windows
    -- that showed it plain draw again when it comes (Data/Items.lua).
    if ns.Items and ns.Items.Quality then pcall(ns.Items.Quality, ns.Items, id) end
    return english
end

--- A profession the data names in English ("Tailoring"), as the client
--- names it.
function Names:Profession(english)
    if type(english) ~= "string" or english == "" or not Names.Local() then return english end
    local kept = professions[english]
    if kept ~= nil then return kept or english end
    local spell = Names.PROFESSION_SPELLS[english]
    local name
    if spell then
        local spells = _G.C_Spell
        local info = spells and Read(spells.GetSpellInfo, spell)
        local ok, text = pcall(function() return type(info) == "table" and info.name or nil end)
        name = (ok and Plain(text)) or Plain(Read(_G.GetSpellInfo, spell))
    end
    professions[english] = name or false
    return name or english
end

--- For /beq probe: what this client gives for one of each.
function Names:ProbeText()
    local here = Names.Local() and "another language" or "English"
    local npc = self:CreatureName(3390) or "none yet"
    local quest = self:QuestTitle(848) or "none yet"
    return ("client %s, zone %s, creature %s, quest %s, profession %s"):format(here,
        tostring(MapName(1413) or "?"), npc, quest,
        tostring(Plain(Read(_G.GetSpellInfo, 3908)) or "?"))
end
