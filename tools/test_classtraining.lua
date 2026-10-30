-- Class spells to train in the gear window's Training drawer (the owner
-- said build it 2026-10-13). Logic/ClassTraining.lua is Butler's file;
-- Butler's test covers the plan, the trainer read and Train all in depth.
--
-- What must hold here:
--   1. The Training button counts the spells waiting, and opens the drawer.
--   2. The drawer lists ready spells with their cost, the next level's,
--      untrained weapon upgrades and the other characters' on this
--      realm and side.
--   3. A class trainer's window keeps the prices and the trainer's spot,
--      and Show the way aims the quest arrow there.
--   4. Turned off, the button goes and nothing is listed.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("classtraining")

local ns = env.Load()
env.InstallItems({}, {}, {})

ns.CLASS_SPELL_PRICES = {}
ns.CLASS_SPELLS = { MAGE = {
    { 1, 4, 1, "Frostbolt" },
    { 2, 8, 2, "Frostbolt", nil, 1 },
    { 3, 10, 1, "Frost Nova" },
    { 4, 14, 1, "Arcane Explosion" },
} }

local known = { [1] = true }
_G.UnitClass = function() return "Mage", "MAGE" end
_G.UnitLevel = function() return 12 end
_G.UnitRace = function() return "Human", "Human", 1 end
_G.UnitFactionGroup = function() return "Alliance" end
_G.UnitName = function(unit) return unit == "npc" and "Jennea Cannon" or "Me Here" end
_G.UnitGUID = function(unit)
    if unit == "npc" then return "Creature-0-1-2-3-5498-0000" end
    return "Player-1-AAA"
end
_G.IsPlayerSpell = function(id) return known[id] == true end
_G.GetRealZoneText = function() return "Stormwind City" end
_G.GetSubZoneText = function() return "Wizard's Sanctum" end
_G.C_Map = {
    GetBestMapForUnit = function() return 1453 end,
    GetPlayerMapPosition = function() return { GetXY = function() return 0.38, 0.79 end } end,
}

for _, module in ipairs(ns.moduleOrder) do
    if module.OnEnable then module:OnEnable() end
end

local UI, Drawer, CT = ns.UI, ns.TrainingDrawer, ns.ClassTraining

-- 1. The button.
UI:Show()
suite.check("the Training button counts what waits", UI.trainingButton.label:GetText() == "Training (2)",
    UI.trainingButton.label:GetText())
suite.check("the drawer starts closed", not Drawer:IsShown())
UI.trainingButton:GetScript("OnClick")(UI.trainingButton)
suite.check("a click opens it", Drawer:IsShown() and ns.db.trainingDrawer == true)

-- 2. What it lists.
local function Texts()
    local list = {}
    for _, row in ipairs(Drawer.lines) do
        if row:IsShown() then list[#list + 1] = row.text:GetText() .. "|" .. (row.right:GetText() or "") end
    end
    return table.concat(list, "\n")
end
local text = Texts()
suite.check("ready now, not priced yet", text:find("READY NOW|price after a trainer visit", 1, true) ~= nil, text)
suite.check("the ranked spell", text:find("Frostbolt (Rank 2)|Not priced yet", 1, true) ~= nil, text)
suite.check("the next level", text:find("AT LEVEL 14", 1, true) ~= nil, text)
suite.check("no trainer seen yet", Drawer.hint:GetText():find("Open a class trainer once", 1, true) ~= nil)

-- 3. At a trainer.
local services = {
    { "Frostbolt", "Rank 2", "available", 100 },
    { "Frost Nova", "", "available", 200 },
}
_G.GetNumTrainerServices = function() return #services end
_G.GetTrainerServiceInfo = function(i) return services[i][1], services[i][2], services[i][3] end
_G.GetTrainerServiceCost = function(i) return services[i][4] end
local handler = _G.BlackthornesEquipmentEventFrame:GetScript("OnEvent")
handler(_G.BlackthornesEquipmentEventFrame, "TRAINER_SHOW")
text = Texts()
suite.check("prices show once a trainer is read", text:find("READY NOW|3s", 1, true) ~= nil
    or text:find("READY NOW|", 1, true) ~= nil and CT:Plan().cost == 300, text)
suite.check("the drawer names the trainer", Drawer.hint:GetText():find("Jennea Cannon", 1, true) ~= nil,
    Drawer.hint:GetText())

local aimed
ns.QuestArrow.AimAtQuest = function(_, questID, title, place) aimed = { title = title, place = place } return true end
Drawer.wayButton:GetScript("OnClick")(Drawer.wayButton)
suite.check("Show the way aims the quest arrow at the trainer", aimed and aimed.place.name == "Jennea Cannon"
    and aimed.place.zone == "Stormwind City" and math.abs(aimed.place.x - 38) < 0.01)

-- Another character's spells.
CT:Data().characters["Player-1-BBB"] = { name = "Bob Stone", class = "MAGE", level = 10, faction = "Alliance",
    ready = { 2, 3 }, at = 1 }
-- Only this realm and side (a player saw the other side's and other
-- realms' characters, 2026-10-18). An older note with no side takes it
-- from this addon's note of that character's gear.
CT:Data().characters["Player-1-HHH"] = { name = "Hord Guy", class = "MAGE", level = 10, faction = "Horde",
    ready = { 2 }, at = 1 }
CT:Data().characters["Player-2-FAR"] = { name = "Far Away", class = "MAGE", level = 10, faction = "Alliance",
    ready = { 2 }, at = 1 }
CT:Data().characters["Player-1-OLD"] = { name = "Old Note", class = "MAGE", level = 10, ready = { 2 }, at = 1 }
CT:Data().characters["Player-1-NOP"] = { name = "No Side", class = "MAGE", level = 10, ready = { 2 }, at = 1 }
ns.db.characterGear = ns.db.characterGear or {}
ns.db.characterGear["Player-1-OLD"] = { faction = "Alliance" }
CT:Changed()
text = Texts()
suite.check("the other characters", text:find("Bob Stone", 1, true) ~= nil and text:find("2 spells at level 10", 1, true) ~= nil, text)
suite.check("an older note takes its side from the gear note", text:find("Old Note", 1, true) ~= nil, text)
suite.check("never the other side", text:find("Hord Guy", 1, true) == nil, text)
suite.check("never another realm", text:find("Far Away", 1, true) == nil, text)
suite.check("never a character whose side isn't known", text:find("No Side", 1, true) == nil, text)
ns.db.characterGear["Player-1-OLD"] = nil

-- A spell the trainer shows as learned leaves the drawer, whatever the
-- client's own check says (a player was told to train spells known a long
-- time, 2026-10-19).
services[2] = { "Frost Nova", "", "used", 200 }
handler(_G.BlackthornesEquipmentEventFrame, "TRAINER_SHOW")
text = Texts()
suite.check("a spell the trainer says is learned is not listed", text:find("Frost Nova", 1, true) == nil, text)
CT:Data().learned["Player-1-AAA"] = nil
services[2] = { "Frost Nova", "", "available", 200 }
handler(_G.BlackthornesEquipmentEventFrame, "TRAINER_SHOW")

-- 5. Skipping a spell (a player asked, the owner said yes, 2026-10-22).
local function RowFor(name)
    for _, row in ipairs(Drawer.lines) do
        if row:IsShown() and row.text:GetText() == name then return row end
    end
end
local told = {}
local butlerSkips = { ["Player-1-AAA"] = { [4] = 50 } }
_G.BlackthornesButler = { ClassTraining = {
    KeepSkip = function(_, guid, id, at) told[#told + 1] = { guid, id, at } end,
    OwnSkips = function(_, guid) return butlerSkips[guid] end,
} }
local before = CT:Plan().cost
local nova = RowFor("Frost Nova (Rank 1)")
suite.check("Frost Nova is ready to train", nova ~= nil, Texts())
nova:GetScript("OnClick")(nova, "RightButton")
text = Texts()
suite.check("a right-click skips it", CT:IsSkipped(3))
suite.check("no longer under ready", #CT:Plan().ready == 1, #CT:Plan().ready)
suite.check("and listed under SKIPPED", text:find("SKIPPED", 1, true) ~= nil and RowFor("Frost Nova (Rank 1)").skipped, text)
suite.check("its cost leaves the total", CT:Plan().cost == before - 200, CT:Plan().cost)
suite.check("Butler's copy is told", told[1] and told[1][1] == "Player-1-AAA" and told[1][2] == 3 and told[1][3] > 0)
suite.check("Train all leaves it out", (function()
    CT.trainerOpen, CT.atClassTrainer = true, true
    for _, service in ipairs(CT:Buyable()) do
        if service.entry[1] == 3 then return false end
    end
    return true
end)())
suite.check("a skip made in Butler counts here too", CT:IsSkipped(4))
butlerSkips["Player-1-AAA"][4] = -60
CT:Changed()
suite.check("and the newest change wins", not CT:IsSkipped(4))

nova = RowFor("Frost Nova (Rank 1)")
nova:GetScript("OnClick")(nova, "RightButton")
suite.check("a right-click brings it back", not CT:IsSkipped(3) and #CT:Plan().ready == 2)
suite.check("Butler's copy hears that too", told[2] and told[2][3] < 0)
_G.BlackthornesButler = nil
CT.trainerOpen, CT.atClassTrainer = false, false

-- 4. Turned off.
ns.HandleSlash("training off")
suite.check("off is saved", ns.db.classTraining == false)
suite.check("the button goes", not UI.trainingButton:IsShown())

_G.UnitGUID, _G.UnitName, _G.C_Map = nil, nil, nil
_G.GetNumTrainerServices, _G.GetTrainerServiceInfo, _G.GetTrainerServiceCost = nil, nil, nil
_G.GetSubZoneText = nil

suite.done()
