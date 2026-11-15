-- Characters skipped for upgrades (a player asked, the owner agreed
-- 2026-10-14): a crafting alt is never told gear is an upgrade, other
-- characters never offer it gear, and gear the others want is not marked
-- to sell on it.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("skipupgrades")

local ARMOR, LEATHER = 4, 2
local function Agi(n) return { ITEM_MOD_AGILITY_SHORT = n } end

local ITEMS = {
    -- The hunter's worn chest, and the rogue's.
    ["item:1"] = { loc = "INVTYPE_CHEST", class = ARMOR, subclass = LEATHER, stats = Agi(10) },
    ["item:11"] = { loc = "INVTYPE_CHEST", class = ARMOR, subclass = LEATHER, stats = Agi(2) },
    -- Better for both.
    ["item:6"] = { loc = "INVTYPE_CHEST", class = ARMOR, subclass = LEATHER, stats = Agi(20) },
}

local ns = env.Load()
_G.UnitClass = function() return "HUNTER", "HUNTER" end
local guid = "Player-1"
_G.UnitGUID = function() return guid end
_G.GetRealmName = function() return "Here" end
_G.UnitFactionGroup = function() return "Horde", "Horde" end
_G.UnitName = function() return "Ana Smith" end
env.InstallItems(ITEMS, { [5] = "item:1" }, { [0] = { [6] = "item:6" } })
_G.C_Container.GetContainerItemInfo = function(bag, slot)
    if bag ~= 0 then return nil end
    return { quality = 1, isBound = false, stackCount = 1 }
end
_G.C_TooltipInfo = { GetHyperlink = function() return { lines = { { type = 11, price = 50 } } } end }

local Alts, Compare, Butler = ns.Alts, ns.Compare, _G.BlackthornesEquipment.Butler
Alts:Record()
ns.db.characterGear["Player-2"] = { class = "ROGUE", level = 20, realm = "Here", faction = "Horde",
    worn = { [5] = "item:11" }, name = "Bob Wither" }

suite.check("nobody is skipped at first", not Alts:PlayerSkipped() and not Alts:IsSkipped("Player-2"))
suite.check("an upgrade here at first", Compare:IsUpgrade("item:6") == true)

-- Skip the character playing.
local redraws = 0
_G.BlackthornesTS = { Upgrades = { RedrawSoon = function() redraws = redraws + 1 end } }
Alts:SetSkipped("Player-1", true)
suite.check("saved account wide by GUID", ns.db.skipUpgrades["Player-1"] == true)
suite.check("and for the character itself", ns.charDB.skipUpgrades == true)
suite.check("Tradeskills is told to ask again", redraws == 1, redraws)

local result = Compare:JudgeCarried("item:6")
suite.check("what was an upgrade is skipped", result.verdict == "skipped" and result.skipped == true, result.verdict)
suite.check("no bag arrow or Tradeskills arrow", Compare:IsUpgrade("item:6") == false)
suite.check("no tooltip line of its own", Compare:Describe(result) == nil)
local advice = Butler:Advise("item:6", 0, 6)
suite.check("Butler hears no upgrade", advice and advice.upgrade == nil)
suite.check("but the other character it helps", advice.alt and advice.alt.key == "Player-2")
suite.check("and no sell coin while another wants it", advice.sell == false)
suite.check("the gear in the bags shows no upgrade", next(Compare:BestInBags()) == nil)

-- A soulbound copy can't be mailed to the other character, so it sells.
local BagIcons = ns.BagIcons
suite.check("no coin on a copy the other character can have", BagIcons:Sells(0, 6, "item:6", result) == false)
_G.C_Container.GetContainerItemInfo = function(bag, slot)
    if bag ~= 0 then return nil end
    return { quality = 1, isBound = true, stackCount = 1 }
end
suite.check("a soulbound copy gets the sell coin", BagIcons:Sells(0, 6, "item:6", result) == true)
_G.C_Container.GetContainerItemInfo = function(bag, slot)
    if bag ~= 0 then return nil end
    return { quality = 1, isBound = false, stackCount = 1 }
end

-- Inside a dungeon the GUID can be kept back: the character's own copy answers.
guid = nil
suite.check("still skipped when the GUID can't be read", Alts:PlayerSkipped() == true)
guid = "Player-1"

-- Back on.
Alts:SetSkipped("Player-1", false)
suite.check("back on", not Alts:PlayerSkipped() and ns.charDB.skipUpgrades == nil)
suite.check("an upgrade again", Compare:IsUpgrade("item:6") == true)

-- Skip the other character: it is never offered gear.
suite.check("the rogue is offered the chest", Alts:BestFor("item:6") ~= nil)
Alts:SetSkipped("Player-2", true)
suite.check("a skipped character is offered nothing", Alts:BestFor("item:6") == nil)
local names = Alts:SkippedNames()
suite.check("named in full", #names == 1 and names[1] == "Bob Wither", names[1])
local list = Alts:Characters()
suite.check("the picker lists the one playing first", list[1].key == "Player-1" and list[2].key == "Player-2")
suite.check("its note is never touched", ns.db.characterGear["Player-2"].class == "ROGUE")

-- A login copies the account's answer to the character's own.
ns.charDB.skipUpgrades = true
Alts:Record()
suite.check("a login follows the account's answer", ns.charDB.skipUpgrades == nil)

-- /beq skip.
ns.HandleSlash("skip on")
suite.check("/beq skip on", Alts:IsSkipped("Player-1"))
ns.HandleSlash("skip")
suite.check("/beq skip turns it round", not Alts:IsSkipped("Player-1"))
ns.HandleSlash("skip list")
suite.check("/beq skip list changes nothing", Alts:IsSkipped("Player-2") and not Alts:IsSkipped("Player-1"))
guid = nil
ns.HandleSlash("skip on")
suite.check("nothing is saved without the GUID", not Alts:IsSkipped("Player-1"))
guid = "Player-1"

_G.BlackthornesTS = nil
suite.done()
