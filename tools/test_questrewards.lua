-- The arrow on the best quest reward, and the chat line on hand-in.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("questrewards")

local function Agi(n) return { ITEM_MOD_AGILITY_SHORT = n } end

local ITEMS = {
    ["item:1"] = { loc = "INVTYPE_CHEST", class = 4, subclass = 2, stats = Agi(10) },
    ["item:2"] = { loc = "INVTYPE_CHEST", class = 4, subclass = 2, stats = Agi(12) },
    ["item:3"] = { loc = "INVTYPE_FEET", class = 4, subclass = 2, stats = Agi(4) },
    ["item:4"] = { loc = "INVTYPE_SHIELD", class = 4, subclass = 6, stats = Agi(40) },
    ["item:5"] = { loc = "INVTYPE_CHEST", class = 4, subclass = 2, stats = Agi(5) },
    ["item:6"] = { loc = "INVTYPE_CHEST", class = 4, subclass = 2, stats = Agi(40), minLevel = 30 },
}

--- A reward button as the game makes one.
local function Button(kind, id)
    local button = env.Stub({ type = kind, _textures = {} })
    button.GetID = function() return id end
    button.CreateTexture = function(self)
        local texture = env.Stub()
        self._textures[#self._textures + 1] = texture
        return texture
    end
    return button
end

local function Arrow(button) return button._textures[1] end

local function LoadWith(choices, named, fixed)
    fixed = fixed or { "item:5" }
    local ns = env.Load()
    _G.UnitClass = function() return "HUNTER", "HUNTER" end
    env.InstallItems(ITEMS, { [5] = "item:1" })
    env.InstallHooks()
    _G.GetNumQuestChoices = function() return #choices end
    _G.GetNumQuestRewards = function() return #fixed end
    _G.GetQuestItemLink = function(kind, index)
        if kind == "choice" then return choices[index] end
        if kind == "reward" then return fixed[index] end
    end

    local buttons = {}
    for i = 1, #choices do buttons[i] = Button("choice", i) end
    -- Rewards given outright, alongside the choices.
    for i = 1, #fixed do buttons[#buttons + 1] = Button("reward", i) end

    _G.QuestInfoRewardsFrame = nil
    for i = 1, 10 do _G["QuestInfoRewardsFrameQuestInfoItem" .. i] = nil end
    if named then
        for i, button in ipairs(buttons) do _G["QuestInfoRewardsFrameQuestInfoItem" .. i] = button end
    else
        _G.QuestInfoRewardsFrame = env.Stub({ RewardButtons = buttons })
    end

    _G.QuestInfo_Display = function() end
    _G.QuestFrame = env.Stub({ _shown = true })
    ns.QuestRewards:OnEnable()
    return ns, buttons
end

-- A chest a little better, boots for an empty slot, and a shield.
local ns, buttons = LoadWith({ "item:2", "item:3", "item:4" })
local index = ns.QuestRewards:Best()
suite.check("the empty boot slot is the bigger gain", index == 2, index)

_G.QuestInfo_Display()
suite.check("the hooked layout marks it", Arrow(buttons[2]) and Arrow(buttons[2]):IsShown())
suite.check("the others are not marked", not Arrow(buttons[1]) and not Arrow(buttons[3]))
suite.check("nor a fixed reward that is no upgrade", not Arrow(buttons[4]))

ns.QuestRewards:QUEST_COMPLETE()
local chat = env.ChatText()
suite.check("hand-in names the best reward", chat:find("best reward for Beast Mastery: item:3", 1, true), chat)
suite.check("and why", chat:find("fills an empty slot", 1, true), chat)

-- The quest log draws through the same function; with the quest giver's
-- window closed the arrows come off rather than marking a stale choice.
_G.QuestFrame:Hide()
_G.QuestInfo_Display()
suite.check("the quest log view hides the arrow", not Arrow(buttons[2]):IsShown())
_G.QuestFrame:Show()

-- A reward the client has not described yet: no "none of these" line, and
-- the real answer once its details arrive.
ns, buttons = LoadWith({ "item:5", "item:7" })
local timers = {}
local immediate = _G.C_Timer.After
_G.C_Timer.After = function(_, fn) timers[#timers + 1] = fn end
ITEMS["item:7"] = { loc = "INVTYPE_FEET", class = 4, subclass = 2, stats = nil }
ns.QuestRewards:QUEST_COMPLETE()
for _, fn in ipairs(timers) do if fn ~= timers[#timers] then fn() end end
suite.check("an unloaded reward waits", not env.ChatText():find("none of these", 1, true), env.ChatText())
-- An item's answer books one pass for the burst it comes in; this runs it.
local ran = #timers
local function Settle()
    for index = ran + 1, #timers do timers[index]() end
    ran = #timers
end
-- Some other item's answer arrives first: still waiting.
ns.QuestRewards:GET_ITEM_INFO_RECEIVED()
Settle()
suite.check("an unrelated answer does not end the wait", ns.QuestRewards.announcePending == true)
ITEMS["item:7"].stats = Agi(3)
ns.QuestRewards:GET_ITEM_INFO_RECEIVED()
ns.QuestRewards:GET_ITEM_INFO_RECEIVED()
suite.check("a burst of answers books one pass", #timers == ran + 1, #timers - ran)
Settle()
suite.check("and is announced when it arrives",
    env.ChatText():find("best reward for Beast Mastery: item:7", 1, true), env.ChatText())

-- A reward that never arrives: after a moment, a known pick is named, and
-- "none of these" is never said on a guess.
env.chat = {}
ITEMS["item:8"] = { loc = "INVTYPE_FEET", class = 4, subclass = 2, stats = nil }
ns, buttons = LoadWith({ "item:5", "item:8" })
timers = {}
_G.C_Timer.After = function(_, fn) timers[#timers + 1] = fn end
ns.QuestRewards:QUEST_COMPLETE()
timers[#timers]()
suite.check("giving up on an unknown reward stays quiet",
    not env.ChatText():find("none of these", 1, true), env.ChatText())
_G.C_Timer.After = immediate

-- Nothing worth taking.
ns, buttons = LoadWith({ "item:5", "item:4", "item:6" })
suite.check("no upgrade, no pick", ns.QuestRewards:Best() == nil)
suite.check("an item above your level is not picked", ns.QuestRewards:Mark() == nil)
ns.QuestRewards:QUEST_COMPLETE()
suite.check("and chat says none beats your gear",
    env.ChatText():find("none of these rewards beats what you wear", 1, true), env.ChatText())

-- Nothing is an upgrade: the coin goes on the choice a vendor pays the most
-- for, by the tooltip's Sell Price, times how many the quest hands over.
local PRICES = { ["item:5"] = 300, ["item:4"] = 250, ["item:6"] = 40 }
local COUNTS = { 1, 2, 1 }
local function InstallPrices()
    _G.C_TooltipInfo = {
        GetHyperlink = function(link)
            return { lines = { { leftText = "Item" }, { type = 11, price = PRICES[link] } } }
        end,
    }
    _G.GetQuestItemInfo = function(kind, index)
        if kind == "choice" then return "Item", "icon", COUNTS[index] end
    end
end
env.chat = {}
ns, buttons = LoadWith({ "item:5", "item:4", "item:6" })
InstallPrices()
local Coin = function(button) return ns.QuestRewards:Coin(button) end
local rich, _, copper = ns.QuestRewards:MostValuable()
suite.check("two shields beat one chest", rich == 2 and copper == 500, copper)
ns.QuestRewards:Mark()
suite.check("the coin is on them", Coin(buttons[2]):IsShown())
suite.check("and not on the others", not Coin(buttons[1]):IsShown() and not Coin(buttons[3]):IsShown())
suite.check("with no arrow", not ns.BagIcons:ExistingArrow(buttons[2]))
ns.QuestRewards:QUEST_COMPLETE()
said = env.ChatText()
suite.check("chat says which to take", said:find("so take item:4. It sells for the most", 1, true), said)
suite.check("and for how much", said:find("5s", 1, true), said)

-- An upgrade among the choices takes the coin off.
ns, buttons = LoadWith({ "item:5", "item:2" })
InstallPrices()
ns.QuestRewards:Mark()
suite.check("an upgrade gets the arrow, not the coin",
    Arrow(buttons[2]):IsShown() and not (ns.QuestRewards:Coin(buttons[1]):IsShown()))
-- The quest log view takes it off too.
ns, buttons = LoadWith({ "item:5", "item:4" })
InstallPrices()
ns.QuestRewards:Mark()
_G.QuestFrame:Hide()
_G.QuestInfo_Display()
suite.check("the quest log view hides the coin", not ns.QuestRewards:Coin(buttons[2]):IsShown())
_G.QuestFrame:Show()
-- No tooltip: the item info's price.
_G.C_TooltipInfo = nil
suite.check("the item info's price without a tooltip", ns.Items:SellPrice("item:5") == 100, ns.Items:SellPrice("item:5"))
_G.GetQuestItemInfo = nil

-- The classic window, with named buttons.
ns, buttons = LoadWith({ "item:5", "item:2" }, true)
suite.check("named buttons are marked too", ns.QuestRewards:Mark() == 2)
suite.check("on the right one", Arrow(buttons[2]) and Arrow(buttons[2]):IsShown())

-- The arrow moves when the pick does, and the setting takes it off.
env.worn[5] = "item:2"
ns.QuestRewards:Mark()
suite.check("an arrow comes off when the choice stops being an upgrade", not Arrow(buttons[2]):IsShown())
env.worn[5] = "item:1"
ns.db.bagArrows = false
suite.check("the arrows setting switches it off", ns.QuestRewards:Mark() == nil)
suite.check("and hides the arrow", not Arrow(buttons[2]):IsShown())
ns.db.bagArrows = true

-- One reward that is no upgrade, nothing to choose: no chat line.
env.chat = {}
ns = LoadWith({ "item:5" })
ns.QuestRewards:QUEST_COMPLETE()
suite.check("a single reward is not announced", not env.ChatText():find("reward", 1, true), env.ChatText())

-- A lone choice that is an upgrade comes with the quest anyway: said so.
env.chat = {}
ns = LoadWith({ "item:2" })
ns.QuestRewards:QUEST_COMPLETE()
suite.check("a lone upgrade is named", env.ChatText():find("this quest gives you item:2", 1, true), env.ChatText())
suite.check("without a choice line", not env.ChatText():find("none of", 1, true), env.ChatText())

-- Choices that are no upgrade, and gloves given outright that are
-- (Cry of the Thunderhawk): the gloves get the arrow and the chat line.
ITEMS["item:9"] = { loc = "INVTYPE_HAND", class = 4, subclass = 2, stats = Agi(6) }
env.chat = {}
ns, buttons = LoadWith({ "item:5", "item:6" }, false, { "item:9" })
suite.check("no choice is picked", ns.QuestRewards:Mark() == nil)
suite.check("the given gloves are marked", Arrow(buttons[3]) and Arrow(buttons[3]):IsShown())
suite.check("the choices get no arrow", not ns.BagIcons:ExistingArrow(buttons[1]) and not ns.BagIcons:ExistingArrow(buttons[2]))
ns.QuestRewards:QUEST_COMPLETE()
local said = env.ChatText()
suite.check("chat names the given upgrade", said:find("this quest gives you item:9", 1, true), said)
suite.check("and why", said:find("fills an empty slot", 1, true), said)
suite.check("never says no reward helps", not said:find("none of these rewards", 1, true), said)
suite.check("only that no choice does", said:find("none of the rewards to choose from", 1, true), said)

-- A given reward the client has not described yet holds the line back.
ITEMS["item:10"] = { loc = "INVTYPE_HAND", class = 4, subclass = 2, stats = nil }
env.chat = {}
ns = LoadWith({ "item:5", "item:6" }, false, { "item:10" })
timers = {}
_G.C_Timer.After = function(_, fn) timers[#timers + 1] = fn end
ns.QuestRewards:QUEST_COMPLETE()
suite.check("an unloaded given reward waits", not env.ChatText():find("none of", 1, true), env.ChatText())
suite.check("and holds its line", ns.QuestRewards.announcePending == true)
ITEMS["item:10"].stats = Agi(5)
ns.QuestRewards:GET_ITEM_INFO_RECEIVED()
timers[#timers]()
suite.check("and is named once it arrives",
    env.ChatText():find("this quest gives you item:10", 1, true), env.ChatText())
_G.C_Timer.After = immediate

-- Take the reward: a button under the quest window on the hand-in page,
-- for the biggest upgrade, and one click hands the quest in with it.
ns, buttons = LoadWith({ "item:2", "item:3", "item:4" })
_G.QuestFrame.GetLeft = function() return 100 end
_G.QuestFrame.GetRight = function() return 450 end
_G.QuestFrame.GetBottom = function() return 200 end
local taken
_G.GetQuestReward = function(choice) taken = choice end
ns.QuestRewards:QUEST_COMPLETE()
local take = ns.QuestRewards.take
suite.check("a Take button on the hand-in page", take and take:IsShown())
suite.check("naming the biggest upgrade", take and take.first:GetText():find("Take", 1, true) ~= nil
    and take.second:GetText():find("fills an empty slot", 1, true) ~= nil,
    take and (tostring(take.first:GetText()) .. " / " .. tostring(take.second:GetText())))
suite.check("under the quest window, placed by screen position, not anchored to it",
    take and take._point and take._point[2] == UIParent)
suite.check("with no foot buttons, it goes by the frame's own edges",
    take and take._point and take._point[4] == 275 and take._point[5] == 196,
    take and take._point and tostring(take._point[4]) .. "," .. tostring(take._point[5]))

-- Classic Era: the frame reaches far below its art, so the button goes
-- just under the window's own Complete Quest and Cancel buttons instead.
_G.QuestFrameCompleteQuestButton = { IsVisible = function() return true end,
    GetLeft = function() return 120 end, GetRight = function() return 230 end, GetBottom = function() return 280 end }
_G.QuestFrameCancelButton = { IsVisible = function() return true end,
    GetLeft = function() return 320 end, GetRight = function() return 420 end, GetBottom = function() return 282 end }
_G.QuestFrameGoodbyeButton = { IsVisible = function() return false end,
    GetLeft = function() return 0 end, GetRight = function() return 900 end, GetBottom = function() return 0 end }
ns.QuestRewards:UpdateTake()
suite.check("under the window's own buttons, not the frame's far edge",
    take._point[4] == 270 and take._point[5] == 280 - ns.QuestRewards.FOOT_GAP - 4,
    tostring(take._point[4]) .. "," .. tostring(take._point[5]))
_G.QuestFrameCompleteQuestButton, _G.QuestFrameCancelButton, _G.QuestFrameGoodbyeButton = nil, nil, nil

take:GetScript("OnClick")(take)
suite.check("a click takes that reward", taken == 2, taken)

-- Not on the page where the quest is offered.
ns.QuestRewards:Moved()
suite.check("gone when the window moves on", not take:IsShown())
_G.QuestInfo_Display()
suite.check("and not shown when a quest is only offered", not take:IsShown())

-- No upgrade: it takes what sells for the most.
ns = LoadWith({ "item:5", "item:6" })
_G.QuestFrame.GetLeft = function() return 100 end
_G.QuestFrame.GetRight = function() return 450 end
_G.QuestFrame.GetBottom = function() return 200 end
local index = ns.QuestRewards:MostValuable()
ns.QuestRewards:QUEST_COMPLETE()
take = ns.QuestRewards.take
if index then
    suite.check("with no upgrade, it takes what sells for the most", take and take:IsShown() and take.choice == index)
else
    suite.check("with nothing worth anything, no button", not (take and take:IsShown()))
end

-- Turned off in Settings.
ns.db.rewardButton = false
ns.QuestRewards:UpdateTake()
suite.check("the setting turns it off", not (take and take:IsShown()))

-- A client that raises costs the arrow, not an error.
ns = LoadWith({ "item:2", "item:3" })
_G.GetQuestItemLink = function() error("secret value") end
suite.check("a link that raises does not break it", ns.QuestRewards:Refresh() == true)
suite.check("and marks nothing", ns.QuestRewards.lastMarked == nil)

suite.done()
