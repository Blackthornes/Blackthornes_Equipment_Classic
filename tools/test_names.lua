-- The game's own names on a client in another language (a player asked,
-- 2026-10-28: the upgrade quest's steps named quests, people, zones and
-- items in English on a German client). Only the words change: the data,
-- the places and every check keep the English names. On an English client
-- nothing changes.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("names")

local function Agi(n) return { ITEM_MOD_AGILITY_SHORT = n } end
local function Gear(loc, n) return { loc = loc, class = 4, subclass = 2, stats = Agi(n) } end

local ns = env.Load()
local Names = ns.Names

_G.UnitClass = function() return "Hunter", "HUNTER", 3 end
_G.UnitFactionGroup = function() return "Alliance", "Alliance" end
_G.UnitRace = function() return "Human", "Human", 1 end
env.InstallItems({
    ["item:900"] = Gear("INVTYPE_CHEST", 10),
    ["item:1002"] = Gear("INVTYPE_CHEST", 30),
}, { [5] = "item:900" }, { [0] = {} }, 10)

local GERMAN_MAPS = { [1429] = "Wald von Elwynn", [1415] = "Östliche Königreiche" }
local here = 1429
_G.C_Map = {
    GetBestMapForUnit = function() return here end,
    GetMapInfo = function(id) return GERMAN_MAPS[id] and { name = GERMAN_MAPS[id], parentMapID = 1415 } end,
}
_G.GetRealZoneText = function(id)
    if id == 36 then return "Die Todesminen" end
    return "Wald von Elwynn"
end

-- Creatures by their ID through the tooltip data, quests by theirs.
local creatureAsks = 0
local CREATURES = { [240] = "Marshal Dughan (de)", [7] = "Kobold-Grubenarbeiter" }
_G.C_TooltipInfo = {
    GetHyperlink = function(link)
        creatureAsks = creatureAsks + 1
        local id = tonumber(link:match("Creature%-0%-0%-0%-0%-(%d+)%-"))
        local name = id and CREATURES[id]
        return name and { lines = { { leftText = name } } } or { lines = {} }
    end,
}
local TITLES = { [62] = "Die Goldmine von Fargodeep" }
local inLog, done = {}, {}
_G.C_QuestLog = {
    GetTitleForQuestID = function(id) return TITLES[id] end,
    RequestLoadQuestByID = function() end,
    IsQuestFlaggedCompleted = function(id) return done[id] == true end,
    IsOnQuest = function(id) return inLog[id] == true end,
    ReadyForTurnIn = function() return false end,
}
local ITEM_NAMES = { [1307] = "Goldrohrstein" }
_G.C_Item = _G.C_Item or {}
local realItemName = _G.C_Item.GetItemNameByID
_G.C_Item.GetItemNameByID = function(id) return ITEM_NAMES[id] or (realItemName and realItemName(id)) end

ns.NAME_IDS = {
    npc = { ["Marshal Dughan"] = 240, ["Kobold Miner"] = 7, ["Nobody Known"] = 999 },
    item = { ["Gold Pickup Schedule"] = 1307 },
}

--------------------------------------------------------------------------------
-- English: every name as the data has it
--------------------------------------------------------------------------------

_G.GetLocale = function() return "enUS" end
Names:Forget()
suite.check("English: a zone as it is", Names:Zone("Elwynn Forest") == "Elwynn Forest")
suite.check("English: a person as they are", Names:NPC("Marshal Dughan") == "Marshal Dughan")
suite.check("English: a quest as it is", Names:Quest(62, "The Fargodeep Mine") == "The Fargodeep Mine")
suite.check("English: an item as it is", Names:Item("Gold Pickup Schedule") == "Gold Pickup Schedule")
suite.check("English: the client is never asked", creatureAsks == 0, creatureAsks)

--------------------------------------------------------------------------------
-- German: the game's own names
--------------------------------------------------------------------------------

_G.GetLocale = function() return "deDE" end
Names:Forget()
suite.check("a zone by its map", Names:Zone("Elwynn Forest") == "Wald von Elwynn", Names:Zone("Elwynn Forest"))
suite.check("a dungeon by its instance", Names:Zone("The Deadmines") == "Die Todesminen", Names:Zone("The Deadmines"))
suite.check("a zone the game does not name stays English", Names:Zone("Nowhere") == "Nowhere")
suite.check("a person by their ID", Names:NPC("Marshal Dughan") == "Marshal Dughan (de)", Names:NPC("Marshal Dughan"))
suite.check("a quest by its ID", Names:Quest(62, "The Fargodeep Mine") == "Die Goldmine von Fargodeep")
suite.check("an item by its ID", Names:Item("Gold Pickup Schedule") == "Goldrohrstein")
suite.check("a name with no ID stays English", Names:NPC("Somebody Else") == "Somebody Else")

-- Kept: a second look asks the client nothing.
local asks = creatureAsks
Names:NPC("Marshal Dughan")
suite.check("a name found is kept", creatureAsks == asks)

-- A miss is asked again only after a while, and comes in later.
local now = 100
_G.GetTime = function() return now end
asks = creatureAsks
suite.check("one the game lacks stays English", Names:NPC("Nobody Known") == "Nobody Known")
suite.check("and it was asked", creatureAsks > asks)
asks = creatureAsks
Names:NPC("Nobody Known")
suite.check("not asked again at once", creatureAsks == asks, creatureAsks - asks)
CREATURES[999] = "Niemand"
now = now + Names.RETRY
suite.check("after a while it is asked again and found", Names:NPC("Nobody Known") == "Niemand")

--------------------------------------------------------------------------------
-- The upgrade quest's steps
--------------------------------------------------------------------------------

local S = ns.Sources
ns.Crafts.ITEMS = {}
ns.RollData.ITEMS = {}
S.ZONES = { [12] = "Elwynn Forest" }
S.NPCS = {}
S.QUESTS = {
    [62] = { "The Fargodeep Mine", 7, 10, 77, 0, "Marshal Dughan", 12, 42.1, 65.9, "" },
}
S.DUNGEONS = {}
S.BOSSES = {}
S.FOREVER = {}
S.STARTS = {}
S.ITEMS = { [1002] = { 5, 10, 0, 0, 0, q = { 62 } } }
S.ENDS = {
    [62] = { "npc", "Marshal Dughan", "Elwynn Forest", 42.1, 65.9,
        o = { "mob", "Kobold Miner", "Elwynn Forest", 39.0, 81.0, "Gold Pickup Schedule" } },
}

local Quest = ns.UpgradeQuest
local function Now()
    local steps, current = Quest:Steps()
    return steps[current]
end

ns.HandleSlash("quest quest")
local quest = Quest:Current()
suite.check("the reward is picked", quest and quest.itemID == 1002)

local step = Now()
suite.check("pick up: the quest and the giver in German",
    step and step.text == "Pick up Die Goldmine von Fargodeep from Marshal Dughan (de) (42.1, 65.9)",
    step and step.text)
suite.check("the place keeps the data's names",
    step.place and step.place.zone == "Elwynn Forest" and step.place.name == "Marshal Dughan",
    step.place and step.place.name)

inLog[62] = true
step = Now()
suite.check("in the log: the mob and the item in German too",
    step and step.text:find("Kobold-Grubenarbeiter", 1, true) ~= nil
        and step.text:find("Goldrohrstein", 1, true) ~= nil
        and step.text:find("Die Goldmine von Fargodeep", 1, true) ~= nil
        and not step.text:find("Kobold Miner", 1, true),
    step and step.text)
suite.check("the objective's place keeps the data's names",
    step.place and step.place.name == "Kobold Miner", step.place and step.place.name)

-- The arrow's words, too, while its place keeps the data's.
local words = ns.QuestArrow.Place({ name = "Marshal Dughan", zone = "Elwynn Forest" }, { zone = "Westfall" })
suite.check("the arrow names the person and zone in German",
    words == "Marshal Dughan (de), Wald von Elwynn", words)

suite.done()
