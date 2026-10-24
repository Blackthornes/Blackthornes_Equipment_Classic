-- The player's other characters: each keeps a note of its class, level,
-- spec and worn gear, and bag gear that is no upgrade here is judged for
-- them (Alts:BestFor), so Butler can offer it as a mail (Butler:Advise's
-- `alt`).

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("alts")

local ARMOR = 4
local CLOTH, LEATHER, MAIL = 1, 2, 3

local function Agi(n) return { ITEM_MOD_AGILITY_SHORT = n } end

local ITEMS = {
    -- The hunter's worn chest.
    ["item:1"] = { loc = "INVTYPE_CHEST", class = ARMOR, subclass = LEATHER, stats = Agi(10) },
    -- The rogue's worn chest.
    ["item:11"] = { loc = "INVTYPE_CHEST", class = ARMOR, subclass = LEATHER, stats = Agi(2) },
    -- Worse than the hunter's, twice the rogue's.
    ["item:4"] = { loc = "INVTYPE_CHEST", class = ARMOR, subclass = LEATHER, stats = Agi(4) },
    -- Mail: no rogue wears it.
    ["item:5"] = { loc = "INVTYPE_CHEST", class = ARMOR, subclass = MAIL, stats = Agi(6) },
    -- Better for the hunter too.
    ["item:6"] = { loc = "INVTYPE_CHEST", class = ARMOR, subclass = LEATHER, stats = Agi(20) },
    -- For the rogue from level 30.
    ["item:7"] = { loc = "INVTYPE_CHEST", class = ARMOR, subclass = LEATHER, stats = Agi(8), minLevel = 30 },
    -- Cloth: better stats than the rogue's leather, but lighter than it wears.
    ["item:8"] = { loc = "INVTYPE_CHEST", class = ARMOR, subclass = CLOTH, stats = Agi(30) },
    -- A cloak is cloth for everyone.
    ["item:9"] = { loc = "INVTYPE_CLOAK", class = ARMOR, subclass = CLOTH, stats = Agi(30) },
}

local ns = env.Load()
_G.UnitClass = function() return "HUNTER", "HUNTER" end
_G.UnitGUID = function() return "Player-1" end
_G.GetRealmName = function() return "Here" end
_G.UnitFactionGroup = function() return "Horde", "Horde" end
env.InstallItems(ITEMS, { [5] = "item:1" }, { [0] = {
    [4] = "item:4", [5] = "item:5", [6] = "item:6", [7] = "item:7",
} })
_G.C_Container.GetContainerItemInfo = function(bag, slot)
    if bag ~= 0 then return nil end
    return { quality = 1, isBound = false, stackCount = 1 }
end
_G.C_TooltipInfo = { GetHyperlink = function() return { lines = { { type = 11, price = 50 } } } end }
ns.Alts:OnEnable()
local function Fire(event, ...) ns.eventFrame:GetScript("OnEvent")(ns.eventFrame, event, ...) end

local Alts = ns.Alts

-- The character playing keeps its note.
suite.check("the character playing writes its note", Alts:Record() == true)
local mine = ns.db.characterGear["Player-1"]
suite.check("with class, level, realm and side", mine and mine.class == "HUNTER" and mine.level == 20
    and mine.realm == "Here" and mine.faction == "Horde")
suite.check("and what it wears", mine.worn[5] == "item:1" and mine.worn[1] == nil)
suite.check("and the spec it is judged as", mine.spec ~= nil)

-- A burst of events writes it once.
local writes = 0
local record = Alts.Record
Alts.Record = function(self) writes = writes + 1; return record(self) end
local timer = C_Timer.After
local waiting = {}
C_Timer.After = function(_, fn) waiting[#waiting + 1] = fn end
Fire("PLAYER_EQUIPMENT_CHANGED")
Fire("PLAYER_EQUIPMENT_CHANGED")
Fire("PLAYER_LEVEL_UP")
for _, fn in ipairs(waiting) do fn() end
suite.check("a burst of gear events writes the note once", writes == 1, writes)
C_Timer.After = timer
Alts.Record = record

-- A rogue alt on the same realm and side, and two that are not.
ns.db.characterGear["Player-2"] = { class = "ROGUE", level = 20, realm = "Here", faction = "Horde",
    worn = { [5] = "item:11" } }
ns.db.characterGear["Player-3"] = { class = "ROGUE", level = 20, realm = "Here", faction = "Alliance",
    worn = {} }
ns.db.characterGear["Player-4"] = { class = "ROGUE", level = 20, realm = "Elsewhere", faction = "Horde",
    worn = {} }

local Butler = _G.BlackthornesEquipment.Butler
local advice = Butler:Advise("item:4", 0, 4)
suite.check("no upgrade here", advice and advice.upgrade == nil)
suite.check("but an upgrade for the rogue", advice.alt and advice.alt.key == "Player-2",
    advice.alt and advice.alt.key)
suite.check("by 100 percent", advice.alt.gain == 100, advice.alt.gain)
suite.check("to wear now", advice.alt.level == nil)

advice = Butler:Advise("item:5", 0, 5)
suite.check("mail is offered to nobody who cannot wear it", advice and advice.alt == nil)

advice = Butler:Advise("item:6", 0, 6)
suite.check("an upgrade for the character playing names no alt", advice.upgrade == "now" and advice.alt == nil)

advice = Butler:Advise("item:7", 0, 7)
suite.check("one that waits on the alt's level says the level", advice.alt and advice.alt.level == 30)

-- Armor goes only to a character whose heaviest kind it is.
suite.check("cloth is never offered to a leather wearer", Alts:BestFor("item:8") == nil)
local cloak = Alts:BestFor("item:9")
suite.check("a cloak still is", cloak and cloak.key == "Player-2")
ns.db.characterGear["Player-8"] = { class = "WARRIOR", level = 20, realm = "Here", faction = "Horde",
    worn = { [5] = "item:11" } }
suite.check("leather is never offered to a mail wearer",
    Alts:Judge(ns.db.characterGear["Player-8"], "item:6") == nil)
suite.check("mail is", Alts:Judge(ns.db.characterGear["Player-8"], "item:5") ~= nil)
ns.db.characterGear["Player-8"] = nil
-- For Butler (soonOnly), mail for a hunter far from 40 waits; from 38 it is
-- offered, and a warrior wearing mail now is never held back.
ns.db.characterGear["Player-8"] = { class = "HUNTER", level = 10, realm = "Here", faction = "Horde",
    worn = { [5] = "item:11" } }
local hunter = ns.db.characterGear["Player-8"]
suite.check("mail waits for a level 10 hunter", Alts:Judge(hunter, "item:5", true) == nil)
suite.check("but the tooltip still says it", Alts:Judge(hunter, "item:5") ~= nil)
hunter.level = 38
local soon = Alts:Judge(hunter, "item:5", true)
suite.check("from 38 it is held", soon ~= nil and soon.level == 40, soon and soon.level)
ns.db.characterGear["Player-8"] = { class = "WARRIOR", level = 10, realm = "Here", faction = "Horde",
    worn = { [5] = "item:11" } }
suite.check("a warrior wears mail now", Alts:Judge(ns.db.characterGear["Player-8"], "item:5", true) ~= nil)
ns.db.characterGear["Player-8"] = nil
local W = ns.Weights
suite.check("plate is too far for a warrior of 37", W:KindTooFar("WARRIOR", 37, ARMOR, 4, "INVTYPE_CHEST"))
suite.check("not at 38", not W:KindTooFar("WARRIOR", 38, ARMOR, 4, "INVTYPE_CHEST"))
suite.check("leather is never too far", not W:KindTooFar("HUNTER", 1, ARMOR, LEATHER, "INVTYPE_CHEST"))
suite.check("nor a ring", not W:KindTooFar("HUNTER", 1, ARMOR, 0, "INVTYPE_FINGER"))
suite.check("an unknown level holds", not W:KindTooFar("HUNTER", nil, ARMOR, MAIL, "INVTYPE_CHEST"))
suite.check("a warrior below 40 wears mail at most, so plate waits",
    W:IsBestArmor("WARRIOR", 20, ARMOR, MAIL, "INVTYPE_CHEST") and W:IsBestArmor("WARRIOR", 20, ARMOR, 4, "INVTYPE_CHEST"))
suite.check("from 40 mail is no longer its heaviest", not W:IsBestArmor("WARRIOR", 40, ARMOR, MAIL, "INVTYPE_CHEST"))
suite.check("rings and shields are not armor kinds",
    W:IsBestArmor("ROGUE", 20, ARMOR, 0, "INVTYPE_FINGER") and W:IsBestArmor("WARRIOR", 20, ARMOR, 6, "INVTYPE_SHIELD"))

-- The other side and another realm are never picked, even for an empty slot.
ns.db.characterGear["Player-2"] = nil
suite.check("other realms and sides are left out", Alts:BestFor("item:4") == nil)

-- Its own note never counts.
ns.db.characterGear["Player-5"] = { class = "HUNTER", level = 20, realm = "Here", faction = "Horde",
    worn = { [5] = "item:1" } }
suite.check("a hunter wearing the same is no upgrade", Alts:BestFor("item:4") == nil)
ns.db.characterGear["Player-5"].worn = { [1] = "item:11" }
local best = Alts:BestFor("item:4")
suite.check("an empty slot is, with no percent", best and best.key == "Player-5" and best.gain == nil)
ns.db.characterGear["Player-5"].worn = {}
suite.check("a note with no gear on record is never judged", Alts:BestFor("item:4") == nil)
ns.db.characterGear["Player-5"].worn = { [1] = "item:11" }
ns.db.characterGear["Player-1"].worn = {}
suite.check("the character playing's own note is never judged", Alts:BestFor("item:4").key == "Player-5")

-- A GUID the client keeps back (a dungeon): the character's own note can't
-- be told from an alt's, so nothing is an upgrade for an alt.
ns.db.characterGear["Player-1"].worn = { [1] = "item:11" }
ns.db.characterGear["Player-5"].worn = { [5] = "item:1" }
local realGUID = _G.UnitGUID
_G.UnitGUID = function() return nil end
suite.check("without the GUID, nothing is offered for an alt", Alts:BestFor("item:4") == nil)
suite.check("nor found elsewhere", next(Alts:BetterElsewhere()) == nil)
_G.UnitGUID = realGUID
ns.db.characterGear["Player-1"].worn = {}
ns.db.characterGear["Player-5"].worn = { [1] = "item:11" }

-- A note the code cannot read is skipped, not an error.
ns.db.characterGear["Player-6"] = { class = "NOBODY" }
ns.db.characterGear["Player-7"] = "garbage"
local ok = pcall(Alts.BestFor, Alts, "item:4")
suite.check("a broken note is skipped", ok)

-- What it carries: unbound bag gear is kept as `spare`, with its name.
_G.UnitName = function() return "Ana" end
Alts:Record()
mine = ns.db.characterGear["Player-1"]
suite.check("the note keeps the name", mine.name == "Ana", mine.name)
suite.check("and the unbound gear in the bags", mine.spare and #mine.spare == 4, mine.spare and #mine.spare)
_G.C_Container.GetContainerItemInfo = function(bag, slot)
    if bag ~= 0 then return nil end
    return { quality = 2, isBound = slot == 4, stackCount = 1 }
end
Alts:Record()
mine = ns.db.characterGear["Player-1"]
local hasBound = false
for _, link in ipairs(mine.spare) do if link == "item:4" then hasBound = true end end
suite.check("soulbound bag gear is not spare", not hasBound and #mine.spare == 3, #mine.spare)

-- The bank, read while it is open, is kept on the next note.
mine.bank, mine.bankAt = { { link = "item:6", bound = true } }, 100
Alts:Record()
mine = ns.db.characterGear["Player-1"]
suite.check("a new note keeps the bank it read before", mine.bank and mine.bank[1].link == "item:6" and mine.bankAt == 100)
suite.check("the bank's containers start with the bank", Alts.BankBags()[1] == -1 and #Alts.BankBags() == 8)

-- A read that finds nothing worn (a /reload or logout, when the client
-- answers nil for every slot) keeps the gear and bags the last note read.
local wornBefore = env.worn
env.worn = {}
local bags = env.bags
env.bags = {}
Alts:Record()
mine = ns.db.characterGear["Player-1"]
suite.check("an empty read keeps the worn gear", mine.worn[5] == "item:1", mine.worn[5])
suite.check("and the spare gear", #mine.spare == 3, #mine.spare)
env.worn, env.bags = wornBefore, bags
Alts:Record()
mine = ns.db.characterGear["Player-1"]

-- Names: Tradeskills' whole name first, else the note's.
suite.check("a note's name", Alts:NameOf("Player-1") == "Ana")
_G.BlackthornesTS = { db = { characters = { ["Player-1"] = {} } },
    Recipes = { GetCharacterName = function(_, key) return key == "Player-1" and "Ana Smith" or nil end } }
suite.check("Tradeskills' whole name wins", Alts:NameOf("Player-1") == "Ana Smith")
_G.BlackthornesTS.Recipes.GetCharacterName = function() error("broken") end
suite.check("a Tradeskills error falls back to the note", Alts:NameOf("Player-1") == "Ana")
_G.BlackthornesTS = nil

-- Better gear owned elsewhere: in the bank, or spare on another character.
for key in pairs(ns.db.characterGear) do if key ~= "Player-1" then ns.db.characterGear[key] = nil end end
local found = Alts:BetterElsewhere()
suite.check("an upgrade in the bank is found", found[5] and found[5].link == "item:6" and found[5].where == "bank",
    found[5] and found[5].where)
suite.check("with its gain", found[5].gain > 0)
mine.bank = { { link = "item:4", bound = false } }
suite.check("nothing better in the bank, nothing found", Alts:BetterElsewhere()[5] == nil)
ns.db.characterGear["Player-8"] = { class = "ROGUE", level = 20, realm = "Here", faction = "Horde",
    worn = {}, spare = { "item:6" }, bank = { { link = "item:5", bound = true } } }
found = Alts:BetterElsewhere()
suite.check("an upgrade spare on another character is found", found[5] and found[5].where == "Player-8")
ns.db.characterGear["Player-8"].spare = {}
ns.db.characterGear["Player-8"].bank = { { link = "item:6", bound = true } }
suite.check("bound gear in another bank is not", Alts:BetterElsewhere()[5] == nil)
ns.db.characterGear["Player-8"].bank = { { link = "item:6", bound = false } }
suite.check("unbound gear in another bank is", (Alts:BetterElsewhere()[5] or {}).where == "Player-8")
ns.db.characterGear["Player-8"].faction = "Alliance"
suite.check("the other side's gear is left out", Alts:BetterElsewhere()[5] == nil)
ns.db.characterGear["Player-8"] = nil

-- The tooltip's line: no upgrade here, an upgrade for an alt.
ns.db.characterGear["Player-2"] = { class = "ROGUE", level = 20, realm = "Here", faction = "Horde",
    worn = { [5] = "item:11" }, name = "Bob" }
local Tooltip = ns.Tooltip
local result = ns.Compare:JudgeCarried("item:4")
suite.check("the tooltip names the alt it helps", Tooltip:AltLine("item:4", result) == "Upgrade for Bob: +100%",
    Tooltip:AltLine("item:4", result))
suite.check("an upgrade here says nothing about alts",
    Tooltip:AltLine("item:6", ns.Compare:JudgeCarried("item:6")) == nil)
suite.check("a level wait is named", (Tooltip:AltLine("item:7", ns.Compare:JudgeCarried("item:7")) or ""):find("at level 30", 1, true))
ns.db.altTooltipLine = false
suite.check("the setting turns it off", Tooltip:AltLine("item:4", result) == nil)
ns.db.altTooltipLine = nil

suite.done()
