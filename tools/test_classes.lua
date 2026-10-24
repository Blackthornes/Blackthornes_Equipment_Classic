-- Every classic class has specs, weights and equip rules, and each is judged
-- by its own: a priest's cloth, a warrior's plate, a mage's wand.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("classes")

local CLASSES = {
    "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST",
    "SHAMAN", "MAGE", "WARLOCK", "DRUID",
}

local ns = env.Load()
local Weights = ns.Weights

-- Every stat a weight may name: what STAT_KEYS maps to, plus the two ways
-- weapon damage is split, plus school spell damage read off the tooltip.
local KNOWN = { rangedDps = true, meleeDps = true }
for _, name in pairs(Weights.STAT_KEYS) do KNOWN[name] = true end
for _, name in pairs(ns.Items.SCHOOLS) do KNOWN[name] = true end

local used = {}
for _, class in ipairs(CLASSES) do
    local specs = Weights.SPECS[class]
    suite.check(class .. " has specs", specs ~= nil)
    suite.check(class .. " has three, in tree order", #specs.order == 3)
    suite.check(class .. "'s default is one of them", specs[specs.default] ~= nil, specs.default)
    suite.check(class .. " knows where its specs split", #specs.columns == 2)
    suite.check(class .. " has armour and weapon rules", specs.armor and specs.weapons)

    for _, key in ipairs(specs.order) do
        local spec = specs[key]
        suite.check(class .. " " .. key .. " has a name and weights", spec and spec.name and spec.weights)
        suite.check(class .. " " .. key .. " resolves from its own key", Weights:ResolveSpec(key) == key)
        for stat in pairs(spec.weights) do
            suite.check(class .. " " .. key .. " weighs a stat items carry: " .. stat, KNOWN[stat])
            used[stat] = true
        end
    end
end
for stat in pairs(KNOWN) do
    if stat ~= "dps" then
        suite.check("some spec weighs " .. stat, used[stat])
    end
end

--------------------------------------------------------------------------------
-- Judging by class
--------------------------------------------------------------------------------

local ARMOR, WEAPON = 4, 2
local ITEMS = {
    ["item:1"] = { loc = "INVTYPE_CHEST", class = ARMOR, subclass = 1,
        stats = { ITEM_MOD_INTELLECT_SHORT = 5 } },
    ["item:2"] = { loc = "INVTYPE_CHEST", class = ARMOR, subclass = 1,
        stats = { ITEM_MOD_INTELLECT_SHORT = 8, ITEM_MOD_SPELL_POWER_SHORT = 4 } },
    ["item:3"] = { loc = "INVTYPE_CHEST", class = ARMOR, subclass = 2,
        stats = { ITEM_MOD_INTELLECT_SHORT = 20 } },
    ["item:4"] = { loc = "INVTYPE_CHEST", class = ARMOR, subclass = 4,
        stats = { ITEM_MOD_STRENGTH_SHORT = 20 } },
    ["item:5"] = { loc = "INVTYPE_SHIELD", class = ARMOR, subclass = 6,
        stats = { ITEM_MOD_STAMINA_SHORT = 5 } },
    ["item:6"] = { loc = "INVTYPE_RANGEDRIGHT", class = WEAPON, subclass = 19,
        stats = { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 8 } },
    ["item:7"] = { loc = "INVTYPE_2HWEAPON", class = WEAPON, subclass = 10,
        stats = { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 20 } },
    ["item:8"] = { loc = "INVTYPE_2HWEAPON", class = WEAPON, subclass = 10,
        stats = { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 5, ITEM_MOD_AGILITY_SHORT = 3 } },
    ["item:9"] = { loc = "INVTYPE_RELIC", class = ARMOR, subclass = 7,
        stats = { ITEM_MOD_STRENGTH_SHORT = 2 } },
}

local function As(class, worn, level)
    local loaded = env.Load()
    _G.UnitClass = function() return class, class end
    env.InstallItems(ITEMS, worn or {}, {}, level or 20)
    return loaded
end

ns = As("PRIEST", { [5] = "item:1" })
local result = ns.Compare:Judge("item:2")
suite.check("spell power counts for a priest", result.verdict == "upgrade", result.verdict)
suite.check("judged as Shadow by default", result.specName == "Shadow", result.specName)
result = ns.Compare:Judge("item:3")
suite.check("a priest cannot wear leather", result.verdict == "cantuse", result.verdict)
suite.check("and is told so", (ns.Compare:Describe(result)) == "Priests can't use this")

ns = As("WARRIOR", {})
result = ns.Compare:Judge("item:4")
suite.check("plate at 20 is not for a warrior yet", result.verdict == "cantuse" and result.laterArmor == 40, result.verdict)
local atTwenty = _G.UnitLevel
_G.UnitLevel = function() return 38 end
result = ns.Compare:Judge("item:4")
suite.check("plate waits for 40 on a warrior", result.verdict == "upgrade" and result.level == 40, result.level)
_G.UnitLevel = atTwenty
suite.check("a warrior can use a shield", ns.Compare:Judge("item:5").verdict == "upgrade")
suite.check("but not a wand", ns.Compare:Judge("item:6").verdict == "cantuse")

ns = As("MAGE", {})
result = ns.Compare:Judge("item:6")
suite.check("a mage's wand damage counts", result.verdict == "upgrade" and result.score > 0, result.score)
suite.check("a mage cannot use a shield", ns.Compare:Judge("item:5").verdict == "cantuse")

ns = As("DRUID", { [16] = "item:8" })
result = ns.Compare:Judge("item:7")
suite.check("a feral druid's weapon damage counts in forms on Forever", result.score == 100, result.score)
suite.check("so a much bigger stick beats a little agility", result.verdict == "upgrade", result.verdict)

-- A player's level 38 feral druid was offered a wand and never a main-hand
-- weapon (2026-10-05).
ITEMS["item:10"] = { loc = "INVTYPE_2HWEAPON", class = WEAPON, subclass = 10,
    stats = { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 6 } }
ITEMS["item:11"] = { loc = "INVTYPE_RANGEDRIGHT", class = WEAPON, subclass = 19,
    stats = { ITEM_MOD_STAMINA_SHORT = 5, ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 20 } }
ITEMS["item:12"] = { loc = "INVTYPE_RANGED", class = WEAPON, subclass = 2,
    stats = { ITEM_MOD_AGILITY_SHORT = 5 } }
ITEMS["item:13"] = { loc = "INVTYPE_THROWN", class = WEAPON, subclass = 16,
    stats = { ITEM_MOD_AGILITY_SHORT = 5 } }
ITEMS["item:14"] = { loc = "INVTYPE_RANGEDRIGHT", stats = { ITEM_MOD_STAMINA_SHORT = 5 } }
ITEMS["item:15"] = { loc = "INVTYPE_RANGEDRIGHT", class = WEAPON, subclass = 10,
    stats = { ITEM_MOD_STAMINA_SHORT = 5 } }
ITEMS["item:16"] = { loc = "INVTYPE_WEAPON", class = WEAPON, subclass = 4,
    stats = { ITEM_MOD_STRENGTH_SHORT = 4, ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 10 } }
ITEMS["item:17"] = { loc = "INVTYPE_RELIC", class = ARMOR, subclass = 8,
    stats = { ITEM_MOD_STRENGTH_SHORT = 2 } }

ns = As("DRUID", { [16] = "item:10" }, 38)
result = ns.Compare:Judge("item:7")
suite.check("a feral druid's bigger stat-less staff is a main-hand upgrade",
    result.verdict == "upgrade" and result.slot == 16, result.verdict)
suite.check("and so is a faster-hitting mace", ns.Compare:Judge("item:16").verdict == "upgrade")
suite.check("a feral druid is never offered a wand", ns.Compare:Judge("item:11").verdict == "cantuse")
suite.check("so the bag arrow never shows on one", not ns.Compare:IsUpgradeNow("item:11"))
suite.check("nor a bow", ns.Compare:Judge("item:12").verdict == "cantuse")
suite.check("nor a thrown weapon", ns.Compare:Judge("item:13").verdict == "cantuse")
suite.check("but an idol goes in that slot", ns.Compare:Judge("item:17").verdict == "upgrade")
suite.check("a ranged-slot item whose kind the client did not say is not offered",
    ns.Compare:Judge("item:14").verdict == "cantuse")
for _, spec in ipairs({ "balance", "resto" }) do
    ns.HandleSlash("spec " .. spec)
    suite.check(spec .. " druids are never offered a wand either",
        ns.Compare:Judge("item:11").verdict == "cantuse")
end

-- Every class: nothing in the ranged slot unless it is a ranged weapon the
-- class can use.
local RANGED = { ["item:11"] = 19, ["item:12"] = 2, ["item:13"] = 16 }
local CAN = {
    WARRIOR = { [2] = true, [16] = true }, HUNTER = { [2] = true },
    ROGUE = { [2] = true, [16] = true }, PRIEST = { [19] = true }, MAGE = { [19] = true },
    WARLOCK = { [19] = true }, PALADIN = {}, SHAMAN = {}, DRUID = {},
}
for _, class in ipairs(CLASSES) do
    ns = As(class, {}, 38)
    for link, kind in pairs(RANGED) do
        local verdict = ns.Compare:Judge(link).verdict
        suite.check(("%s and ranged weapon kind %d"):format(class, kind),
            (verdict ~= "cantuse") == (CAN[class][kind] == true), verdict)
    end
    suite.check(class .. " is never offered a staff that claims the ranged slot",
        ns.Compare:Judge("item:15").verdict == "cantuse")
end

-- Forever's druids train polearms from 20.
ITEMS["item:18"] = { loc = "INVTYPE_2HWEAPON", class = WEAPON, subclass = 6,
    stats = { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 30 } }
ns = As("DRUID", { [16] = "item:10" }, 38)
suite.check("a druid can use a polearm on Forever", ns.Compare:Judge("item:18").verdict == "upgrade")
ns = As("DRUID", {}, 15)
result = ns.Compare:Judge("item:18")
suite.check("from level 20", result.verdict == "upgrade" and result.level == 20, result.level)

-- The finder never asks about a wand for a druid.
ns = As("DRUID", {}, 38)
local wearable = ns.Weights:CanUse("DRUID", WEAPON, 19, "INVTYPE_RANGEDRIGHT")
suite.check("the finder's wear check refuses a wand for a druid", wearable == false)
suite.check("and a weapon with no kind given",
    ns.Weights:CanUse("DRUID", nil, nil, "INVTYPE_2HWEAPON") == false)

ns = As("PALADIN", {})
suite.check("a paladin can use a libram", ns.Compare:Judge("item:9").verdict == "upgrade")
ns = As("HUNTER", {})
suite.check("a hunter cannot", ns.Compare:Judge("item:9").verdict == "cantuse")

--------------------------------------------------------------------------------
-- A second weapon: warriors and hunters from 20, rogues from 10, nobody else
--------------------------------------------------------------------------------

ITEMS["item:20"] = { loc = "INVTYPE_WEAPON", class = WEAPON, subclass = 15,
    stats = { ITEM_MOD_AGILITY_SHORT = 5 } }
ITEMS["item:21"] = { loc = "INVTYPE_WEAPON", class = WEAPON, subclass = 15,
    stats = { ITEM_MOD_AGILITY_SHORT = 3 } }
ITEMS["item:22"] = { loc = "INVTYPE_WEAPONOFFHAND", class = WEAPON, subclass = 7,
    stats = { ITEM_MOD_STRENGTH_SHORT = 4 } }

ns = As("ROGUE", { [16] = "item:20" }, 12)
result = ns.Compare:Judge("item:21")
suite.check("a rogue's second dagger fills the empty off hand",
    result.verdict == "upgrade" and result.slot == 17, result.verdict)

ns = As("ROGUE", { [16] = "item:20" }, 8)
result = ns.Compare:Judge("item:21")
suite.check("but not before the rogue can dual wield", result.slot == 16 and result.verdict == "downgrade",
    result.verdict)

ns = As("PALADIN", {})
result = ns.Compare:Judge("item:22")
suite.check("a paladin cannot use an off-hand sword", result.verdict == "cantuse", result.verdict)

ns = As("WARRIOR", {}, 12)
result = ns.Compare:Judge("item:22")
suite.check("a warrior waits for 20 to use one", result.verdict == "upgrade" and result.level == 20, result.level)

ns = As("PALADIN", {})
_G.CanDualWield = function() return true end
result = ns.Compare:Judge("item:22")
suite.check("unless the client says this character can", result.verdict == "upgrade" and not result.level,
    result.verdict)
_G.CanDualWield = nil

-- Old enough, but the client says this warrior has not trained it.
ns = As("WARRIOR", {}, 30)
_G.CanDualWield = function() return false end
result = ns.Compare:Judge("item:22")
suite.check("an untrained warrior's off-hand sword waits on training",
    result.verdict == "upgrade" and result.train == "Dual Wield", result.train)
suite.check("so it is not an upgrade to wear now", not ns.Compare:IsUpgradeNow("item:22"))
suite.check("and the tooltip says to train",
    (ns.Compare:Describe(result) or ""):find("once you train Dual Wield", 1, true), ns.Compare:Describe(result))
_G.CanDualWield = nil

--------------------------------------------------------------------------------
-- Picking a spec by name
--------------------------------------------------------------------------------

ns = As("WARRIOR", {})
ns.HandleSlash("spec tank")
local spec, why = ns.Weights:CurrentSpec()
suite.check("/beq spec tank makes a warrior Protection", spec == "prot" and why == "picked", spec)
env.chat = {}
ns.HandleSlash("spec holy")
suite.check("a warrior cannot be Holy",
    env.ChatText():find("holy isn't a spec (try arms, fury, prot, auto)", 1, true), env.ChatText())

ns = As("PALADIN", {})
ns.HandleSlash("spec holy")
suite.check("a paladin can", ns.Weights:CurrentSpec() == "holy")

-- Talents pick the spec from the tree's columns, as for the hunter.
ns = As("MAGE", {})
_G.C_ClassTalents = { GetActiveConfigID = function() return 1 end }
_G.C_Traits = {
    GetConfigInfo = function() return { treeIDs = { 1 } } end,
    GetTreeNodes = function() return { 1, 2 } end,
    GetNodeInfo = function(_, node)
        return ({ { posX = 1020, ranksPurchased = 1 }, { posX = 9080, ranksPurchased = 4 } })[node]
    end,
}
spec, why = ns.Weights:CurrentSpec()
suite.check("most points on the right of a mage's tree is Frost", spec == "frost" and why == "talents", spec)

--------------------------------------------------------------------------------
-- The probe lists the client's classes
--------------------------------------------------------------------------------

ns = As("HUNTER", {})
local tokens = { "WARRIOR", "HUNTER", "DEATHKNIGHT" }
_G.C_CreatureInfo = { GetClassInfo = function(id)
    if tokens[id] then return { classFile = tokens[id] } end
end }
local line = ns.Probe:Classes()
suite.check("the probe lists the classes", line == "WARRIOR, HUNTER, DEATHKNIGHT (no weights)", line)

suite.done()
