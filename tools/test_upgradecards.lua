-- The upgrade quest cards: How You Gear Up styles, why a pick was chosen,
-- the map marker's clicks, the quest log's green marks and Upgrade Done!
-- at each Effects level.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("upgradecards")

local ns = env.Load()
_G.UnitClass = function() return "Hunter", "HUNTER", 3 end
_G.UnitFactionGroup = function() return "Alliance", "Alliance" end
_G.UnitRace = function() return "Human", "Human", 1 end
_G.GetRealZoneText = function() return "Elwynn Forest" end
env.InstallItems({ ["item:900"] = { loc = "INVTYPE_CHEST", class = 4, subclass = 2, stats = {} } }, { [5] = "item:900" }, { [0] = {} }, 20)

local Quest = ns.UpgradeQuest

-- Styles ---------------------------------------------------------------------
suite.check("Anything is the style until one is picked", Quest:Style().key == "anything"
    and ns.db.upgradeQuestStyle == nil and #Quest.StyleLines(Quest:Style()) == 0)

local lines = Quest.StyleLines({ sets = { zone = true, solo = true, easy = true } })
suite.check("Quick and Close says what it sets", #lines == 3 and lines[3] == "Easy picks first")

Quest:SetStyle("quick")
suite.check("Quick and Close is saved and ticks This Zone Only and Solo",
    ns.db.upgradeQuestStyle == "quick" and Quest:Sets("zone") == true and ns.db.soloQuestsOnly == true)
Quest:SetStyle("vendor")
suite.check("a new style unticks what the old one set",
    ns.db.upgradeQuestStyle == "vendor" and ns.db.soloQuestsOnly == false and Quest:Sets("first") == "vendor")
Quest:BoxChanged("first", false)
suite.check("unticking a box the style needs reads Anything again", ns.db.upgradeQuestStyle == nil)
Quest:SetStyle("nonsense")
suite.check("an unknown style saves nothing", ns.db.upgradeQuestStyle == nil)

-- Why ------------------------------------------------------------------------
suite.check("the most gain is the biggest", Quest.Why(10, 1, { gain = 10, ease = 5 }) == "biggest")
suite.check("the easiest is the easiest", Quest.Why(5, 5, { gain = 10, ease = 5 }) == "easiest")
suite.check("else it is the best mix", Quest.Why(5, 2, { gain = 10, ease = 5 }) == "mix")
suite.check("with nothing to weigh it is the best mix", Quest.Why(5, 2, nil) == "mix")

-- Map marker -----------------------------------------------------------------
local MapPins = ns.MapPins
MapPins.spotlight = nil
suite.check("no marker, no click", MapPins:SpotClick("LeftButton") == nil)
local aimed
ns.QuestArrow = ns.QuestArrow or {}
local oldAim = ns.QuestArrow.AimAtQuest
ns.QuestArrow.AimAtQuest = function(_, id, name, place) aimed = { id, name, place } end
MapPins.spotlight = { place = { zone = "Elwynn Forest", x = 40, y = 60 }, name = "Leather Vest", questID = 77 }
suite.check("left-click aims the arrow at the marker", MapPins:SpotClick("LeftButton") == "arrow"
    and aimed and aimed[1] == 77 and aimed[2] == "Leather Vest" and aimed[3].x == 40)
local turnedOn = false
local oldOn = Quest.TurnOn
Quest.TurnOn = function() turnedOn = true end
suite.check("right-click opens the quest", MapPins:SpotClick("RightButton") == "quest" and turnedOn)
Quest.TurnOn, ns.QuestArrow.AimAtQuest = oldOn, oldAim
MapPins.spotlight = nil

-- Quest log marks ------------------------------------------------------------
local oldMark = Quest.RewardMark
local mark
Quest.RewardMark = function() return mark end
local MarkText = ns.QuestLogUI.MarkText
mark = nil
suite.check("no upgrade, no mark", MarkText(5) == nil)
mark = { percent = 6, slot = 1 }
local text = MarkText(5)
suite.check("an upgrade shows its gain and slot", type(text) == "string" and text:find("+6%", 1, true) ~= nil)
mark = { percent = 0, slot = 1, empty = true }
local empty = MarkText(5)
suite.check("an empty slot shows the slot alone", type(empty) == "string" and not empty:find("%%"))
Quest.RewardMark = oldMark

-- Upgrade Done! --------------------------------------------------------------
local Done = ns.UpgradeDone
local quest = { name = "Leather Vest", link = "item:1001", slot = 5, howMuch = "+8%" }
for _, level in ipairs({ "full", "subtle", "off" }) do
    ns.db.effectsLevel = level ~= "full" and level or nil
    local shown = Done:Show(quest, 3)
    if ns.Motion and ns.Motion.Step then ns.Motion:Step(2) end
    local sparks = 0
    for _, spark in ipairs(Done.sparks or {}) do if spark:IsShown() then sparks = sparks + 1 end end
    suite.check("Upgrade Done! shows on " .. level, shown == true and Done.frame:IsShown()
        and Done.count:GetText() == "Done: 3")
    if level ~= "full" then
        suite.check("no sparks on " .. level, sparks == 0)
    end
    Done:Hide()
end
ns.db.effectsLevel = nil
suite.check("Upgrade Done! puts itself away", not Done.frame:IsShown())
suite.check("Upgrade Done! fades after its hold", (function()
    Done:Show(quest, 1)
    Done:Step(Done.HOLD + Done.FADE + 0.1)
    return not Done.frame:IsShown()
end)())
suite.check("Upgrade Done! needs a quest", Done:Show(nil, 1) == false)

suite.done()
