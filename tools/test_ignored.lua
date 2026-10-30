-- Ignoring an upgrade on the quest panel keeps it out of the upgrade quest
-- for good, and Settings > Upgrade quest > Ignored lists what was ignored,
-- to restore one or all (asked 2026-10-08). The list is the one Skip kept,
-- so upgrades skipped before stay ignored.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("ignored")

local function Agi(n) return { ITEM_MOD_AGILITY_SHORT = n } end
local function Gear(loc, n) return { loc = loc, class = 4, subclass = 2, stats = Agi(n) } end

local ITEMS = {
    ["item:900"] = Gear("INVTYPE_CHEST", 10),   -- worn
    ["item:1001"] = Gear("INVTYPE_CHEST", 20),  -- sold by a vendor
    ["item:1002"] = Gear("INVTYPE_CHEST", 30),  -- sold by a vendor, better
}

local ns = env.Load()
_G.UnitClass = function() return "Hunter", "HUNTER", 3 end
_G.UnitFactionGroup = function() return "Alliance", "Alliance" end
_G.UnitRace = function() return "Human", "Human", 1 end
_G.GetRealZoneText = function() return "Elwynn Forest" end
env.InstallItems(ITEMS, { [5] = "item:900" }, { [0] = {} }, 20)
_G.C_QuestLog = {
    IsQuestFlaggedCompleted = function() return false end,
    IsOnQuest = function() return false end,
    ReadyForTurnIn = function() return false end,
}

-- Names by item ID, as the client gives them once it has the item; 7777
-- has not arrived yet, so it is asked for.
local NAMES = { [1001] = "Leather Vest", [1002] = "Wolfhide Jerkin" }
local asked = {}
local byLink = _G.C_Item.GetItemInfo
_G.C_Item.GetItemInfo = function(item)
    if type(item) == "number" then
        if not NAMES[item] then return nil end
        return NAMES[item], ("|cff1eff00|Hitem:%d|h[%s]|h|r"):format(item, NAMES[item])
    end
    return byLink(item)
end
_G.C_Item.RequestLoadItemDataByID = function(id) asked[id] = true end

local S = ns.Sources
ns.Crafts.ITEMS = {}
ns.RollData.ITEMS = {}
S.ZONES = { [12] = "Elwynn Forest" }
S.NPCS = { [1] = { "Corina Steele", 12, 41.5, 65.9, "A" } }
S.QUESTS = {}
S.DUNGEONS = {}
S.BOSSES = {}
S.FOREVER = {}
S.ITEMS = {
    [1001] = { 15, 18, 0, 0, 12050, v = { 1, 0 } },
    [1002] = { 15, 18, 0, 0, 13000, v = { 1, 0 } },
}

local Quest, Panel, Ignored, Settings = ns.UpgradeQuest, ns.QuestPanel, ns.IgnoredUI, ns.SettingsUI

-- An upgrade skipped before Ignore existed is still ignored.
ns.charDB.upgradeQuestSkipped = { [7777] = true }

ns.HandleSlash("quest vendor")
suite.check("the vendor tab picks the best", Quest:Current() and Quest:Current().itemID == 1002)

-- The panel's button says Ignore and does it.
Panel:Refresh()
suite.check("the panel's button reads Ignore", Panel.skipButton.label:GetText() == "Ignore")
Panel.skipButton:GetScript("OnClick")(Panel.skipButton, "LeftButton")
suite.check("ignoring it picks the next best", Quest:Current() and Quest:Current().itemID == 1001)
suite.check("and keeps it ignored", ns.charDB.upgradeQuestSkipped[1002] == true)
suite.check("the old skip is kept", ns.charDB.upgradeQuestSkipped[7777] == true)

-- A fresh look never brings it back.
Quest.rescan = true
Quest:Update()
suite.check("it is not picked again", Quest:Current() and Quest:Current().itemID == 1001)

-- The list, by name; the unknown item asked for.
local list = Quest:IgnoredList()
suite.check("two ignored", #list == 2, #list)
suite.check("named, by name", list[1].name == "Item 7777" and list[2].name == "Wolfhide Jerkin",
    list[1].name .. " / " .. list[2].name)
suite.check("with its link", list[2].link and list[2].link:find("Hitem:1002", 1, true) ~= nil)
suite.check("an item not yet sent is asked for", asked[7777] == true)

-- Settings: the button opens the window and counts what is ignored.
Settings:Show()
local button = Settings.controls.questReset
suite.check("Settings counts the ignored", button.label:GetText() == "Ignored (2)", button.label:GetText())
button:GetScript("OnClick")(button, "LeftButton")
suite.check("and opens the list", Ignored.frame and Ignored.frame:IsShown())
suite.check("with a row each", Ignored.rows[1]:IsShown() and Ignored.rows[2]:IsShown() and not Ignored.rows[3]:IsShown())
suite.check("the empty line hidden", not Ignored.empty:IsShown())

-- Restore one.
local row = Ignored.rows[2]
suite.check("the row is the jerkin", row.entry and row.entry.itemID == 1002)
row.restore:GetScript("OnClick")(row.restore, "LeftButton")
suite.check("restoring forgets it", ns.charDB.upgradeQuestSkipped[1002] == nil)
suite.check("the list redraws", Ignored.rows[1]:IsShown() and not Ignored.rows[2]:IsShown())
suite.check("the quest followed now stays", Quest:Current() and Quest:Current().itemID == 1001)
ns.HandleSlash("quest ignore")
suite.check("the restored upgrade can be picked again", Quest:Current() and Quest:Current().itemID == 1002,
    Quest:Current() and Quest:Current().itemID)
Quest:Restore(1001)

suite.check("and Settings counts what is left", button.label:GetText() == "Ignored (1)", button.label:GetText())

-- Many ignored scroll.
for id = 5001, 5015 do ns.charDB.upgradeQuestSkipped[id] = true end
Ignored:Refresh()
suite.check("ten rows show", Ignored.rows[10]:IsShown())
suite.check("the count says there is more", Ignored.count:GetText() == "Scroll for more.", Ignored.count:GetText())
Ignored:Scroll(100)
suite.check("the wheel stops at the end", Ignored.offset == 6, Ignored.offset)

-- Restore all.
Ignored.restoreAll:GetScript("OnClick")(Ignored.restoreAll, "LeftButton")
suite.check("restore all forgets them all", next(ns.charDB.upgradeQuestSkipped) == nil)
suite.check("the list says nothing is ignored", Ignored.empty:IsShown() and not Ignored.rows[1]:IsShown())
suite.check("Settings says Ignored", button.label:GetText() == "Ignored", button.label:GetText())

-- The old words still work.
ns.HandleSlash("quest skip")
suite.check("/beq quest skip still ignores", ns.charDB.upgradeQuestSkipped[1002] == true)
ns.HandleSlash("quest reset")
suite.check("/beq quest reset still restores", next(ns.charDB.upgradeQuestSkipped) == nil)
ns.HandleSlash("quest ignored")
suite.check("/beq quest ignored opens the list", Ignored.frame:IsShown())

-- Every button reads.
suite.check("Restore all is a gold button", Ignored.restoreAll.label:GetText() == "Restore All")

suite.done()
