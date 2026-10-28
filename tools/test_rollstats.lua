-- Random rolls on Era: the game's stats for a rolled link leave out what the
-- roll adds, so the tooltip's own lines are counted too. A hunter's Lupine
-- Slippers of the Monkey were called worse than plain Spirit boots.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("rollstats")

local ARMOR, LEATHER = 4, 2
local function Boots(stats)
    return { loc = "INVTYPE_FEET", class = ARMOR, subclass = LEATHER, stats = stats }
end

local EMBOSSED = "item:2309"
local MONKEY = "|cff1eff00|Hitem:15017:0:0:0:0:0:617:0|h[Lupine Slippers of the Monkey]|h|r"
local PLAIN_MONKEY = "item:15017:0:0:0:0:0:617:0"

local ITEMS = {
    [EMBOSSED] = Boots({ RESISTANCE0_NAME = 48, ITEM_MOD_STAMINA_SHORT = 2, ITEM_MOD_SPIRIT_SHORT = 2 }),
    -- What Era hands back for the rolled link: the armor and nothing more.
    [PLAIN_MONKEY] = Boots({ RESISTANCE0_NAME = 49 }),
    [MONKEY] = Boots({ RESISTANCE0_NAME = 49 }),
}

local TOOLTIPS = {
    [MONKEY] = { "Lupine Slippers of the Monkey", "Soulbound", "Feet", "49 Armor", "+3 Agility",
        "+2 Stamina", "Durability 30 / 30", "Requires Level 11" },
}

local ns = env.Load()
_G.UnitClass = function() return "Hunter", "HUNTER", 3 end
env.InstallItems(ITEMS, { [8] = EMBOSSED }, { [0] = { [1] = MONKEY } }, 15)
_G.C_TooltipInfo = {
    GetHyperlink = function(link)
        local texts = TOOLTIPS[link]
        if not texts then return nil end
        local lines = {}
        for i, text in ipairs(texts) do lines[i] = { leftText = text } end
        return { lines = lines }
    end,
    GetItemByID = function() return nil end,
}

local Items = ns.Items

suite.check("the roll is read off the link", Items.RollID(MONKEY) == 617)
suite.check("no roll on plain gear", Items.RollID(EMBOSSED) == nil and Items.RollID("item:1:0:0:0:0:0:0") == nil)

local key, amount = Items.StatLine("+3 Agility")
suite.check("a stat line is read", key == "ITEM_MOD_AGILITY_SHORT" and amount == 3, key)
suite.check("other lines are not", Items.StatLine("49 Armor") == nil and Items.StatLine("Requires Level 11") == nil)

local stats = Items:Stats(MONKEY)
suite.check("the roll's Agility counts", stats.ITEM_MOD_AGILITY_SHORT == 3, stats.ITEM_MOD_AGILITY_SHORT)
suite.check("and its Stamina", stats.ITEM_MOD_STAMINA_SHORT == 2, stats.ITEM_MOD_STAMINA_SHORT)
suite.check("the armor stays", stats.RESISTANCE0_NAME == 49)
suite.check("the game's own table is left alone", ITEMS[MONKEY].stats.ITEM_MOD_AGILITY_SHORT == nil)

local result = ns.Compare:JudgeCarried(MONKEY)
suite.check("judged for Beast Mastery", result and result.specName == "Beast Mastery", result and result.specName)
suite.check("the Monkey boots are an upgrade", result and result.verdict == "upgrade",
    result and result.verdict)
suite.check("by a lot", result and result.percent and result.percent > 100, result and result.percent)

-- A stat the game already counts is never counted twice.
ITEMS[EMBOSSED].stats = { RESISTANCE0_NAME = 48, ITEM_MOD_STAMINA_SHORT = 2, ITEM_MOD_SPIRIT_SHORT = 2 }
local both = "item:15018:0:0:0:0:0:617:0"
ITEMS[both] = Boots({ RESISTANCE0_NAME = 49, ITEM_MOD_AGILITY_SHORT = 3, ITEM_MOD_STAMINA_SHORT = 2 })
TOOLTIPS[both] = TOOLTIPS[MONKEY]
stats = Items:Stats(both)
suite.check("a stat the game gave is not added again", stats.ITEM_MOD_AGILITY_SHORT == 3
    and stats.ITEM_MOD_STAMINA_SHORT == 2)

suite.done()
