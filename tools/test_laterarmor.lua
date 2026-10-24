-- Mail and plate a class learns at 40 count only from level 38 (the owner,
-- 2026-10-24), so they aren't kept in the bags for many levels.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("laterarmor")

local ARMOR, LEATHER, MAIL = 4, 2, 3
local function Agi(n) return { ITEM_MOD_AGILITY_SHORT = n, ITEM_MOD_STAMINA_SHORT = n } end

local ITEMS = {
    ["item:1"] = { loc = "INVTYPE_CHEST", class = ARMOR, subclass = LEATHER, stats = Agi(1) },
    ["item:2"] = { loc = "INVTYPE_CHEST", class = ARMOR, subclass = MAIL, stats = Agi(20) },
    ["item:3"] = { loc = "INVTYPE_CHEST", class = ARMOR, subclass = LEATHER, stats = Agi(20) },
}

local ns = env.Load()
_G.UnitClass = function() return "HUNTER", "HUNTER" end
local level = 12
env.InstallItems(ITEMS, { [5] = "item:1" }, {})
_G.UnitLevel = function() return level end

local Compare = ns.Compare
local function Judge(link) return Compare:Judge(link) end

local mail = Judge("item:2")
suite.check("mail far off is not for a level 12 hunter", mail.verdict == "cantuse" and mail.laterArmor == 40, mail.verdict)
suite.check("no tooltip line for it", Compare:Describe(mail) == nil)
suite.check("leather is still an upgrade", Judge("item:3").verdict == "upgrade")

level = 37
suite.check("still not at 37", Judge("item:2").verdict == "cantuse")

level = 38
mail = Judge("item:2")
suite.check("at 38 it is an upgrade for later", mail.verdict == "upgrade" and mail.level == 40, mail.verdict)
suite.check("not one to wear now", not Compare.WearableUpgrade(mail))

level = 40
mail = Judge("item:2")
suite.check("at 40 it is an upgrade to wear", Compare.WearableUpgrade(mail), mail.verdict)

-- Another character: the same rule by its own level.
local function Alt(lvl) return { class = "HUNTER", level = lvl, spec = "beast", worn = { [5] = "item:1" } } end
suite.check("no mail for a level 12 hunter alt", ns.Alts:Judge(Alt(12), "item:2") == nil)
local later = ns.Alts:Judge(Alt(38), "item:2")
suite.check("a level 38 hunter alt waits for 40", later and later.level == 40, later and later.level)

suite.done()
