-- Queue it: a crafted upgrade sent to Tradeskills' queue (a player asked,
-- 2026-10-10). Gear you can make is queued as a craft; gear still to learn
-- has its materials put on the shopping list; gear nobody makes goes on the
-- list itself. Without Tradeskills there is no button.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("tsqueue")

local function Gear(loc, n)
    return { loc = loc, class = 4, subclass = 2, stats = { ITEM_MOD_AGILITY_SHORT = n } }
end

local ns = env.Load()
_G.UnitClass = function() return "Hunter", "HUNTER", 3 end
_G.UnitFactionGroup = function() return "Alliance", "Alliance" end
_G.UnitRace = function() return "Human", "Human", 1 end
env.InstallItems({
    ["item:900"] = Gear("INVTYPE_CHEST", 10),
    ["item:3001"] = Gear("INVTYPE_CHEST", 30),
    ["item:3002"] = Gear("INVTYPE_FEET", 20),
    ["item:3003"] = Gear("INVTYPE_HEAD", 15),
}, { [5] = "item:900" }, {}, 20)

ns.Sources.ITEMS = {}
ns.Sources.FOREVER = {}
ns.RollData.ITEMS = {}

local C = ns.Crafts
C.PROFESSIONS = { [165] = "Leatherworking", [197] = "Tailoring" }
C.ZONES = { [12] = "Elwynn Forest" }
C.NPCS = { [50] = { "Adele Fielder", 12, 46.2, 62.1, "A" } }
C.TRAINERS = { [1] = { 50 } }
C.MATERIALS = { [2318] = { "Light Leather", 0 }, [2320] = { "Coarse Thread", 10 } }
C.RECIPES = { [2407] = { "Pattern: Linen Hat", 60, 0, d = 500 } }
C.ITEMS = {
    [3001] = { 165, 50, 9001, 15, 18, 0, 0, 0, m = { 2318, 8, 2320, 4 }, t = { 100, 1 } },
    [3002] = { 165, 90, 9002, 15, 20, 0, 0, 0, m = { 2318, 6 }, t = { 100, 1 } },
    [3003] = { 197, 75, 9003, 10, 15, 0, 0, 0, m = { 2320, 2 }, r = { 2407 } },
}
_G.C_TradeSkillUI = {
    GetAllProfessionTradeSkillLines = function() return { 165 } end,
    GetProfessionInfoBySkillLineID = function()
        return { professionName = "Leatherworking", skillLevel = 100, maxSkillLevel = 150 }
    end,
}
_G.IsPlayerSpell = function(id) return id == 9001 end

local TSQ, Finder = ns.TradeskillsQueue, ns.Finder
local function Source(itemID)
    return TSQ.CraftSource(Finder:SourcesFor(itemID, Finder:Player()))
end

suite.check("without Tradeskills there is no button", not TSQ:Available())

local known, learn, other = Source(3001), Source(3002), Source(3003)
suite.check("a recipe you know is queued as a craft", TSQ.Plan(known) == "craft", known and known.state)
suite.check("one an alt knows too", TSQ.Plan({ state = "alt" }) == "craft")
suite.check("one still to learn queues its materials", TSQ.Plan(learn) == "materials", learn and learn.state)
suite.check("one needing more skill too", TSQ.Plan({ state = "skill" }) == "materials")
suite.check("gear nobody makes is bought", TSQ.Plan(other) == "buy", other and other.state)

-- Tradeskills' queue, as its calls answer.
local crafts, buys, opened = {}, {}, 0
local recipeKnown = true
local queue = {
    Ensure = function(_, recipeID, quantity)
        if not recipeKnown then return nil, "not seen yet" end
        crafts[recipeID] = quantity
        return true
    end,
    EnsureBuy = function(_, itemID, count, forItem)
        buys[#buys + 1] = { itemID = itemID, count = count, forItem = forItem }
        return true
    end,
    ForUpgrade = function(_, itemID)
        for _, line in ipairs(buys) do if line.forItem == itemID then return "buy" end end
        if itemID == 3001 and crafts[9001] then return "craft" end
        return nil
    end,
    ShowQueue = function() opened = opened + 1; return true end,
}
_G.BlackthornesTS = { Queue = queue }

suite.check("with Tradeskills it shows", TSQ:Available())
suite.check("and reads Queue it", TSQ:Label(3001) == "Queue It")

suite.check("a known craft is queued", TSQ:Queue(known) == true and crafts[9001] == 1)
suite.check("then reads Queued", TSQ:Label(3001) == "Queued")
suite.check("and nothing went on the list to buy", #buys == 0)
TSQ:Queue(known)
suite.check("a click on Queued opens the Queue tab", opened == 1)

TSQ:Queue(learn)
suite.check("a recipe to learn puts its materials on the list",
    #buys == 1 and buys[1].itemID == 2318 and buys[1].count == 6 and buys[1].forItem == 3002)

buys = {}
TSQ:Queue(other)
suite.check("gear nobody makes goes on the list itself",
    #buys == 1 and buys[1].itemID == 3003 and buys[1].count == 1 and buys[1].forItem == 3003)

buys, crafts, recipeKnown = {}, {}, false
TSQ:Queue(known)
suite.check("a craft Tradeskills has not read yet still gets its materials listed",
    #buys == 2 and buys[2].itemID == 2320 and buys[2].count == 4)
suite.check("and says why", env.ChatText():find("not seen yet", 1, true) ~= nil)

-- The learn source as the upgrade quest kept it, before the recipe was learned.
buys = {}
recipeKnown = true
_G.IsPlayerSpell = function(id) return id == 9001 or id == 9002 end
ns.Crafting:Forget()
TSQ:Queue(learn)
suite.check("a kept source is read again: learned since, so it is queued", crafts[9002] == 1 and #buys == 0)

-- The finder's crafted rows wear the button; the rest do not.
buys, crafts = {}, {}
ns.FinderUI:Show()
ns.FinderUI:SetFilter("craft")
local shown, label = 0, nil
for _, row in ipairs(ns.FinderUI.rows) do
    if rawget(row, "pick") and row.queueIt:IsShown() then
        shown = shown + 1
        label = label or row.queueIt.label:GetText()
    end
end
suite.check("crafted rows in the finder show Queue it", shown > 0 and label == "Queue It", tostring(shown) .. " " .. tostring(label))
ns.FinderUI:Hide()

queue.Ensure = function() error("boom") end
queue.ForUpgrade = function() return nil end
suite.check("an error in Tradeskills never reaches the player", pcall(TSQ.Queue, TSQ, Source(3002)))

_G.BlackthornesTS = { Queue = { Ensure = queue.Ensure } }
suite.check("an older Tradeskills without the calls shows no button", not TSQ:Available())
_G.BlackthornesTS = nil

suite.done()
