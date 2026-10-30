-- "Current step only" on the upgrade quest panel (the owner asked
-- 2026-10-13): ticked, the panel shows only the step to do now and grows
-- shorter; unticked, every step as before. Ticking it looks for nothing
-- again.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("queststeponly")

local function Agi(n) return { ITEM_MOD_AGILITY_SHORT = n } end
local function Gear(loc, n) return { loc = loc, class = 4, subclass = 2, stats = Agi(n) } end

local ITEMS = {
    ["item:900"] = Gear("INVTYPE_CHEST", 10),
    ["item:1002"] = Gear("INVTYPE_CHEST", 30),
}

local ns = env.Load()
_G.UnitClass = function() return "Hunter", "HUNTER", 3 end
_G.UnitFactionGroup = function() return "Horde", "Horde" end
_G.UnitRace = function() return "Tauren", "Tauren", 6 end
_G.UnitLevel = function() return 10 end
_G.GetRealZoneText = function() return "Mulgore" end
env.InstallItems(ITEMS, { [5] = "item:900" }, { [0] = {} }, 10)

local LOG = {
    { title = "Mulgore", isHeader = true },
    { title = "Supervisor Fizsprocket", questID = 765, level = 12 },
}
local objectives = {
    { text = "Fizsprocket's Clipboard: 0/1", finished = false },
    { text = "Venture Co. Worker slain: 3/12", finished = false },
}
local inLog, ready, watched, opened = {}, {}, {}, nil
local finds = 0
_G.C_QuestLog = {
    IsQuestFlaggedCompleted = function() return false end,
    IsOnQuest = function(id) return inLog[id] == true end,
    ReadyForTurnIn = function(id) return ready[id] == true end,
    IsComplete = function(id) return ready[id] == true end,
    GetNumQuestLogEntries = function() return inLog[765] and #LOG or 1 end,
    GetInfo = function(index) return LOG[index] end,
    GetLogIndexForQuestID = function(id) finds = finds + 1 return inLog[id] and id == 765 and 2 or nil end,
    GetQuestObjectives = function(id) return id == 765 and objectives or nil end,
    GetQuestWatchType = function(id) return watched[id] and 0 or nil end,
    AddQuestWatch = function(id) watched[id] = true end,
    RemoveQuestWatch = function(id) watched[id] = nil end,
}
_G.QuestMapFrame_OpenToQuestDetails = function(id) opened = id end

local S = ns.Sources
ns.Crafts.ITEMS = {}
ns.RollData.ITEMS = {}
S.ZONES = { [215] = "Mulgore" }
S.NPCS = {}
S.QUESTS = { [765] = { "Supervisor Fizsprocket", 5, 12, 178, 0, "Morin Cloudstalker", 215, 51.9, 59.6, "" } }
S.DUNGEONS = {}
S.BOSSES = {}
S.FOREVER = {}
S.STARTS = {}
S.ITEMS = { [1002] = { 5, 12, 0, 0, 0, q = { 765 } } }
S.ENDS = {
    [765] = { "npc", "Morin Cloudstalker", "Mulgore", 51.9, 59.6,
        o = { "mob", "Supervisor Fizsprocket", "Mulgore", 64.9, 43.3, "Fizsprocket's Clipboard" } },
}

local Quest, Panel = ns.UpgradeQuest, ns.QuestPanel

local function ShownSteps()
    local count = 0
    for _, row in ipairs(Panel.steps or {}) do
        if row:IsShown() then count = count + 1 end
    end
    return count
end

suite.check("off by default", ns.db.upgradeQuestStepOnly == false and not Quest:StepOnly())

ns.HandleSlash("quest quest")
suite.check("the quest reward is picked", Quest:Current() and Quest:Current().itemID == 1002)
local steps = Quest:Steps()
suite.check("the quest has several steps", #steps > 1, #steps)

Panel:Refresh()
local fullHeight = Panel.frame:GetHeight()
suite.check("unticked, every step shows", ShownSteps() == #steps, ShownSteps())

local scans = 0
local scan = ns.Finder.Scan
ns.Finder.Scan = function(...) scans = scans + 1 return scan(...) end
local refresh = Quest.Refresh
local refreshes = 0
if refresh then Quest.Refresh = function(...) refreshes = refreshes + 1 return refresh(...) end end

local function Option(text)
    for _, line in ipairs(Panel:OptionLines()) do
        if line.text == text then return line end
    end
end
suite.check("Options has the line", Option("Current Step Only") ~= nil and not Option("Current Step Only").checked)
Option("Current Step Only").run()
suite.check("ticking saves it", ns.db.upgradeQuestStepOnly == true and Quest:StepOnly())
suite.check("and looks for nothing again", scans == 0 and refreshes == 0, scans .. " " .. refreshes)

Panel:Refresh()
suite.check("ticked, one step shows", ShownSteps() == 1, ShownSteps())
local only
for _, row in ipairs(Panel.steps) do if row:IsShown() then only = row end end
suite.check("and it is the step to do now", only and rawget(only, "now") == true)
suite.check("the panel is shorter", Panel.frame:GetHeight() < fullHeight,
    Panel.frame:GetHeight() .. " < " .. fullHeight)
suite.check("the item and buttons stay", Panel.item:IsShown() and Panel.skipButton:IsShown())
suite.check("the line shows ticked", Option("Current Step Only").checked == true)

Quest:SetStepOnly(false)
Panel:Refresh()
suite.check("unticked again, every step is back", ShownSteps() == #steps, ShownSteps())
suite.check("and the panel its height", Panel.frame:GetHeight() == fullHeight)

ns.Finder.Scan = scan
if refresh then Quest.Refresh = refresh end
suite.done()
