-- Judging an item against what is worn: upgrades, downgrades, empty slots,
-- rings and trinkets, two-handers, what a hunter cannot use, and level.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("compare")

local ARMOR, WEAPON = 4, 2
local LEATHER, MAIL, SHIELD, MISC = 2, 3, 6, 0
local BOW, STAFF, DAGGER = 2, 10, 15

local function Agi(n) return { ITEM_MOD_AGILITY_SHORT = n } end

local ITEMS = {
    ["item:1"] = { loc = "INVTYPE_CHEST", class = ARMOR, subclass = LEATHER, stats = Agi(10) },
    ["item:2"] = { loc = "INVTYPE_CHEST", class = ARMOR, subclass = LEATHER, stats = Agi(15) },
    ["item:3"] = { loc = "INVTYPE_CHEST", class = ARMOR, subclass = LEATHER, stats = Agi(6) },
    ["item:4"] = { loc = "INVTYPE_CHEST", class = ARMOR, subclass = LEATHER, stats = Agi(10.05) },
    ["item:5"] = { loc = "INVTYPE_FEET", class = ARMOR, subclass = LEATHER, stats = Agi(2) },
    ["item:6"] = { loc = "INVTYPE_CHEST", class = ARMOR, subclass = MAIL, stats = Agi(30) },
    ["item:7"] = { loc = "INVTYPE_SHIELD", class = ARMOR, subclass = SHIELD, stats = Agi(30) },
    ["item:8"] = { loc = "INVTYPE_CHEST", class = ARMOR, subclass = LEATHER, stats = Agi(30), minLevel = 25 },
    ["item:10"] = { loc = "INVTYPE_FINGER", class = ARMOR, subclass = MISC, stats = Agi(10) },
    ["item:11"] = { loc = "INVTYPE_FINGER", class = ARMOR, subclass = MISC, stats = Agi(2) },
    ["item:12"] = { loc = "INVTYPE_FINGER", class = ARMOR, subclass = MISC, stats = Agi(5) },
    ["item:20"] = { loc = "INVTYPE_2HWEAPON", class = WEAPON, subclass = STAFF, stats = Agi(8) },
    ["item:21"] = { loc = "INVTYPE_WEAPON", class = WEAPON, subclass = DAGGER, stats = Agi(5) },
    ["item:22"] = { loc = "INVTYPE_WEAPON", class = WEAPON, subclass = DAGGER, stats = Agi(12) },
    ["item:30"] = { loc = "INVTYPE_RANGED", class = WEAPON, subclass = BOW,
        stats = { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 5 } },
    ["item:31"] = { loc = "INVTYPE_RANGED", class = WEAPON, subclass = BOW,
        stats = { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 6 } },
    ["item:40"] = { loc = "", class = 7, subclass = 0, stats = {} },
}

local function LoadWith(worn, bags, level, class)
    local ns = env.Load()
    _G.UnitClass = function() return class or "HUNTER", class or "HUNTER" end
    env.InstallItems(ITEMS, worn, bags, level)
    return ns
end

local ns = LoadWith({ [5] = "item:1" })
local Compare = ns.Compare

local result = Compare:Judge("item:2")
suite.check("more agility is an upgrade", result.verdict == "upgrade", result.verdict)
suite.check("by 50%", math.floor(result.percent + 0.5) == 50, result.percent)
suite.check("judged for Beast Mastery", result.specName == "Beast Mastery", result.specName)
local text, color = Compare:Describe(result)
suite.check("the line says so", text == "Upgrade for Beast Mastery: +50%", text)
suite.check("in the upgrade colour", color == "upgrade", color)
suite.check("and gets the bag arrow", Compare:IsUpgradeNow("item:2"))

result = Compare:Judge("item:3")
suite.check("less is a downgrade", result.verdict == "downgrade", result.verdict)
text, color = Compare:Describe(result)
suite.check("the line gives the loss", text == "Worse for Beast Mastery: -40%", text)
suite.check("in the downgrade colour", color == "downgrade", color)
suite.check("and no arrow", not Compare:IsUpgradeNow("item:3"))

result = Compare:Judge("item:4")
suite.check("half a percent is the same", result.verdict == "same", result.verdict)
suite.check("worded as the same", (Compare:Describe(result)) == "About the same for Beast Mastery")

result = Compare:Judge("item:1")
suite.check("the worn item itself is equipped", result.verdict == "equipped", result.verdict)
suite.check("and says nothing", Compare:Describe(result) == nil)

result = Compare:Judge("item:5")
suite.check("an empty slot is an upgrade", result.verdict == "upgrade" and result.empty, result.verdict)
suite.check("worded as filling it", (Compare:Describe(result)) == "Upgrade for Beast Mastery: fills an empty slot")

-- What a hunter cannot wear, or cannot wear yet.
result = Compare:Judge("item:7")
suite.check("a shield is no use to a hunter", result.verdict == "cantuse", result.verdict)
suite.check("and says so", (Compare:Describe(result)) == "Hunters can't use this")

result = Compare:Judge("item:6")
suite.check("mail at 20 is not for a hunter yet", result.verdict == "cantuse" and result.laterArmor == 40, result.verdict)
local atTwenty = _G.UnitLevel
_G.UnitLevel = function() return 38 end
result = Compare:Judge("item:6")
suite.check("mail at 38 waits for 40", result.verdict == "upgrade" and result.level == 40, result.level)
text, color = Compare:Describe(result)
suite.check("the line names the level", text == "Upgrade for Beast Mastery at level 40: +200%", text)
suite.check("in the warning colour", color == "warn", color)
suite.check("and there is no arrow yet", not Compare:IsUpgradeNow("item:6"))
_G.UnitLevel = atTwenty

result = Compare:Judge("item:8")
suite.check("an item above your level waits for it", result.level == 25, result.level)

ns = LoadWith({ [5] = "item:1" }, nil, 40)
suite.check("mail at 40 is an upgrade now", ns.Compare:IsUpgradeNow("item:6"))

-- Rings go against the weaker of the two worn.
ns = LoadWith({ [11] = "item:10", [12] = "item:11" })
result = ns.Compare:Judge("item:12")
suite.check("a ring beats the weaker ring", result.verdict == "upgrade", result.verdict)
suite.check("measured against that one", math.floor(result.percent + 0.5) == 150, result.percent)

ns = LoadWith({ [11] = "item:10" })
result = ns.Compare:Judge("item:12")
suite.check("a free ring slot is filled", result.verdict == "upgrade" and not result.empty, result.verdict)

-- Weapons.
ns = LoadWith({ [16] = "item:21", [17] = "item:22" })
result = ns.Compare:Judge("item:20")
suite.check("a two-hander is up against both hands", result.against == 17, result.against)
suite.check("so it can be a downgrade", result.verdict == "downgrade", result.verdict)

ns = LoadWith({ [16] = "item:21" })
result = ns.Compare:Judge("item:22")
suite.check("with no off hand, a dagger is judged against the main hand",
    result.verdict == "upgrade" and not result.empty, result.verdict)

ns = LoadWith({ [16] = "item:20" })
result = ns.Compare:Judge("item:21")
suite.check("a one-hander against a two-hander", result.against == 8, result.against)

ns = LoadWith({ [18] = "item:30" })
result = ns.Compare:Judge("item:31")
suite.check("bow damage counts as ranged", result.score == 36 and result.against == 30, result.score)

-- Things that are not judged.
suite.check("a non-gear item gets nothing", ns.Compare:Judge("item:40") == nil)
suite.check("an unknown item gets nothing", ns.Compare:Judge("item:999") == nil)
suite.check("nor does nil", ns.Compare:Judge(nil) == nil)

ns = LoadWith({ [5] = "item:1" }, nil, 20, "DEATHKNIGHT")
suite.check("a class with no weights gets nothing", ns.Compare:Judge("item:2") == nil)

-- Picking a spec changes the verdict's name.
ns = LoadWith({ [5] = "item:1" })
ns.HandleSlash("spec sv")
result = ns.Compare:Judge("item:2")
suite.check("judged as the picked spec", result.specName == "Survival", result.specName)

-- A client that raises costs the verdict, not an error.
_G.C_Item.GetItemStats = function() error("secret value") end
suite.check("stats that raise give nothing", ns.Compare:Judge("item:2") == nil)
suite.check("and no arrow", not ns.Compare:IsUpgradeNow("item:2"))

-- /beq bags lists what is in the bags.
ns = LoadWith({ [5] = "item:1" }, { [0] = { [1] = "item:2", [2] = "item:40", [3] = "item:3" } })
ns.HandleSlash("bags")
local chat = env.ChatText()
suite.check("/beq bags lists the upgrade", chat:find("item:2  |cff4fd18bUpgrade for Beast Mastery: +50%", 1, true), chat)
suite.check("and the downgrade", chat:find("Worse for Beast Mastery: -40%", 1, true), chat)
suite.check("but not the non-gear", not chat:find("item:40", 1, true), chat)

ns = LoadWith({}, {})
ns.HandleSlash("bags")
suite.check("empty bags say so", env.ChatText():find("nothing in your bags to wear", 1, true), env.ChatText())

-- The call Tradeskills makes, by item ID.
ns = LoadWith({ [5] = "item:1", [11] = "item:10", [12] = "item:11" })
suite.check("an ID that is an upgrade gets the arrow", ns.Compare:IsUpgrade(2) == true)
suite.check("a link works too", ns.Compare:IsUpgrade("item:2") == true)
suite.check("a downgrade by ID does not", ns.Compare:IsUpgrade(3) == false)
suite.check("nor the worn chest by ID", ns.Compare:IsUpgrade(1) == false)
suite.check("nor a worn ring, though the other ring is weaker", ns.Compare:IsUpgrade(10) == false)
suite.check("a better ring than the weaker one does", ns.Compare:IsUpgrade(12) == true)
suite.check("one to wait for does not", ns.Compare:IsUpgrade(8) == false)
suite.check("non-gear does not", ns.Compare:IsUpgrade(40) == false)
suite.check("an unknown ID does not", ns.Compare:IsUpgrade(999) == false)
suite.check("nor nil", ns.Compare:IsUpgrade(nil) == false)
suite.check("reachable through the global", _G.BlackthornesEquipment.Compare == ns.Compare)
_G.GetInventoryItemLink = function() error("secret value") end
suite.check("a worn read that raises does not raise here", pcall(ns.Compare.IsUpgrade, ns.Compare, 2))

suite.done()
