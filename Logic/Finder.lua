-- Blackthornes Equipment -- Logic/Finder.lua
-- Where to go for an upgrade: gear a vendor sells, a quest gives or a dungeon
-- boss drops, that beats what the character wears today.
--
-- Data/Sources.lua says where each item comes from (Classic data). The game
-- says what the item is: its stats arrive from the server the first time an
-- item is asked about, and GET_ITEM_INFO_RECEIVED says when. So a scan judges
-- what the client already knows, asks for a batch of what it does not, and
-- the window scans again as answers come in.
--
-- Only what the character can get now is offered: their own faction's
-- vendors and quest givers, quests open at their level that they have not
-- done, and dungeons whose recommended range starts at or below their level.
-- Every verdict comes from Compare:Judge, so the finder, the tooltip and the
-- bag arrow always agree.

local _, ns = ...
local L = ns.L

local Finder = ns.NewModule("Finder")

local Items = ns.Items
local Compare = ns.Compare
local Weights = ns.Weights

-- Gear more than this many item levels under the character's level is not
-- looked at: it would almost never be an upgrade, and asking the server
-- about all of it would be a flood.
local LEVELS_BELOW = 12

-- How many items to ask the server about per scan. The rest wait for the
-- next scan, which the answers trigger.
local ASK_PER_SCAN = 40

-- How many times one item is asked about before giving up on it for the
-- session. An item Forever's server does not have never arrives, and asking
-- again every scan kept the client's item queue busy, so the game's own
-- windows (the quest reward choices) waited behind it.
local ASK_TRIES = 3

-- How many upgrades to keep per slot.
local PER_SLOT = 3
Finder.PER_SLOT = PER_SLOT

-- Classic's class and race bits, as quests and items carry them.
local CLASS_BITS = {
    WARRIOR = 1, PALADIN = 2, HUNTER = 4, ROGUE = 8, PRIEST = 16,
    SHAMAN = 64, MAGE = 128, WARLOCK = 256, DRUID = 1024,
}
local RACE_BITS = {
    Human = 1, Orc = 2, Dwarf = 4, NightElf = 8, Scourge = 16, Undead = 16,
    Tauren = 32, Gnome = 64, Troll = 128,
}
local ALLIANCE_RACES = 1 + 4 + 8 + 64
local HORDE_RACES = 2 + 16 + 32 + 128
Finder.ALLIANCE_RACES, Finder.HORDE_RACES = ALLIANCE_RACES, HORDE_RACES

-- Forever's own races, by the game's race ID. Both Skyborne races share the
-- race name "Skyborne", so only the ID tells the High Order (Alliance) from
-- the Windshapers (Horde).
local RACE_SIDES = { [95] = "Alliance", [96] = "Horde" }

--- a AND b, bit by bit. The game has bit.band; written out for a Lua without
--- it (the test runner).
local function Band(a, b)
    if bit and bit.band then return bit.band(a, b) end
    local result, place = 0, 1
    while a > 0 and b > 0 do
        if a % 2 == 1 and b % 2 == 1 then result = result + place end
        a, b, place = math.floor(a / 2), math.floor(b / 2), place * 2
    end
    return result
end

Finder.Band = Band

Finder.KINDS = { "vendor", "quest", "dungeon", "craft" }

--- Lay the Forever client's own numbers (Data/ForeverItems.lua) over the
--- Classic rows: required level, item level, classes and races, and the
--- vendor price of gear a vendor sells. Done once as the addon loads, so the
--- finder's level and class checks read Forever's numbers with no lookup
--- per item. Reputations and sources stay as they are.
function Finder.LayForeverItems(client, sources, crafts)
    for itemID, row in pairs(client or {}) do
        local item = sources and sources[itemID]
        if item then
            item[1], item[2], item[3], item[4] = row[1], row[2], row[3], row[4]
            if item.v then item[5] = row[5] end
        end
        local craft = crafts and crafts[itemID]
        if craft then
            craft[4], craft[5], craft[6], craft[7] = row[1], row[2], row[3], row[4]
        end
    end
end

Finder.LayForeverItems(ns.ForeverItems, ns.Sources and ns.Sources.ITEMS, ns.Crafts and ns.Crafts.ITEMS)

--- Leave out the Classic quests the Forever client does not have
--- (Data/ForeverGoneQuests.lua): their rows go, and so do their IDs in each
--- item's quest lists and any quest's `p`. Done once as the addon loads,
--- before QuestLearn lays what was learned in game, so a quest met in game
--- still shows.
function Finder.DropGoneQuests(gone, sources)
    if type(gone) ~= "table" or type(sources) ~= "table" then return 0 end
    local quests, items = sources.QUESTS, sources.ITEMS
    local dropped = 0
    if type(quests) == "table" then
        for questID in pairs(gone) do
            local quest = quests[questID]
            if quest and not quest.learned then
                quests[questID] = nil
                dropped = dropped + 1
            end
        end
        for _, quest in pairs(quests) do
            if quest.p and gone[quest.p] and not quests[quest.p] then quest.p = nil end
        end
    end
    local function Strip(list)
        if type(list) ~= "table" then return end
        for i = #list, 1, -1 do
            if gone[list[i]] and not (quests and quests[list[i]]) then table.remove(list, i) end
        end
    end
    for _, item in pairs(type(items) == "table" and items or {}) do
        Strip(item.q)
        Strip(item.g)
    end
    return dropped
end

Finder.DropGoneQuests(ns.ForeverGoneQuests, ns.Sources)

--------------------------------------------------------------------------------
-- The character
--------------------------------------------------------------------------------

--- A plain copy of a client string, or nil (a secret value raises when used).
local function Plain(value)
    local ok, copy = pcall(function()
        if type(value) == "string" and value ~= "" then return value .. "" end
    end)
    if ok then return copy end
    return nil
end

local function Read(fn, ...)
    if type(fn) ~= "function" then return nil end
    local result = { pcall(fn, ...) }
    if not result[1] then return nil end
    return unpack(result, 2)
end

--- The character's side, "Alliance" or "Horde", and its Classic race bit.
--- A race Classic never had (Forever's Skyborne) gets every race of its
--- side, so quests and gear are still kept to that side; without it, every
--- race-limited quest of both sides was offered.
-- @return the side and the race bit, or nil when the side cannot be read
function Finder.Side()
    local faction = Plain(Read(_G.UnitFactionGroup, "player"))
    local _, raceFile, raceID = Read(_G.UnitRace, "player")
    local raceBit = RACE_BITS[Plain(raceFile) or ""]
    if faction ~= "Alliance" and faction ~= "Horde" then
        local ok, id = pcall(function() return tonumber(raceID) end)
        faction = ok and id and RACE_SIDES[id] or nil
        if not faction and raceBit then
            faction = Band(raceBit, ALLIANCE_RACES) ~= 0 and "Alliance" or "Horde"
        end
    end
    if faction ~= "Alliance" and faction ~= "Horde" then return nil end
    return faction, raceBit or (faction == "Alliance" and ALLIANCE_RACES or HORDE_RACES)
end

--- Who is looking: level, faction ("A" or "H"), class and race bits.
-- @return a table, or nil when the level or faction cannot be read
function Finder:Player()
    local level = Items:PlayerLevel()

    local faction, raceBit = Finder.Side()
    if not level or not faction then return nil end

    local class = Weights:PlayerClass()
    local zone = Plain(Read(_G.GetRealZoneText))
    -- By the data's name for it, on a client in another language too.
    if ns.Waypoints then zone = ns.Waypoints:DataZone(zone) end
    return {
        level = level,
        zone = zone,
        faction = faction == "Alliance" and "A" or "H",
        class = class,
        classBit = CLASS_BITS[class] or 0,
        raceBit = raceBit,
    }
end

--- Has this character turned in a quest? False when the client cannot say.
function Finder:QuestDone(questID)
    local log = _G.C_QuestLog
    local done = Read(log and log.IsQuestFlaggedCompleted, questID)
    if done == nil then done = Read(_G.IsQuestFlaggedCompleted, questID) end
    if done == true then return true end
    -- Quests seen handed in, for a client that cannot say.
    local seen = ns.charDB and ns.charDB.questsTurnedIn
    return type(seen) == "table" and seen[questID] == true
end

--- Remember a quest handed in (QUEST_TURNED_IN), kept per character in
--- `questsTurnedIn`, in case the client has no call to ask.
function Finder:OnQuestTurnedIn(_, questID)
    local ok, id = pcall(function() return tonumber(questID) end)
    if ok and id and ns.charDB then
        if type(ns.charDB.questsTurnedIn) ~= "table" then ns.charDB.questsTurnedIn = {} end
        ns.charDB.questsTurnedIn[id] = true
    end
    self:MarkStale()
end

--------------------------------------------------------------------------------
-- Quest chains
--------------------------------------------------------------------------------

-- How far back a chain is followed, as in tools/make_sources.py.
local CHAIN_MOST = 20

local function QuestPlace(questID)
    local quest = ns.Sources.QUESTS[questID]
    if not quest then return nil end
    return {
        questID = questID, title = quest[1], questLevel = quest[3], name = quest[6],
        zone = ns.Sources.ZONES[quest[7]],
        x = quest[8] ~= 0 and quest[8] or nil, y = quest[9] ~= 0 and quest[9] or nil,
        group = Finder.Need(quest[11]),
    }
end

--- Does a quest hand over the item outright (its "You will also receive"),
--- rather than as one of the rewards to choose from?
function Finder.Given(itemID, questID)
    local item = itemID and ns.Sources.ITEMS[itemID]
    for _, given in ipairs(item and item.g or {}) do
        if given == questID then return true end
    end
    return false
end

--- The quests still to do before a quest opens, first one first: a list of
--- { questID, title, questLevel, name, zone, x, y, group }. A quest earlier
--- in the chain that the data does not have is named in the second return,
--- by its title, so the player can still be told to do it.
function Finder:Chain(questID)
    local chain, unknown = {}, nil
    local quest = ns.Sources.QUESTS[questID]
    for _ = 1, CHAIN_MOST do
        if not quest then break end
        local before = quest.p
        if not before then
            -- Named, but not in the data: whether it is done cannot be
            -- asked, so the steps let a later quest tick it off.
            if quest[10] ~= "" then unknown = quest[10] end
            break
        end
        if self:QuestDone(before) then break end
        table.insert(chain, 1, QuestPlace(before))
        quest = ns.Sources.QUESTS[before]
    end
    return chain, unknown
end

--------------------------------------------------------------------------------
-- Solo quests
--------------------------------------------------------------------------------

-- What a quest can need besides the player, as Data/Sources.lua marks it
-- (tools/make_sources.py works it out from Classic's quest data).
Finder.NEEDS = { group = true, dungeon = true, raid = true, battleground = true }

--- What a quest needs besides the player ("group", "dungeon", "raid" or
--- "battleground"), or nil when it can be done alone.
function Finder.Need(group)
    return Finder.NEEDS[group] and group or nil
end

--- Can a source be got alone? Everything but a quest that needs a group,
--- a dungeon, a raid or a battleground, or comes after one that does.
function Finder.Solo(source)
    if type(source) ~= "table" or source.kind ~= "quest" then return true end
    return not (Finder.Need(source.group) or Finder.Need(source.chainGroup))
end

--- Does the player want only quests they can do alone? Saved account wide
--- as `soloQuestsOnly`, off unless ticked.
function Finder:SoloOnly()
    return ns.db ~= nil and ns.db.soloQuestsOnly == true
end

--- Tell everything that shows where upgrades come from that the quest
--- filters changed.
function Finder:QuestFilterChanged()
    self:MarkStale()
    for _, name in ipairs({ "FinderUI", "UpgradeQuest", "SettingsUI" }) do
        local module = ns[name]
        if module and module.OnQuestFilterChanged then pcall(module.OnQuestFilterChanged, module) end
    end
end

--- Tick or untick "Solo quests only", for the finder window, the upgrade
--- quest and everything else that shows where upgrades come from.
function Finder:SetSoloOnly(on)
    if not ns.db then return end
    ns.db.soloQuestsOnly = on and true or false
    self:QuestFilterChanged()
end

-- How far above the character's level a quest may be, as the finder's
-- stepper sets it: 0 to QUEST_LEVELS_MOST, or QUEST_LEVELS_ANY for no limit.
-- Classic shows a quest 5 or more levels up in red.
Finder.QUEST_LEVELS_MOST = 10
Finder.QUEST_LEVELS_ANY = 11
Finder.QUEST_LEVELS_DEFAULT = 4

--- How many levels above the character a quest may be, or nil for any.
--- Saved account wide as `questLevelsAbove`.
function Finder:QuestLevelsAbove()
    local value = tonumber(ns.db and ns.db.questLevelsAbove) or self.QUEST_LEVELS_DEFAULT
    value = math.max(0, math.min(self.QUEST_LEVELS_ANY, math.floor(value)))
    if value >= self.QUEST_LEVELS_ANY then return nil end
    return value
end

function Finder:SetQuestLevelsAbove(value)
    if not ns.db then return end
    value = math.max(0, math.min(self.QUEST_LEVELS_ANY, math.floor(tonumber(value) or 0)))
    ns.db.questLevelsAbove = value
    self:QuestFilterChanged()
end

--- Does a quest source pass the quest filters at `level`? Anything that
--- is not a quest always does.
function Finder:QuestAllowed(source, level)
    if type(source) ~= "table" or source.kind ~= "quest" then return true end
    if self:SoloOnly() and not Finder.Solo(source) then return false end
    local above = self:QuestLevelsAbove()
    if above and level and (tonumber(source.questLevel) or 0) > level + above then return false end
    return true
end

--------------------------------------------------------------------------------
-- Sources
--------------------------------------------------------------------------------

local function Allows(mask, flag)
    return mask == 0 or flag == 0 or Band(mask, flag) ~= 0
end

local function ZoneName(zoneID)
    return ns.Sources.ZONES[zoneID]
end

-- The game's standings, 1 Hated to 8 Exalted.
local STANDINGS = {
    L["Hated"], L["Hostile"], L["Unfriendly"], L["Neutral"], L["Friendly"], L["Honored"], L["Revered"], L["Exalted"],
}
Finder.STANDINGS = STANDINGS

--- This character's standing with a faction (1 Hated to 8 Exalted) and the
--- faction's name, or nil when the game cannot say (never met them, say).
function Finder:Standing(factionID)
    local reputation = _G.C_Reputation
    local data = Read(reputation and reputation.GetFactionDataByID, factionID)
    if type(data) == "table" and tonumber(data.reaction) then
        return tonumber(data.reaction), data.name
    end
    local name, _, standing = Read(_G.GetFactionInfoByID, factionID)
    if tonumber(standing) then return tonumber(standing), name end
    return nil, name
end

--- Does an item ask for a standing with a faction at all, reached or not?
--- The upgrade quest offers such gear last.
function Finder.Rep(itemID)
    local item = ns.Sources.ITEMS[itemID]
    local craft = ns.Crafts and ns.Crafts.ITEMS[itemID]
    return ((item and item.r) or (craft and craft.f)) ~= nil
end

--- What an item asks of the character's reputation that they do not have
--- yet: { faction, standing, have } in words, or nil when nothing.
function Finder:Needs(itemID)
    local item = ns.Sources.ITEMS[itemID]
    local craft = ns.Crafts and ns.Crafts.ITEMS[itemID]
    local rep = (item and item.r) or (craft and craft.f)
    if not rep then return nil end

    -- Standing in the data counts from 0 (Hated); the game's from 1.
    local need = rep[2] + 1
    local have, name = self:Standing(rep[1])
    if have and have >= need then return nil end
    if type(name) ~= "string" or name == "" then
        name = ns.Sources.FACTIONS[rep[1]] or L["a faction"]
    end
    return { faction = name, standing = STANDINGS[need] or "?", have = have and STANDINGS[have] }
end

--- Every place this character can get an item from now, as a list of
--- tables { kind, ... }, vendors first, then quests, then dungeons.
function Finder:SourcesFor(itemID, player)
    local S = ns.Sources
    -- Gear only seen on Forever has no Classic entry; the game says what
    -- level it needs when it is judged.
    local item = S.ITEMS[itemID] or { 0, 0, 0, 0, 0 }
    local seen = S.FOREVER and S.FOREVER[itemID]
    -- Gear players make: whoever on the account can make it, or where to
    -- learn it (Logic/Crafting.lua).
    local craft = ns.Crafting and ns.Crafting:SourceFor(itemID, player, Band)
    if not S.ITEMS[itemID] and not seen then return { craft } end

    local found = {}
    if item[1] > player.level or not Allows(item[3], player.classBit)
        or not Allows(item[4], player.raceBit) then
        return found
    end

    local vendors = item.v or {}
    for i = 1, #vendors, 2 do
        local npc = S.NPCS[vendors[i]]
        if npc and npc[5]:find(player.faction, 1, true) then
            -- Where Forever has the vendor, when seen there (Logic/NPCSpots.lua).
            local name, zone, x, y = npc[1], ZoneName(npc[2]), npc[3], npc[4]
            if ns.NPCSpots then name, zone, x, y = ns.NPCSpots:Place(vendors[i], name, zone, x, y) end
            -- What the vendor charges on Forever, once a merchant window showed it.
            local seenPrice = ns.NPCSpots and ns.NPCSpots:Price(itemID)
            found[#found + 1] = {
                kind = "vendor", name = name, zone = zone, x = x, y = y,
                price = seenPrice or item[5], priceSeen = seenPrice ~= nil, limited = vendors[i + 1] > 0,
            }
        end
    end

    for _, questID in ipairs(item.q or {}) do
        local quest = S.QUESTS[questID]
        if quest and quest[2] <= player.level and Allows(quest[4], player.raceBit)
            and Allows(quest[5], player.classBit) and not self:QuestDone(questID) then
            local chain, unknown = self:Chain(questID)
            -- The first quest still to do in the chain that needs others.
            local chainGroup
            for _, before in ipairs(chain) do
                chainGroup = chainGroup or Finder.Need(before.group)
            end
            local source = {
                chain = #chain + (unknown and 1 or 0), first = unknown or (chain[1] and chain[1].title),
                kind = "quest", questID = questID, title = quest[1], questLevel = quest[3],
                name = quest[6], zone = ZoneName(quest[7]),
                x = quest[8] ~= 0 and quest[8] or nil, y = quest[9] ~= 0 and quest[9] or nil,
                after = quest[10] ~= "" and quest[10] or nil, group = Finder.Need(quest[11]),
                chainGroup = chainGroup,
                -- Handed over with the quest, not picked from its choices.
                given = Finder.Given(itemID, questID) or nil,
            }
            if self:QuestAllowed(source, player.level) then found[#found + 1] = source end
        end
    end

    local drops = item.d or {}
    for i = 1, #drops, 2 do
        local boss = S.BOSSES[drops[i]]
        local dungeon = boss and S.DUNGEONS[boss[2]]
        if dungeon and dungeon[2] <= player.level
            and (dungeon[5] == "" or dungeon[5] == player.faction) then
            found[#found + 1] = {
                kind = "dungeon", name = boss[1], dungeon = dungeon[1],
                minLevel = dungeon[2], maxLevel = dungeon[3], zone = dungeon[4],
                raid = dungeon[6] or false,
                chance = drops[i + 1],
            }
        end
    end

    -- What Farmer's loot records saw drop on Forever: it marks the Classic
    -- drop as confirmed, with Forever's own rate where there is one, or adds
    -- a drop Classic never had.
    for _, drop in ipairs(seen or {}) do
        local dungeon = S.DUNGEONS[drop[2]]
        if dungeon and dungeon[2] <= player.level
            and (dungeon[5] == "" or dungeon[5] == player.faction) then
            local rate = drop[3] > 0 and drop[3] or nil
            local match
            for _, source in ipairs(found) do
                if source.kind == "dungeon" and source.name:lower() == drop[1]:lower() then
                    match = source
                end
            end
            if match then
                match.forever = true
                match.chance = rate or match.chance
            else
                found[#found + 1] = {
                    kind = "dungeon", name = drop[1], dungeon = dungeon[1],
                    minLevel = dungeon[2], maxLevel = dungeon[3], zone = dungeon[4],
                    raid = dungeon[6] or false, chance = rate, forever = true,
                }
            end
        end
    end

    found[#found + 1] = craft

    -- Somewhere in the zone the character is standing in comes first: a
    -- vendor down the road beats the same item across the world.
    if player.zone then
        local here, there = {}, {}
        for _, source in ipairs(found) do
            local list = source.zone == player.zone and here or there
            list[#list + 1] = source
        end
        for _, source in ipairs(there) do here[#here + 1] = source end
        found = here
    end

    return found
end

--- The items worth judging for this character: in level range, with at least
--- one source open to them. A list of { itemID, sources }.
function Finder:Candidates(player, only, pause)
    local list = {}
    local floor = player.level - LEVELS_BELOW
    local ids = {}
    for itemID, item in pairs(ns.Sources.ITEMS) do
        if item[2] >= floor and item[1] <= player.level then ids[#ids + 1] = itemID end
    end
    for itemID in pairs(ns.Sources.FOREVER or {}) do
        if not ns.Sources.ITEMS[itemID] then ids[#ids + 1] = itemID end
    end
    -- Recipes the characters learned that Classic's data lacks.
    if ns.Crafting and ns.Crafting.LayLearned then ns.Crafting:LayLearned() end
    for itemID, craft in pairs(ns.Crafts and ns.Crafts.ITEMS or {}) do
        if not ns.Sources.ITEMS[itemID] and not (ns.Sources.FOREVER or {})[itemID]
            and craft[5] >= floor and craft[4] <= player.level then
            ids[#ids + 1] = itemID
        end
    end
    for _, itemID in ipairs(ids) do
        if pause then pause() end
        -- Gear the class can never wear (plate for a mage) is dropped by the
        -- scan anyway; asked first, from the client's instant item info, its
        -- vendors, quests, drops and crafts are never worked out.
        if Finder.Wearable(player.class, itemID) ~= false then
            local sources = self:SourcesFor(itemID, player)
            if only then
                local kept = {}
                for _, source in ipairs(sources) do
                    if source.kind == only then kept[#kept + 1] = source end
                end
                sources = kept
            end
            if #sources > 0 then
                list[#list + 1] = {
                    itemID = itemID, sources = sources, needs = self:Needs(itemID), rep = Finder.Rep(itemID),
                }
            end
        end
    end
    table.sort(list, function(a, b) return a.itemID < b.itemID end)
    return list
end

--------------------------------------------------------------------------------
-- Asking the client
--------------------------------------------------------------------------------

--- Does the client have this item's details yet? True when it cannot say,
--- so a client without the call is simply asked through Judge.
function Finder:IsCached(itemID)
    local C = _G.C_Item
    local cached = Read(C and C.IsItemDataCachedByID, itemID)
    if cached == nil then return true end
    return cached
end

--- Ask the server about an item; GET_ITEM_INFO_RECEIVED answers.
--- What was asked is remembered, so an answer about some other item (a chat
--- link, another addon's window) does not set off a scan.
--- Nothing is asked while a quest giver's window is open: the reward
--- choices there wait on the same queue, and the scan can ask again once it
--- closes. An item asked ASK_TRIES times without arriving is not asked again.
--- @return true when the server was asked
function Finder:Request(itemID)
    self.asked = self.asked or {}
    self.tries = self.tries or {}
    if (self.tries[itemID] or 0) >= ASK_TRIES then return false end
    if self.QuestWindowOpen() then return false end
    self.asked[itemID] = true
    self.tries[itemID] = (self.tries[itemID] or 0) + 1
    local C = _G.C_Item
    local request = C and C.RequestLoadItemDataByID
    if type(request) == "function" then
        Read(request, itemID)
    else
        Read(C and C.GetItemInfo or _G.GetItemInfo, itemID)
    end
    return true
end

--- Is the game's quest giver window (offer, progress or hand-in) open?
function Finder.QuestWindowOpen()
    local frame = _G.QuestFrame
    if type(frame) ~= "table" then return false end
    local ok, shown = pcall(function() return frame:IsShown() and true or false end)
    return ok and shown or false
end

--- Can this class wear the item at all? Read from the client's own item
--- table, which needs no server answer, so nothing is asked about gear the
--- class could never use. Nil when the client cannot say without asking.
local function Wearable(class, itemID)
    local info = Items:Info(("item:%d"):format(itemID))
    if not info then return nil end
    if not Compare.SLOTS[info.equipLoc] then return false end
    local usable = Weights:CanUse(class, info.classID, info.subclassID, info.equipLoc)
        and Compare:ClassAllows(class, itemID)
    return usable and true or false
end
Finder.Wearable = Wearable

--- The item's own link, quality colour and all, where the client has it.
local function LinkFor(itemID)
    local _, link = Items.Call({ "C_Item.GetItemInfo", "GetItemInfo" }, itemID)
    return Items.PlainLink(link) or ("item:%d"):format(itemID)
end

--- A rolled item's link from the client ("[Chain Vest of the Monkey]"),
--- or the plain item's when the client has none for the roll.
local function RolledLink(rolled, itemID)
    local _, link = Items.Call({ "C_Item.GetItemInfo", "GetItemInfo" }, rolled)
    link = Items.PlainLink(link)
    if link and link:find("|H", 1, true) then return link end
    return LinkFor(itemID)
end

--- The item IDs in the carried bags, as a set.
function Finder:Carried()
    local carried = {}
    for bag = 0, 4 do
        for slot = 1, Items:BagSize(bag) do
            local link = Items:InBag(bag, slot)
            local id = link and tonumber(link:match("item:(%d+)"))
            if id then carried[id] = true end
        end
    end
    return carried
end

--------------------------------------------------------------------------------
-- The scan
--------------------------------------------------------------------------------

--- Is a verdict an upgrade worth listing? Wearable now, or, when planning
--- ahead, wearable by the level planned for.
local function Counts(result, reach, level)
    if Compare.WearableUpgrade(result) then return true end
    return reach > level and result.verdict == "upgrade" and result.level ~= nil
        and result.level <= reach and not result.train
end

--- Every pick's sources are gear nobody on the account can make: a
--- crafter or the auction house would have to supply it.
local function Remote(sources)
    for _, source in ipairs(sources) do
        if not (source.kind == "craft" and source.state == "other") then return false end
    end
    return true
end

--- The verdicts kept from earlier scans, for gear, level, talents, weapon
--- skills and stat weights as they are now. Judging thousands of items on
--- every scan made the game hitch; most scans only need the few items whose
--- details just arrived judged. Started afresh when any of those changes.
local function WornStatsRead()
    local read = 0
    for slot = 1, 19 do
        local link = Items:Equipped(slot)
        if link and Items:Stats(link) then read = read + 1 end
    end
    return read
end

function Finder:JudgeKey()
    -- Worn gear whose stats had not loaded yet (just after login) scores
    -- nothing, so its count is part of the key too.
    return table.concat({
        tostring(Items:WornSignature()), tostring(WornStatsRead()), tostring(Items:PlayerLevel()),
        tostring(Weights.generation or 0), tostring(self.judgeGeneration or 0),
        -- A character skipped for upgrades has none (Alts:SetSkipped).
        tostring(ns.Alts and ns.Alts:PlayerSkipped() or false),
        -- Learning Dual Wield changes what an off-hand weapon is judged
        -- against, and may come with no skill or talent event.
        tostring(Weights:CanDualWield(Weights:PlayerClass(), Items:PlayerLevel())),
    }, "|")
end

function Finder:Judged()
    local key = self:JudgeKey()
    if key ~= self.judgedKey or type(self.judged) ~= "table" then
        self.judgedKey, self.judged = key, {}
    end
    return self.judged
end

--- Forget the kept verdicts (talents or weapon skills changed).
function Finder:ForgetVerdicts()
    self.judgeGeneration = (self.judgeGeneration or 0) + 1
    self.stale = true
end

--- One item's verdict, judged once per Judged() set. Gear with random rolls
--- is judged at its best roll.
-- @return best roll (or nil), ok, result
function Finder:JudgeOnce(judged, itemID)
    local kept = judged[itemID]
    if kept then return kept.best, true, kept.result end
    local best = ns.Rolls and ns.Rolls.Best and ns.Rolls:Best(itemID)
    local link = best and best.link or ("item:%d"):format(itemID)
    local ok, result = true, best and best.result
    if not best then ok, result = pcall(Compare.Judge, Compare, link) end
    -- Only a full answer is kept: an item still loading, or rolled gear with
    -- rolls the client has not seen yet, is judged again next time.
    local data = ns.RollData
    local group = data and data.ITEMS and data.ITEMS[itemID]
    local rolls = group and data.GROUPS and data.GROUPS[group]
    local allRolls = not rolls or (best and (best.rolls or 0) * 2 >= #rolls)
    if ok and result and allRolls then
        judged[itemID] = { best = best, result = result }
    end
    return best, ok, result
end

--- The order picks show in, best first: what can be had now before gear
--- that waits on a reputation, both before gear someone else would have to
--- make, then by the percent shown (an empty slot, which shows none, ahead
--- of any), then nearest first, then by gain. The percent comes before
--- nearness so a tie broken by nearness never fights the gain: mixing the
--- two could order three picks in a circle, which table.sort may refuse
--- with an error. Upgrades that show the same "+12%" come nearest first (a
--- player asked, 2026-10-09). The finder window sorts its rings and
--- trinkets, two slots shown as one, by it too.
function Finder.Order(a, b)
    if (a.needs == nil) ~= (b.needs == nil) then return a.needs == nil end
    if a.remote ~= b.remote then return not a.remote end
    local pa, pb = Finder.Shown(a.result), Finder.Shown(b.result)
    if (pa == nil) ~= (pb == nil) then return pa == nil end
    if pa and pa ~= pb then return pa > pb end
    if (a.near or 0) ~= (b.near or 0) then return (a.near or 0) < (b.near or 0) end
    if (a.gain or 0) ~= (b.gain or 0) then return (a.gain or 0) > (b.gain or 0) end
    return a.itemID < b.itemID
end

--- Look for upgrades, from every kind of source or only `only` ("vendor",
--- "quest", "dungeon" or "craft"), and `ahead` levels past the character's
--- (0 or nil for now).
-- @return nil and why, or a table:
--   slots     { [inventory slot] = { pick, ... } } best first, at most
--             PER_SLOT each; a pick is { itemID, link, result, gain,
--             sources, needs, rep, roll, at }: `rep` for gear tied to
--             a reputation (reached or not), `roll` for gear with random rolls
--             (Logic/Rolls.lua's best), `at` the level it can be worn from
--             when that is still ahead
--   all       { [inventory slot] = { pick, ... } } the same, every pick
--             kept, for the upgrade quest's "This zone only", whose best
--             here is seldom among the best anywhere
--   count     how many picks in all
--   checked   how many items were judged
--   waiting   how many the server has still to answer about
--   player    the player table
--   reach     the level looked at
function Finder:Scan(only, ahead)
    return self:Build(only, ahead)
end

--- The scan itself. `pause`, when given, is called between items: the
--- background scan hands one in that yields once a frame's share is used.
function Finder:Build(only, ahead, pause)
    local player = self:Player()
    if not player then return nil, "nolevel" end

    local weights = Weights:ForPlayer()
    if not weights then return nil, "noweights" end

    -- Looking ahead: everything open to the character at the level planned
    -- for, judged against what is worn today.
    local level = player.level
    local reach = math.min(60, level + math.max(0, math.floor(tonumber(ahead) or 0)))
    local plan = player
    if reach > level then
        plan = {}
        for key, value in pairs(player) do plan[key] = value end
        plan.level = reach
    end

    -- Gear already in the bags is the gear window's to show, not something
    -- to go and buy or farm again.
    local carried = self:Carried()

    local judged = self:Judged()
    -- The key these verdicts were made under; a scan made meanwhile may move
    -- self.judgedKey on before this one finishes.
    local judgedKey = self.judgedKey
    local worn = Compare:WornIDs()
    local slots, checked, waiting, asked = {}, 0, 0, 0
    for _, candidate in ipairs(self:Candidates(plan, only, pause)) do
        if pause then pause() end
        local itemID = candidate.itemID
        local wearable = not carried[itemID] and Wearable(player.class, itemID)
        if wearable ~= false then
            if wearable == nil or not self:IsCached(itemID) then
                waiting = waiting + 1
                if asked < ASK_PER_SCAN and self:Request(itemID) then
                    asked = asked + 1
                end
            elseif not worn[itemID] then
                local best, ok, result = self:JudgeOnce(judged, itemID)
                if ok and result then
                    checked = checked + 1
                    if Counts(result, reach, level) and result.slot then
                        local list = slots[result.slot] or {}
                        slots[result.slot] = list
                        list[#list + 1] = {
                            itemID = itemID, link = best and RolledLink(best.link, itemID) or LinkFor(itemID),
                            result = result,
                            gain = (result.score or 0) - (result.against or 0),
                            sources = candidate.sources, needs = candidate.needs, rep = candidate.rep,
                            roll = best, at = result.level, remote = Remote(candidate.sources),
                        }
                    end
                elseif ok then
                    -- Known to the client but its stats are not in yet.
                    waiting = waiting + 1
                end
            end
        end
    end

    local count, all = 0, {}
    local spot = Finder.Spot(player.zone)
    for slot, list in pairs(slots) do
        -- Best first, by Finder.Order.
        for _, pick in ipairs(list) do pick.near = Finder.Nearness(pick.sources, player.zone, spot) end
        table.sort(list, Finder.Order)
        local copy = {}
        for i, pick in ipairs(list) do copy[i] = pick end
        all[slot] = copy
        for i = #list, PER_SLOT + 1, -1 do list[i] = nil end
        count = count + #list
        slots[slot] = list
    end

    local found = {
        slots = slots, all = all, count = count, checked = checked, waiting = waiting, player = player,
        reach = reach,
    }
    if not only and reach == level then
        self.latest, self.latestAt, self.latestKey = found, self.Now(), judgedKey
    end
    return found
end

--- The whole percent an upgrade shows ("+12%"), or nil for one that shows
--- no percent (an empty slot).
function Finder.Shown(result)
    local percent = type(result) == "table" and tonumber(result.percent)
    return percent and math.floor(percent + 0.5) or nil
end

--- Where the character stands on the map of `zone`: { x, y } from 0 to 1,
--- or nil when the client does not say, or the map it gives is not that
--- zone's (a city or a cave inside it). Never guessed.
function Finder.Spot(zone)
    if not zone or not (ns.QuestArrow and ns.Waypoints) then return nil end
    local ok, spot = pcall(function()
        local here = ns.QuestArrow:Here()
        if here and here.x and here.y and here.map == ns.Waypoints:MapFor(zone) then
            return { x = here.x, y = here.y }
        end
    end)
    return ok and spot or nil
end

--- How near the nearest of some sources is, smaller nearer: the squared
--- map distance (0 to 2) for one in `zone` with a spot when `spot` is
--- known, 2.5 for one in the zone without, 3 for one elsewhere.
function Finder.Nearness(sources, zone, spot)
    local best = 3
    if not zone then return best end
    local zoneOf = ns.UpgradeQuest and ns.UpgradeQuest.SourceZone
    for _, source in ipairs(sources or {}) do
        local where = zoneOf and zoneOf(source) or source.zone
        if where == zone or source.dungeon == zone then
            local near = 2.5
            local x, y = tonumber(source.x), tonumber(source.y)
            if spot and x and y and where == zone then
                near = (x / 100 - spot.x) ^ 2 + (y / 100 - spot.y) ^ 2
            end
            if near < best then best = near end
        end
    end
    return best
end

--- Seconds, for how old a kept scan is.
function Finder.Now()
    local now = _G.GetTime and Read(_G.GetTime)
    return tonumber(now) or os.time()
end

--- The latest scan of everything for now, made again (in the background,
--- once there is one) when the gear, the level or the bags changed since, at
--- most every few seconds. For the character sheet's slots, which ask on
--- every hover.
function Finder:Latest()
    if self.background then return self.latest end
    local fresh = self.latest and not self.stale and (self.Now() - (self.latestAt or 0)) < 60
    if not fresh and (not self.latest or (self.Now() - (self.latestAt or 0)) >= 2) then
        -- Made a slice per frame, the last one kept on show meanwhile. The
        -- very first is too: done in one go, a hover froze the game.
        self:ScanInBackground()
    end
    return self.latest
end

--- Was this item asked about by a scan? (GET_ITEM_INFO_RECEIVED's item.)
function Finder:Asked(itemID)
    local ok, id = pcall(function() return tonumber(itemID) end)
    return ok and id ~= nil and self.asked ~= nil and self.asked[id] == true
end

function Finder:MarkStale()
    self.stale = true
end

--------------------------------------------------------------------------------
-- Scanning in the background
--
-- A full scan after the gear or level changes judges hundreds of items. Done
-- in one go it freezes the game for a moment, so the upgrade quest has it
-- done a slice per frame instead, and is told when it is finished.
--------------------------------------------------------------------------------

-- How long one frame's slice may run, in milliseconds, and how many items a
-- slice takes on a client without a timer to measure with.
local SLICE_MS = 6
local SLICE_ITEMS = 40

--- The latest full scan, if nothing has changed since it was started.
function Finder:Fresh()
    -- While a scan runs, the last one is out of date. The key catches a
    -- change whose event was missed.
    if self.background or self.stale or not self.latest then return nil end
    if self.latestKey == self:JudgeKey() then return self.latest end
    return nil
end

--- Is a background scan under way?
function Finder:Scanning()
    return self.background ~= nil
end

--- Run `build(pause)` a slice per frame and hand what it returns to
--- `finish(found, why)`. Without timers or coroutines it runs at once.
local function Sliced(build, finish)
    local Clock = ns.Perf and ns.Perf.Clock or function() return nil end
    local started, count = Clock(), 0
    local after = _G.C_Timer and _G.C_Timer.After
    local canYield = type(after) == "function" and type(coroutine) == "table"
    local function Pause()
        if not canYield then return end
        count = count + 1
        local now = Clock()
        if (now and started and now - started >= SLICE_MS) or (not now and count >= SLICE_ITEMS) then
            coroutine.yield()
            started, count = Clock(), 0
        end
    end

    if not canYield then
        finish(build(nil))
        return
    end

    local worker = coroutine.create(function() return build(Pause) end)
    local function Step()
        started, count = Clock(), 0
        local ok, found, why = coroutine.resume(worker)
        local finished = Clock()
        if ns.Perf and started and finished then ns.Perf:Add("Finder:background slice", finished - started) end
        if not ok then
            ns.Debug("finder:", tostring(found))
            finish(nil, "error")
        elseif coroutine.status(worker) == "dead" then
            finish(found, why)
        else
            after(0, Step)
        end
    end
    Step()
end

--- Make a full scan for now, a slice per frame, then call each of the
--- waiting `done` functions with it (or with nil and why). A scan already
--- under way takes the new caller too. Without timers it runs at once.
function Finder:ScanInBackground(done)
    if self.background then
        if done then self.background.waiting[#self.background.waiting + 1] = done end
        return
    end
    local job = { waiting = { done } }
    self.background = job
    -- Whatever changes from here on makes this scan stale.
    self.stale = false

    Sliced(function(pause) return Finder:Build(nil, nil, pause) end, function(found, why)
        Finder.background = nil
        for _, fn in ipairs(job.waiting) do
            local ok, err = pcall(fn, found, why)
            if not ok then ns.Debug("finder:", tostring(err)) end
        end
    end)
end

--- The finder window's own scan (its filter and how far ahead it looks), a
--- slice per frame, for a refresh after an event: a bag change or an item
--- answer no longer freezes the game while the window is open. Only the
--- latest one asked for calls `done`; one it replaces is left to finish
--- quietly. Kept apart from ScanInBackground, whose scan the upgrade
--- quest and the character sheet share.
function Finder:ScanSliced(only, ahead, done)
    local job = {}
    self.sliced = job
    Sliced(function(pause) return Finder:Build(only, ahead, pause) end, function(found, why)
        if Finder.sliced ~= job then return end
        Finder.sliced = nil
        if done then
            local ok, err = pcall(done, found, why)
            if not ok then ns.Debug("finder:", tostring(err)) end
        end
    end)
end

function Finder:OnEnable()
    for _, event in ipairs({ "PLAYER_EQUIPMENT_CHANGED", "PLAYER_LEVEL_UP", "BAG_UPDATE_DELAYED",
        "TRAIT_CONFIG_UPDATED", "CHARACTER_POINTS_CHANGED", "PLAYER_TALENT_UPDATE" }) do
        ns.RegisterEvent(self, event, self.MarkStale)
    end
    -- Only answers a scan asked for: the client loads items for chat links
    -- and the auction house all the time.
    ns.RegisterEvent(self, "GET_ITEM_INFO_RECEIVED", function(_, _, itemID)
        if Finder:Asked(itemID) then Finder:MarkStale() end
    end)
    ns.RegisterEvent(self, "QUEST_TURNED_IN", self.OnQuestTurnedIn)
    -- Talents move the spec the weights come from: Forever's trait tree,
    -- else Era's talent points.
    for _, event in ipairs({ "TRAIT_CONFIG_UPDATED", "CHARACTER_POINTS_CHANGED", "PLAYER_TALENT_UPDATE" }) do
        ns.RegisterEvent(self, event, self.ForgetVerdicts)
    end
    ns.RegisterEvent(self, "SKILL_LINES_CHANGED", self.ForgetVerdicts)
end

--------------------------------------------------------------------------------
-- Words
--------------------------------------------------------------------------------

local MONEY = {
    { 10000, "g", "ffffd700" },
    { 100, "s", "ffc7c7cf" },
    { 1, "c", "ffeda55f" },
}

--- Copper as "1g 20s 5c", each part in its coin's colour.
function Finder.Money(copper)
    copper = math.floor(tonumber(copper) or 0)
    if copper <= 0 then return nil end
    local parts = {}
    for _, coin in ipairs(MONEY) do
        local amount = math.floor(copper / coin[1])
        copper = copper - amount * coin[1]
        if amount > 0 then
            parts[#parts + 1] = ("|c%s%d%s|r"):format(coin[3], amount, coin[2])
        end
    end
    return table.concat(parts, " ")
end

--- The character's money in copper, or nil when it can't be read.
function Finder.MoneyHeld()
    local ok, copper = pcall(function()
        local money = _G.GetMoney and _G.GetMoney()
        local n = tonumber(money)
        if n and n == n then return n + 0 end
    end)
    return ok and copper or nil
end

--- How much more copper the character needs to buy at `price`, or nil when
--- they can afford it or either side is unknown.
function Finder.Short(price)
    price = tonumber(price)
    if not price or price <= 0 then return nil end
    local held = Finder.MoneyHeld()
    if not held or held >= price then return nil end
    return price - held
end

-- What a quest needs besides the player, in words.
local NEED_WORDS = {
    group = L["group"], dungeon = L["dungeon"], raid = L["raid"], battleground = L["battleground"],
}

local function Place(source)
    if not source.zone then return nil end
    if source.x and source.y then
        return ("%s (%s, %s)"):format(source.zone, source.x, source.y)
    end
    return source.zone
end

--- The item a quest starts from, by its ID, when the source names one.
function Finder.StartsItem(source)
    if type(source) ~= "table" or source.kind ~= "quest" or source.x then return nil end
    local starts = ns.Sources.STARTS
    local row = type(starts) == "table" and source.questID and starts[source.questID]
    return type(row) == "table" and row[1] or nil
end

--- The items a source's words name, as { { id, name } }, so text kept plain
--- can show them in their rarity colour when drawn.
function Finder.NamedItems(source)
    if type(source) ~= "table" then return nil end
    if source.kind == "quest" and not source.x and type(source.name) == "string" then
        return { { Finder.StartsItem(source), source.name } }
    end
    local learn = source.kind == "craft" and (source.state == "learn" or source.state == "skill")
        and source.learn
    if type(learn) == "table" and type(learn.recipe) == "string"
        and (learn.how == "recipe" or learn.how == "drop") then
        return { { learn.recipeID, learn.recipe } }
    end
    return nil
end

--- One source in words, without its kind: what the window shows after the
--- coloured "Vendor", "Quest" or "Dungeon" tag. `plain` leaves item names
--- uncoloured, for text that is saved.
function Finder:Describe(source, plain)
    if source.kind == "vendor" then
        local text = source.name
        local where = Place(source)
        if where then text = text .. ", " .. where end
        local price = self.Money(source.price)
        if price then text = text .. "  " .. price end
        local short = self.Money(self.Short(source.price))
        if short then
            text = L.Format("%s  |c%sneed|r %s |c%smore|r", text, ns.COLORS.downgrade, short, ns.COLORS.downgrade)
        end
        if source.limited then text = L.Format("%s  (limited stock)", text) end
        return text
    elseif source.kind == "quest" then
        local text = L.Format("%s (level %d)", source.title, source.questLevel or 0)
        local need = Finder.Need(source.group)
        if need then text = text .. ", " .. (NEED_WORDS[need] or need) end
        if (source.chain or 0) > 1 then
            text = L.Format("%s, after %d earlier quests", text, source.chain)
        elseif (source.chain or 0) == 1 and source.first then
            text = L.Format("%s, after %s", text, source.first)
        end
        local where = Place(source)
        if source.x then
            if where then
                text = L.Format("%s, from %s in %s", text, source.name, where)
            else
                text = L.Format("%s, from %s", text, source.name)
            end
        else
            -- The item that starts it, in its rarity colour (plain for text
            -- that is saved).
            local shown = plain and source.name or Items.ColorName(Finder.StartsItem(source), source.name)
            text = L.Format("%s, starts from %s", text, shown)
        end
        return text
    elseif source.kind == "dungeon" then
        local text = L.Format("%s in %s", source.name, source.dungeon)
        if not source.raid then
            text = text .. (" (%d-%d)"):format(source.minLevel, source.maxLevel)
        end
        if source.chance then text = L.Format("%s, %s%% drop", text, tostring(source.chance)) end
        return text
    elseif source.kind == "craft" and ns.Crafting then
        return ns.Crafting:Describe(source, self.Money, plain)
    end
    return ""
end

Finder.LABELS = { vendor = L["Vendor"], quest = L["Quest"], dungeon = L["Dungeon"], craft = L["Crafted"] }

--- The tag a source shows: "Vendor", "Quest", "Dungeon", "Raid" or
--- "Crafted".
function Finder.Label(source)
    if source.kind == "dungeon" and source.raid then return L["Raid"] end
    return Finder.LABELS[source.kind] or ""
end

--- What a reputation still asks for, in words: "Needs Honored with
--- Warsong Outriders (you are Friendly)".
function Finder.NeedsText(needs)
    if needs.have then
        return L.Format("Needs %s with %s (you are %s)", needs.standing, needs.faction, needs.have)
    end
    return L.Format("Needs %s with %s", needs.standing, needs.faction)
end

--------------------------------------------------------------------------------
-- /beq find
--------------------------------------------------------------------------------

--- A pick's random roll in words: "best roll of the Monkey, 4.5% of drops;
--- 38% of drops are an upgrade", or nil for gear without rolls.
function Finder.RollText(pick)
    local roll = pick and pick.roll
    if not (roll and ns.Rolls) then return nil end
    local name = ns.Rolls:Describe(roll.link)
    local text = name and L.Format("Best roll %s: %s of drops", name, ns.Rolls.Percent(roll.chance))
        or L.Format("Best roll: %s of drops", ns.Rolls.Percent(roll.chance))
    if roll.upgradeChance and roll.upgradeChance > roll.chance then
        text = L.Format("%s, and %s of drops are an upgrade", text, ns.Rolls.Percent(roll.upgradeChance))
    end
    return text
end

ns.RegisterCommand("find", L["where to get upgrades: vendors, quests, dungeons and crafting"], function()
    if ns.FinderUI then ns.FinderUI:Toggle() end
end)
