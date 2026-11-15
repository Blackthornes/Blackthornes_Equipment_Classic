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

-- The client lets worn gear go from its memory now and then: the link comes
-- back with no name and no stats. That is no gear change, so nothing is
-- judged again and the list holds still (a player's report, 2026-11-13).
do
    local named, blank = "|cffffffff|Hitem:900:|h[Worn Chest]|h|r", "|cffffffff|Hitem:900:|h[]|h|r"
    ITEMS[named] = Chest(10)
    env.worn[5] = named
    Finder:Scan()
    local asked = {}
    local realRequest, realCached = C_Item.RequestLoadItemDataByID, C_Item.IsItemDataCachedByID
    C_Item.RequestLoadItemDataByID = function(id) asked[#asked + 1] = id end
    judges = 0
    env.worn[5] = blank
    for _ = 1, 5 do found = Finder:Scan() end
    suite.check("a worn link that lost its name and stats judges nothing again", judges == 0, judges)
    suite.check("and the list still shows the same upgrades", found.count == 3, found.count)
    local wornAsked = false
    for _, id in ipairs(asked) do if id == 900 then wornAsked = true end end
    suite.check("and the worn piece is asked for again", wornAsked)
    env.worn[5] = named
    judges = 0
    found = Finder:Scan()
    suite.check("when it comes back nothing is judged again either", judges == 0 and found.count == 3,
        judges .. " " .. found.count)

    -- A piece judged before that the client lets go of keeps its verdict and
    -- is not asked about again.
    asked = {}
    C_Item.IsItemDataCachedByID = function(id) return id ~= 1002 end
    found = Finder:Scan()
    suite.check("an upgrade the client forgot is still listed", found.count == 3, found.count)
    suite.check("and not asked about again", #asked == 0, #asked)
    C_Item.RequestLoadItemDataByID, C_Item.IsItemDataCachedByID = realRequest, realCached

    -- Something new while the worn stats are missing waits, never judged
    -- against nothing.
    ITEMS["item:1006"] = Chest(5)
    S.ITEMS[1006] = { 15, 15, 0, 0, 100, v = { 1, 0 } }
    env.worn[5] = blank
    judges = 0
    found = Finder:Scan()
    suite.check("a new item is not judged while the worn stats are missing", judges == 0 and found.waiting >= 1,
        judges .. " " .. found.waiting)
    env.worn[5] = named
    judges = 0
    found = Finder:Scan()
    suite.check("and is judged once they are back", judges == 1 and found.count == 3, judges .. " " .. found.count)
    ITEMS["item:1006"], S.ITEMS[1006] = nil, nil
    env.worn[5] = "item:900"
    ITEMS[named] = nil
    Finder:Scan()
end

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
    local settled, realSettled = {}, Finder.AnswersSettled
    Finder.AnswersSettled = function(self, ...)
        local again = realSettled(self, ...)
        settled[#settled + 1] = again
        return again
    end
    Finder.followUp = true   -- as after a real change (gear worn, a setting)
    for _, fn in ipairs(held) do fn() end
    suite.check("and marks the scan out of date once when it settles", settled[1] == true, tostring(settled[1]))
    -- The scan that follows asks about more items. Their answers must not
    -- start yet another scan, or it never stops.
    held = {}
    Finder.asked[1004] = true
    Finder:OnItemAnswer(1004)
    for _, fn in ipairs(held) do fn() end
    suite.check("the answers after that follow-up start no more scans", settled[2] == false, tostring(settled[2]))
    Finder.AnswersSettled = realSettled
    local heard
    Finder:WatchAnswers(function(again) heard = again end)
    suite.check("and the watchers hear not to look again", Finder:AnswersSettled() == false and heard == false)
    Finder:MarkStale()
    suite.check("a real change lets one more follow", Finder:AnswersSettled() == true and heard == true)
    Finder.answerWatchers[#Finder.answerWatchers] = nil
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

    -- A scan is kept until something it reads changes; no clock makes it old.
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
    suite.check("one seven minutes old is still used", again == 0, again)
    clock = clock + 3600
    Finder:Latest()
    suite.check("even an hour later", again == 0, again)
    Finder:MarkStale()
    Finder:Latest()
    suite.check("a real change looks again", again == 1, again)
    Finder.ScanInBackground = realBackground
    Finder.Now = realNow
end

--------------------------------------------------------------------------------
-- Many items the client has not seen: asked a batch at a time, one scan after
--------------------------------------------------------------------------------

do
    local S = ns.Sources
    local realItems = S.ITEMS
    local items = {}
    for id, row in pairs(realItems) do items[id] = row end
    -- 100 pieces the client has never seen, beside the three it has.
    local unseen = {}
    for id = 2001, 2100 do
        items[id] = { 15, 15, 0, 0, 100, v = { 1, 0 } }
        ITEMS["item:" .. id] = Chest(12)
        unseen[id] = true
    end
    S.ITEMS = items
    local held, requests = {}, {}
    local realAfter = _G.C_Timer.After
    _G.C_Timer.After = function(_, fn) held[#held + 1] = fn end
    local function Run()
        local fns = held
        held = {}
        for _, fn in ipairs(fns) do fn() end
    end
    local realCached, realRequest = C_Item.IsItemDataCachedByID, C_Item.RequestLoadItemDataByID
    C_Item.IsItemDataCachedByID = function(id) return not unseen[id] end
    C_Item.RequestLoadItemDataByID = function(id) requests[#requests + 1] = id end
    local scans, realBuild = 0, Finder.Build
    Finder.Build = function(self, ...) scans = scans + 1 return realBuild(self, ...) end
    local realKeep, realWatchers = Finder.keepAsking, Finder.answerWatchers
    local open = true
    Finder.keepAsking = function() return open end
    local looks = 0
    Finder.answerWatchers = { function(again, done) if again or done then looks = looks + 1 end end }
    Finder.asked, Finder.tries, Finder.followUp = {}, {}, false

    -- The server answers what it was asked, and the burst settles.
    local function Answer(drop)
        local batch = requests
        requests = {}
        for _, id in ipairs(batch) do
            if not (drop and drop[id]) then
                unseen[id] = nil
                Finder:OnItemAnswer(id)
            end
        end
        Run()
    end

    Finder.judged = nil
    local found = Finder:Scan()
    suite.check("a scan asks about forty at most", #requests == 40, #requests)
    suite.check("and waits on all hundred", found.waiting == 100, found.waiting)
    scans = 0
    Answer()
    suite.check("their answers ask for the next forty, with no scan", #requests == 40 and scans == 0 and looks == 0,
        #requests .. " " .. scans .. " " .. looks)
    Answer()
    suite.check("and the last twenty", #requests == 20 and scans == 0 and looks == 0,
        #requests .. " " .. scans .. " " .. looks)
    Answer()
    suite.check("the window hears once, when all are in", looks == 1 and #requests == 0 and scans == 0,
        looks .. " " .. #requests .. " " .. scans)
    found = Finder:Scan()
    suite.check("the scan after that waits on nothing", found.waiting == 0, found.waiting)
    suite.check("and asks for nothing", #requests == 0, #requests)

    -- With nothing showing the list, the rest is left unasked.
    for id = 2001, 2100 do unseen[id] = true end
    Finder.judged = nil
    Finder.asked, Finder.tries = {}, {}
    open, looks, requests = false, 0, {}
    Finder:Scan()
    Answer()
    suite.check("with the window shut nothing more is asked", #requests == 0, #requests)
    open = true

    -- A batch the server never answers does not stop the rest.
    for id = 2001, 2100 do unseen[id] = true end
    Finder.judged = nil
    Finder.asked, Finder.tries = {}, {}
    looks, requests, held = 0, {}, {}
    Finder:Scan()
    suite.check("a scan that leaves some unasked keeps a wait going", #held == 1, #held)
    requests = {}
    Run()   -- the wait runs out with no answer at all
    suite.check("no answer at all still asks for the next batch", #requests == 40 and looks == 0,
        #requests .. " " .. looks)

    -- Items the server never answers are given up on, and no longer counted.
    for id = 2001, 2100 do unseen[id] = nil end
    unseen[2001], unseen[2002] = true, true
    Finder.asked, Finder.tries, Finder.queue = {}, {}, nil
    requests, held = {}, {}
    Finder.judged = nil
    for _ = 1, 3 do found = Finder:Scan() end
    suite.check("an item asked three times is still counted while it may come", found.waiting == 2, found.waiting)
    found = Finder:Scan()
    suite.check("then it is given up on and not counted as waiting", found.waiting == 0, found.waiting)

    Finder.keepAsking, Finder.answerWatchers = realKeep, realWatchers
    Finder.Build = realBuild
    C_Item.IsItemDataCachedByID, C_Item.RequestLoadItemDataByID = realCached, realRequest
    _G.C_Timer.After = realAfter
    S.ITEMS = realItems
    for id = 2001, 2100 do ITEMS["item:" .. id] = nil end
    Finder.asked, Finder.tries, Finder.queue = {}, {}, nil
    Finder:MarkStale()
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
--------------------------------------------------------------------------------
-- Spell and skill events judge again only when a weapon skill really changed
--------------------------------------------------------------------------------

do
    local Skills = ns.WeaponSkills
    local known = {}
    local realSpell = rawget(_G, "IsPlayerSpell")
    _G.IsPlayerSpell = function(id) return known[id] == true end
    Skills.kept = nil
    Skills.signature = Skills.Signature(Skills:ReadKnown())
    local generation = Finder.judgeGeneration or 0
    for _ = 1, 10 do Skills:Learned() end
    suite.check("ten skill events with nothing learned judge nothing again",
        (Finder.judgeGeneration or 0) == generation, Finder.judgeGeneration)
    known[227] = true   -- Staves
    Skills:Learned()
    suite.check("a weapon skill learned judges again once",
        (Finder.judgeGeneration or 0) == generation + 1, Finder.judgeGeneration)
    Skills:Learned()
    suite.check("and the next event changes nothing",
        (Finder.judgeGeneration or 0) == generation + 1, Finder.judgeGeneration)
    _G.IsPlayerSpell = realSpell
    Skills.kept = nil
end

suite.done()
