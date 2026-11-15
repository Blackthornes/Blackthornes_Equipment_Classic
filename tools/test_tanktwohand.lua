-- Protection warriors and paladins tank with a one-hander and a shield
-- (the owner, 2026-11-13): a two-hander is never their upgrade, and a
-- shield fills the off hand even while a two-hander is worn. Bear Tank
-- druids carry no shield and are left alone.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("tanktwohand")

local ARMOR, WEAPON = 4, 2
local SHIELD, PLATE = 6, 4
local SWORD1H, SWORD2H, MACE2H, STAFF = 7, 8, 5, 10

local function Tank(n)
    return { ITEM_MOD_STRENGTH_SHORT = n, ITEM_MOD_STAMINA_SHORT = n }
end

local ITEMS = {
    -- Worn: a weak two-hander.
    ["item:1"] = { loc = "INVTYPE_2HWEAPON", class = WEAPON, subclass = SWORD2H, stats = Tank(2) },
    -- A much better two-hander, a one-hander and a shield.
    ["item:2"] = { loc = "INVTYPE_2HWEAPON", class = WEAPON, subclass = SWORD2H, stats = Tank(40) },
    ["item:3"] = { loc = "INVTYPE_WEAPON", class = WEAPON, subclass = SWORD1H, stats = Tank(10) },
    ["item:4"] = { loc = "INVTYPE_SHIELD", class = ARMOR, subclass = SHIELD, stats = Tank(10) },
    ["item:5"] = { loc = "INVTYPE_CHEST", class = ARMOR, subclass = PLATE, stats = Tank(10) },
    -- For the druid.
    ["item:6"] = { loc = "INVTYPE_2HWEAPON", class = WEAPON, subclass = STAFF, stats = Tank(2) },
    ["item:7"] = { loc = "INVTYPE_2HWEAPON", class = WEAPON, subclass = MACE2H,
        stats = { ITEM_MOD_STAMINA_SHORT = 40, ITEM_MOD_AGILITY_SHORT = 40 } },
}

local ns = env.Load()
local class = "PALADIN"
_G.UnitClass = function() return class, class end
local worn = { [16] = "item:1" }
env.InstallItems(ITEMS, worn, {})
_G.UnitLevel = function() return 40 end

local Compare, Weights = ns.Compare, ns.Weights
local function Verdict(link) local r = Compare:Judge(link); return r and r.verdict end

suite.check("Protection is a shield tank", Weights:ShieldTank("PALADIN", "prot")
    and Weights:ShieldTank("WARRIOR", "prot"))
suite.check("other specs are not", not Weights:ShieldTank("PALADIN", "ret")
    and not Weights:ShieldTank("WARRIOR", "arms")
    and not Weights:ShieldTank("DRUID", "bear")
    and not Weights:ShieldTank(nil, nil))

-- Retribution keeps two-handers.
ns.charDB.spec = "ret"
suite.check("Retribution sees the big two-hander", Verdict("item:2") == "upgrade", Verdict("item:2"))

-- Protection.
ns.charDB.spec = "prot"
local big = Compare:Judge("item:2")
suite.check("Protection never gets a two-hander", big.verdict == "cantuse" and big.tankTwoHand, big.verdict)
suite.check("no tooltip line for it", Compare:Describe(big) == nil)
suite.check("no bag arrow on it", Compare:IsUpgrade("item:2") == false)
local shield = Compare:Judge("item:4")
suite.check("a shield fills the off hand beside a worn two-hander",
    shield.verdict == "upgrade", shield.verdict)
suite.check("the one-hander is still judged", Verdict("item:3") ~= "cantuse", Verdict("item:3"))
suite.check("armor is untouched", Verdict("item:5") == "upgrade", Verdict("item:5"))
suite.check("an upgrade quest for a two-hander is let go",
    ns.UpgradeQuest:TankTwoHand({ link = "item:2" }) == true
    and ns.UpgradeQuest:TankTwoHand({ link = "item:3" }) == false)
local advice = ns.Butler:Advise("item:2")
suite.check("Butler is not told it can never be worn", not (advice and advice.never))

-- A Protection warrior the same.
class = "WARRIOR"
suite.check("Protection warriors too", Compare:Judge("item:2").tankTwoHand == true)
ns.charDB.spec = "arms"
suite.check("Arms keeps two-handers", Verdict("item:2") == "upgrade", Verdict("item:2"))

-- Alts.
local note = { class = "PALADIN", spec = "prot", level = 40, worn = { [16] = "item:1" } }
suite.check("a Protection alt is never offered a two-hander", ns.Alts:Judge(note, "item:2") == nil)
note.spec = "ret"
suite.check("a Retribution alt still is", ns.Alts:Judge(note, "item:2") ~= nil)

-- Bear Tank druids are left alone.
class = "DRUID"
ns.charDB.spec = "bear"
worn[16] = "item:6"
local mace = Compare:Judge("item:7")
suite.check("a bear still sees two-handers", mace.verdict == "upgrade" and not mace.tankTwoHand, mace.verdict)

suite.done()
