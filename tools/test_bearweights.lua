-- Druids: Bear Tank is its own set beside Feral Combat, picked by hand since
-- talents can't tell cat from bear. Feral Combat's weights are unchanged.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("bearweights")

local ARMOR, LEATHER = 4, 2

local ITEMS = {
    -- Worn: 10 agility. In the bags: armor, stamina and dodge, no agility.
    ["item:1"] = { loc = "INVTYPE_CHEST", class = ARMOR, subclass = LEATHER,
        stats = { ITEM_MOD_AGILITY_SHORT = 10 } },
    ["item:2"] = { loc = "INVTYPE_CHEST", class = ARMOR, subclass = LEATHER,
        stats = { ITEM_MOD_STAMINA_SHORT = 8, RESISTANCE0_NAME = 60 } },
}

local function LoadDruid()
    local ns = env.Load()
    _G.UnitClass = function() return "Druid", "DRUID" end
    env.InstallItems(ITEMS, { [5] = "item:1" }, { [0] = { [1] = "item:2" } }, 40)
    return ns
end

local ns = LoadDruid()
local Weights, Compare = ns.Weights, ns.Compare
local SPECS = Weights.SPECS.DRUID

suite.check("druids have a Bear Tank set", SPECS.bear and SPECS.bear.name == "Bear Tank")
suite.check("it is listed last, after the three trees", SPECS.order[4] == "bear", SPECS.order[4])
suite.check("the feral key stays, so saved weights keep working", SPECS.feral ~= nil)
suite.check("feral weights are as they were", SPECS.feral.weights.stamina == 0.8
    and SPECS.feral.weights.armor == 0.05 and SPECS.feral.weights.dodge == 6)
suite.check("bears weigh dodge", (SPECS.bear.weights.dodge or 0) > 0)
suite.check("and armor more than feral does",
    SPECS.bear.weights.armor > SPECS.feral.weights.armor * 2)
suite.check("a weapon's damage is only a tie-breaker in Bear Form on Era",
    SPECS.bear.weights.meleeDps < 1)
suite.check("its name shows", Weights:SpecName("DRUID", "bear") == "Bear Tank")

-- Talents only ever pick a tree, never Bear Tank.
local spec = Weights:CurrentSpec()
suite.check("a druid starts out judged as feral", spec == "feral", spec)
suite.check("as a cat, agility beats armor and stamina",
    Compare:Judge("item:2").verdict == "downgrade", Compare:Judge("item:2").verdict)

ns.HandleSlash("spec bear")
local why
spec, why = Weights:CurrentSpec()
suite.check("/beq spec bear picks Bear Tank", spec == "bear" and why == "picked", spec)
suite.check("and says so", env.ChatText():find("Bear Tank", 1, true), env.ChatText())
suite.check("as a bear, armor and stamina beat agility",
    Compare:Judge("item:2").verdict == "upgrade", Compare:Judge("item:2").verdict)

ns.HandleSlash("spec cat")
suite.check("/beq spec cat goes back to feral", Weights:CurrentSpec() == "feral")

ns.HandleSlash("spec tank")
suite.check("for a druid, tank means Bear Tank", Weights:CurrentSpec() == "bear", Weights:CurrentSpec())
suite.check("for a warrior, tank still means Protection",
    Weights:ResolveSpec("tank", "WARRIOR") == "prot")
suite.check("and for a paladin", Weights:ResolveSpec("tank", "PALADIN") == "prot")

-- A player's own feral weights stay with the cat set.
Weights:SetWeight("DRUID", "feral", "stamina", 2)
suite.check("feral weights are saved under feral", ns.db.customWeights.DRUID.feral.stamina == 2)
suite.check("and never touch the bear set", Weights:Get("DRUID", "bear").stamina == 1.0)

-- The Settings drop-down lists it.
local found = false
for _, key in ipairs(ns.SettingsUI:SpecChoices()) do
    if key == "bear" then found = true end
end
suite.check("Judge Gear As: lists Bear Tank", found)

suite.done()
