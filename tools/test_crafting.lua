-- Crafted gear as an upgrade: who can make it, how to learn it, what the
-- materials cost, with and without Tradeskills; and the finder's Crafted
-- filter and plan-ahead stepper.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("crafting")

local function Agi(n) return { ITEM_MOD_AGILITY_SHORT = n } end
local function Gear(loc, n, extra)
    local item = { loc = loc, class = 4, subclass = 2, stats = Agi(n) }
    for k, v in pairs(extra or {}) do item[k] = v end
    return item
end

local ITEMS = {
    ["item:900"] = Gear("INVTYPE_CHEST", 10),     -- worn
    ["item:3001"] = Gear("INVTYPE_CHEST", 30),    -- known recipe
    ["item:3002"] = Gear("INVTYPE_FEET", 20),     -- bind on pickup, learn from a recipe
    ["item:3003"] = Gear("INVTYPE_HEAD", 15),     -- another profession
    ["item:3004"] = Gear("INVTYPE_HANDS", 15),    -- another profession, bind on pickup
    ["item:3005"] = Gear("INVTYPE_CHEST", 50, { minLevel = 23 }),  -- for later
}

local ns = env.Load()
_G.UnitClass = function() return "Hunter", "HUNTER", 3 end
_G.UnitFactionGroup = function() return "Alliance", "Alliance" end
_G.UnitRace = function() return "Human", "Human", 1 end
env.InstallItems(ITEMS, { [5] = "item:900" }, {}, 20)

ns.Sources.ITEMS = {}
ns.Sources.FOREVER = {}
ns.RollData.ITEMS = {}

local C = ns.Crafts
C.PROFESSIONS = { [165] = "Leatherworking", [197] = "Tailoring" }
C.ZONES = { [12] = "Elwynn Forest", [14] = "Durotar" }
C.NPCS = {
    [50] = { "Adele Fielder", 12, 46.2, 62.1, "A" },
    [51] = { "Karolek", 14, 50, 50, "H" },
    [52] = { "Drake Lindgren", 12, 83.4, 66.7, "A" },
}
C.TRAINERS = { [1] = { 51, 50 } }
C.MATERIALS = { [2318] = { "Light Leather", 0 }, [2320] = { "Coarse Thread", 10 } }
C.RECIPES = {
    [2406] = { "Pattern: Fine Leather Boots", 90, 500, v = { 52, 0 } },
    [2407] = { "Pattern: Linen Hat", 60, 0, d = 500 },
}
C.ITEMS = {
    [3001] = { 165, 50, 9001, 15, 18, 0, 0, 0, m = { 2318, 8, 2320, 4 }, t = { 100, 1 } },
    [3002] = { 165, 90, 9002, 15, 20, 0, 0, 1, m = { 2318, 6 }, r = { 2406 } },
    [3003] = { 197, 75, 9003, 10, 15, 0, 0, 0, m = { 2320, 2 }, r = { 2407 } },
    [3004] = { 197, 75, 9004, 10, 15, 0, 0, 1, m = { 2320, 2 }, t = { 50, 1 } },
    [3005] = { 165, 60, 9005, 23, 25, 0, 0, 0, m = { 2318, 4 }, t = { 200, 1 } },
}

-- Leatherworking at 100, read the way Forever lists professions (twice).
_G.C_TradeSkillUI = {
    GetAllProfessionTradeSkillLines = function() return { 2945, 165 } end,
    GetProfessionInfoBySkillLineID = function()
        return { professionName = "Leatherworking", skillLevel = 100, maxSkillLevel = 150 }
    end,
}
_G.IsPlayerSpell = function(id) return id == 9001 end

local Crafting, Finder = ns.Crafting, ns.Finder
local player = Finder:Player()
local function Source(itemID) return Crafting:SourceFor(itemID, player, Finder.Band) end

local professions = Crafting:Professions()
suite.check("professions are read once each", professions[165] == 100 and professions[197] == nil)

local known = Source(3001)
suite.check("a recipe you know: you can make it", known.state == "known", known.state)
suite.check("materials priced where a vendor sells them, the rest unpriced",
    known.cost == 40 and known.partial == true, tostring(known.cost))
suite.check("it reads plainly",
    Crafting:Describe(known, Finder.Money) == "You can make it (Leatherworking)  materials over |cffeda55f40c|r",
    Crafting:Describe(known, Finder.Money))
suite.check("its materials in words", Crafting:MaterialsText(3001) == "8 Light Leather, 4 Coarse Thread")

local learn = Source(3002)
suite.check("bind on pickup with your profession: learn it", learn.state == "learn", learn.state)
suite.check("from the recipe your side's vendor sells", learn.learn.how == "recipe" and learn.name == "Drake Lindgren")
suite.check("so the map can find it", learn.zone == "Elwynn Forest" and learn.x == 83.4)
suite.check("in words", Crafting:Describe(learn, Finder.Money):find(
    "Leatherworking 90: Pattern: Fine Leather Boots, sold by Drake Lindgren in Elwynn Forest (83.4, 66.7) for |cffc7c7cf5s|r",
    1, true) ~= nil, Crafting:Describe(learn, Finder.Money))

local other = Source(3003)
suite.check("another profession, bind on equip: someone else makes it", other.state == "other", other.state)
suite.check("in words", Crafting:Describe(other, Finder.Money):find("Made with Tailoring 75", 1, true) == 1)
suite.check("bind on pickup from a profession you lack is never offered", Source(3004) == nil)

C.ITEMS[3002][2] = 120
Crafting:Forget()
local skill = Source(3002)
suite.check("not enough skill yet says so", skill.state == "skill"
    and Crafting:Describe(skill, Finder.Money):find("Needs Leatherworking 120, you have 100", 1, true) == 1,
    Crafting:Describe(skill, Finder.Money))
C.ITEMS[3002][2] = 90

-- Trainers: your own side's, in the zone you are in.
C.ITEMS[3002].r = nil
C.ITEMS[3002].t = { 300, 1 }
Crafting:Forget()
local trainer = Source(3002)
suite.check("a trainer of your side", trainer.learn.how == "trainer" and trainer.name == "Adele Fielder",
    trainer.name)
suite.check("and what it costs", Crafting:Describe(trainer, Finder.Money):find("for |cffc7c7cf3s|r", 1, true) ~= nil)
C.ITEMS[3002].t = nil
C.ITEMS[3002].r = { 2406 }

--------------------------------------------------------------------------------
-- With Tradeskills
--------------------------------------------------------------------------------

_G.BlackthornesTS = {
    Prices = { GetValue = function(_, id)
        if id == 2318 then return 50 end
        if id == 3003 then return 25000 end
    end },
    Recipes = {
        GetAccountWide = function()
            return { [9003] = { knownBy = { "alt-1", "horde-alt" } }, [9001] = { knownBy = { "me" } } }
        end,
        GetCharacterName = function(_, key) return key == "alt-1" and "Bob Wither" or "Grom Hall" end,
        GetShortCharacterName = function(_, key) return key == "alt-1" and "Bob" or "Grom" end,
    },
    Config = { GetCharacterKey = function() return "me" end },
    db = { characters = { ["alt-1"] = { faction = "Alliance" }, ["horde-alt"] = { faction = "Horde" } } },
}
Crafting:Forget()

known = Source(3001)
suite.check("auction prices fill in the rest", known.cost == 440 and not known.partial, tostring(known.cost))
local alt = Source(3003)
suite.check("an alt of your side who knows it can make it", alt.state == "alt" and #alt.who == 1
    and alt.who[1] == "Bob Wither", alt.who[1])
suite.check("in words, with the auction price beside it",
    Crafting:Describe(alt, Finder.Money):find("Bob Wither can make it (Tailoring)", 1, true) == 1
    and Crafting:Describe(alt, Finder.Money):find("|cffffd7002g|r |cffc7c7cf50s|r at the auction house", 1, true) ~= nil,
    Crafting:Describe(alt, Finder.Money))
suite.check("the tooltip says so too", Crafting:TooltipLine(3003) == "Bob Wither can make this")

-- An older Tradeskills without the full name still gives the short one.
_G.BlackthornesTS.Recipes.GetCharacterName = nil
Crafting:Forget()
suite.check("an older Tradeskills falls back to the short name", Source(3003).who[1] == "Bob")
_G.BlackthornesTS.Recipes.GetCharacterName = function(_, key) return key == "alt-1" and "Bob Wither" or "Grom Hall" end
Crafting:Forget()
suite.check("and for your own", Crafting:TooltipLine(3001) == "You can make this")

-- The skill Forever asks for, as Tradeskills read it from the recipe item.
_G.BlackthornesTS.RecipeBook = { GetSkill = function(_, id) if id == 9003 then return 60 end end }
Crafting:Forget()
suite.check("Forever's skill beats Classic's", Source(3003).skill == 60, Source(3003).skill)
suite.check("Classic's stands where Tradeskills has none", Source(3001).skill == C.ITEMS[3001][2])
_G.BlackthornesTS.RecipeBook.GetSkill = function() error("boom") end
suite.check("and a raise falls back to Classic's", Source(3003).skill == C.ITEMS[3003][2])
_G.BlackthornesTS.RecipeBook = nil

-- Recipes Forever added (Merchant's Favor ones among them) are not in
-- Classic's data, so a learned one comes from what Tradeskills read: what it
-- makes, its profession and its materials.
env.items["item:3101"] = Gear("INVTYPE_CHEST", 40, { minLevel = 18 })
env.items["item:3102"] = Gear("INVTYPE_HANDS", 25)
env.items["item:3103"] = { loc = "", class = 0, subclass = 0 }   -- a potion, not gear
env.items["item:3104"] = Gear("INVTYPE_LEGS", 25)                -- only a Horde alt knows it
env.items["item:7777"] = { loc = "", class = 7, subclass = 0 }   -- a material Classic does not list
_G.BlackthornesTS.Recipes.GetAccountWide = function()
    return {
        [9003] = { knownBy = { "alt-1", "horde-alt" } }, [9001] = { knownBy = { "me" } },
        [9101] = { knownBy = { "me" }, outputItemID = 3101, skillLineID = 2945,
            reagents = { { itemID = 2318, quantity = 12 }, { itemID = 7777, quantity = 2 } } },
        [9102] = { knownBy = { "alt-1" }, outputItemID = 3102, skillLineID = 197, reagents = {} },
        [9103] = { knownBy = { "me" }, outputItemID = 3103, skillLineID = 165, reagents = {} },
        [9104] = { knownBy = { "horde-alt" }, outputItemID = 3104, skillLineID = 165, reagents = {} },
        [9105] = { knownBy = { "me" }, outputItemID = 3001, skillLineID = 165, reagents = {} },
    }
end
Crafting:Forget()
Crafting:LayLearned()
local favor = C.ITEMS[3101]
suite.check("a learned recipe Classic lacks is laid in", favor and favor.learned == true and favor[3] == 9101
    and favor[1] == 165 and favor[4] == 18, favor and favor[1])
suite.check("with its materials", favor and favor.m[1] == 2318 and favor.m[2] == 12 and favor.m[4] == 2)
suite.check("you can make it", Source(3101) and Source(3101).state == "known")
suite.check("an alt's learned recipe: ask the alt", Source(3102) and Source(3102).state == "alt"
    and Source(3102).who[1] == "Bob Wither")
suite.check("what isn't gear is left out", C.ITEMS[3103] == nil and Crafting.pending[3103] == false)
suite.check("one only the other side knows is not offered", C.ITEMS[3104] and Source(3104) == nil)
suite.check("Classic's row is kept as it is", C.ITEMS[3001].learned == nil and C.ITEMS[3001][3] == 9001)
suite.check("its materials read by name, from the client where Classic has none",
    Crafting:MaterialsText(3101) == "12 Light Leather, 2 Item", Crafting:MaterialsText(3101))
suite.check("the tooltip says so", Crafting:TooltipLine(3101) == "You can make this")

-- An item the client has not loaded waits, and is laid once it has.
env.items["item:3106"] = nil
local realRecipes = _G.BlackthornesTS.Recipes.GetAccountWide
_G.BlackthornesTS.Recipes.GetAccountWide = function()
    local all = realRecipes()
    all[9106] = { knownBy = { "me" }, outputItemID = 3106, skillLineID = 165, reagents = {} }
    return all
end
Crafting:Forget()
Crafting:LayLearned()
suite.check("an item not loaded yet waits", C.ITEMS[3106] == nil and type(Crafting.pending[3106]) == "table")
env.items["item:3106"] = Gear("INVTYPE_WAIST", 20)
Crafting:LayLearned()
suite.check("and is laid once the client has it", C.ITEMS[3106] and C.ITEMS[3106].learned == true)
_G.BlackthornesTS.Recipes.GetAccountWide = realRecipes

-- Nobody knows it any more: it is not offered.
_G.BlackthornesTS.Recipes.GetAccountWide = function()
    return { [9003] = { knownBy = { "alt-1", "horde-alt" } }, [9001] = { knownBy = { "me" } } }
end
Crafting:Forget()
suite.check("a learned recipe nobody knows now is not offered", Source(3101) == nil)
for _, id in ipairs({ 3101, 3102, 3104, 3106 }) do C.ITEMS[id] = nil end

-- Tradeskills raising never breaks anything.
_G.BlackthornesTS.Recipes.GetAccountWide = function() error("boom") end
Crafting:Forget()
suite.check("a Tradeskills error is shrugged off", Source(3003).state == "other")
_G.BlackthornesTS = nil
Crafting:Forget()

--------------------------------------------------------------------------------
-- In the finder
--------------------------------------------------------------------------------

local found = Finder:Scan()
local chest = found.slots[5] and found.slots[5][1]
suite.check("crafted gear is offered", chest and chest.itemID == 3001, chest and chest.itemID)
suite.check("as a Crafted source", chest.sources[1].kind == "craft" and Finder.Label(chest.sources[1]) == "Crafted")
local head = found.slots[1] and found.slots[1][1]
suite.check("gear only a crafter elsewhere makes is marked as such", head and head.remote == true)
suite.check("bind on pickup from another profession is not offered", found.slots[10] == nil)
suite.check("gear for a later level is not offered now", chest.itemID ~= 3005)

local ahead = Finder:Scan(nil, 5)
suite.check("looking five levels ahead finds it", ahead.slots[5][1].itemID == 3005 and ahead.slots[5][1].at == 23,
    ahead.slots[5][1].itemID)
suite.check("and says how far it looked", ahead.reach == 25)

local onlyCrafts = Finder:Scan("craft")
suite.check("the Crafted filter keeps crafted gear", onlyCrafts.count >= 2)
suite.check("vendors only has none", Finder:Scan("vendor").count == 0)

local UI = ns.FinderUI
UI:Show()
for _, box in ipairs(UI.sourceBoxes) do
    if box.kind ~= "craft" then box:GetScript("OnClick")(box) end
end
UI:PickSlot(5)
suite.check("Crafted alone shows crafted gear", ns.db.finderSourcesOff.vendor == true
    and ns.db.finderSourcesOff.craft == nil and UI.rows[1]:IsShown())
suite.check("crafted rows say so", UI.rows[1].source:GetText():find("Crafted", 1, true) ~= nil,
    UI.rows[1].source:GetText())
-- The row's second line wraps rather than being cut, and the materials
-- line on the tooltip is a light colour, passed whole.
local long = ("word "):rep(math.floor(UI.rows[1].sourceWidth / 6) * 3)
local tall = UI:FillRow(UI.measureRow, { pick = UI.lines[1].pick,
    sources = { { kind = "vendor", name = long, zone = "Elwynn Forest" } } })
suite.check("a line longer than the row still shows in full",
    UI.measureRow.source:GetText():find(long, 1, true) ~= nil and not UI.measureRow.source:GetText():find("...", 1, true))
-- The source line is kept for the hover now (one line a row); the row
-- stays one line tall.
suite.check("and the row stays one line", not UI.measureRow.source:IsShown() and UI.measureRow:GetHeight() == tall, tall)
UI.measureRow:Hide()
local colours = {}
local realAdd = _G.GameTooltip.AddLine
_G.GameTooltip.AddLine = function(self, text, r, g, b, wrap)
    colours[#colours + 1] = { text = text, r = r, g = g, b = b, wrap = wrap }
    return realAdd(self, text)
end
for _, row in ipairs(UI.rows) do
    local pick = rawget(row, "pick")
    if type(pick) == "table" and pick.itemID == 3001 then row:GetScript("OnEnter")(row) end
end
local materials
for _, line in ipairs(colours) do
    if type(line.text) == "string" and line.text:find("Materials:", 1, true) then materials = line end
end
local tr, tg, tb = ns.Theme.Unpack("text")
suite.check("the tooltip lists the materials", materials ~= nil)
suite.check("in the light text colour, wrapped", materials and materials.r == tr and materials.g == tg
    and materials.b == tb and materials.wrap == true)
_G.GameTooltip.AddLine = realAdd

UI.ahead:SetValue(5)
suite.check("the stepper plans ahead", ns.db.finderAhead == 5 and UI.specLabel:GetText():find("planning for 25", 1, true),
    UI.specLabel:GetText())
local later
for _, row in ipairs(UI.rows) do
    local pick = rawget(row, "pick")
    if type(pick) == "table" and pick.itemID == 3005 then later = row end
end
suite.check("the row says when it can be worn", later and later.gain:GetText():find("at 23", 1, true) == 1,
    later and later.gain:GetText())
UI:PickSlot(1)
suite.check("the head row is not dated: it can be worn now", UI.rows[1].gain:GetText() == "empty slot",
    UI.rows[1].gain:GetText())
suite.check("the stepper reads as a level", UI.AheadText(5) == "Level 25" and UI.AheadText(0) == "Now")
UI.ahead:SetValue(0)
for _, box in ipairs(UI.sourceBoxes) do
    if box.kind ~= "craft" then box:GetScript("OnClick")(box) end
end
suite.check("ticked again, every source shows", next(ns.db.finderSourcesOff) == nil)

suite.done()
