-- Where to get upgrades' "This zone only": ticked, the list keeps to the
-- zone the character is in; unticked, it lists every upgrade from anywhere. Its own setting, apart from the upgrade
-- quest panel's box.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("finderzone")

local function Agi(n) return { ITEM_MOD_AGILITY_SHORT = n } end
local function Chest(n) return { loc = "INVTYPE_CHEST", class = 4, subclass = 2, stats = Agi(n) } end

local ITEMS = {
    ["item:900"] = Chest(10),    -- worn
    ["item:1001"] = Chest(20),   -- a vendor's in Elwynn Forest
    ["item:1101"] = Chest(60),   -- four vendor's in Westfall, all better
    ["item:1102"] = Chest(70),
    ["item:1103"] = Chest(80),
    ["item:1104"] = Chest(90),
}

local ns = env.Load()
_G.UnitClass = function() return "Hunter", "HUNTER", 3 end
_G.UnitFactionGroup = function() return "Alliance", "Alliance" end
_G.UnitRace = function() return "Human", "Human", 1 end
local zone = "Elwynn Forest"
_G.GetRealZoneText = function() return zone end
env.InstallItems(ITEMS, { [5] = "item:900" }, { [0] = {} }, 20)
_G.C_QuestLog = { IsQuestFlaggedCompleted = function() return false end }

local S = ns.Sources
ns.Crafts.ITEMS = {}
ns.RollData.ITEMS = {}
S.ZONES = { [12] = "Elwynn Forest", [40] = "Westfall" }
S.NPCS = {
    [1] = { "Corina Steele", 12, 41.5, 65.9, "A" },
    [2] = { "Kirsta Deepshadow", 40, 56.3, 31.0, "A" },
}
S.QUESTS = {}
S.DUNGEONS = {}
S.BOSSES = {}
S.FOREVER = {}
S.ITEMS = {
    [1001] = { 15, 18, 0, 0, 500, v = { 1, 0 } },
    [1101] = { 15, 18, 0, 0, 500, v = { 2, 0 } },
    [1102] = { 15, 18, 0, 0, 500, v = { 2, 0 } },
    [1103] = { 15, 18, 0, 0, 500, v = { 2, 0 } },
    [1104] = { 15, 18, 0, 0, 500, v = { 2, 0 } },
}

local UI = ns.FinderUI

local function Listed()
    local ids = {}
    for _, line in ipairs(UI.lines or {}) do ids[#ids + 1] = line.pick.itemID end
    return table.concat(ids, ",")
end

suite.check("off by default", ns.db.finderZoneOnly == false and not UI:ZoneOnly())
UI:Show()
suite.check("off, every one from anywhere, best first", Listed() == "1104,1103,1102,1101,1001", Listed())

suite.check("the window has the tick box", UI.zone ~= nil and not UI.zone:GetChecked())
suite.check("named as on the quest panel", UI.zone.label:GetText() == "This Zone Only")
UI.zone:GetScript("OnEnter")(UI.zone)
local tip = table.concat(GameTooltip._lines, "\n")
suite.check("hovering says what it does", tip:find("zone you're in", 1, true) ~= nil, tip)
UI.zone:GetScript("OnLeave")(UI.zone)

UI.zone:GetScript("OnClick")(UI.zone)
suite.check("ticking it saves it", ns.db.finderZoneOnly == true and UI:ZoneOnly())
suite.check("only what Elwynn Forest has", Listed() == "1001", Listed())
suite.check("the footer says how many are left out", UI.footer:GetText() == "Your filters hide 4 more.",
    UI.footer:GetText())
suite.check("the upgrade quest's own box is left alone", ns.db.upgradeQuestZoneOnly == false)

zone = "Westfall"
UI:Refresh()
suite.check("in Westfall, its four", Listed() == "1104,1103,1102,1101", Listed())

zone = "Duskwood"
UI:Refresh()
suite.check("a zone with nothing lists nothing", Listed() == "", Listed())
suite.check("and offers to look anywhere", UI.empty:GetText():find("Nothing in Duskwood", 1, true) ~= nil
    and UI.empty.button and UI.empty.button:IsShown(), UI.empty:GetText())
UI.empty.button:GetScript("OnClick")(UI.empty.button)
suite.check("Show All unticks This Zone Only", ns.db.finderZoneOnly == false)
UI:SetZoneOnly(true)

UI.zone:GetScript("OnClick")(UI.zone)
suite.check("unticked, the best from anywhere again", ns.db.finderZoneOnly == false
    and Listed() == "1104,1103,1102,1101,1001", Listed())

suite.done()
