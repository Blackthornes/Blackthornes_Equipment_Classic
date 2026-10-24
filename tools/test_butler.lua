-- What Equipment tells Blackthornes Butler about one carried item
-- (Butler:Advise): an upgrade now or later and by how much, the sell coin,
-- a tool kept to use, nothing for what is not gear, and never an error.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("butler")

local ARMOR, WEAPON = 4, 2
local LEATHER, MAIL = 2, 3
local AXE, DAGGER, FISHING_POLE = 0, 15, 20

local function Agi(n) return { ITEM_MOD_AGILITY_SHORT = n } end

local ITEMS = {
    -- Worn.
    ["item:1"] = { loc = "INVTYPE_CHEST", class = ARMOR, subclass = LEATHER, stats = Agi(10) },
    -- Half as good again: an upgrade to wear now.
    ["item:2"] = { loc = "INVTYPE_CHEST", class = ARMOR, subclass = LEATHER, stats = Agi(15) },
    -- Mail, which a hunter of 20 waits until 40 to wear.
    ["item:3"] = { loc = "INVTYPE_CHEST", class = ARMOR, subclass = MAIL, stats = Agi(30) },
    -- Worse than the worn chest: white, and soulbound green.
    ["item:4"] = { loc = "INVTYPE_CHEST", class = ARMOR, subclass = LEATHER, stats = Agi(4) },
    ["item:5"] = { loc = "INVTYPE_CHEST", class = ARMOR, subclass = LEATHER, stats = Agi(5) },
    -- Boots for an empty slot: an upgrade with no percent to give.
    ["item:6"] = { loc = "INVTYPE_FEET", class = ARMOR, subclass = LEATHER, stats = Agi(2) },
    -- Not gear: a reagent.
    ["item:7"] = { loc = "", class = 7, subclass = 0, stats = {} },
    -- The mining pick, a fishing pole, a dagger that adds to Skinning, and
    -- a known tool that is never worn.
    ["item:2901"] = { loc = "INVTYPE_WEAPON", class = WEAPON, subclass = AXE, stats = {} },
    ["item:8"] = { loc = "INVTYPE_2HWEAPON", class = WEAPON, subclass = FISHING_POLE, stats = {} },
    ["item:9"] = { loc = "INVTYPE_WEAPON", class = WEAPON, subclass = DAGGER, stats = {} },
    ["item:6219"] = { loc = "", class = 7, subclass = 0, stats = {} },
}

-- Quality and soulbound for each bag slot.
local SLOTS = {
    [4] = { quality = 1 },                  -- white
    [5] = { quality = 2, bound = true },    -- soulbound green
}

local ns = env.Load()
_G.UnitClass = function() return "HUNTER", "HUNTER" end
env.InstallItems(ITEMS, { [5] = "item:1" }, { [0] = {
    [2] = "item:2", [3] = "item:3", [4] = "item:4", [5] = "item:5", [6] = "item:6",
} })
_G.C_Container.GetContainerItemInfo = function(bag, slot)
    local s = SLOTS[slot]
    if bag ~= 0 or not s then return nil end
    return { quality = s.quality, isBound = s.bound == true, stackCount = 1 }
end
_G.C_TooltipInfo = { GetHyperlink = function(link)
    local lines = { { type = 11, price = 50 } }
    if link == "item:9" then lines[2] = { type = 0, leftText = "Equip: Skinning +10." } end
    return { lines = lines }
end }

local Butler = _G.BlackthornesEquipment.Butler
suite.check("Butler answers on the global", type(Butler) == "table" and type(Butler.Advise) == "function")

-- Upgrades.
local advice = Butler:Advise("item:2", 0, 2)
suite.check("an upgrade to wear now", advice and advice.upgrade == "now", advice and advice.upgrade)
suite.check("worth 50 percent", advice.gain == 50, advice.gain)
suite.check("is never sold", advice.sell == false and advice.tool == false)
suite.check("the same as the bag arrow", ns.Compare:IsUpgradeNow("item:2", true))

-- Mail is kept for a hunter only from 38 (the owner, 2026-10-24); at 20 it
-- is no upgrade to hold, so Butler sorts it like anything else.
advice = Butler:Advise("item:3", 0, 3)
suite.check("mail is not held at 20", advice and advice.upgrade == nil, advice and advice.upgrade)
suite.check("and has no size", advice.gain == nil, advice.gain)
local realLevel = _G.UnitLevel
_G.UnitLevel = function() return 38 end
ns.Compare:ForgetScores()
advice = Butler:Advise("item:3", 0, 3)
suite.check("from 38 mail waits for level 40", advice and advice.upgrade == "later", advice and advice.upgrade)
suite.check("with its size", advice.gain == 200, advice.gain)
suite.check("and is not sold", advice.sell == false)
_G.UnitLevel = realLevel
ns.Compare:ForgetScores()

advice = Butler:Advise("item:6", 0, 6)
suite.check("an empty slot is an upgrade now", advice and advice.upgrade == "now")
suite.check("with no percent to give", advice.gain == nil, advice.gain)

-- The sell coin.
advice = Butler:Advise("item:4", 0, 4)
suite.check("white gear that is no upgrade sells", advice and advice.sell == true)
suite.check("and is no upgrade", advice.upgrade == nil and advice.gain == nil)
advice = Butler:Advise("item:5", 0, 5)
suite.check("a soulbound green sells without Enchanting", advice and advice.sell == true)
advice = Butler:Advise("item:5")
suite.check("without its slot, a green is not called sold", advice and advice.sell == false)
ns.db.bagSellCoins = false
advice = Butler:Advise("item:4", 0, 4)
suite.check("no coin when the coins are unticked", advice and advice.sell == false)
ns.db.bagSellCoins = nil

-- Tools.
advice = Butler:Advise("item:2901")
suite.check("the mining pick is a tool", advice and advice.tool == true and advice.sell == false)
advice = Butler:Advise("item:8")
suite.check("a fishing pole is a tool", advice and advice.tool == true)
advice = Butler:Advise("item:9")
suite.check("a dagger that adds to Skinning is a tool", advice and advice.tool == true)
advice = Butler:Advise(6219)
suite.check("a tool never worn is one too, by item ID", advice and advice.tool == true)

-- What is not gear, after the cheap check alone.
local judged = 0
local judge = ns.Compare.JudgeCarried
ns.Compare.JudgeCarried = function(...)
    judged = judged + 1
    return judge(...)
end
suite.check("a reagent says nothing", Butler:Advise("item:7") == nil)
suite.check("an item not loaded yet says nothing", Butler:Advise("item:999") == nil)
suite.check("nor anything that is not a link", Butler:Advise({}) == nil and Butler:Advise(nil) == nil)
suite.check("without judging the gear", judged == 0, judged)
ns.Compare.JudgeCarried = judge

-- Never raises.
ns.Compare.JudgeCarried = function() error("boom") end
local ok, answer = pcall(Butler.Advise, Butler, "item:2", 0, 2)
suite.check("an error inside says nothing, and does not raise", ok and answer == nil)
ns.Compare.JudgeCarried = judge

suite.done()
