-- The Upgrades window must not scan again and again while it is open.
-- The client says GET_ITEM_INFO_RECEIVED every time it loads an item, for
-- anyone: a tooltip, a chat link, our own list of upgrades. Only the answer
-- to a question the finder is still waiting on may count.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("refreshloop")

local ns = env.Load()
local Finder = ns.Finder

-- Hold the timers, so a test says when a burst settles.
local held = {}
local realAfter = _G.C_Timer.After
_G.C_Timer.After = function(_, fn) held[#held + 1] = fn end
local function Run()
    local batch = held
    held = {}
    for _, fn in ipairs(batch) do fn() end
end

local requests = {}
_G.C_Item = _G.C_Item or {}
local realRequest = _G.C_Item.RequestLoadItemDataByID
_G.C_Item.RequestLoadItemDataByID = function(id) requests[#requests + 1] = id end
local realQuestWindow = Finder.QuestWindowOpen
Finder.QuestWindowOpen = function() return false end

local realWatchers, realKeep = Finder.answerWatchers, Finder.keepAsking
local looks = 0
Finder.answerWatchers = { function(again, done) if again or done then looks = looks + 1 end end }
Finder.keepAsking = function() return true end
Finder.asked, Finder.tries, Finder.pending = {}, {}, {}
Finder.queue, Finder.followUp = nil, false

suite.check("asking about an item goes to the server", Finder:Request(7001) == true and #requests == 1)
suite.check("its answer counts", Finder:OnItemAnswer(7001) == true and #held == 1, #held)
Run()
suite.check("and the window hears once", looks == 1, looks)

-- The loop: the item is loaded again (the list reads its link, the mouse
-- goes over it), the client says the event again, and that used to start
-- another scan, whose list read the link again.
for _ = 1, 25 do
    Finder:OnItemAnswer(7001)
    Run()
end
suite.check("the same item loading again is left alone", looks == 1, looks)
suite.check("and starts no timer", #held == 0, #held)
suite.check("it still counts as asked", Finder:Asked(7001) == true)
suite.check("a text id reads the same", Finder:OnItemAnswer("7001") == false)

suite.check("an item nobody asked about is left alone", Finder:OnItemAnswer(7999) == false and #held == 0)
suite.check("so is an answer with no id", Finder:OnItemAnswer(nil) == false and #held == 0)

-- Asked again (a scan after a real change), its answer counts once more.
suite.check("asked again", Finder:Request(7001) == true and #requests == 2)
Finder:OnItemAnswer(7001)
Finder:OnItemAnswer(7001)
suite.check("one answer for one question", #held == 1, #held)
Run()
suite.check("and the window hears once more", looks == 2, looks)

-- A burst: three asked, six events. One look when it settles.
Finder.tries = {}
for _, id in ipairs({ 7002, 7003, 7004 }) do Finder:Request(id) end
for _, id in ipairs({ 7002, 7003, 7004, 7002, 7003, 7004 }) do Finder:OnItemAnswer(id) end
suite.check("a burst holds three timers, not six", #held == 3, #held)
Run()
suite.check("and the window hears once for the burst", looks == 3, looks)

-- Asked a moment ago: a second scan (a tick box, a filter) does not ask
-- again and spends no try. Only once its answer has had time to come.
local realNow, clock = Finder.Now, os.time()
Finder.Now = function() return clock end
local realCached = _G.C_Item.IsItemDataCachedByID
local have = {}
_G.C_Item.IsItemDataCachedByID = function(id) return have[id] == true end
Finder.asked, Finder.tries, Finder.pending, Finder.askedAt = {}, {}, {}, {}
Finder.queue, Finder.followUp = nil, false
requests, held, looks = {}, {}, 0
suite.check("an item is asked about", Finder:Request(7010) == true and #requests == 1)
suite.check("asked again at once, nothing goes out", Finder:Request(7010) == false and #requests == 1, #requests)
suite.check("and no try is spent", Finder.tries[7010] == 1, Finder.tries[7010])
suite.check("its answer is still due", Finder:AskMore() == 1 and #requests == 1, #requests)
suite.check("so a wait is kept going", #held == 1, #held)

-- The server dropped it: once the wait is over it is asked again, with no
-- scan, three times in all, and then let go.
clock = clock + Finder.ANSWER_WAIT + 1
Run()
suite.check("no answer at all asks again", #requests == 2 and Finder.tries[7010] == 2 and looks == 0,
    #requests .. " " .. tostring(Finder.tries[7010]) .. " " .. looks)
clock = clock + Finder.ANSWER_WAIT + 1
Run()
suite.check("and a third time", #requests == 3 and Finder.tries[7010] == 3 and looks == 0, #requests)
clock = clock + Finder.ANSWER_WAIT + 1
Run()
suite.check("then it is given up on", #requests == 3 and Finder:GaveUp(7010) == true, #requests)
suite.check("and the window hears once that nothing more is due", looks == 1 and #held == 0,
    looks .. " " .. #held)

-- An item the client got by itself (a tooltip loaded it) is not asked again.
suite.check("another item is asked about", Finder:Request(7011) == true and #requests == 4)
have[7011] = true
clock = clock + Finder.ANSWER_WAIT + 1
suite.check("one the client now has is not asked again", Finder:AskMore() == 0 and #requests == 4, #requests)

_G.C_Item.IsItemDataCachedByID = realCached

Finder.Now = realNow
Finder.asked, Finder.tries, Finder.pending, Finder.askedAt = {}, {}, {}, {}
_G.C_Timer.After = realAfter
_G.C_Item.RequestLoadItemDataByID = realRequest
Finder.QuestWindowOpen = realQuestWindow
Finder.answerWatchers, Finder.keepAsking = realWatchers, realKeep

suite.done()
