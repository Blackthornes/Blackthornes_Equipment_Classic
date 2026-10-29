-- Random rolls on a German client: a warrior's worn legs "des Bären" (+5
-- Stärke, +5 Ausdauer) were scored on their armor alone, so plain legs with
-- fewer stats were called a +141% upgrade. The roll's lines are matched by
-- the stat's name, whatever the client's format line says.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("rollstats_german")

local ARMOR, MAIL = 4, 3
local function Legs(stats)
    return { loc = "INVTYPE_LEGS", class = ARMOR, subclass = MAIL, stats = stats }
end

local BEAR = "|cff1eff00|Hitem:15524:0:0:0:0:0:1199:0|h[Kundschafter-Beinschützer des Bären]|h|r"
local STORM = "item:15000"

local ITEMS = {
    -- What Era hands back for the rolled link: the armor and nothing more.
    [BEAR] = Legs({ RESISTANCE0_NAME = 152 }),
    ["item:15524:0:0:0:0:0:1199:0"] = Legs({ RESISTANCE0_NAME = 152 }),
    [STORM] = Legs({ RESISTANCE0_NAME = 141, ITEM_MOD_STRENGTH_SHORT = 3,
        ITEM_MOD_STAMINA_SHORT = 3, ITEM_MOD_SPIRIT_SHORT = 1 }),
}

local TOOLTIPS = {
    [BEAR] = { "Kundschafter-Beinschützer des Bären", "Seelengebunden", "Beine", "152 Rüstung",
        "+5 Ausdauer", "+5\194\160Stärke", "Haltbarkeit 65 / 65", "Benötigt Stufe 17" },
}

-- A client whose format lines don't match its tooltip: only the names do.
_G.ITEM_MOD_STRENGTH = "%c%s zu Stärke"
_G.ITEM_MOD_STAMINA = nil
_G.SPELL_STAT1_NAME = "Stärke"
_G.SPELL_STAT3_NAME = "Ausdauer"

local ns = env.Load("deDE")
_G.UnitClass = function() return "Krieger", "WARRIOR", 1 end
env.InstallItems(ITEMS, { [7] = BEAR }, { [0] = { [1] = STORM } }, 20)
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

local key, amount = Items.StatLine("+5 Stärke")
suite.check("a German stat line is read by name", key == "ITEM_MOD_STRENGTH_SHORT" and amount == 5, key)
key = Items.StatLine("+5 Ausdauer")
suite.check("and Stamina by our own word", key == "ITEM_MOD_STAMINA_SHORT", key)
suite.check("armor is not a stat line", Items.StatLine("152 Rüstung") == nil)
suite.check("a level line is not", Items.StatLine("Benötigt Stufe 17") == nil)

local stats = Items:Stats(BEAR)
suite.check("the Bear's Strength counts", stats.ITEM_MOD_STRENGTH_SHORT == 5, stats.ITEM_MOD_STRENGTH_SHORT)
suite.check("and its Stamina", stats.ITEM_MOD_STAMINA_SHORT == 5, stats.ITEM_MOD_STAMINA_SHORT)

local result = ns.Compare:Judge(STORM)
suite.check("the plain legs are no upgrade over the Bear's", result and result.verdict == "downgrade",
    result and (tostring(result.verdict) .. " " .. tostring(result.percent)))

suite.done()
