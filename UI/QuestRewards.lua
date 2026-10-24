-- Blackthornes Equipment -- UI/QuestRewards.lua
-- When a quest lets you choose a reward, put the green arrow on the choice
-- that is the biggest upgrade for your spec, and say which in chat when you
-- hand the quest in. A reward the quest gives outright ("You will also
-- receive") gets the arrow and a chat line too when it is an upgrade.
--
-- Each reward is judged exactly as bag items are (Compare:Judge), so the
-- arrow here, the arrow in the bags and the tooltip line agree. Only an
-- upgrade that can be worn now is marked; when no choice is one, the choice
-- a vendor pays the most for gets a gold coin instead, and chat says so.
--
-- The reward buttons are the game's own quest window buttons. As in the
-- bags, the arrow is a texture this addon adds over one; nothing of
-- Blizzard's is changed.

local _, ns = ...
local L = ns.L

local QuestRewards = ns.NewModule("QuestRewards")

local Compare = ns.Compare
local Items = ns.Items

-- The most reward buttons the classic quest window names.
local MAX_BUTTONS = 10

local function Field(object, key)
    if type(object) ~= "table" then return nil end
    local ok, value = pcall(function() return object[key] end)
    if ok then return value end
    return nil
end

local function Ask(object, method, ...)
    local fn = Field(object, method)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, object, ...)
    if ok then return value end
    return nil
end

-- The same switch as the bag arrows: one setting for every upgrade arrow.
function QuestRewards:IsEnabled()
    return not (ns.db and ns.db.bagArrows == false)
end

--------------------------------------------------------------------------------
-- The choices
--------------------------------------------------------------------------------

--- How many rewards the open quest lets you choose between.
function QuestRewards:Count()
    return tonumber((Items.Call({ "GetNumQuestChoices" }))) or 0
end

--- The link of choice `index`, or nil.
function QuestRewards:Link(index)
    return Items.PlainLink(Items.Call({ "GetQuestItemLink" }, "choice", index))
end

--- Has the client got an item's details? True when it cannot say.
function QuestRewards:IsCached(link)
    local id = tonumber(link:match("item:(%d+)"))
    local cached = id and Items.Call({ "C_Item.IsItemDataCachedByID" }, id)
    if cached == nil then return Items:Info(link) ~= nil and Items:Stats(link) ~= nil end
    return cached == true
end

--- How many rewards the open quest gives outright, besides the choices.
function QuestRewards:FixedCount()
    return tonumber((Items.Call({ "GetNumQuestRewards" }))) or 0
end

--- The link of fixed reward `index`, or nil.
function QuestRewards:FixedLink(index)
    return Items.PlainLink(Items.Call({ "GetQuestItemLink" }, "reward", index))
end

--- Judge one reward as a carried item.
-- @return the verdict or nil, and whether it is gear still worth waiting
-- for: no link yet, or gear whose stats have not arrived. A cached item
-- that still cannot be judged is not.
function QuestRewards:Judge(link)
    local ok, result = pcall(Compare.JudgeCarried, Compare, link)
    if not ok then return nil, false end
    if result ~= nil then return result, false end
    if not link then return nil, true end
    local okInfo, info = pcall(Items.Info, Items, link)
    local gear = okInfo and (info == nil or Compare.SLOTS[info.equipLoc])
    return nil, (gear and not Items:Stats(link) and not self:IsCached(link)) and true or false
end

--- The rewards given outright that are upgrades that can be worn now.
-- @return a list of { index, link, result }, and how many fixed rewards
-- could not be judged yet
function QuestRewards:Given()
    local given, unknown = {}, 0
    for index = 1, self:FixedCount() do
        local link = self:FixedLink(index)
        local result, waiting = self:Judge(link)
        if waiting then unknown = unknown + 1 end
        if Compare.WearableUpgrade(result) then
            given[#given + 1] = { index = index, link = link, result = result }
        end
    end
    return given, unknown
end

--- The choice that is the biggest upgrade that can be worn now.
-- @return index, link, result; or nil when none of them is one
-- The fourth return is how many choices are gear whose details the client
-- has not had yet, so they could not be judged.
function QuestRewards:Best()
    local bestIndex, bestLink, bestResult, bestGain
    local unknown = 0
    for index = 1, self:Count() do
        local link = self:Link(index)
        local result, waiting = self:Judge(link)
        if waiting then unknown = unknown + 1 end
        if Compare.WearableUpgrade(result) then
            -- Gain in score, not percent: +5 on a slot worth 50 beats +50% on
            -- a slot worth 2. An empty slot counts its whole score.
            local gain = (result.score or 0) - (result.against or 0)
            if not bestGain or gain > bestGain then
                bestIndex, bestLink, bestResult, bestGain = index, link, result, gain
            end
        end
    end
    return bestIndex, bestLink, bestResult, unknown
end

--- How many of choice `index` the quest hands over (a stack of potions).
function QuestRewards:Quantity(index)
    local _, _, count = Items.Call({ "GetQuestItemInfo" }, "choice", index)
    local ok, number = pcall(function() return tonumber(count) end)
    return ok and number and number > 0 and number or 1
end

--- The choice a vendor pays the most for, for when none is an upgrade.
-- @return index, link, copper; or nil when no choice sells for anything
-- (or there is only one: nothing to choose)
function QuestRewards:MostValuable()
    if self:Count() < 2 then return nil end
    local bestIndex, bestLink, bestCopper
    for index = 1, self:Count() do
        local link = self:Link(index)
        local price = link and Items:SellPrice(link)
        local copper = price and price * self:Quantity(index) or 0
        if copper > 0 and (not bestCopper or copper > bestCopper) then
            bestIndex, bestLink, bestCopper = index, link, copper
        end
    end
    return bestIndex, bestLink, bestCopper
end

--------------------------------------------------------------------------------
-- The buttons
--------------------------------------------------------------------------------

-- The gold coin on the choice worth the most at a vendor: a texture this
-- addon adds over the button, as the arrow is, kept here by button.
local COIN_TEXTURE = "Interface\\MoneyFrame\\UI-GoldIcon"
local coins = setmetatable({}, { __mode = "k" })

function QuestRewards:Coin(button)
    if coins[button] then return coins[button] end
    local create = Field(button, "CreateTexture")
    if type(create) ~= "function" then return nil end
    local ok, texture = pcall(create, button, nil, "OVERLAY", nil, 7)
    if not ok or not texture then return nil end
    texture:SetSize(14, 14)
    texture:SetPoint("TOPLEFT", button, "TOPLEFT", 2, -2)
    texture:SetTexture(COIN_TEXTURE)
    texture:Hide()
    coins[button] = texture
    return texture
end

--- Every reward button in the quest window, choices and fixed rewards alike.
function QuestRewards:Buttons()
    local buttons = {}
    local list = Field(_G.QuestInfoRewardsFrame, "RewardButtons")
    if type(list) == "table" then
        for _, button in ipairs(list) do buttons[#buttons + 1] = button end
    end
    if #buttons == 0 then
        for i = 1, MAX_BUTTONS do
            local button = _G["QuestInfoRewardsFrameQuestInfoItem" .. i]
            if type(button) ~= "table" then break end
            buttons[#buttons + 1] = button
        end
    end
    return buttons
end

--- The button showing choice `index`: the game marks choices with
--- type "choice" and numbers them through GetID.
function QuestRewards:ButtonFor(index)
    for _, button in ipairs(self:Buttons()) do
        if Field(button, "type") == "choice" and Ask(button, "GetID") == index then
            return button
        end
    end
    return nil
end

--- Put the arrow on the best choice and on each fixed reward that is an
--- upgrade, and take it off the rest.
-- @return the choice index marked, or nil
function QuestRewards:Mark()
    local enabled = self:IsEnabled()
    local best = enabled and self:Best() or nil
    local fixed = {}
    if enabled then
        for _, upgrade in ipairs((self:Given())) do fixed[upgrade.index] = true end
    end
    -- No choice helps: the coin goes on the one worth the most to sell.
    local richest = enabled and best == nil and self:MostValuable() or nil
    local marked = nil

    for _, button in ipairs(self:Buttons()) do
        local kind, id = Field(button, "type"), Ask(button, "GetID")
        local isBest = best ~= nil and kind == "choice" and id == best
        local isFixed = kind == "reward" and id ~= nil and fixed[id] == true
        local coin = coins[button]
        if richest ~= nil and kind == "choice" and id == richest then
            coin = self:Coin(button)
            if coin then coin:Show() end
        elseif coin then
            coin:Hide()
        end
        if isBest or isFixed then
            local arrow = ns.BagIcons:Arrow(button)
            if arrow then
                arrow:Show()
                if isBest then marked = best end
            end
        else
            local arrow = ns.BagIcons:ExistingArrow(button)
            if arrow then arrow:Hide() end
        end
    end
    self.lastMarked = marked
    return marked
end

--- Take the arrow and the coin off every reward button.
function QuestRewards:HideArrows()
    for _, button in ipairs(self:Buttons()) do
        if coins[button] then coins[button]:Hide() end
        local arrow = ns.BagIcons:ExistingArrow(button)
        if arrow then arrow:Hide() end
    end
end

--------------------------------------------------------------------------------
-- Take it
--
-- One click on the right reward (the owner, 2026-10-11: the addons should do
-- the work for the player). A button of this addon's own, parented to
-- UIParent and placed under the quest window by screen position (read
-- only), never anchored to it or put inside it. It names the pick: the
-- biggest upgrade, else the choice a vendor pays the most for. Its click
-- hands the quest in with that reward through the game's GetQuestReward,
-- the call the window's own Complete button makes. "Take reward button"
-- in Settings (`rewardButton`, on unless unticked).
--------------------------------------------------------------------------------

local function NameOf(link)
    local name = type(link) == "string" and link:match("%[(.-)%]")
    if not name then
        local info = Items.Call({ "C_Item.GetItemInfo", "GetItemInfo" }, link)
        name = type(info) == "string" and info or nil
    end
    return name or L["it"]
end

function QuestRewards:TakeEnabled()
    return not (ns.db and ns.db.rewardButton == false)
end

--- What the button would take: index, link and its words, or nil.
function QuestRewards:Pick()
    if self:Count() < 2 then return nil end
    local index, link, result, unknown = self:Best()
    if index then
        return index, link, L.Format("Take %s (%s)", NameOf(link), Compare:HowMuch(result))
    end
    if unknown and unknown > 0 then return nil end
    local richIndex, richLink, copper = self:MostValuable()
    if richIndex then
        local money = copper and ns.Finder and ns.Finder.Money and ns.Finder.Money(copper)
        local name = NameOf(richLink)
        return richIndex, richLink, money and L.Format("Take %s (sells for %s)", name, money)
            or L.Format("Take %s", name)
    end
end

function QuestRewards:BuildTake()
    if self.take then return self.take end
    local button = ns.Widgets.CreateButton(UIParent, L["Take"], function(frame)
        local index = rawget(frame, "choice")
        if not index then return end
        local take = rawget(_G, "GetQuestReward")
        if type(take) == "function" then pcall(take, index) end
        frame:Hide()
    end, { width = 220, height = 24, primary = true })
    button:SetFrameStrata("DIALOG")
    button:HookScript("OnEnter", function(frame)
        local link = rawget(frame, "link")
        if not link or not GameTooltip then return end
        GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
        pcall(GameTooltip.SetHyperlink, GameTooltip, link)
        GameTooltip:AddLine(L["Click to hand in the quest and take this"], ns.Theme.Unpack("good"))
        GameTooltip:Show()
    end)
    button:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    button:Hide()
    self.take = button
    return button
end

-- The quest window's own buttons along its foot. On Classic Era the frame
-- reaches well past the art drawn for it, so its own edges sit far below
-- what the player sees; these buttons mark where the window really ends.
QuestRewards.FOOT_BUTTONS = {
    "QuestFrameCompleteQuestButton", "QuestFrameCancelButton",
    "QuestFrameCompleteButton", "QuestFrameGoodbyeButton",
    "QuestFrameAcceptButton", "QuestFrameDeclineButton",
}
-- How far under the lowest of those buttons the window's rim ends.
QuestRewards.FOOT_GAP = 10

--- Left, right and bottom of the quest window as the player sees it: from
--- the shown buttons along its foot, else the frame's own edges.
function QuestRewards.Edges()
    local left, right, bottom
    for _, name in ipairs(QuestRewards.FOOT_BUTTONS) do
        local button = rawget(_G, name)
        if button and Ask(button, "IsVisible") then
            local l, r, b = Ask(button, "GetLeft"), Ask(button, "GetRight"), Ask(button, "GetBottom")
            if type(l) == "number" and type(r) == "number" and type(b) == "number" then
                left = left and math.min(left, l) or l
                right = right and math.max(right, r) or r
                bottom = bottom and math.min(bottom, b) or b
            end
        end
    end
    if left and right and bottom then
        return left, right, bottom - QuestRewards.FOOT_GAP
    end
    return Ask(_G.QuestFrame, "GetLeft"), Ask(_G.QuestFrame, "GetRight"), Ask(_G.QuestFrame, "GetBottom")
end

--- Show the button under the quest window for the pick, or hide it.
function QuestRewards:UpdateTake()
    local index, link, words
    if self:IsEnabled() and self:TakeEnabled() and Ask(_G.QuestFrame, "IsShown") then
        index, link, words = self:Pick()
    end
    if not index then
        if self.take then self.take:Hide() end
        return
    end
    local left, right, bottom = QuestRewards.Edges()
    if not (left and bottom and right) then return end
    local button = self:BuildTake()
    button.choice, button.link = index, link
    button:SetText(words)
    local width = math.max(160, (ns.Theme.TextWidth and ns.Theme.TextWidth("normal", words) or 200) + 28)
    button:SetWidth(width)
    button:ClearAllPoints()
    button:SetPoint("TOP", UIParent, "BOTTOMLEFT", (left + right) / 2, bottom - 4)
    button:Show()
end

function QuestRewards:HideTake()
    if self.take then self.take:Hide() end
end

--------------------------------------------------------------------------------
-- Saying so in chat
--------------------------------------------------------------------------------

--- How much better a verdict is, in words.
local function How(result)
    return result.empty and L["fills an empty slot"]
        or result.percent and ("%+d%%"):format(math.floor(result.percent + 0.5))
        or L["better stats"]
end

--- One line when a quest is handed in with rewards to choose from, and one
--- for each reward it gives outright that is an upgrade.
-- A reward the client has not described yet cannot be judged, so the line
-- waits for its details (GET_ITEM_INFO_RECEIVED) rather than saying none of
-- them helps.
-- Every item answer looks again; after a few seconds it gives up waiting:
-- a best pick is still named, but "none of these" is never said on a guess.
local GIVE_UP = 3

function QuestRewards:Announce(final)
    self.announcePending = false
    if not self:IsEnabled() then return end
    local choices = self:Count()
    local given, unknownGiven = self:Given()
    if choices == 0 and #given == 0 and unknownGiven == 0 then return end

    local index, link, result, unknown = self:Best()
    if choices < 2 then
        -- A lone choice comes with the quest, the same as a fixed reward.
        if index then given[#given + 1] = { link = link, result = result } end
        index, unknown = nil, unknown + unknownGiven
    else
        unknown = unknown + unknownGiven
    end
    if unknown > 0 and not final then
        self.announcePending = true
        if not self.waitToken then
            local token = {}
            self.waitToken = token
            local after = Field(_G.C_Timer, "After")
            if type(after) == "function" then
                after(GIVE_UP, function()
                    if QuestRewards.waitToken ~= token then return end
                    QuestRewards.waitToken = nil
                    if QuestRewards.announcePending and Ask(_G.QuestFrame, "IsShown") then
                        pcall(QuestRewards.Announce, QuestRewards, true)
                    end
                end)
            end
        end
        return
    end
    self.waitToken = nil
    for _, upgrade in ipairs(given) do
        ns.Print(L.Format("this quest gives you %s, an upgrade for %s |c%s%s|r",
            upgrade.link, upgrade.result.specName, ns.COLORS.upgrade, How(upgrade.result)))
    end
    if choices < 2 then return end
    if unknown > 0 and not index then return end
    if index then
        ns.Print(L.Format("best reward for %s: %s |c%s%s|r",
            result.specName, link, ns.COLORS.upgrade, How(result)))
    else
        local none = #given > 0 and L["none of the rewards to choose from beats what you wear"]
            or L["none of these rewards beats what you wear"]
        local _, richLink, copper = self:MostValuable()
        local money = copper and ns.Finder and ns.Finder.Money(copper)
        if richLink and money then
            ns.Print(L.Format("|c%s%s,|r so take %s. It sells for the most (%s)",
                ns.COLORS.muted, none, richLink, money))
        else
            ns.Print(("|c%s%s|r"):format(ns.COLORS.muted, none))
        end
    end
end

--------------------------------------------------------------------------------
-- Being told a quest window opened
--------------------------------------------------------------------------------

function QuestRewards:Refresh()
    local ok = pcall(self.Mark, self)
    if self.handingIn then pcall(self.UpdateTake, self) end
    return ok
end

--- Mark once the game has laid the window out: the quest events can reach
--- this addon before the quest frame has drawn its buttons.
---
--- An item's details arriving fires an event per item, dozens in a burst
--- while the finder is asking for them, so one pass is booked for all of
--- them; `announce` says the hand-in line waiting on them is said after it.
function QuestRewards:RefreshSoon(announce)
    if announce then self.announceAfter = true end
    if self.pending then return end
    local after = Field(_G.C_Timer, "After")
    if type(after) == "function" then
        self.pending = true
        after(0, function()
            QuestRewards.pending = false
            local announceNow = QuestRewards.announceAfter
            QuestRewards.announceAfter = nil
            QuestRewards:Refresh()
            if announceNow and QuestRewards.announcePending then pcall(QuestRewards.Announce, QuestRewards) end
        end)
    else
        self.announceAfter = nil
        self:Refresh()
        if announce and self.announcePending then pcall(self.Announce, self) end
    end
end

function QuestRewards:QUEST_COMPLETE()
    -- The hand-in page: the only one where a reward can be taken.
    self.handingIn = true
    self:RefreshSoon()
    pcall(self.Announce, self)
end

--- A choice the client had not seen before arrives a moment later: mark
--- again, and say the hand-in line that was waiting on it.
function QuestRewards:GET_ITEM_INFO_RECEIVED()
    if not Ask(_G.QuestFrame, "IsShown") then
        self.announcePending = false
        return
    end
    self:RefreshSoon(true)
end

--- The window moved on to another quest (or closed): a line still waiting
--- would describe the wrong rewards, so it is dropped.
function QuestRewards:Moved()
    self.announcePending = false
    self.waitToken = nil
    self.handingIn = false
    pcall(self.HideTake, self)
end

function QuestRewards:OnEnable()
    -- The game lays out the reward buttons in QuestInfo_Display, for the
    -- offer, the progress and the hand-in alike; marking after it runs is
    -- marking the buttons as they are.
    local hook = _G.hooksecurefunc
    if type(hook) == "function" and type(_G.QuestInfo_Display) == "function" then
        -- The quest log draws its rewards through the same function, but
        -- the choice calls describe the quest giver's window, so arrows are
        -- only marked while that window is open.
        -- Nothing here may raise: an error in a hook could stop the rest of the
        -- game's own code that called QuestInfo_Display.
        self.hooked = pcall(hook, "QuestInfo_Display", function()
            if Ask(_G.QuestFrame, "IsShown") then
                QuestRewards:Refresh()
            else
                pcall(QuestRewards.HideArrows, QuestRewards)
            end
        end)
    end

    ns.RegisterEvent(self, "QUEST_DETAIL", function()
        QuestRewards:Moved()
        QuestRewards:RefreshSoon()
    end)
    ns.RegisterEvent(self, "QUEST_GREETING", self.Moved)
    ns.RegisterEvent(self, "QUEST_FINISHED", self.Moved)
    ns.RegisterEvent(self, "QUEST_COMPLETE", self.QUEST_COMPLETE)
    ns.RegisterEvent(self, "GET_ITEM_INFO_RECEIVED", self.GET_ITEM_INFO_RECEIVED)
end
