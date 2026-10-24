-- Dungeon Quests (the owner said build it, 2026-10-20): every dungeon and
-- raid quest, Classic's from Data/DungeonQuests.lua and Forever's own
-- learned from the quest log, with Done, In Log or To Do for each.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("dungeonquests")

local ns = env.Load()
for _, module in ipairs(ns.moduleOrder) do
    if module.OnEnable then module:OnEnable() end
end

local DQ, UI = ns.DungeonQuests, ns.DungeonQuestsUI

local count = 0
for _ in pairs(ns.DUNGEON_QUESTS) do count = count + 1 end
suite.check("the data has Classic's dungeon quests", count > 100, count)
local unknown = 0
for _, q in pairs(ns.DUNGEON_QUESTS) do
    if not DQ.Dungeon(q[1]) then unknown = unknown + 1 end
end
suite.check("every quest names a dungeon the addon knows", unknown == 0, unknown)
unknown = 0
for _, q in pairs(ns.FOREVER_DUNGEON_QUESTS or {}) do
    if not DQ.Dungeon(q[1]) then unknown = unknown + 1 end
end
suite.check("so does every Forever quest", unknown == 0, unknown)

-- A pretend data set and character, so the counts can be checked.
local realData, realForever = ns.DUNGEON_QUESTS, ns.FOREVER_DUNGEON_QUESTS
ns.FOREVER_DUNGEON_QUESTS = {}
ns.DUNGEON_QUESTS = {
    [1] = { "389", "Searching for the Lost Satchel", 9, 16, "H", 0, "Rahauro", "Thunder Bluff", 70, 30, 0, 0 },
    [2] = { "389", "Hidden Enemies", 10, 16, "H", 0, "Thrall", "Orgrimmar", 31, 37, 5000, 0 },
    [3] = { "389", "Slaying the Beast", 9, 16, "H", 0, "Neeru Fireblade", "Orgrimmar", 49, 50, 0, 0 },
    [4] = { "36", "Red Silk Bandanas", 14, 17, "A", 0, "Scout Riell", "Westfall", 56, 47, 0, 0 },
    [5] = { "389", "Only Mages", 9, 16, "", 128, "A Trainer", "Orgrimmar", 40, 40, 0, 0 },
    [6] = { "209", "Far Ahead", 44, 47, "H", 0, "Someone", "Tanaris", 50, 50, 0, 0 },
}
DQ.version = (DQ.version or 0) + 1
local player = { level = 14, faction = "H", classBit = 1 }
ns.Finder.Player = function() return player end
local doneIDs = { [1] = true }
ns.Finder.QuestDone = function(_, id) return doneIDs[id] == true end
local logLines = {}
ns.QuestLog.Size = function() return #logLines, "retail" end
ns.QuestLog.Line = function(index) return logLines[index] end
logLines = { { header = true, title = "Ragefire Chasm" }, { questID = 2, title = "Hidden Enemies", level = 16 } }
DQ.logStale = true

local data = DQ:Build()
suite.check("only this side's and class's quests at this level",
    data.all == 3 and #data.dungeons == 1, data.all .. " in " .. #data.dungeons)
local rfc = data.dungeons[1]
suite.check("the dungeon is Ragefire Chasm", rfc and rfc.name == "Ragefire Chasm", rfc and rfc.name)
local statuses = {}
for _, q in ipairs(rfc.quests) do statuses[q.questID] = q.status end
suite.check("done, in the log and to do", statuses[1] == "done" and statuses[2] == "log" and statuses[3] == "todo")
suite.check("one of three done", data.done == 1 and rfc.done == 1)

DQ:SetMyLevelOnly(false)
data = DQ:Build()
local seen = {} for _, d in ipairs(data.dungeons) do for _, q in ipairs(d.quests) do seen[#seen+1] = q.questID end end
suite.check("My Level Only off shows quests far past or ahead", data.all == 4, data.all .. ":" .. table.concat(seen, ",") .. ":" .. tostring(DQ.MyLevelOnly()))
suite.check("My Level Only is saved as false only", ns.db.dungeonQuestsMyLevel == false)
DQ:SetMyLevelOnly(true)
suite.check("on again leaves nothing saved", ns.db.dungeonQuestsMyLevel == nil)

DQ:SetHideDone(true)
data = DQ:Build()
suite.check("Hide Done takes the row out but keeps the count",
    #data.dungeons[1].quests == 2 and data.done == 1 and data.all == 3)
DQ:SetHideDone(false)

suite.check("the start line names who and where",
    DQ.From(DQ:All()[2]) == "Thrall, Orgrimmar", DQ.From(DQ:All()[2]))
suite.check("the place it starts", DQ.Place(DQ:All()[2]).zone == "Orgrimmar")

-- Learning Forever's own: a quest under a Forever dungeon's heading.
local forever, foreverName
for key, place in pairs(ns.FOREVER_DUNGEON_PLACES) do forever, foreverName = key, place[1] break end
logLines = {
    { header = true, title = foreverName },
    { questID = 900001, title = "A New Forever Quest", level = 20 },
    { header = true, title = "Elwynn Forest" },
    { questID = 900002, title = "Not a Dungeon Quest", level = 5 },
}
DQ:LearnLog()
local store = ns.db.learnedDungeonQuests or {}
suite.check("a quest under a dungeon heading is learned",
    store[900001] and store[900001].dungeon == forever and store[900001].title == "A New Forever Quest")
suite.check("a quest under a zone heading is not", store[900002] == nil)
suite.check("a quest the data has is never learned again", not DQ:Learn(2, "389", { title = "Hidden Enemies" }))
player.level = 20
data = DQ:Build()
local found
for _, d in ipairs(data.dungeons) do if d.key == forever then found = d end end
suite.check("the learned quest shows under its dungeon", found and #found.quests == 1 and found.forever)
suite.check("Forever's own dungeons come last", data.dungeons[#data.dungeons].key == forever)

-- Accepted inside a dungeon, with no heading over it.
_G.GetInstanceInfo = function() return "Ragefire Chasm", "party", 1, "", 5, 0, false, 389 end
logLines = { { questID = 900003, title = "Picked Up Inside", level = 15 } }
DQ:LearnLog(900003)
suite.check("a quest accepted inside a dungeon is learned for it",
    ns.db.learnedDungeonQuests[900003] and ns.db.learnedDungeonQuests[900003].dungeon == "389")
_G.GetInstanceInfo = nil

-- Forever's own, shipped at a release from quests met in game.
local realForever = ns.FOREVER_DUNGEON_QUESTS
ns.FOREVER_DUNGEON_QUESTS = {
    [900010] = { forever, "Shipped Forever Quest", 18, 22, "", 0, "", "", 0, 0, 0, 0 },
    [2] = { "389", "Not Over Classic's", 1, 1, "", 0, "", "", 0, 0, 0, 0 },
}
ns.db.learnedDungeonQuests[900010] = { dungeon = forever, title = "Shipped Forever Quest",
    giver = "A Giver", zone = "Tirisfal Glades", x = 60, y = 50, side = "H" }
DQ.version = DQ.version + 1
local all = DQ:All()
suite.check("a shipped Forever quest shows", all[900010] and all[900010].title == "Shipped Forever Quest")
suite.check("it never covers Classic's own", all[2].title == "Hidden Enemies")
suite.check("what this account learned fills in its giver and side",
    all[900010].giver == "A Giver" and all[900010].zone == "Tirisfal Glades" and all[900010].side == "H")
ns.FOREVER_DUNGEON_QUESTS = realForever
ns.db.learnedDungeonQuests[900010] = nil
DQ.version = DQ.version + 1

-- The window.
player.level = 14
UI:Show()
suite.check("the window opens", UI.frame and UI.frame:IsShown())
suite.check("it picks a dungeon with something to do", ns.db.dungeonQuestsPick ~= nil)
UI:Pick("389")
suite.check("the total reads as a count", UI.total:GetText() ~= nil and UI.total:GetText():find("still to do", 1, true) ~= nil,
    UI.total:GetText())
local shown = 0
for _, row in ipairs(UI.questRows) do if row:IsShown() then shown = shown + 1 end end
suite.check("its quests show", shown == 3, shown)
-- A long name wraps onto two lines and its row grows to fit, never "...".
local first = UI.questRows[1]
first.name.GetStringHeight = function() return 34 end
UI:FillQuests()
suite.check("a long quest name wraps and its row grows", first:GetHeight() > 38, first:GetHeight())
suite.check("the next row sits below it", UI.questRows[2]._point and UI.questRows[2]._point[3] == -(UI.questTop + first:GetHeight()),
    UI.questRows[2]._point and UI.questRows[2]._point[3])
shown = 0
for _, row in ipairs(UI.questRows) do if row:IsShown() then shown = shown + 1 end end
suite.check("and every quest still shows", shown == 3, shown)
first.name.GetStringHeight = nil
UI:FillQuests()
UI.questRows[2]:GetScript("OnClick")(UI.questRows[2])
suite.check("a picked quest says where it starts", UI.foot:GetText():find("Orgrimmar", 1, true) ~= nil
    or UI.foot:GetText():find("Thunder Bluff", 1, true) ~= nil, UI.foot:GetText())
UI:Hide()
suite.check("the window closes", not UI.frame:IsShown())

ns.HandleSlash("dungeons")
suite.check("/beq dungeons opens it", UI.frame:IsShown())
UI:Hide()
suite.check("the gear window has a Dungeon Quests button", ns.UI.dungeonButton ~= nil or ns.UI.frame == nil)

-- A Forever dungeon whose place has no door takes the levels and door of
-- the row Data/ForeverDrops.lua laid in Sources.DUNGEONS.
ns.FOREVER_DUNGEON_PLACES["9901"] = { "Test Hall", "" }
ns.Sources.DUNGEONS["9901"] = { "Test Hall", 13, 18, "Ironforge", "" }
local hall = DQ.Dungeon("9901")
suite.check("a Forever dungeon takes its door from the drops' row", hall.door == "Ironforge", hall.door)
suite.check("and its levels", hall.low == 13 and hall.high == 18)
ns.Sources.DUNGEONS["9901"] = { "Test Hall", 1, 60, "Test Hall", "" }
suite.check("a door that only repeats the name is no door", DQ.Dungeon("9901").door == nil)
ns.FOREVER_DUNGEON_PLACES["9901"], ns.Sources.DUNGEONS["9901"] = nil, nil
suite.check("Hall of Thanes says where its door is", DQ.Dungeon("3065").door == "Ironforge")

ns.DUNGEON_QUESTS, ns.FOREVER_DUNGEON_QUESTS = realData, realForever
suite.check("the probe line reads", type(DQ:Describe()) == "string")

-- Quest names come from the game when it has them, the data's otherwise;
-- a quest it has not loaded is asked for once and redrawn when it comes.
local realLog = _G.C_QuestLog
local asked, titles = {}, { [7001] = "Forever's Own Name" }
_G.C_QuestLog = setmetatable({
    GetTitleForQuestID = function(id) return titles[id] end,
    RequestLoadQuestByID = function(id) asked[#asked + 1] = id end,
}, { __index = realLog })
DQ.titles, DQ.asked = {}, {}
suite.check("the game's name wins", DQ:TitleOf({ questID = 7001, title = "Old" }) == "Forever's Own Name")
suite.check("the data's name stands in", DQ:TitleOf({ questID = 7002, title = "Data Name" }) == "Data Name")
DQ:TitleOf({ questID = 7002, title = "Data Name" })
suite.check("a quest not loaded is asked for once", #asked == 1 and asked[1] == 7002, #asked)
titles[7002] = "Loaded Now"
DQ:TitleLoaded(7002, true)
suite.check("once loaded, the game's name shows", DQ:TitleOf({ questID = 7002, title = "Data Name" }) == "Loaded Now")
suite.check("the quest names probe line reads", DQ:DescribeTitles():find("title call found", 1, true) ~= nil,
    DQ:DescribeTitles())
_G.C_QuestLog = realLog
DQ.titles, DQ.asked = {}, {}

-- Dungeon doors are learned as the character walks in.
local Doors = ns.DungeonDoors
local realHere, realInside, realDQInside = ns.QuestArrow.Here, ns.QuestArrow.Inside, DQ.Inside
ns.db.dungeonDoors = nil
ns.QuestArrow.Inside = function() return false end
ns.QuestArrow.Here = function() return { zone = "Ironforge", x = 0.42, y = 0.31 } end
DQ.Inside = function() return "3065" end
Doors:Leaving()
suite.check("walking in keeps the door", Doors:Arrived() == true)
local spot = Doors:Spot("3065")
suite.check("a spot in the door's own zone is used", spot and spot.zone == "Ironforge"
    and spot.x == 42 and spot.y == 31, spot and (spot.zone .. " " .. spot.x .. " " .. spot.y))
suite.check("it is found by the dungeon's name too", Doors:SpotByName(DQ.Dungeon("3065").name) ~= nil)
local place = Doors:Fill({ zone = "Ironforge" }, DQ.Dungeon("3065").name)
suite.check("a door place gets the spot", place.x == 42 and place.y == 31)
Doors:Keep("3065", "Dun Morogh", 10, 10)
suite.check("a hearth elsewhere is not used", Doors:Spot("3065").zone == "Ironforge")
suite.check("arriving with nothing noted keeps nothing", Doors:Arrived() == false)
DQ.Inside = function() return nil end
Doors:Leaving()
suite.check("arriving outside a dungeon keeps nothing", Doors:Arrived() == false)

-- On Forever the loading screen noted nothing, so the spot outside is noted
-- as the character walks, and the arrival is looked at again a little later.
ns.db.dungeonDoors = nil
Doors.outside, Doors.lastTry = nil, nil
ns.QuestArrow.Here = function() return { zone = "Ironforge", x = 0.40, y = 0.30 } end
suite.check("a walk outside notes the spot", Doors:Note() == true and Doors.outside ~= nil)
ns.QuestArrow.Here = function() return nil end
Doors:Leaving()
suite.check("a loading screen with no position keeps the last spot", Doors.outside ~= nil
    and Doors.outside.x == 40)
local realAfter, waiting = _G.C_Timer and _G.C_Timer.After, {}
_G.C_Timer = _G.C_Timer or {}
_G.C_Timer.After = function(_, fn) waiting[#waiting + 1] = fn end
ns.QuestArrow.Inside = function() return true end
DQ.Inside = function() return nil end
Doors:Entered()
suite.check("arriving before the game names the dungeon waits", ns.db.dungeonDoors == nil and #waiting > 0)
suite.check("the probe says why", (Doors.lastTry or ""):find("not in a known dungeon", 1, true) ~= nil,
    Doors.lastTry)
suite.check("inside, nothing new is noted", Doors:Note() == false and Doors.outside.x == 40)
DQ.Inside = function() return "3065" end
for _, fn in ipairs(waiting) do fn() end
local learned = Doors:Learned("3065")
suite.check("a look again keeps the door", learned and learned.zone == "Ironforge" and learned.x == 40,
    Doors.lastTry)
suite.check("the door is kept once", #ns.db.dungeonDoors["3065"].spots == 1)
suite.check("the probe line reads", Doors:Describe():find("last try: kept 3065", 1, true) ~= nil,
    Doors:Describe())
_G.C_Timer.After = realAfter

-- A dungeon whose door zone the data lacks waits for two spots that agree.
ns.FOREVER_DUNGEON_PLACES["9902"] = { "Doorless Hall", "" }
Doors:Keep("9902", "Elwynn Forest", 50, 50)
suite.check("one spot alone is not trusted", Doors:Spot("9902") == nil)
Doors:Keep("9902", "Elwynn Forest", 51, 49)
suite.check("two that agree are", Doors:Spot("9902") ~= nil)
ns.FOREVER_DUNGEON_PLACES["9902"] = nil
for i = 1, 8 do Doors:Keep("3065", "Ironforge", 40, 30 + i) end
suite.check("only a few spots are kept", #ns.db.dungeonDoors["3065"].spots == Doors.KEEP)
suite.check("the doors probe line reads", type(Doors:Describe()) == "string")
ns.QuestArrow.Here, ns.QuestArrow.Inside, DQ.Inside = realHere, realInside, realDQInside
ns.db.dungeonDoors = nil

-- Before any walk in, the shipped door spot is used.
suite.check("door spots are shipped", type(ns.DUNGEON_DOOR_SPOTS) == "table"
    and ns.DUNGEON_DOOR_SPOTS["36"] ~= nil)
local deadmines = Doors:Spot("36")
suite.check("a new player gets the shipped door", deadmines and deadmines.zone == "Westfall"
    and deadmines.x > 0 and deadmines.y > 0)
local mines = Doors:Fill({ zone = "Westfall" }, "The Deadmines")
suite.check("the door place gets the shipped spot", mines.x == deadmines.x and mines.y == deadmines.y)
Doors:Keep("36", "Westfall", 42.5, 71.7)
suite.check("a door walked through wins", Doors:Spot("36").x == 42.5 and not Doors:Spot("36").shipped)
ns.db.dungeonDoors = nil
local spire = Doors:Fill({ zone = "Blackrock Mountain" }, "Blackrock Spire")
suite.check("a mountain door brings its own zone", spire.zone ~= "Blackrock Mountain" and (spire.x or 0) > 0,
    tostring(spire.zone))
suite.check("a monastery wing finds its door", Doors:SpotByName("Scarlet Monastery Library") ~= nil)
suite.check("a dungeon with no shipped spot keeps only its zone",
    (Doors:Fill({ zone = "Ironforge" }, DQ.Dungeon("3065").name).x or 0) == 0)
suite.check("the doors probe line counts shipped spots", Doors:Describe():find("shipped", 1, true) ~= nil)

suite.done()
