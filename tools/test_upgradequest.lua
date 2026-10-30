-- The upgrade quest: off until turned on, then the best next upgrade with
-- the steps to get it, ticking off as the game shows them done, and the
-- next one picked once it is worn.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("upgradequest")

local function Agi(n) return { ITEM_MOD_AGILITY_SHORT = n } end
local function Gear(loc, n) return { loc = loc, class = 4, subclass = 2, stats = Agi(n) } end

local ITEMS = {
    ["item:900"] = Gear("INVTYPE_CHEST", 10),   -- worn
    ["item:1001"] = Gear("INVTYPE_CHEST", 20),  -- sold by a vendor
    ["item:1002"] = Gear("INVTYPE_CHEST", 30),  -- quest reward
    ["item:1003"] = Gear("INVTYPE_CHEST", 5),   -- worse
    ["item:2001"] = Gear("INVTYPE_CHEST", 40),  -- a dungeon drop, seen later
    ["item:9000"] = Gear("INVTYPE_CHEST", 50),  -- better than anything on offer
    ["item:3001"] = { loc = "INVTYPE_CHEST", class = 4, subclass = 2, stats = Agi(100), minLevel = 22 },
    ["item:3002"] = { loc = "INVTYPE_CHEST", class = 4, subclass = 2, stats = Agi(22), minLevel = 22 },
}

local ns = env.Load()
_G.UnitClass = function() return "Hunter", "HUNTER", 3 end
_G.UnitFactionGroup = function() return "Alliance", "Alliance" end
_G.UnitRace = function() return "Human", "Human", 1 end
_G.GetRealZoneText = function() return "Elwynn Forest" end
env.InstallItems(ITEMS, { [5] = "item:900" }, { [0] = {} }, 20)

local onQuest, ready, turnedIn = false, false, false
_G.C_QuestLog = {
    IsQuestFlaggedCompleted = function() return turnedIn end,
    IsOnQuest = function(id) return id == 10 and onQuest end,
    ReadyForTurnIn = function(id) return id == 10 and ready end,
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
    [1003] = { 15, 18, 0, 0, 40, v = { 1, 0 } },
}

local Quest, Panel = ns.UpgradeQuest, ns.QuestPanel

local toasts = {}
local realShow = ns.Toast.Show
ns.Toast.Show = function(self, banner)
    toasts[#toasts + 1] = banner
    return realShow(self, banner)
end

-- Every tab's quest forgotten, as on a new character.
local function Reset()
    ns.charDB.upgradeQuestTabs = {}
    ns.charDB.upgradeQuestTab = nil
    ns.charDB.upgradeQuest = nil
end

local function StepTexts()
    local texts = {}
    for _, step in ipairs((Quest:Steps())) do texts[#texts + 1] = step.text end
    return table.concat(texts, " | ")
end

--------------------------------------------------------------------------------
-- Off by default
--------------------------------------------------------------------------------

suite.check("off by default", ns.db.upgradeQuest == false and not Quest:IsEnabled())
Quest:Update()
suite.check("off, it picks nothing", ns.charDB.upgradeQuest == nil)
Panel:Refresh()
suite.check("and shows nothing", not (Panel.frame and Panel.frame:IsShown()))

--------------------------------------------------------------------------------
-- Turned on: the best next upgrade
--------------------------------------------------------------------------------

ns.HandleSlash("quest")
suite.check("/beq quest turns it on", ns.db.upgradeQuest == true)
suite.check("and says so", env.ChatText():find("upgrade quest on", 1, true) ~= nil, env.ChatText())
local quest = Quest:Current()
-- The quest reward is +200%, the vendor's +100%; a quest is a little more
-- work than buying, but not twice as much.
suite.check("picks the best upgrade worth the trip", quest and quest.itemID == 1002, quest and quest.itemID)
suite.check("kept per character", ns.charDB.upgradeQuest == quest)
suite.check("with how much better", quest.howMuch == "+200%", quest.howMuch)
suite.check("a banner says so", toasts[#toasts] and toasts[#toasts].title == "New upgrade quest")
suite.check("the panel shows", Panel.frame and Panel.frame:IsShown())
suite.check("with the item", Panel.name:GetText() == "item:1002", Panel.name:GetText())
suite.check("how much better and from where", Panel.gain:GetText():find("+200% over what you wear", 1, true)
    and Panel.gain:GetText():find("Quest", 1, true), Panel.gain:GetText())

local steps, current = Quest:Steps()
suite.check("the quest's steps", StepTexts() == "Travel to Elwynn Forest"
    .. " | Pick up Wolves of the Forest from Marshal Dughan (42.1, 65.9)"
    .. " | Complete Wolves of the Forest (level 18)"
    .. " | Hand it in and choose item:1002"
    .. " | Put on item:1002", StepTexts())
suite.check("already in the zone, so travel is done", steps[1].done and current == 2, current)

-- A reward the quest gives outright is not chosen; the data says so even
-- for a quest kept from before it did.
S.ITEMS[1002].g = { 10 }
suite.check("a given reward is got, not chosen", StepTexts():find("Hand it in to get item:1002", 1, true), StepTexts())
S.ITEMS[1002].g = nil
suite.check("without it, a reward is one of a choice", ns.Finder.Given(1002, 10) == false)
suite.check("the panel counts the steps", Panel.progress:GetText() == "4 steps left", Panel.progress:GetText())
suite.check("the step to do now is lit", Panel.steps[2].now and not Panel.steps[1].now)
suite.check("steps to come are numbered", Panel.steps[3].number:GetText() == "3.")
suite.check("Show on map is offered", Panel.mapButton:IsShown())

-- Picked up, done, handed in, worn.
onQuest = true
Quest:Update()
suite.check("taking the quest ticks off picking it up", select(2, Quest:Steps()) == 3)
suite.check("the panel follows", Panel.progress:GetText() == "3 steps left", Panel.progress:GetText())
ready = true
suite.check("its objectives done", select(2, Quest:Steps()) == 4)
onQuest, ready, turnedIn = false, false, true
env.bags[0][1] = "item:1002"
steps, current = Quest:Steps()
suite.check("handed in, the reward in the bags: put it on", current == 5 and steps[4].done and steps[2].done,
    current)
suite.check("the progress bar fills", (function()
    Panel:Refresh()
    return Panel.fill:GetWidth() > 200
end)(), Panel.fill:GetWidth())

env.bags[0][1] = nil
env.worn[5] = "item:1002"
Quest:Update()
suite.check("worn, the quest is complete", Quest:DoneCount() == 1)
suite.check("with a banner", (function()
    for _, banner in ipairs(toasts) do
        if banner.title == "Upgrade quest complete" then return true end
    end
end)())
-- Nothing on offer beats what is worn now.
suite.check("and nothing left to chase", Quest:Current() == nil and Quest.state == "none", Quest.state)
suite.check("the panel says so", Panel.empty:IsShown()
    and Panel.empty:GetText():find("No quest reward is an upgrade", 1, true) ~= nil, Panel.empty:GetText())
suite.check("with Pick one still there", Panel.otherButton:IsShown() and not Panel.skipButton:IsShown()
    and Panel.otherButton.label:GetText() == "Pick one", Panel.otherButton.label:GetText())

--------------------------------------------------------------------------------
-- Skipping, and the vendor's steps
--------------------------------------------------------------------------------

env.worn[5] = "item:900"
turnedIn = false
ns.Finder:MarkStale()
-- A tab that found nothing looks again when the gear changes.
Quest:OnEvent("PLAYER_EQUIPMENT_CHANGED")
suite.check("a new quest once there is an upgrade again", Quest:Current() and Quest:Current().itemID == 1002)
suite.check("its Change button names what it does", Panel.otherButton.label:GetText() == "Change", Panel.otherButton.label:GetText())
ns.HandleSlash("quest skip")
suite.check("skip leaves the tab with the next best: no other quest reward here", Quest:Current() == nil)
suite.check("and remembers it", ns.charDB.upgradeQuestSkipped[1002] == true)
ns.HandleSlash("quest vendor")
quest = Quest:Current()
suite.check("the Vendor tab has its own upgrade", Quest:Tab() == "vendor" and quest and quest.itemID == 1001,
    quest and quest.itemID)
suite.check("the vendor's steps", StepTexts() == "Travel to Elwynn Forest"
    .. " | Find Corina Steele (41.5, 65.9)"
    .. " | Buy item:1001 for |cffffd700" .. "1g|r |cffc7c7cf20s|r |cffeda55f50c|r"
    .. " | Put on item:1001", StepTexts())
local place = Quest:NextPlace()
suite.check("the next place is the vendor", place and place.name == "Corina Steele" and place.x == 41.5)

-- Show on map uses the game's pin.
local waypoint
_G.UiMapPoint = { CreateFromCoordinates = function(id, x, y) return { id = id, x = x, y = y } end }
_G.C_Map = {
    GetBestMapForUnit = function() return 1429 end,
    GetMapInfo = function(id)
        return ({ [1429] = { name = "Elwynn Forest", parentMapID = 0 } })[id]
    end,
    GetMapChildrenInfo = function() return {} end,
    SetUserWaypoint = function(point) waypoint = point end,
}
suite.check("Show on map pins the vendor", Panel:ShowOnMap() == true and waypoint
    and math.abs(waypoint.x - 0.415) < 1e-9, waypoint and waypoint.x)

-- And the world map gets a pin for it.
local canvas = env.Stub({ _width = 1000, _height = 600 })
function canvas:GetHeight() return 600 end
_G.WorldMapFrame = env.Stub({ _shown = true, GetCanvas = function() return canvas end,
    GetMapID = function() return 1429 end })
ns.MapPins.key = nil
ns.MapPins:Draw()
local pin = ns.MapPins.pins and ns.MapPins.pins[1]
suite.check("a map pin for the quest's next place", pin and pin:IsShown() and pin.hunt.quest == true)

ns.HandleSlash("quest reset")
suite.check("/beq quest reset brings skipped ones back", next(ns.charDB.upgradeQuestSkipped) == nil)

-- Something as good turns up another way: the quest is dropped.
env.worn[5] = "item:9000"
Quest:Update()
suite.check("an upgrade no longer wanted is dropped", Quest:Current() == nil)
suite.check("and chat says why", env.ChatText():find("already wearing something as good", 1, true) ~= nil)
suite.check("with a banner", (function()
    for _, banner in ipairs(toasts) do
        if banner.title == "You already beat this one" then return true end
    end
end)())
suite.check("without counting as done", Quest:DoneCount() == 1)
env.worn[5] = "item:900"

-- Beaten while the quest's item sits in the bags, not yet put on: the
-- quest still closes rather than asking to put on the weaker one.
Reset()
ns.Finder:MarkStale()
Quest:Update()
local beaten = Quest:Current()
suite.check("a new quest to beat", beaten ~= nil)
env.bags[0][1] = beaten.link
env.worn[5] = "item:9000"
Quest:Update()
suite.check("beaten in the bags, it is dropped too", Quest:Current() == nil or Quest:Current().itemID ~= beaten.itemID)
env.bags[0][1] = nil
env.worn[5] = "item:900"

--------------------------------------------------------------------------------
-- Waiting on the server
--------------------------------------------------------------------------------

local clock = 100
_G.GetTime = function() return clock end
local cached = false
_G.C_Item.IsItemDataCachedByID = function() return cached end
_G.C_Item.RequestLoadItemDataByID = function() return true end
Reset()
ns.Finder:MarkStale()
Quest:Update()
suite.check("waits for the server's answers before picking", Quest:Current() == nil and Quest.state == "waiting",
    Quest.state)
suite.check("and says it is looking", Panel.empty:GetText():find("Looking for your next upgrade", 1, true) ~= nil)
cached = true
-- GET_ITEM_INFO_RECEIVED marks the finder's scan out of date.
ns.Finder:MarkStale()
Quest:Update()
suite.check("picks once they are in", Quest:Current() ~= nil)
_G.GetTime = nil
_G.C_Item.IsItemDataCachedByID = nil

--------------------------------------------------------------------------------
-- Dungeons and crafting
--------------------------------------------------------------------------------

_G.GetRealZoneText = function() return "Westfall" end
local dungeon = {
    itemID = 2001, link = "item:2001", howMuch = "+300%",
    source = { kind = "dungeon", name = "Edwin VanCleef", dungeon = "The Deadmines", minLevel = 17,
        maxLevel = 26, zone = "Westfall", chance = 5, forever = true },
}
steps, current = Quest:Steps(dungeon)
suite.check("a dungeon's steps", #steps == 4 and steps[1].text == "Travel to Westfall"
    and steps[2].text == "Gather a group and enter The Deadmines (levels 17 to 26)"
    and steps[3].text == "Defeat Edwin VanCleef and loot item:2001", steps[2].text)
suite.check("in Westfall, the door is next", steps[1].done and current == 2, current)
suite.check("with the drop chance and no Forever word", steps[3].note:find("5% drop", 1, true) and not steps[3].note:find("Forever", 1, true),
    steps[3].note)
suite.check("the map takes you to the door", steps[2].place.zone == "Westfall")
_G.GetRealZoneText = function() return "The Deadmines" end
steps, current = Quest:Steps(dungeon)
suite.check("inside, the boss is next", current == 3 and steps[1].done, current)
suite.check("a rare drop counts as harder to get", Quest.Ease(dungeon.source) < Quest.Ease({ kind = "dungeon" }))

ns.Crafts.ITEMS = { [2001] = { 165, 100, 555, 15, 18, 0, 0, 0, m = { 2318, 4 } } }
ns.Crafts.MATERIALS = { [2318] = { "Light Leather", 15 } }
local craft = {
    itemID = 2001, link = "item:2001",
    source = { kind = "craft", state = "known", profession = "Leatherworking", skill = 100 },
}
steps = Quest:Steps(craft)
suite.check("a craft's steps", #steps == 3 and steps[1].text == "Gather the materials: 4 Light Leather"
    and steps[2].text == "Make item:2001 (Leatherworking)", steps[1] and steps[1].text)
env.bags[0] = { "item:2318", "item:2318", "item:2318", "item:2318" }
steps, current = Quest:Steps(craft)
suite.check("materials in the bags tick it off", steps[1].done and current == 2, current)
env.bags[0] = {}
craft.source.state = "alt"
craft.source.who = { "Bob" }
steps = Quest:Steps(craft)
suite.check("an alt can make it", steps[1].text == "Ask Bob to make item:2001 (Leatherworking) and mail it to you")

--------------------------------------------------------------------------------
-- A quest handed in with another reward taken
--------------------------------------------------------------------------------

_G.GetRealZoneText = function() return "Elwynn Forest" end
ns.Crafts.ITEMS = {}
env.bags[0] = {}
env.worn[5] = "item:900"
turnedIn = false
Reset()
ns.charDB.upgradeQuestSkipped = {}
ns.charDB.upgradeQuestTab = "quest"
ns.Finder:MarkStale()
Quest:Update()
suite.check("the quest reward is picked again", Quest:Current() and Quest:Current().itemID == 1002)
clock = 500
_G.GetTime = function() return clock end
turnedIn = true
Quest:Update()
suite.check("handed in, it waits a moment for the reward to reach the bags",
    Quest:Current() and Quest:Current().itemID == 1002)
clock = 506
Quest:Update()
suite.check("still not in the bags: the quest is dropped",
    env.ChatText():find("that quest is already done", 1, true) ~= nil)
suite.check("and never picked again", ns.charDB.upgradeQuestSkipped[1002] == true
    and Quest:Current() == nil, Quest:Current() and Quest:Current().itemID)
suite.check("the Vendor tab keeps its own", Quest:QuestOn("vendor") and Quest:QuestOn("vendor").itemID == 1001)
_G.GetTime = nil
turnedIn = false

-- A client that cannot say which quests are done: hand-ins seen are kept.
local realLog = _G.C_QuestLog
_G.C_QuestLog = {}
suite.check("an unknown quest is not done", ns.Finder:QuestDone(10) == false)
ns.Finder:OnQuestTurnedIn("QUEST_TURNED_IN", 10)
suite.check("a quest seen handed in is done", ns.Finder:QuestDone(10) == true
    and ns.charDB.questsTurnedIn[10] == true)
suite.check("so the finder leaves its reward out", (function()
    for _, source in ipairs(ns.Finder:SourcesFor(1002, ns.Finder:Player())) do
        if source.kind == "quest" then return false end
    end
    return true
end)())
_G.C_QuestLog = realLog

--------------------------------------------------------------------------------
-- Quest chains
--------------------------------------------------------------------------------

local done = {}
_G.C_QuestLog = {
    IsQuestFlaggedCompleted = function(id) return done[id] == true end,
    IsOnQuest = function() return false end,
}
S.QUESTS = {
    [10] = { "Wolves of the Forest", 15, 18, 0, 0, "Marshal Dughan", 12, 42.1, 65.9, "The Fargodeep Mine", p = 11 },
    [11] = { "The Fargodeep Mine", 10, 12, 0, 0, "Marshal Dughan", 12, 42.1, 65.9, "Bounty on Murlocs", p = 12 },
    [12] = { "Bounty on Murlocs", 8, 10, 0, 0, "Guard Thomas", 12, 74, 72, "Report to Goldshire", p = 13 },
    [13] = { "Report to Goldshire", 1, 5, 0, 0, "Guard Thomas", 12, 74, 72, "" },
}
Reset()
ns.charDB.upgradeQuestSkipped = {}
ns.charDB.questsTurnedIn = nil
ns.Finder:MarkStale()
local player = ns.Finder:Player()
local chained = ns.Finder:SourcesFor(1002, player)[1]
suite.check("the finder counts the quests before it", chained.chain == 3, chained.chain)
suite.check("and says so", ns.Finder:Describe(chained):find("after 3 earlier quests", 1, true) ~= nil,
    ns.Finder:Describe(chained))
Quest:Update()
-- Three quests first make the bigger upgrade less worth the trip than the
-- vendor's, a short walk away.
suite.check("a long chain counts as more work: the Vendor tab is picked first",
    Quest:Tab() == "vendor" and Quest:Current() and Quest:Current().itemID == 1001,
    Quest:Current() and Quest:Current().itemID)
suite.check("the Quest tab still has the reward", Quest:QuestOn("quest") and Quest:QuestOn("quest").itemID == 1002)

local chainQuest = { itemID = 1002, link = "item:1002", source = chained }
steps, current = Quest:Steps(chainQuest)
suite.check("the chain comes first, from its first quest",
    steps[1].text == "Do Report to Goldshire: pick it up from Guard Thomas in Elwynn Forest (74, 72)"
    and steps[2].text == "Do Bounty on Murlocs: pick it up from Guard Thomas in Elwynn Forest (74, 72)"
    and steps[3].text == "Then 1 more quest in the chain, up to The Fargodeep Mine", StepTexts and steps[1].text)
suite.check("saying how many", steps[1].note == "3 quests to do before Wolves of the Forest.", steps[1].note)
suite.check("then the quest itself", steps[5].text:find("Pick up Wolves of the Forest", 1, true) ~= nil
    and #steps == 8, #steps)
suite.check("the first quest is the step to do now", current == 1 and steps[1].place.x == 74, current)

done[13] = true
steps = Quest:Steps(chainQuest)
suite.check("a quest done drops off the chain", steps[1].text:find("Do Bounty on Murlocs", 1, true) == 1
    and steps[2].text:find("Do The Fargodeep Mine", 1, true) == 1 and #steps == 7, steps[1].text)
done[12], done[11] = true, true
steps = Quest:Steps(chainQuest)
suite.check("the whole chain done leaves the quest itself", steps[2].text:find("Pick up Wolves", 1, true) == 1
    and #steps == 5, steps[1].text)

-- An earlier quest the data only names.
S.QUESTS[11] = { "The Fargodeep Mine", 10, 12, 0, 0, "Marshal Dughan", 12, 42.1, 65.9, "Lost Necklace" }
done[11] = nil
steps = Quest:Steps({ itemID = 1002, link = "item:1002", source = ns.Finder:SourcesFor(1002, player)[1] })
suite.check("one only named is still a step", steps[1].text == "Do Lost Necklace"
    and steps[1].note:find("Skip this one if you have done it", 1, true) ~= nil, steps[1].text)
_G.C_QuestLog = realLog
S.QUESTS = { [10] = { "Wolves of the Forest", 15, 18, 0, 0, "Marshal Dughan", 12, 42.1, 65.9, "" } }

--------------------------------------------------------------------------------
-- A level up that opens something better
--------------------------------------------------------------------------------

onQuest, ready, turnedIn = false, false, false
ns.charDB.questsTurnedIn = {}
ns.charDB.upgradeQuestSkipped = {}
Reset()
env.worn[5] = "item:900"
env.bags[0] = {}
ns.Finder:MarkStale()
Quest:Update()
local following = Quest:Current()
suite.check("following the quest reward", following and following.itemID == 1002, following and following.itemID)
-- A level up offers a better upgrade on the tab shown: here the vendor's.
Quest:SelectTab("vendor")
following = Quest:Current()
suite.check("the Vendor tab's upgrade", following and following.itemID == 1001, following and following.itemID)

-- Level 22 opens a vest only a little better than the quest's reward:
-- nothing is offered, and the quest stays.
S.ITEMS[3002] = { 22, 25, 0, 0, 500, v = { 1, 0 } }
_G.UnitLevel = function() return 22 end
ns.Finder:MarkStale()
Quest:OnEvent("PLAYER_LEVEL_UP", 22)
suite.check("a level up keeps the quest", Quest:Current() and Quest:Current().itemID == 1001)
suite.check("a little better is not offered", Quest:Offer() == nil)
S.ITEMS[3002] = nil

-- Level 23 opens one far better, sold close by.
S.ITEMS[3001] = { 22, 25, 0, 0, 500, v = { 1, 0 } }
_G.UnitLevel = function() return 23 end
ns.Finder:MarkStale()
local shown = #toasts
Quest:OnEvent("PLAYER_LEVEL_UP", 23)
local offer = Quest:Offer()
suite.check("a far better one is offered", offer and offer.pick.itemID == 3001, offer and offer.pick.itemID)
suite.check("but not swapped in", Quest:Current().itemID == 1001)
suite.check("with the level it opened at", offer and offer.level == 23, offer and offer.level)
suite.check("and a banner", #toasts > shown and toasts[#toasts].title == "New upgrade on offer")
suite.check("the panel shows the offer", Panel.offerBox:IsShown()
    and Panel.offerTitle:GetText() == "New upgrade on offer at level 23", Panel.offerTitle:GetText())
suite.check("naming it", Panel.offerName:GetText() == "item:3001", Panel.offerName:GetText())
suite.check("with Switch and Keep current", Panel.switchButton:IsShown() and Panel.keepButton:IsShown())
Quest:Update()
suite.check("offered once, not again on every update", #toasts == shown + 1, #toasts - shown)

Panel.keepButton:GetScript("OnClick")(Panel.keepButton)
suite.check("Keep current leaves the quest", Quest:Current().itemID == 1001 and Quest:Offer() == nil)
suite.check("and the box goes", not Panel.offerBox:IsShown())
_G.UnitLevel = function() return 24 end
ns.Finder:MarkStale()
Quest:OnEvent("PLAYER_LEVEL_UP", 24)
suite.check("one kept past is not offered again", Quest:Offer() == nil)

Quest.declined = {}
_G.UnitLevel = function() return 25 end
ns.Finder:MarkStale()
Quest:OnEvent("PLAYER_LEVEL_UP", 25)
suite.check("offered again after a log in", Quest:Offer() ~= nil)
Panel.switchButton:GetScript("OnClick")(Panel.switchButton)
suite.check("Switch follows it", Quest:Current().itemID == 3001 and Quest:Offer() == nil)
suite.check("with its own steps", StepTexts():find("Buy item:3001", 1, true) ~= nil, StepTexts())
suite.check("the box goes", not Panel.offerBox:IsShown())

Quest:OnEvent("BAG_UPDATE_DELAYED")
suite.check("nothing is offered without a level up", Quest:Offer() == nil)
ns.HandleSlash("quest switch")
suite.check("/beq quest switch with nothing on offer says so",
    env.ChatText():find("no new upgrade is on offer", 1, true) ~= nil)

S.ITEMS[3001] = nil
_G.UnitLevel = function() return 20 end
Reset()
ns.Finder:MarkStale()
Quest:Update()

--------------------------------------------------------------------------------
-- Tabs: one upgrade per kind of source
--------------------------------------------------------------------------------

Reset()
ns.charDB.upgradeQuestSkipped = {}
ns.Finder:MarkStale()
Quest:Update()
suite.check("the first time, the tab most worth the trip is shown", Quest:Tab() == "quest"
    and Quest:Current().itemID == 1002, Quest:Tab())
suite.check("each tab keeps its own", Quest:QuestOn("vendor").itemID == 1001 and Quest:QuestOn("quest").itemID == 1002
    and Quest:QuestOn("dungeon") == nil and Quest:QuestOn("craft") == nil)
suite.check("the copy older versions read follows the tab shown", ns.charDB.upgradeQuest == Quest:Current())

Panel:Refresh()
suite.check("four source tabs and the Quest log tab on the panel", #Panel.tabs == 5
    and Panel.tabs[1].label:GetText() == "Vendor" and Panel.tabs[3].label:GetText() == "Dungeons and Raids"
    and Panel.tabs[4].label:GetText() == "Crafted" and Panel.tabs[5].label:GetText() == "Quest log")
suite.check("the tabs hang from the panel, not the screen's corner", (function()
    for _, tab in ipairs(Panel.tabs) do
        if rawget(tab, "_parent") ~= Panel.frame then return false end
        local point = rawget(tab, "_point")
        if not (point and point[2] == Panel.frame) then return false end
    end
    return true
end)())
suite.check("the one shown is lit", Panel.tabs[2].shown and not Panel.tabs[1].shown)
suite.check("a tab with nothing on it is dimmed", Panel.tabs[3].empty and not Panel.tabs[1].empty)
suite.check("the header names the tab", Panel.title:GetText() == "Quest", Panel.title:GetText())
suite.check("tabs fit across the panel", (function()
    local total = 0
    for _, tab in ipairs(Panel.tabs) do total = total + tab:GetWidth() end
    return total + (#Panel.tabs - 1) * 4 <= Panel.WIDTH - 20 + 0.01
end)())
suite.check("hovering a tab says what is on it", pcall(Panel.tabs[1]:GetScript("OnEnter"), Panel.tabs[1]))

Panel.tabs[1]:GetScript("OnClick")(Panel.tabs[1])
suite.check("clicking a tab shows its upgrade", Quest:Tab() == "vendor" and Quest:Current().itemID == 1001
    and Panel.name:GetText() == "item:1001", Panel.name:GetText())
suite.check("and the other tab's is kept", Quest:QuestOn("quest").itemID == 1002)
Panel.tabs[2]:GetScript("OnClick")(Panel.tabs[2])
suite.check("flipping back finds it as it was", Quest:Current().itemID == 1002)

ns.HandleSlash("quest crafted")
suite.check("/beq quest crafted shows the Crafted tab", Quest:Tab() == "craft"
    and env.ChatText():find("showing the Crafted tab", 1, true) ~= nil)
suite.check("which says when it has nothing", Panel.empty:IsShown()
    and Panel.empty:GetText():find("No crafted upgrade right now", 1, true) ~= nil, Panel.empty:GetText())
ns.HandleSlash("quest dungeons")
suite.check("/beq quest dungeons", Quest:Tab() == "dungeon")

-- The tab is picked on the panel or typed; Settings has no row for it
-- (the owner, 2026-10-15).
ns.SettingsUI:Show()
suite.check("Settings has no quest tab row", ns.SettingsUI.controls.questTab == nil)
ns.HandleSlash("quest vendor")
suite.check("/beq quest vendor picks one", Quest:Tab() == "vendor", Quest:Tab())
ns.SettingsUI:Hide()

-- Worn, the same upgrade on two tabs is one quest done.
local doneBefore = Quest:DoneCount()
env.worn[5] = "item:1002"
Quest:Update()
suite.check("worn from another tab, it is done once", Quest:DoneCount() == doneBefore + 1, Quest:DoneCount())
env.worn[5] = "item:900"

-- A quest saved before there were tabs goes on its own tab.
ns.charDB.upgradeQuestTabs = nil
ns.charDB.upgradeQuestTab = nil
ns.charDB.upgradeQuest = { itemID = 1002, link = "item:1002", source = { kind = "quest", questID = 10 } }
suite.check("an older quest is kept, on its tab", Quest:QuestOn("quest") and Quest:QuestOn("quest").itemID == 1002
    and Quest:Tab() == "quest")

-- The close gem turns the quest off, its quests kept.
Panel:Refresh()
Panel.trim.closeButton:GetScript("OnClick")(Panel.trim.closeButton)
suite.check("the close gem turns it off", ns.db.upgradeQuest == false and not Panel.frame:IsShown())
suite.check("and says how to bring it back", env.ChatText():find("Bring it back", 1, true) ~= nil)
suite.check("keeping its quests", Quest:QuestOn("quest") ~= nil)
ns.HandleSlash("quest")

--------------------------------------------------------------------------------
-- Text that wraps, and turning it off
--------------------------------------------------------------------------------

suite.check("long steps wrap rather than cut", Panel.Lines("small",
    "Pick up Wolves of the Forest from Marshal Dughan in Elwynn Forest (42.1, 65.9)", 200) > 1)
suite.check("short ones take one line", Panel.Lines("small", "Put It On", 200) == 1)
suite.check("a link's hidden part takes no room",
    Panel.Lines("small", "|cff1eff00|Hitem:1001::::::::20:::::|h[Vest]|h|r", 60) == 1)

-- Ignore and Switch are on the panel and typed; Settings keeps Open and
-- Ignored (the owner, 2026-10-15).
ns.SettingsUI:Show()
local controls = ns.SettingsUI.controls
local function Click(button) button:GetScript("OnClick")(button) end
suite.check("Settings has no Ignore or Switch button",
    controls.questSkip == nil and controls.questSwitch == nil)
local skippedID = Quest:Current() and Quest:Current().itemID
ns.HandleSlash("quest ignore")
suite.check("/beq quest ignore ignores", skippedID and ns.charDB.upgradeQuestSkipped[skippedID] == true
    and (Quest:Current() == nil or Quest:Current().itemID ~= skippedID))
ns.HandleSlash("quest switch")
suite.check("/beq quest switch with nothing on offer says so",
    env.ChatText():find("no new upgrade is on offer", 1, true) ~= nil)
Click(controls.questReset)
suite.check("the Ignored button lists them", ns.IgnoredUI.frame and ns.IgnoredUI.frame:IsShown())
Click(ns.IgnoredUI.restoreAll)
suite.check("and Restore all brings them back", next(ns.charDB.upgradeQuestSkipped) == nil)
ns.IgnoredUI:Hide()
ns.HandleSlash("quest off")
Click(controls.questOpen)
suite.check("the Open button turns it on and shows the panel", ns.db.upgradeQuest == true
    and Panel.frame:IsShown() and controls.upgradeQuest:GetChecked())

local box = ns.SettingsUI.controls.upgradeQuest
suite.check("the settings box is ticked while it is on", box:GetChecked())
box:GetScript("OnClick")(box)
suite.check("unticking it turns it off", ns.db.upgradeQuest == false and not Panel.frame:IsShown())
suite.check("the quest is kept for next time", Quest:Current() ~= nil)
ns.HandleSlash("quest off")
suite.check("/beq quest off", ns.db.upgradeQuest == false)

ns.SettingsUI:ResetPositions()
suite.check("the panel's spot is reset with the others", ns.db.questPoint == nil)

--------------------------------------------------------------------------------
-- Looting and the quest log do not rescan a tab that found nothing
--------------------------------------------------------------------------------

local clock = 1000
local realTime = rawget(_G, "time")
_G.time = function() return clock end
ns.HandleSlash("quest")
Quest:OnEvent("PLAYER_EQUIPMENT_CHANGED")
local emptyNone = 0
for _, tab in ipairs(Quest.TABS) do
    if not Quest:Quests()[tab.key] and Quest.states[tab.key] == "none" then emptyNone = emptyNone + 1 end
end
suite.check("some tab has nothing to chase", emptyNone > 0, emptyNone)
-- Each event also reaches the finder, which marks its last scan out of date.
local function Event(name)
    if name ~= "QUEST_LOG_UPDATE" and name ~= "ZONE_CHANGED_NEW_AREA" then ns.Finder:MarkStale() end
    Quest:OnEvent(name)
end
local realBuild, scans = ns.Finder.Build, 0
ns.Finder.Build = function(...) scans = scans + 1 return realBuild(...) end
for _ = 1, 20 do
    Event("BAG_UPDATE_DELAYED")
    Event("QUEST_LOG_UPDATE")
    Event("ZONE_CHANGED_NEW_AREA")
end
suite.check("twenty loots and quest log ticks scan nothing", scans == 0, scans)
clock = clock + 61
Event("BAG_UPDATE_DELAYED")
suite.check("a bag change a minute later looks once", scans == 1, scans)
Event("BAG_UPDATE_DELAYED")
suite.check("and not again straight after", scans == 1, scans)
Event("PLAYER_EQUIPMENT_CHANGED")
suite.check("new gear worn looks again", scans == 2, scans)
ns.Finder.Build = realBuild
_G.time = realTime

--------------------------------------------------------------------------------
-- A bag change or quest log tick that moves nothing on the panel draws
-- nothing again; one that ticks a step off does
--------------------------------------------------------------------------------

do
    local realChanged, draws = Quest.Changed, 0
    Quest.Changed = function(self, ...) draws = draws + 1 return realChanged(self, ...) end
    local quest = Quest:Current()
    suite.check("a quest is shown to draw", quest ~= nil)
    Quest:OnEvent("BAG_UPDATE_DELAYED")
    draws = 0
    for _ = 1, 10 do
        Quest:OnEvent("BAG_UPDATE_DELAYED")
        Quest:OnEvent("QUEST_LOG_UPDATE")
    end
    suite.check("ten quiet bag changes and quest log ticks draw nothing", draws == 0, draws)
    if quest then
        env.bags[0] = { [1] = "item:" .. quest.itemID }
        Quest:OnEvent("BAG_UPDATE_DELAYED")
        suite.check("getting the upgrade ticks a step off and draws once", draws == 1, draws)
        env.bags[0] = {}
        Quest:OnEvent("BAG_UPDATE_DELAYED")
    end
    draws = 0
    local other = Quest:Tab() == "vendor" and "quest" or "vendor"
    Quest:SelectTab(other)
    suite.check("a click always draws", draws >= 1, draws)
    Quest.Changed = realChanged
end

ns.Toast.Show = realShow
suite.done()
