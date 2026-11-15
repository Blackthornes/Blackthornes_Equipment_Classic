-- Keeping the game smooth: the finder judges each item once until something
-- that changes a verdict happens, item answers nobody asked for set off no
-- scan, and /beq perf says what took longest when the game still hitches.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("speed")

local function Agi(n) return { ITEM_MOD_AGILITY_SHORT = n } end
local function Chest(n) return { loc = "INVTYPE_CHEST", class = 4, subclass = 2, stats = Agi(n) } end

local ITEMS = {
    ["item:900"] = Chest(10),      -- worn
    ["item:901"] = Chest(50),      -- put on later
    ["item:1001"] = Chest(15),
    ["item:1002"] = Chest(20),
    ["item:1003"] = Chest(30),
}

local ns = env.Load()
_G.UnitClass = function() return "Hunter", "HUNTER", 3 end
_G.UnitFactionGroup = function() return "Alliance", "Alliance" end
_G.UnitRace = function() return "Human", "Human", 1 end
env.InstallItems(ITEMS, { [5] = "item:900" }, {}, 20)

local S = ns.Sources
ns.Crafts.ITEMS = {}
ns.RollData.ITEMS = {}
S.ZONES = { [12] = "Elwynn Forest" }
S.NPCS = { [1] = { "Corina Steele", 12, 41.5, 65.9, "A" } }
S.QUESTS, S.DUNGEONS, S.BOSSES, S.FOREVER = {}, {}, {}, {}
S.ITEMS = {
    [1001] = { 15, 15, 0, 0, 100, v = { 1, 0 } },
    [1002] = { 15, 15, 0, 0, 100, v = { 1, 0 } },
    [1003] = { 15, 15, 0, 0, 100, v = { 1, 0 } },
}

local Finder, Compare = ns.Finder, ns.Compare
local realJudge, judges = Compare.Judge, 0
Compare.Judge = function(...) judges = judges + 1 return realJudge(...) end

--------------------------------------------------------------------------------
-- Each item is judged once
--------------------------------------------------------------------------------

local found = Finder:Scan()
suite.check("the first scan finds the three upgrades", found and found.count == 3, found and found.count)
suite.check("and judges each once", judges == 3, judges)
judges = 0
for _ = 1, 10 do Finder:Scan() end
suite.check("ten more scans judge nothing again", judges == 0, judges)
found = Finder:Scan()
suite.check("and still find the same upgrades", found.count == 3 and found.slots[5][1].itemID == 1003)

env.worn[5] = "item:901"
judges = 0
found = Finder:Scan()
suite.check("new gear worn judges them again", judges == 3, judges)
suite.check("and none beats it now", found.count == 0, found.count)
env.worn[5] = "item:900"
Finder:Scan()

judges = 0
_G.UnitLevel = function() return 21 end
Finder:Scan()
suite.check("a level up judges them again", judges == 3, judges)

ns.Weights:Changed()
judges = 0
Finder:Scan()
suite.check("changed stat weights judge them again", judges == 3, judges)

judges = 0
Finder:ForgetVerdicts()
Finder:Scan()
suite.check("new talents or weapon skills judge them again", judges == 3, judges)

-- An item whose details have not arrived is asked again next time.
ITEMS["item:1004"] = nil
S.ITEMS[1004] = { 15, 15, 0, 0, 100, v = { 1, 0 } }
judges = 0
found = Finder:Scan()
suite.check("an item not loaded yet is waited on", found.waiting == 1, found.waiting)
suite.check("and asked for", Finder:Asked(1004) and not Finder:Asked(4242))
ITEMS["item:1004"] = Chest(40)
found = Finder:Scan()
suite.check("once loaded it is judged and listed", found.slots[5][1].itemID == 1004, found.slots[5][1].itemID)

--------------------------------------------------------------------------------
-- Item answers nobody asked for
--------------------------------------------------------------------------------

local Quest = ns.UpgradeQuest
ns.db.upgradeQuest = true
local updates = 0
local realUpdate = Quest.Update
Quest.Update = function(...) updates = updates + 1 return realUpdate(...) end
Quest.waiting, Quest.updating = false, false
for _ = 1, 20 do Quest:OnEvent("GET_ITEM_INFO_RECEIVED", 4242, true) end
suite.check("twenty answers about a chat link look at nothing", updates == 0, updates)
Quest:OnEvent("GET_ITEM_INFO_RECEIVED", 1004, true)
suite.check("an answer a scan asked for waits for the rest of the burst", updates == 0, updates)
ns.Finder:AnswersSettled()
suite.check("and looks again once they settle", updates == 1, updates)
Quest.Update = realUpdate

--------------------------------------------------------------------------------
-- The full scan runs a slice per frame
--------------------------------------------------------------------------------

-- More gear, so one frame's share cannot cover it all.
for id = 2001, 2060 do
    ITEMS["item:" .. id] = Chest(10 + id % 40)
    S.ITEMS[id] = { 15, 15, 0, 0, 100, v = { 1, 0 } }
end
local frames, realAfter = {}, _G.C_Timer.After
_G.C_Timer.After = function(_, fn) frames[#frames + 1] = fn end
local tick = 0
_G.debugprofilestop = function() tick = tick + 1 return tick end   -- 1 ms per look at the clock
ns.Perf:Reset()

ns.charDB.upgradeQuestTabs, ns.charDB.upgradeQuestTab, ns.charDB.upgradeQuest = nil, nil, nil
Quest.states = {}
Quest.rescan = true
ns.Finder:MarkStale()
Quest:Update()
suite.check("the quest waits while the scan runs", Quest.state == "waiting" and Finder:Scanning(), Quest.state)
local slices = 0
while #frames > 0 and slices < 500 do
    local fn = table.remove(frames, 1)
    fn()
    if Finder:Scanning() then slices = slices + 1 end
end
suite.check("the scan took several frames", slices > 3, slices)
suite.check("and then the quest is picked", not Finder:Scanning() and Quest:Current() ~= nil
    and Quest.state == "active", Quest.state)
local slice = ns.Perf.rows["Finder:background slice"]
suite.check("no frame's slice ran long", slice and slice.worst <= 12, slice and slice.worst)

-- Gear changing mid-scan makes the result stale; the quest looks again.
frames = {}
Quest.rescan = true
ns.Finder:MarkStale()
Quest:Skip()
suite.check("a skip starts a new scan", Finder:Scanning())
env.worn[5] = "item:901"
ns.Finder:MarkStale()
while #frames > 0 do table.remove(frames, 1)() end
suite.check("a scan made stale mid-way is not used", Quest:Current() == nil and not Finder:Scanning(),
    Quest:Current() and Quest:Current().itemID)

_G.C_Timer.After = realAfter
_G.debugprofilestop = nil
env.worn[5] = "item:900"

--------------------------------------------------------------------------------
-- /beq perf
--------------------------------------------------------------------------------

local Perf = ns.Perf
local now = 0
_G.debugprofilestop = function() return now end

local listener = { moduleName = "Listener" }
ns.RegisterEvent(listener, "PLAYER_REGEN_ENABLED", function() now = now + 120 end)
ns.eventFrame:GetScript("OnEvent")(ns.eventFrame, "PLAYER_REGEN_ENABLED")
local row = Perf.rows["Listener on PLAYER_REGEN_ENABLED"]
suite.check("an event handler is timed", row and row.worst == 120 and row.runs == 1,
    row and row.worst)

local slow = { moduleName = "Slow" }
function slow:Work(ms) now = now + ms return "done" end
Perf:Wrap(slow, "Work")
suite.check("a wrapped method still answers", slow:Work(30) == "done")
slow:Work(250)
row = Perf.rows["Slow:Work"]
suite.check("and keeps its worst and its total", row.worst == 250 and row.total == 280 and row.runs == 2)

function slow:Broken() error("boom", 0) end
Perf:Wrap(slow, "Broken")
local ok, err = pcall(slow.Broken, slow)
suite.check("an error passes through unchanged", not ok and err == "boom", err)

Perf:WrapAll()
suite.check("the finder's scan is watched", Perf.rows["Finder:Scan"] == nil and (function()
    Finder:Scan()
    return Perf.rows["Finder:Scan"] ~= nil
end)())

env.chat = {}
ns.HandleSlash("perf")
local text = env.ChatText()
suite.check("/beq perf lists the slowest first", text:find("Slow:Work  worst 250 ms, 2 runs", 1, true) ~= nil
    and text:find("Slow:Work", 1, true) < text:find("Listener on", 1, true), text)
ns.HandleSlash("perf clear")
suite.check("/beq perf clear starts over", Perf.rows["Slow:Work"] == nil
    and Perf.rows["Listener on PLAYER_REGEN_ENABLED"] == nil)
Perf:Reset()
env.chat = {}
Perf:Report(10)
suite.check("and says when nothing is measured yet", env.ChatText():find("nothing measured yet", 1, true) ~= nil)

-- The speed check is typed only (the owner, 2026-10-23): no Settings row.
ns.SettingsUI:Show()
suite.check("Settings has no speed check row",
    ns.SettingsUI.controls.perfShow == nil and ns.SettingsUI.controls.perfClear == nil)
ns.SettingsUI:Hide()

_G.debugprofilestop = nil
env.chat = {}
ns.HandleSlash("perf")
suite.check("a client with no timer says so", env.ChatText():find("no timer", 1, true) ~= nil)

--------------------------------------------------------------------------------
-- Scanning only when something that matters changes
--------------------------------------------------------------------------------

do
    -- Item answers come in bursts: hold the timers, then let them run.
    local held = {}
    local realAfter = _G.C_Timer.After
    _G.C_Timer.After = function(_, fn) held[#held + 1] = fn end
    local stales, realMark = 0, Finder.MarkStale
    Finder.MarkStale = function(self, ...) stales = stales + 1 return realMark(self, ...) end
    Finder.asked = Finder.asked or {}
    Finder.asked[1001], Finder.asked[1002], Finder.asked[1003] = true, true, true
    Finder:OnItemAnswer(1001)
    Finder:OnItemAnswer(1002)
    Finder:OnItemAnswer(1003)
    suite.check("a burst of answers marks nothing while it comes", stales == 0, stales)
    for _, fn in ipairs(held) do fn() end
    suite.check("and marks the scan out of date once when it settles", stales == 1, stales)
    suite.check("an answer nobody asked for is left alone", Finder:OnItemAnswer(4242) == false)
    _G.C_Timer.After = realAfter

    stales = 0
    Finder.carriedSeen = nil
    env.bags[0] = { [1] = "item:1001" }
    Finder:OnBags()
    stales = 0
    env.bags[0] = { [1] = "item:1001", [2] = "item:1001" }
    Finder:OnBags()
    suite.check("a stack growing marks nothing", stales == 0, stales)
    env.bags[0] = { [2] = "item:1001" }
    Finder:OnBags()
    suite.check("moving a piece marks nothing", stales == 0, stales)
    env.bags[0] = { [2] = "item:1001", [3] = "item:1002" }
    Finder:OnBags()
    suite.check("new gear in the bags marks the scan out of date", stales == 1, stales)
    env.bags[0] = {}
    Finder:OnBags()
    Finder.MarkStale = realMark

    -- A scan kept for a while is not looked at again every minute.
    local clock = 5000
    local realNow = Finder.Now
    Finder.Now = function() return clock end
    Finder:ScanInBackground()
    local realBackground, again = Finder.ScanInBackground, 0
    Finder.ScanInBackground = function() again = again + 1 end
    clock = clock + 120
    Finder:Latest()
    suite.check("a scan two minutes old is still used", again == 0, again)
    clock = clock + 300
    Finder:Latest()
    suite.check("one seven minutes old is looked at again", again == 1, again)
    Finder.ScanInBackground = realBackground
    Finder.Now = realNow
end

--------------------------------------------------------------------------------
-- The arrow rests when it has nowhere to point
--------------------------------------------------------------------------------

do
    local ArrowUI = ns.QuestArrowUI
    local realDraw, draws = ArrowUI.Draw, 0
    local frame = ArrowUI.frame
    ArrowUI.frame = ArrowUI.frame or { IsShown = function() return false end }
    ArrowUI.Draw = function(self) draws = draws + 1 end
    ArrowUI.state = { mode = "nowhere" }
    ArrowUI.since, ArrowUI.restFor = 0, 0
    for _ = 1, 100 do ArrowUI:Step(0.03) end
    suite.check("with nowhere to go it looks about twice a second, not thirty times",
        draws >= 4 and draws <= 8, draws)
    draws = 0
    ArrowUI.state = { mode = "arrow" }
    for _ = 1, 10 do ArrowUI:Step(0.03) end
    suite.check("pointing somewhere it keeps up every step", draws == 10, draws)
    ArrowUI.Draw, ArrowUI.frame, ArrowUI.state = realDraw, frame, nil
end

Compare.Judge = realJudge
suite.done()
