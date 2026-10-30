-- Clicking an upgrade in "Where to get upgrades" follows it on the upgrade
-- quest panel, on its source's tab (asked 2026-10-06). Right-click still
-- tracks it, Alt-click still pins it, a chat-link click still links it.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("followquest")

local function Agi(n) return { ITEM_MOD_AGILITY_SHORT = n } end
local function Gear(loc, n) return { loc = loc, class = 4, subclass = 2, stats = Agi(n) } end

local ITEMS = {
    ["item:900"] = Gear("INVTYPE_CHEST", 10),   -- worn
    ["item:1001"] = Gear("INVTYPE_CHEST", 20),  -- sold by a vendor
    ["item:1002"] = Gear("INVTYPE_CHEST", 30),  -- quest reward
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

local S = ns.Sources
ns.Crafts.ITEMS = {}
ns.RollData.ITEMS = {}
S.ZONES = { [12] = "Elwynn Forest" }
S.NPCS = { [1] = { "Corina Steele", 12, 41.5, 65.9, "A" } }
S.QUESTS = { [10] = { "Wolves of the Forest", 15, 18, 0, 0, "Marshal Dughan", 12, 42.1, 65.9, "" } }
S.DUNGEONS = {}
S.BOSSES = {}
S.FOREVER = {}
S.ITEMS = {
    [1001] = { 15, 18, 0, 0, 12050, v = { 1, 0 } },
    [1002] = { 15, 18, 0, 0, 0, q = { 10 } },
}

local Quest, Panel, UI = ns.UpgradeQuest, ns.QuestPanel, ns.FinderUI

local function RowFor(itemID)
    for _, row in ipairs(UI.rows) do
        if row:IsShown() and row.pick and row.pick.itemID == itemID then return row end
    end
end
local function Click(row, button) row:GetScript("OnClick")(row, button or "LeftButton") end
local function TooltipText(row)
    GameTooltip._lines = {}
    row:GetScript("OnEnter")(row)
    local text = table.concat(GameTooltip._lines, "\n")
    row:GetScript("OnLeave")(row)
    return text
end

suite.check("the quest starts off", not Quest:IsEnabled())
UI:Show()
local vendorRow, questRow = RowFor(1001), RowFor(1002)
suite.check("both upgrades are listed", vendorRow ~= nil and questRow ~= nil)
suite.check("hovering says a click follows it", TooltipText(vendorRow):find("Click to follow it on the quest panel", 1, true) ~= nil)
suite.check("and what that does, the green Quest tag included",
    TooltipText(vendorRow):find("It becomes your upgrade quest", 1, true) ~= nil
    and TooltipText(vendorRow):find("green Quest tag", 1, true) ~= nil)
suite.check("the window has no help line under the list", (UI.hint:GetText() or "") == "")
suite.check("the hover ends with the right-click hint",
    TooltipText(vendorRow):find("Right-click for more.", 1, true) ~= nil)

-- A skipped upgrade can still be chosen by hand.
Quest:Skipped()[1001] = true
Click(vendorRow)
suite.check("a click turns the quest on", Quest:IsEnabled() and ns.db.upgradeQuest == true)
suite.check("and follows the vendor's chest on the Vendor tab", Quest:Tab() == "vendor"
    and Quest:Current() and Quest:Current().itemID == 1001, Quest:Tab())
suite.check("the copy older versions read follows", ns.charDB.upgradeQuest == Quest:Current())
suite.check("it is no longer skipped", not Quest:Skipped()[1001])
suite.check("the quest panel opens on it", Panel.frame and Panel.frame:IsShown()
    and Panel.name:GetText() == "item:1001", Panel.name and Panel.name:GetText())
suite.check("the chat says so", env.ChatText():find("following item:1001", 1, true) ~= nil)
vendorRow = RowFor(1001)
suite.check("the row is marked Following", vendorRow.item:GetText():find("Following", 1, true) ~= nil,
    vendorRow.item:GetText())
suite.check("and hovering says it is the quest", TooltipText(vendorRow):find("Your upgrade quest", 1, true) ~= nil)
suite.check("and how to drop it", TooltipText(vendorRow):find("To drop it, click Ignore on the quest panel", 1, true) ~= nil)

-- The quest reward goes on the Quest tab, and the vendor's is kept.
Click(RowFor(1002))
suite.check("the quest reward goes on the Quest tab", Quest:Tab() == "quest" and Quest:Current().itemID == 1002)
suite.check("the Vendor tab keeps its pick", Quest:QuestOn("vendor") and Quest:QuestOn("vendor").itemID == 1001)
suite.check("the panel shows the Quest tab", Panel.title:GetText() == "Quest", Panel.title:GetText())

-- A folded panel unfolds.
Panel:ToggleFold()
Click(RowFor(1001))
suite.check("a folded panel unfolds", not Panel.folded and Quest:Tab() == "vendor")

-- Following from the finder while the panel shows the Quest log tab shows
-- the followed quest's tab instead.
ns.charDB.questLogTab = true
Click(RowFor(1002))
suite.check("following leaves the Quest log tab", ns.charDB.questLogTab == nil and Quest:Tab() == "quest")
Click(RowFor(1001))

-- Other clicks keep their jobs.
Click(RowFor(1002), "RightButton")
local menu = ns.RowMenu and ns.RowMenu.frame
local trackLine
for _, line in ipairs(menu and menu.lines or {}) do
    if line.label and line.label:GetText() == "Track" then trackLine = line end
end
suite.check("right-click opens the row's menu, with Track", trackLine ~= nil and trackLine:IsShown())
if trackLine then trackLine:GetScript("OnClick")(trackLine) end
suite.check("its Track line tracks", ns.Tracking:IsTracked(1002) and Quest:Tab() == "vendor")
ns.Tracking:Untrack(1002)
_G.IsModifiedClick = function(what) return what == "CHATLINK" end
local linked
_G.ChatEdit_InsertLink = function(link) linked = link end
Click(RowFor(1002))
suite.check("a chat-link click links it and nothing else", linked == "item:1002" and Quest:Tab() == "vendor")
_G.IsModifiedClick, _G.ChatEdit_InsertLink = nil, nil
_G.IsAltKeyDown = function() return true end
Click(RowFor(1002))
suite.check("Alt-click does not change the quest", Quest:Tab() == "vendor")
_G.IsAltKeyDown = nil

-- What cannot be followed yet says why, and changes nothing.
local function Says(pick, words)
    local source, why = Quest.CanFollow(pick)
    return source == nil and type(why) == "string" and why:find(words, 1, true) ~= nil, why
end
local vendor = { kind = "vendor", name = "Corina Steele" }
suite.check("a reputation not reached", Says({ itemID = 1001, sources = { vendor },
    needs = { standing = "Honored", faction = "Stormwind" } }, "Honored with Stormwind"))
suite.check("a level not reached", Says({ itemID = 1001, sources = { vendor }, at = 22 }, "level 22"))
suite.check("only another player's craft", Says({ itemID = 1001,
    sources = { { kind = "craft", state = "other" } } }, "another player"))
suite.check("an alt's craft can be followed", Quest.CanFollow({ itemID = 1001,
    sources = { { kind = "craft", state = "alt" } } }) ~= nil)
local before = Quest:Current().itemID
UI:Follow({ itemID = 1002, link = "item:1002", sources = { vendor }, at = 22 })
suite.check("a click on one changes nothing", Quest:Current().itemID == before)
suite.check("and the chat says why", env.ChatText():find("can't be an upgrade quest yet: you can wear it from level 22", 1, true) ~= nil)

-- Turned off and on again by hand, the picks are still there.
Quest:SetEnabled(false)
suite.check("off, nothing is marked", not Quest:IsFollowing(1001))
suite.check("off, the panel hides", not Panel.frame:IsShown())

suite.done()
