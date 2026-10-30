-- The Quest log tab on the upgrade quest panel: the character's quests read
-- from the log either way the client offers, listed by zone with their
-- objectives, tracked from a tick box, with a right-click menu, quest item
-- buttons that never move in combat, and the game's tracker hidden only
-- while asked and never in combat.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("questlog")

local ns = env.Load()
_G.UnitClass = function() return "Hunter", "HUNTER", 3 end
_G.UnitLevel = function() return 24 end
_G.GetRealZoneText = function() return "Duskwood" end

local S = ns.Sources
S.ENDS = {
    [101] = { "npc", "Chef Grual", "Duskwood", 73.8, 43.5, o = { "mob", "Lean Wolf", "Duskwood", 40.0, 50.0 } },
    [102] = { "npc", "Commander Althea Ebonlocke", "Duskwood", 73.6, 46.8 },
}
S.QUESTS = S.QUESTS or {}

-- A retail-style quest log: headings and quests by index, objectives and
-- tracking by quest ID.
local watched = { [101] = true, [103] = true }
local reads = 0
local LOG = {
    { title = "Duskwood", isHeader = true },
    { title = "The Night Watch", questID = 102, level = 24 },
    { title = "Seasoned Wolf Kabobs", questID = 101, level = 23 },
    { title = "Westfall", isHeader = true },
    { title = "The Defias Brotherhood", questID = 103, level = 22, suggestedGroup = 5 },
}
local OBJECTIVES = {
    [102] = { { text = "Skeletal Fiend slain: 15/15", finished = true }, { text = "Skeletal Horror slain: 9/15", finished = false } },
    [101] = { { text = "Lean Wolf Flank: 5/5", finished = true } },
    [103] = { { text = "Head of VanCleef: 0/1", finished = false } },
}
local selected, abandonSet, popup, pushed = nil, nil, nil, 0
_G.C_QuestLog = {
    GetNumQuestLogEntries = function() reads = reads + 1 return #LOG end,
    GetInfo = function(index) return LOG[index] end,
    GetQuestObjectives = function(id) return OBJECTIVES[id] end,
    GetQuestWatchType = function(id) return watched[id] and 0 or nil end,
    AddQuestWatch = function(id) watched[id] = true end,
    RemoveQuestWatch = function(id) watched[id] = nil end,
    ReadyForTurnIn = function(id) return id == 101 end,
    IsComplete = function(id) return id == 101 end,
    GetSelectedQuest = function() return selected end,
    SetSelectedQuest = function(id) selected = id end,
    SetAbandonQuest = function() abandonSet = selected end,
    IsPushableQuest = function() return true end,
}
_G.GetQuestLogSpecialItemInfo = function(index)
    if index == 2 then return "|cffffffff|Hitem:7297::::::::|h[Morbent's Bane]|h|r", 134400, 1 end
end
_G.StaticPopup_Show = function(which, text) popup = { which, text } end
_G.QuestLogPushQuest = function() pushed = pushed + 1 end
_G.GetNumGroupMembers = function() return 0 end

-- Secure frames: remember the template and the attributes they are given.
local secure = {}
local realCreate = _G.CreateFrame
_G.CreateFrame = function(kind, name, parent, template)
    local frame = realCreate(kind, name, parent, template)
    frame._template = template
    frame._attributes = {}
    frame.SetAttribute = function(self, key, value) self._attributes[key] = value end
    frame._alpha = 1
    frame.SetAlpha = function(self, value) self._alpha = value end
    if template == "SecureActionButtonTemplate" then secure[#secure + 1] = frame end
    return frame
end

local combat = false
_G.InCombatLockdown = function() return combat end

local function Fire(event, ...)
    ns.eventFrame._scripts.OnEvent(ns.eventFrame, event, ...)
end

local Log, Tab, Panel = ns.QuestLog, ns.QuestLogUI, ns.QuestPanel

--------------------------------------------------------------------------------
-- Reading the log
--------------------------------------------------------------------------------

local data = Log:Read()
suite.check("read the newer way", data.how == "new", data.how)
suite.check("two zones", #data.zones == 2 and data.zones[1].title == "Duskwood" and data.zones[2].title == "Westfall")
suite.check("three quests, two tracked", data.count == 3 and data.tracked == 2, data.count .. "/" .. data.tracked)
local watch = data.zones[1].quests[1]
suite.check("a quest keeps its ID, level and zone", watch.questID == 102 and watch.level == 24 and watch.zone == "Duskwood")
suite.check("objectives as the log words them",
    #watch.objectives == 2 and watch.objectives[1].done and not watch.objectives[2].done)
suite.check("its item button", watch.item and watch.item.itemID == 7297, watch.item and watch.item.link)
local kabobs = data.zones[1].quests[2]
suite.check("a finished quest says so", kabobs.complete == true and not watch.complete)
suite.check("a group quest is tagged", data.zones[2].quests[1].tag == "Group (5)", data.zones[2].quests[1].tag)
suite.check("the place to go: the hand-in once done", Log.Place(kabobs).name == "Chef Grual")
suite.check("who to hand it to", Log.HandIn(kabobs) == "Chef Grual")

-- An arrow aimed at a place with no quest (Show the trainer's weapon master)
-- did not come from the log, so reading the log never puts it away.
do
    local arrow = ns.QuestArrow
    local forgot = false
    local free, forget, savedData = arrow.free, arrow.ForgetQuest, Tab.data
    arrow.free = { free = true, title = "Learn Staves", place = { zone = "Orgrimmar" } }
    arrow.ForgetQuest = function() forgot = true end
    Tab.data = data
    Tab:ForgetGone()
    suite.check("an aim with no quest stays when the log is read", not forgot)
    arrow.free, arrow.ForgetQuest, Tab.data = free, forget, savedData
end
suite.check("quests 5 levels up are red, a level under is yellow",
    Log.Difficulty(29) == "red" and Log.Difficulty(23) == "yellow" and Log.Difficulty(14) == "grey"
    and Log.Difficulty(18) == "green", Log.Difficulty(18))

-- A classic client: the old calls, by log index.
do
    local saved = _G.C_QuestLog
    _G.C_QuestLog = nil
    _G.GetNumQuestLogEntries = function() return 3 end
    _G.GetQuestLogTitle = function(index)
        if index == 1 then return "Elwynn Forest", 0, 0, 1, nil end
        if index == 2 then return "Wolves Across the Border", 6, 0, nil, nil, 1, nil, 33 end
        if index == 3 then return "A Folded Zone", 0, 0, true, true end
    end
    _G.GetNumQuestLeaderBoards = function() return 1 end
    _G.GetQuestLogLeaderBoard = function() return "Tough Wolf Meat: 8/8", "item", 1 end
    local classicWatched = {}
    _G.IsQuestWatched = function(index) return classicWatched[index] == true end
    _G.AddQuestWatch = function(index) classicWatched[index] = true end
    _G.RemoveQuestWatch = function(index) classicWatched[index] = nil end
    local old = Log:Read()
    suite.check("classic: read the old way", old.how == "old")
    local wolves = old.zones[1].quests[1]
    suite.check("classic: a done quest (complete = 1)", wolves and wolves.complete == true and wolves.questID == 33)
    suite.check("classic: objectives from the leader board", wolves.objectives[1].done == true)
    suite.check("classic: a heading folded in the game's log", old.zones[2].collapsed == true)
    suite.check("classic: tracking by log index", Log:SetTracked(wolves, true) and classicWatched[2] == true)
    _G.C_QuestLog = saved
    _G.GetNumQuestLogEntries, _G.GetQuestLogTitle, _G.GetNumQuestLeaderBoards = nil, nil, nil
    _G.GetQuestLogLeaderBoard, _G.IsQuestWatched, _G.AddQuestWatch, _G.RemoveQuestWatch = nil, nil, nil, nil
end

do
    local saved = _G.C_QuestLog
    _G.C_QuestLog = nil
    suite.check("no quest log calls: nothing read, nothing raised", Log:Read().how == nil)
    _G.C_QuestLog = saved
end

--------------------------------------------------------------------------------
-- The tab
--------------------------------------------------------------------------------

ns.db.upgradeQuest = true
Tab:OnEnable()
Panel:Build()
suite.check("the panel is wider for five tabs", Panel.WIDTH == 384 and #Panel.tabs == 5)
local logButton = Panel.tabs[5]
logButton:GetScript("OnClick")(logButton)
suite.check("clicking Quest log shows it", Panel:ShowsLog() and ns.charDB.questLogTab == true)
suite.check("the header names it", Panel.title:GetText() == "Quest log")
suite.check("and counts the quests", Panel.progress:GetText() == "3 quests, 2 tracked", Panel.progress:GetText())
suite.check("its tab is lit, the source tabs are not", logButton.shown and not Panel.tabs[1].shown)
suite.check("the upgrade quest's own list is hidden", not Panel.body:IsShown())
suite.check("the tab's view shows", Tab.view:IsShown())

local rows = Tab.shown
suite.check("three rows", #rows == 3, #rows)
suite.check("the level and title", rows[1].title:GetText():find("[24] The Night Watch", 1, true), rows[1].title:GetText())
suite.check("a done objective is ticked green",
    rows[1].objectives[1]:GetText():find("Skeletal Fiend slain: 15/15", 1, true)
    and rows[1].objectives[1]._color[1] < 0.5)
suite.check("a finished quest says who to hand it to",
    rows[2].objectives[1]:GetText() == "- Ready to hand in to Chef Grual", rows[2].objectives[1]:GetText())
suite.check("tracked quests are ticked", rows[2].track:GetChecked() and not rows[1].track:GetChecked())
suite.check("the zone you're in is green", Tab.heads[1].here == true and not Tab.heads[2].here)

-- Rows are filled again only when their quest changed.
local titleSets = 0
local realSet = rows[1].title.SetText
rows[1].title.SetText = function(self, text)
    titleSets = titleSets + 1
    return realSet(self, text)
end
Panel:Refresh()
suite.check("an unchanged quest's row is left as drawn", titleSets == 0, titleSets)

-- Tracking from the tick box.
rows[1].track:GetScript("OnClick")(rows[1].track)
suite.check("ticking a quest tracks it", watched[102] == true)
suite.check("and the row shows it", Tab.shown[1].track:GetChecked() == true)

-- Tracked only.
Tab.trackedBox:GetScript("OnClick")(Tab.trackedBox)
suite.check("Tracked only is saved", ns.db.questLogTrackedOnly == true)
rows[2].track:GetScript("OnClick")(rows[2].track)
suite.check("untracked quests drop out", #Tab.shown == 2, #Tab.shown)
Tab.trackedBox:GetScript("OnClick")(Tab.trackedBox)
suite.check("and come back when unticked", #Tab.shown == 3)

-- Folding a zone.
Tab.heads[1]:GetScript("OnClick")(Tab.heads[1])
suite.check("a heading folds its zone", ns.charDB.questLogFolded.Duskwood == true and #Tab.shown == 1)
Tab:FoldAll()
suite.check("Fold all folds the rest", #Tab.shown == 0 and Tab.foldButton.label:GetText() == "Open all", #Tab.shown .. Tab.foldButton.label:GetText())
Tab:FoldAll()
suite.check("and opens them all again", #Tab.shown == 3 and Tab.foldButton.label:GetText() == "Fold all")

-- With Tracked only, Fold all acts on the zones listed: when every listed
-- zone is folded it reads "Open all", and a click opens them.
do
    Tab.trackedBox:GetScript("OnClick")(Tab.trackedBox)
    rows = Tab.shown
    local listed = {}
    for _, title in ipairs(Tab.listedZones) do listed[title] = true end
    for _, zone in ipairs(Tab.data.zones) do
        ns.charDB.questLogFolded[zone.title] = listed[zone.title] or nil
    end
    Tab:Changed()
    local word = Tab.foldButton.label:GetText()
    Tab:FoldAll()
    suite.check("Tracked only: Fold all opens the listed zones", word == "Open all" and #Tab.shown > 0,
        word .. " " .. #Tab.shown)
    for title in pairs(ns.charDB.questLogFolded) do ns.charDB.questLogFolded[title] = nil end
    Tab.trackedBox:GetScript("OnClick")(Tab.trackedBox)
    Tab:Changed()
    suite.check("and unticked, all three show again", #Tab.shown == 3, #Tab.shown)
end

-- Events while the tab is hidden read nothing.
Panel.tabs[1]:GetScript("OnClick")(Panel.tabs[1])
suite.check("a source tab takes over from the log", not Panel:ShowsLog() and not Tab.view:IsShown())
reads = 0
Fire("QUEST_LOG_UPDATE")
Fire("QUEST_LOG_UPDATE")
suite.check("quest events while the tab is hidden read nothing", reads == 0, reads)
ns.HandleSlash("quest log")
suite.check("/beq quest log brings it back", Panel:ShowsLog() and reads == 1, reads)
Fire("UNIT_QUEST_LOG_CHANGED", "party1")
suite.check("another unit's quest log is not ours", reads == 1, reads)

--------------------------------------------------------------------------------
-- The menu
--------------------------------------------------------------------------------

local night = Tab.shown[1].quest
local function Labels(quest)
    local list = {}
    for _, item in ipairs(Tab:MenuFor(quest)) do list[#list + 1] = item[1] end
    return table.concat(list, ", ")
end
suite.check("the menu, alone", Labels(night) == "Show on Map, Point the arrow here, Untrack, Open in quest log, Abandon quest",
    Labels(night))
_G.GetNumGroupMembers = function() return 2 end
suite.check("Share shows in a group", Labels(night):find("Share with party", 1, true))
Tab.shown[1]:GetScript("OnClick")(Tab.shown[1], "RightButton")
suite.check("right-click opens it", Tab.menu:IsShown() and Tab.menu.title:GetText() == "The Night Watch")
do
    local oneLine = Tab.menu:GetHeight()
    Tab.menu.title.GetStringHeight = function() return 36 end
    Tab.shown[1]:GetScript("OnClick")(Tab.shown[1], "RightButton")
    suite.check("a long quest title wraps and the menu grows under it",
        Tab.menu:GetHeight() > oneLine + 20, Tab.menu:GetHeight())
    Tab.menu.title.GetStringHeight = nil
    Tab.shown[1]:GetScript("OnClick")(Tab.shown[1], "RightButton")
end
local share
for _, entry in ipairs(Tab.menu.entries) do
    if entry:IsShown() and entry.label:GetText() == "Share with party" then share = entry end
end
selected = 555
share:GetScript("OnClick")(share)
suite.check("Share pushes the quest", pushed == 1 and not Tab.menu:IsShown())
suite.check("and puts the log's own pick back", selected == 555, selected)
Tab:Act("abandon", night)
suite.check("Abandon goes through the game's own box", abandonSet == 102 and popup[1] == "ABANDON_QUEST"
    and popup[2] == "The Night Watch")

-- A quest the game's log cannot be made to pick is never shared or
-- abandoned: the game would act on whichever quest it had picked.
do
    local unpickable = { title = "No ID", index = 9 }
    abandonSet, pushed = nil, 0
    popup[1], popup[2] = nil, nil
    suite.check("an unpickable quest is not abandoned", ns.QuestLog:Abandon(unpickable) == false
        and abandonSet == nil and popup[1] == nil)
    suite.check("nor shared", ns.QuestLog:Share(unpickable) == false and pushed == 0, pushed)
end

--------------------------------------------------------------------------------
-- The arrow
--------------------------------------------------------------------------------

ns.Waypoints.MapFor = function(_, zone) return zone == "Duskwood" and 1431 or nil end
Tab:Act("arrow", night)
suite.check("the arrow follows the quest", ns.QuestArrow.IsOn() and ns.QuestArrow:FreeQuest().questID == 102)
local places = ns.QuestArrow:Places()
suite.check("pointing at its hand-in (no objective spot known)",
    #places == 1 and places[1].name == "Commander Althea Ebonlocke" and places[1].forQuest == "The Night Watch")
Fire("QUEST_REMOVED", 102)
suite.check("a quest leaving the log lets the arrow go", ns.QuestArrow:FreeQuest() == nil)
Tab:Act("arrow", night)
ns.QuestArrow:Aim(1)
suite.check("aiming at an upgrade quest step lets it go too", ns.QuestArrow:FreeQuest() == nil)

-- The last objective done: the arrow moves on to whoever takes it back by
-- itself, without the quest being clicked again (a player found it stuck
-- on the objective until clicked, 2026-10-10).
do
    local ready = false
    local readyFn, completeFn = _G.C_QuestLog.ReadyForTurnIn, _G.C_QuestLog.IsComplete
    _G.C_QuestLog.ReadyForTurnIn = function(id) return id == 101 and ready end
    _G.C_QuestLog.IsComplete = function(id) return id == 101 and ready end
    ns.QuestLog:Aim({ questID = 101, title = "Seasoned Wolf Kabobs" })
    local first = ns.QuestArrow:Places()[1]
    suite.check("a quest still to do points at its objective", first and first.name == "Lean Wolf",
        first and first.name)
    ready = true
    first = ns.QuestArrow:Places()[1]
    suite.check("done, it points at the hand-in on its own", first and first.name == "Chef Grual",
        first and first.name)
    _G.C_QuestLog.ReadyForTurnIn, _G.C_QuestLog.IsComplete = readyFn, completeFn
    ns.QuestArrow:ForgetQuest(101)
end

--------------------------------------------------------------------------------
-- Quest item buttons
--------------------------------------------------------------------------------

Tab:CloseMenu()
Panel.frame:Show()
Tab.viewHeight = 400
local itemRow = Tab.shown[1]
itemRow.spot._left, itemRow.spot._top = 600, 500
Tab:PlaceItems()
local button = secure[1]
suite.check("a secure button for the quest's item", button ~= nil and button._template == "SecureActionButtonTemplate")
suite.check("set to use that item", button._attributes.type == "item" and button._attributes.item == "item:7297")
suite.check("placed over its row, not inside the panel", button._parent == UIParent and button._point[4] == 600
    and button._point[5] == 500 and button:IsShown())

combat = true
itemRow.spot._left = 620
Tab:PlaceItems()
suite.check("in combat it is not moved", button._point[4] == 600 and button:IsShown())
suite.check("but fades while out of place", button._alpha == 0)
combat = false
Fire("PLAYER_REGEN_ENABLED")
suite.check("and is put back after the fight", button._point[4] == 620 and button._alpha == 1)

Panel.frame:Hide()
Tab:PlaceItems()
suite.check("the panel hidden: the button goes too", not button:IsShown())
Panel.frame:Show()

--------------------------------------------------------------------------------
-- The game's tracker
--------------------------------------------------------------------------------

-- A game frame that records its alpha and mouse, and fails the test if
-- anything calls Hide or Show on it: that would run the game's own code as
-- this addon and taint Edit Mode's layout.
local touched = false
local function GameFrame(fields)
    local frame = env.Stub(fields)
    frame._alpha, frame._mouse = 1, frame._mouse ~= false
    frame._kids = frame._kids or {}
    frame.Hide = function() touched = true end
    frame.Show = function() touched = true end
    frame.SetAlpha = function(self, value) self._alpha = value end
    frame.GetAlpha = function(self) return self._alpha end
    -- The retail engine's calls, clicks and mouse-over apart.
    frame.IsMouseClickEnabled = function(self) return self._mouse end
    frame.IsMouseMotionEnabled = function(self) return self._mouse end
    frame.SetMouseClickEnabled = function(self, on)
        if combat and self._protected then error("blocked in combat") end
        self._mouse = on and true or false
    end
    frame.SetMouseMotionEnabled = frame.SetMouseClickEnabled
    frame.IsProtected = function(self) return self._protected end
    frame.GetChildren = function(self) return unpack(self._kids) end
    return frame
end

local line = GameFrame({ _shown = true, _protected = false })
local quiet = GameFrame({ _shown = true, _mouse = false })
local tracker = GameFrame({ _shown = true, _protected = false, _mouse = false, _kids = { line, quiet } })
local function Hidden() return tracker._alpha == 0 and not line._mouse end
local function Back() return tracker._alpha == 1 and line._mouse and not quiet._mouse end
_G.ObjectiveTrackerFrame = tracker
Tab:ApplyTracker()
suite.check("off unless ticked: the game's tracker stays", Back())
Tab:SetHidesTracker(true)
suite.check("ticked: out of sight while the panel is up", Hidden() and ns.db.hideQuestTracker == true)
suite.check("its lines let clicks through", not line._mouse and Tab:TrackerHidden("ObjectiveTrackerFrame"))

local added = GameFrame({ _shown = true })
tracker._kids[3] = added
Fire("QUEST_WATCH_LIST_CHANGED")
suite.check("a line the game adds later lets clicks through too", not added._mouse)

Panel.frame:Hide()
Tab:OnPanelShown(false)
suite.check("the panel closed: the game's tracker comes back", Back() and added._mouse)
Panel.frame:Show()
Tab:OnPanelShown(true)
suite.check("and goes when it opens", Hidden())

-- A protected line keeps the mouse it had until the fight ends.
Panel.frame:Hide()
Tab:OnPanelShown(false)
combat, line._protected = true, true
Panel.frame:Show()
Tab:OnPanelShown(true)
suite.check("in combat the tracker still goes out of sight", tracker._alpha == 0 and line._mouse)
combat = false
Fire("PLAYER_REGEN_ENABLED")
suite.check("and its protected line lets clicks through once the fight ends", Hidden())
line._protected = false

Tab:SetHidesTracker(false)
suite.check("unticked: it comes back", Back() and ns.db.hideQuestTracker == false)
suite.check("the game's tracker is never hidden or shown by the addon", not touched)

--------------------------------------------------------------------------------
-- Settings and the probe
--------------------------------------------------------------------------------

ns.SettingsUI:Show()
local controls = ns.SettingsUI.controls
controls.hideQuestTracker:GetScript("OnClick")(controls.hideQuestTracker)
suite.check("Settings ticks the same setting", ns.db.hideQuestTracker == true and Hidden())
controls.hideQuestTracker:GetScript("OnClick")(controls.hideQuestTracker)
suite.check("and unticks it", ns.db.hideQuestTracker == false and Back())
suite.check("the probe describes the log", Log:Describe():find("3 quests in 2 headings", 1, true), Log:Describe())

--------------------------------------------------------------------------------
-- The Blizzard window style
--------------------------------------------------------------------------------

-- A fresh load with the style picked: the tab builds, fills and wears the
-- game's colours, tick boxes and scroll knob.
do
    local questLog, itemInfo = _G.C_QuestLog, _G.GetQuestLogSpecialItemInfo
    local blizz = env.Load()
    _G.BlackthornesEquipmentDB.windowStyle = "blizzard"
    blizz.LoadSavedVariables()
    local Look = blizz.BlizzardLook
    -- The pretend client has all of the game's art (test_blizzardlook covers
    -- a client without it).
    Look.HasArt = function() return true end
    Look.Style()
    _G.C_QuestLog, _G.GetQuestLogSpecialItemInfo = questLog, itemInfo
    _G.UnitClass = function() return "Hunter", "HUNTER", 3 end
    _G.UnitLevel = function() return 24 end
    _G.GetRealZoneText = function() return "Duskwood" end
    for id in pairs(watched) do watched[id] = nil end
    watched[101], watched[103] = true, true

    suite.check("Blizzard style: picked", Look.On())
    -- Count the tick boxes dressed: Tracked only, Hide the tracker, a row each.
    local dressedBoxes, checkbox = 0, Look.Checkbox
    Look.Checkbox = function(...)
        local dressed = checkbox(...)
        if dressed then dressedBoxes = dressedBoxes + 1 end
        return dressed
    end
    blizz.db.upgradeQuest = true
    blizz.QuestLogUI:OnEnable()
    blizz.QuestPanel:Build()
    blizz.HandleSlash("quest log")
    local BTab = blizz.QuestLogUI
    suite.check("Blizzard style: the tab shows", blizz.QuestPanel:ShowsLog() and BTab.view:IsShown())
    suite.check("Blizzard style: three rows", #BTab.shown == 3, #BTab.shown)
    local glass = Look.PALETTE.glass
    local band = { blizz.Theme.Unpack("glass") }
    suite.check("Blizzard style: plain rows in the game's colours",
        math.abs(band[1] - glass[1]) < 0.001, band[1])
    suite.check("Blizzard style: tick boxes wear the game's art", dressedBoxes >= 5, dressedBoxes)
    suite.check("Blizzard style: the scroll thumb is the game's knob", BTab.bar.thumb.blizzard == true)
    suite.check("Blizzard style: the footer's main button wears the game's red",
        rawget(BTab.mapButton or {}, "blizzardFace") ~= nil, tostring(BTab.mapButton))
end

suite.done()
