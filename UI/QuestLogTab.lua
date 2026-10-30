-- Blackthornes Equipment -- UI/QuestLogTab.lua
-- The Quest log tab on the upgrade quest panel (UI/QuestPanel.lua): the
-- character's quests as the game's tracker shows them, inside the panel
-- (the owner asked 2026-10-10, from a mockup he picked: one place for every
-- quest, with the same clicks).
--
--   * Every quest in the log, under its zone, the zone the character is in
--     in green. A heading folds with a click; Fold all folds them all.
--   * A tick box on each quest tracks it, as the game's tracker does.
--     "Tracked only" lists only those.
--   * Objectives as the log words them, ticked green when done, and "Ready
--     to hand in" once the quest is.
--   * A quest that leads to an upgrade quest's reward says so.
--   * A quest that hands out an item to use gets a button for it.
--   * Click a quest to pick it for the buttons below; shift-click links it
--     in chat; right-click opens a menu: Show on map, Point the arrow here,
--     Track or Untrack, Open in quest log, Share with party, Abandon quest.
--   * "Hide the game's quest tracker" (off unless ticked) hides the game's
--     own tracker while this panel is up; untick it and it comes back.
--
-- Nothing of the game's tracker is moved, re-parented, hidden or shown.
-- "Hiding" it is ns.Veil (UI/Veil.lua): see-through, its lines no longer
-- taking the mouse, caught again after a burst of quest events, and put back
-- when the panel closes. Never Hide or Show: that runs the game's own code
-- as this addon and taints Edit Mode. A protected line waits for combat to
-- end, as the controller bag button does (UI/BagIcons.lua).
--
-- Quest item buttons are secure buttons (using an item is protected), so
-- they are kept outside the panel and placed over their row by screen
-- position, as Pets' Feed button is: the panel stays free to move, fold and
-- close in combat. In combat they cannot be moved, shown or hidden, so a
-- button whose row moved fades out until the fight ends and then comes back
-- in its place.
--
-- The quest events come in bursts (several per kill or loot), so they only
-- mark the log stale; it is read once, a moment later, and only while the
-- tab is on screen. Rows keep what they show and are only filled again when
-- their quest changed.

local _, ns = ...
local L = ns.L

local QuestLogUI = ns.NewModule("QuestLogUI")

local Theme = ns.Theme
local Widgets = ns.Widgets

local STRIP = 54
local FOOTER = 34
local MAX_LIST = 380
local SCROLL_BAR = 6
local ITEM = 30
local MARK = 16
local HEAD = 22
local WHEEL = 40
local MOST_OBJECTIVES = 10
local MOST_ITEMS = 8

local function InCombat()
    local fn = _G.InCombatLockdown
    if type(fn) ~= "function" then return false end
    local ok, value = pcall(fn)
    return ok and value == true
end

local function Colored(rgb, text)
    return ("|cff%02x%02x%02x%s|r"):format(math.floor(rgb[1] * 255 + 0.5), math.floor(rgb[2] * 255 + 0.5),
        math.floor(rgb[3] * 255 + 0.5), text)
end

local function Explain(control, title, text, anchor)
    control:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, anchor or "ANCHOR_TOP")
        GameTooltip:AddLine(title, Theme.Unpack("accent"))
        if text then GameTooltip:AddLine(text, 1, 1, 1, true) end
        GameTooltip:Show()
    end)
    control:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

local function LineHeight(size)
    local base = (ns.QuestPanel and ns.QuestPanel.LINE_HEIGHT or {})[size] or 13
    return base + (Theme.TextStep and Theme.TextStep() or 0)
end

local function Lines(size, text, width)
    return ns.QuestPanel.Lines(size, text, width)
end

--- The zone the character is in, by name.
local function HereZone()
    for _, name in ipairs({ "GetRealZoneText", "GetZoneText" }) do
        local fn = _G[name]
        if type(fn) == "function" then
            local ok, zone = pcall(function()
                local value = fn()
                if type(value) == "string" and value ~= "" then return value .. "" end
            end)
            if ok and zone then return zone end
        end
    end
    return nil
end

--------------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------------

--- "Tracked only": list only tracked quests. Account wide, off unless ticked.
function QuestLogUI:TrackedOnly()
    return ns.db ~= nil and ns.db.questLogTrackedOnly == true
end

function QuestLogUI:SetTrackedOnly(on)
    if not ns.db then return end
    ns.db.questLogTrackedOnly = on and true or false
    self:Changed()
end

--- "Hide the game's quest tracker" while the panel is up. Account wide, off
--- unless ticked.
function QuestLogUI:HidesTracker()
    return ns.db ~= nil and ns.db.hideQuestTracker == true
end

function QuestLogUI:SetHidesTracker(on)
    if not ns.db then return end
    ns.db.hideQuestTracker = on and true or false
    self:ApplyTracker()
    self:Changed()
end

--- Headings folded on the tab, by name, per character.
local function Folded()
    local char = ns.charDB
    if not char then return {} end
    if type(char.questLogFolded) ~= "table" then char.questLogFolded = {} end
    return char.questLogFolded
end

--- Settings, the panel's tick boxes and the menu all go through here.
function QuestLogUI:Changed()
    if ns.QuestPanel and ns.QuestPanel.frame then ns.QuestPanel:Refresh() end
    if ns.SettingsUI and ns.SettingsUI.Refresh then ns.SettingsUI:Refresh() end
end

--------------------------------------------------------------------------------
-- Building
--------------------------------------------------------------------------------

function QuestLogUI:Build(frame, top)
    if self.view then return self.view end
    local panel = ns.QuestPanel
    local width, pad = panel.WIDTH, panel.PAD
    self.listWidth = width - pad * 2 - SCROLL_BAR - 2

    local view = CreateFrame("Frame", nil, frame)
    view:SetPoint("TOPLEFT", 0, -top)
    view:SetPoint("TOPRIGHT", 0, -top)
    view:SetHeight(1)
    view:Hide()
    self.view = view

    -- The two switches and Settings.
    local tracked = Widgets.CreateCheckbox(view, L["Tracked only"], function(checked)
        QuestLogUI:SetTrackedOnly(checked)
    end, self:TrackedOnly())
    tracked:SetPoint("TOPLEFT", pad, -2)
    Explain(tracked, L["Tracked only"], L["Lists only the quests you track."],
        "ANCHOR_BOTTOM")
    self.trackedBox = tracked

    local hide = Widgets.CreateCheckbox(view, L["Hide the game's quest tracker"], function(checked)
        QuestLogUI:SetHidesTracker(checked)
    end, self:HidesTracker())
    hide:SetPoint("TOPLEFT", pad, -26)
    Explain(hide, L["Hide the game's quest tracker"],
        L["Hides the game's quest tracker while the panel is up."], "ANCHOR_BOTTOM")
    self.hideBox = hide

    local settings = Widgets.CreateButton(view, L["Settings"], function()
        if ns.db then ns.db.settingsPage = "quest" end
        if ns.SettingsUI then ns.SettingsUI:Show() end
    end, { width = Theme.TextWidth("small", L["Settings"]) + 24, height = 20 })
    settings:SetPoint("TOPRIGHT", -pad, -1)
    Explain(settings, L["Settings"], L["Opens the upgrade quest settings."])

    -- The list, sunk into the panel and scrolled with the mouse wheel.
    local well = Theme.CreatePanel(view, "panel", "border")
    well:SetPoint("TOPLEFT", pad - 4, -STRIP)
    well:SetPoint("TOPRIGHT", -(pad - 4), -STRIP)
    well:SetHeight(40)
    Theme.Recess(well)
    self.well = well

    local scroll = CreateFrame("ScrollFrame", nil, view)
    scroll:SetPoint("TOPLEFT", pad, -STRIP - 2)
    scroll:SetSize(self.listWidth, 36)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(_, delta) QuestLogUI:ScrollBy(-delta * WHEEL) end)
    self.scroll = scroll

    local list = CreateFrame("Frame", nil, scroll)
    list:SetSize(self.listWidth, 1)
    scroll:SetScrollChild(list)
    self.list = list
    self.offset = 0

    -- A thin gold bar on the right while the list is longer than its room.
    local bar = CreateFrame("Frame", nil, view)
    bar:SetWidth(SCROLL_BAR - 2)
    bar:SetPoint("TOPRIGHT", well, "TOPRIGHT", -3, -3)
    bar:SetHeight(30)
    bar.track = bar:CreateTexture(nil, "BACKGROUND")
    bar.track:SetAllPoints(bar)
    bar.track:SetColorTexture(Theme.Unpack("row"))
    bar.thumb = bar:CreateTexture(nil, "ARTWORK")
    bar.thumb:SetWidth(SCROLL_BAR - 2)
    bar.thumb:SetColorTexture(Theme.Unpack("accent", 0.8))
    -- The game's scroll knob in the Blizzard window style (UI/BlizzardLook.lua).
    if ns.BlizzardLook then ns.BlizzardLook.Thumb(bar.thumb) end
    bar:EnableMouse(true)
    bar:SetScript("OnMouseDown", function(clicked)
        -- A click above or below the thumb moves a page that way.
        local okTop, top = pcall(clicked.GetTop, clicked)
        local cx, cy = GetCursorPosition()
        local scale = clicked:GetEffectiveScale()
        if not (okTop and type(top) == "number" and cy and scale and scale > 0) then return end
        local at = top - cy / scale
        local thumbTop = (QuestLogUI.thumbY or 0)
        QuestLogUI:ScrollBy(at < thumbTop and -(QuestLogUI.viewHeight or 100) or (QuestLogUI.viewHeight or 100))
    end)
    bar:Hide()
    self.bar = bar

    local empty = Theme.CreateLabel(view, "small", "text")
    empty:SetPoint("TOPLEFT", pad, -STRIP - 8)
    empty:SetWidth(width - pad * 2)
    empty:SetWordWrap(true)
    self.empty = empty

    -- The buttons along the bottom act on the quest picked, or the first one
    -- in this zone.
    local map = Widgets.CreateButton(view, L["Show on Map"], function() QuestLogUI:Act("map") end,
        { width = 96, height = 22, primary = true })
    Explain(map, L["Show on Map"],
        L["Pins the quest you picked on your map: where to do it, or where to hand it in."])
    self.mapButton = map

    local arrow = Widgets.CreateButton(view, L["Arrow"], function() QuestLogUI:Act("arrow") end,
        { width = 60, height = 22 })
    Explain(arrow, L["Quest arrow"],
        L["Points the arrow at the quest you picked. Click again for your upgrade quest."])
    self.arrowButton = arrow

    local open = Widgets.CreateButton(view, L["Open log"], function() QuestLogUI:Act("open") end,
        { width = 76, height = 22 })
    Explain(open, L["Open the quest log"], L["Opens the game's quest log on the quest you picked."])
    self.openButton = open

    local fold = Widgets.CreateButton(view, L["Fold all"], function() QuestLogUI:FoldAll() end,
        { width = 64, height = 22 })
    Explain(fold, L["Fold all"], L["Folds every zone, or opens them all again."])
    self.foldButton = fold

    self.rows, self.heads = {}, {}
    return view
end

--- A zone heading: a fold sign, its name, and how many quests it holds.
function QuestLogUI:BuildHead(index)
    local head = CreateFrame("Button", nil, self.list)
    head:SetSize(self.listWidth, HEAD)
    head:RegisterForClicks("LeftButtonUp")
    head.sign = Theme.CreateLabel(head, "small", "gilt")
    head.sign:SetPoint("LEFT", 6, 0)
    head.label = Theme.CreateLabel(head, "small", "gilt")
    head.label:SetPoint("LEFT", 20, 0)
    head.count = Theme.CreateLabel(head, "tiny", "muted", "RIGHT")
    head.count:SetPoint("RIGHT", -6, 0)
    head.line = head:CreateTexture(nil, "ARTWORK")
    head.line:SetPoint("BOTTOMLEFT", 4, 2)
    head.line:SetPoint("BOTTOMRIGHT", -4, 2)
    head.line:SetHeight(1)
    head.line:SetColorTexture(Theme.Unpack("metal", 0.55))
    head:SetScript("OnClick", function(self)
        if not self.zone then return end
        local folded = Folded()
        folded[self.zone] = not folded[self.zone] or nil
        QuestLogUI:Changed()
    end)
    head:SetScript("OnEnter", function(self)
        self.label:SetTextColor(Theme.Unpack("accentHi"))
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(self.zone or "", Theme.Unpack("accent"))
        GameTooltip:AddLine(self.note or L["Click to fold or open this zone."], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    head:SetScript("OnLeave", function(self)
        self.label:SetTextColor(Theme.Unpack(self.here and "good" or "gilt"))
        GameTooltip:Hide()
    end)
    head:Hide()
    self.heads[index] = head
    return head
end

--- A quest's row: dark glass, a tick box to track it, its title and level
--- in the game's difficulty colour, the objectives, and room on the right
--- for its item button.
function QuestLogUI:BuildRow(index)
    local row = CreateFrame("Button", nil, self.list)
    row:SetWidth(self.listWidth)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row.band = row:CreateTexture(nil, "BACKGROUND", nil, -1)
    row.band:SetAllPoints(row)
    row.line = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    row.line:SetPoint("BOTTOMLEFT")
    row.line:SetPoint("BOTTOMRIGHT")
    row.line:SetHeight(1)
    row.line:SetColorTexture(Theme.Unpack("border", 0.6))
    -- The gold wash, only under the mouse or on the quest picked.
    row.wash = row:CreateTexture(nil, "BACKGROUND", nil, 2)
    row.wash:SetAllPoints(row)
    row.wash:SetColorTexture(Theme.Unpack("accent", 0.10))
    row.wash:Hide()
    Theme.Halo(row, 4, 0, "accent")

    row.track = Widgets.CreateCheckbox(row, "", function(checked)
        local quest = row.quest
        if quest and ns.QuestLog then
            ns.QuestLog:SetTracked(quest, checked)
            QuestLogUI:LogChanged()
        end
    end, false)
    row.track:SetPoint("TOPLEFT", 5, -3)
    row.track:SetWidth(MARK)
    Explain(row.track, L["Track"], L["Tracks this quest in the game's quest tracker."])

    row.title = Theme.CreateLabel(row, "small", "text")
    row.title:SetPoint("TOPLEFT", MARK + 10, -4)
    row.title:SetWordWrap(true)

    row.objectives = {}
    for which = 1, MOST_OBJECTIVES do
        local label = Theme.CreateLabel(row, "small", "text")
        label:SetWordWrap(true)
        label:Hide()
        row.objectives[which] = label
    end
    row.note = Theme.CreateLabel(row, "tiny", "accent")
    row.note:SetWordWrap(true)
    row.note:Hide()

    -- Where the quest's item button goes (it is not a child of the panel).
    row.spot = CreateFrame("Frame", nil, row)
    row.spot:SetSize(ITEM, ITEM)
    row.spot:SetPoint("TOPRIGHT", -6, -5)
    row.spot.well = Theme.Fill(row.spot, "well", 0.8)
    Theme.Border(row.spot, "metal", 0.6)
    row.spot:Hide()

    row:SetScript("OnEnter", function(self)
        self.wash:Show()
        Theme.SetHalo(self, 0.35, "accent")
        local quest = self.quest
        if not quest then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(quest.title, Theme.Unpack("accent"))
        if quest.zone then GameTooltip:AddLine(quest.zone, 1, 1, 1) end
        GameTooltip:AddLine(L["Click to pick it for the buttons below."], 0.9, 0.9, 0.9)
        GameTooltip:AddLine(L["Shift-click to link it in chat."], 0.9, 0.9, 0.9)
        GameTooltip:AddLine(L["Right-click for the map, the arrow, sharing and more."], 0.9, 0.9, 0.9)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function(self)
        self.wash:SetShown(self.picked == true)
        Theme.SetHalo(self, 0, "accent")
        GameTooltip:Hide()
    end)
    row:SetScript("OnClick", function(self, button)
        local quest = self.quest
        if not quest then return end
        if button == "RightButton" then
            QuestLogUI:OpenMenu(quest)
            return
        end
        QuestLogUI:CloseMenu()
        if type(IsModifiedClick) == "function" and type(ChatEdit_InsertLink) == "function" then
            local ok, chatLink = pcall(IsModifiedClick, "CHATLINK")
            if ok and chatLink then
                local link = quest.questID and type(GetQuestLink) == "function" and select(2, pcall(GetQuestLink, quest.questID))
                if type(link) == "string" then
                    pcall(ChatEdit_InsertLink, link)
                    return
                end
            end
        end
        QuestLogUI.picked = quest.questID or quest.title
        QuestLogUI:Changed()
    end)

    row:Hide()
    self.rows[index] = row
    return row
end

--------------------------------------------------------------------------------
-- Filling it in
--------------------------------------------------------------------------------

--- The words for a quest's lines, and a key that changes when any do.
local function Words(quest, upgrades)
    local level = quest.level and quest.level > 0 and ("[%d] "):format(quest.level) or ""
    local color = ns.QuestLog.DIFFICULTY[ns.QuestLog.Difficulty(quest.level)]
    local title = Colored(color, level .. quest.title)
    if quest.tag then title = title .. "  " .. Colored(Theme.colors.quest, quest.tag) end

    local lines = ns.QuestLog.ObjectiveLines(quest)
    local note
    local link = quest.questID and upgrades[quest.questID]
    if link then
        note = type(link) == "string" and L.Format("Part of your upgrade quest: %s", link) or L["Part of your upgrade quest"]
    end

    local key = { title, tostring(quest.tracked), tostring(quest.item and quest.item.link), note or "" }
    for _, line in ipairs(lines) do key[#key + 1] = line.text end
    return title, lines, note, table.concat(key, "\n")
end

--- Fill a quest's row if its quest changed; returns how tall it is.
function QuestLogUI:FillRow(row, quest, band, upgrades, picked)
    row.quest = quest
    local title, lines, note, key = Words(quest, upgrades)
    if row.key ~= key then
        row.key = key
        local textWidth = self.listWidth - MARK - 12 - (quest.item and (ITEM + 12) or 6)
        row.title:SetWidth(textWidth)
        row.title:SetText(title)
        local height = 4 + Lines("small", title, textWidth) * LineHeight("small") + 2
        for which, label in ipairs(row.objectives) do
            local line = lines[which]
            if line then
                label:ClearAllPoints()
                label:SetPoint("TOPLEFT", MARK + 18, -height)
                label:SetWidth(textWidth - 8)
                label:SetText(line.text)
                label:SetTextColor(Theme.Unpack(line.color))
                label:Show()
                height = height + Lines("small", line.text, textWidth - 8) * LineHeight("small") + 1
            else
                label:Hide()
            end
        end
        if note then
            row.note:ClearAllPoints()
            row.note:SetPoint("TOPLEFT", MARK + 18, -(height + 1))
            row.note:SetWidth(textWidth - 8)
            row.note:SetText(note)
            row.note:Show()
            height = height + Lines("tiny", note, textWidth - 8) * LineHeight("tiny") + 2
        else
            row.note:Hide()
        end
        if quest.item then height = math.max(height, ITEM + 8) end
        row.spot:SetShown(quest.item ~= nil)
        row.tall = height + 5
        row:SetHeight(row.tall)
    end
    row.track:SetChecked(quest.tracked)
    row.band:SetColorTexture(Theme.Unpack(picked and "glassActive" or (band % 2 == 0 and "glassAlt" or "glass")))
    row.picked = picked
    row.wash:SetShown(picked)
    return row.tall
end

--- Fill a zone's heading; returns how tall it is.
function QuestLogUI:FillHead(head, zone, shown, here, folded)
    head.zone = zone.title
    head.here = here
    head.sign:SetText((folded or zone.collapsed) and "+" or "-")
    head.label:SetText(zone.label or zone.title)
    head.label:SetTextColor(Theme.Unpack(here and "good" or "gilt"))
    if zone.collapsed then
        head.count:SetText(L["folded in your quest log"])
        head.note = L["Folded in your quest log. Open it there to see these quests."]
    else
        head.count:SetText(tostring(shown))
        head.note = nil
    end
    return HEAD + 2
end

--- Fill the tab; returns how tall it is. Reads the log first if it changed.
function QuestLogUI:Fill()
    local view = self.view
    view:Show()
    self.trackedBox:SetChecked(self:TrackedOnly())
    self.hideBox:SetChecked(self:HidesTracker())

    if self.dirty ~= false or not self.data then
        self.data = ns.QuestLog:Read()
        self.dirty = false
        self:ForgetGone()
    end
    local data = self.data
    local trackedOnly = self:TrackedOnly()
    local folded = Folded()
    local here = HereZone()
    local upgrades = ns.QuestLog.ForUpgrades()

    -- The quest picked: the one clicked, while it is still in the log.
    local pickedQuest
    for _, zone in ipairs(data.zones) do
        for _, quest in ipairs(zone.quests) do
            if self.picked and (quest.questID or quest.title) == self.picked then pickedQuest = quest end
        end
    end
    if not pickedQuest then self.picked = nil end

    local y, band, rowIndex, headIndex = 0, 0, 0, 0
    local anyFolded, anyOpen = false, false
    self.shown = {}
    -- The zones listed, so Fold all acts on what the button's word is
    -- worked out from (Tracked only leaves some out).
    self.listedZones = {}
    for _, zone in ipairs(data.zones) do
        local quests = {}
        for _, quest in ipairs(zone.quests) do
            if not trackedOnly or quest.tracked then quests[#quests + 1] = quest end
        end
        if #quests > 0 or (zone.collapsed and not trackedOnly) then
            headIndex = headIndex + 1
            local head = self.heads[headIndex] or self:BuildHead(headIndex)
            local isFolded = folded[zone.title] == true
            self.listedZones[#self.listedZones + 1] = zone.title
            if isFolded then anyFolded = true else anyOpen = true end
            head:ClearAllPoints()
            head:SetPoint("TOPLEFT", 0, -y)
            y = y + self:FillHead(head, zone, #quests, here ~= nil and zone.title == here, isFolded)
            head:Show()
            if not isFolded then
                for _, quest in ipairs(quests) do
                    rowIndex = rowIndex + 1
                    band = band + 1
                    local row = self.rows[rowIndex] or self:BuildRow(rowIndex)
                    local tall = self:FillRow(row, quest, band, upgrades, quest == pickedQuest)
                    row:ClearAllPoints()
                    row:SetPoint("TOPLEFT", 0, -y)
                    row.y = y
                    row:Show()
                    self.shown[#self.shown + 1] = row
                    y = y + tall
                end
            end
        end
    end
    for index = rowIndex + 1, #self.rows do
        self.rows[index]:Hide()
        self.rows[index].quest = nil
    end
    for index = headIndex + 1, #self.heads do self.heads[index]:Hide() end

    -- Nothing to list: say why.
    local width = ns.QuestPanel.WIDTH - ns.QuestPanel.PAD * 2
    local text
    if not data.how then
        text = L["Your quest log can't be shown here."]
    elseif data.count == 0 then
        text = L["Your quest log is empty."]
    elseif headIndex == 0 then
        text = L["No tracked quests. Tick a quest's box to track it, or untick Tracked only to see them all."]
    end
    local listHeight
    if text then
        self.empty:SetText(text)
        self.empty:Show()
        listHeight = Lines("small", text, width) * LineHeight("small") + 16
        self.scroll:Hide()
    else
        self.empty:Hide()
        self.scroll:Show()
        listHeight = math.min(y, MAX_LIST) + 4
    end

    self.contentHeight = y
    self.viewHeight = listHeight - 4
    self.list:SetHeight(math.max(1, y))
    self.scroll:SetHeight(math.max(1, self.viewHeight))
    self.well:SetHeight(listHeight)
    self:ScrollBy(0)

    -- The buttons under the well.
    local footY = STRIP + listHeight + 8
    local pad = ns.QuestPanel.PAD
    self.mapButton:ClearAllPoints()
    self.mapButton:SetPoint("TOPLEFT", pad, -footY)
    self.arrowButton:ClearAllPoints()
    self.arrowButton:SetPoint("LEFT", self.mapButton, "RIGHT", 6, 0)
    local free = ns.QuestArrow and ns.QuestArrow.IsOn() and ns.QuestArrow:FreeQuest()
    self.arrowButton:SetLabelColor(free and "good" or "gilt")
    self.openButton:ClearAllPoints()
    self.openButton:SetPoint("LEFT", self.arrowButton, "RIGHT", 6, 0)
    self.foldButton:ClearAllPoints()
    self.foldButton:SetPoint("TOPRIGHT", -pad, -footY)
    self.foldButton:SetText((anyFolded and not anyOpen) and L["Open all"] or L["Fold all"])
    local any = data.count > 0
    self.mapButton:SetShown(any)
    self.arrowButton:SetShown(any)
    self.foldButton:SetShown(headIndex > 0)

    local height = footY + 22 + 10
    view:SetHeight(height)
    self:PlaceItemsSoon()
    return height
end

--- "6 quests, 4 tracked", for the panel's header.
function QuestLogUI:Progress()
    local data = self.data
    if not (data and data.how) then return "" end
    if data.count == 1 then return L.Format("%d quest, %d tracked", data.count, data.tracked) end
    return L.Format("%d quests, %d tracked", data.count, data.tracked)
end

function QuestLogUI:Hide()
    if self.view then self.view:Hide() end
    self:CloseMenu()
    self:PlaceItems()
end

--- Move the list by `delta` pixels (0 to keep it inside its bounds).
function QuestLogUI:ScrollBy(delta)
    if not self.scroll then return end
    local most = math.max(0, (self.contentHeight or 0) - (self.viewHeight or 0))
    self.offset = math.max(0, math.min(most, (self.offset or 0) + (delta or 0)))
    pcall(self.scroll.SetVerticalScroll, self.scroll, self.offset)
    local bar = self.bar
    if most > 0 then
        local room = math.max(10, (self.viewHeight or 10) - 6)
        local thumb = math.max(16, room * (self.viewHeight / self.contentHeight))
        self.thumbY = (room - thumb) * (self.offset / most)
        bar:SetHeight(room)
        bar.thumb:ClearAllPoints()
        bar.thumb:SetPoint("TOPLEFT", 0, -self.thumbY)
        bar.thumb:SetHeight(thumb)
        bar:Show()
    else
        self.thumbY = 0
        bar:Hide()
    end
    if delta ~= 0 then self:PlaceItemsSoon() end
end

function QuestLogUI:FoldAll()
    local data = self.data
    if not data then return end
    local folded = Folded()
    local titles = self.listedZones
    if not titles then
        titles = {}
        for _, zone in ipairs(data.zones) do titles[#titles + 1] = zone.title end
    end
    local anyOpen = false
    for _, title in ipairs(titles) do
        if not folded[title] then anyOpen = true end
    end
    for _, title in ipairs(titles) do folded[title] = anyOpen or nil end
    self:Changed()
end

--------------------------------------------------------------------------------
-- The quest the buttons act on
--------------------------------------------------------------------------------

--- The quest picked, or else the first in the zone the character is in,
--- or else the first listed.
function QuestLogUI:Target()
    local data = self.data
    if not data then return nil end
    local here, first, inZone = HereZone(), nil, nil
    for _, zone in ipairs(data.zones) do
        for _, quest in ipairs(zone.quests) do
            if self.picked and (quest.questID or quest.title) == self.picked then return quest end
            first = first or quest
            if not inZone and here and zone.title == here then inZone = quest end
        end
    end
    return inZone or first
end

function QuestLogUI:Act(what, quest)
    quest = quest or self:Target()
    local log = ns.QuestLog
    if what == "open" then return log:Open(quest) end
    if not quest then return false end
    if what == "map" then return log:ShowOnMap(quest) end
    if what == "arrow" then
        local arrow = ns.QuestArrow
        local free = arrow and arrow.IsOn() and arrow:FreeQuest()
        -- Pointing at this one already: back to the upgrade quest.
        -- Only the log quest is let go: moving on to another tab would take
        -- the panel off the Quest log tab.
        if free and free.questID == quest.questID and free.title == quest.title then
            arrow.free = nil
            arrow:Changed(true)
            self:Changed()
            return true
        end
        local ok = log:Aim(quest)
        self:Changed()
        return ok
    end
    if what == "track" or what == "untrack" then
        local ok = log:SetTracked(quest, what == "track")
        self:LogChanged()
        return ok
    end
    if what == "share" then return log:Share(quest) end
    if what == "abandon" then return log:Abandon(quest) end
    return false
end

--------------------------------------------------------------------------------
-- The right-click menu
--------------------------------------------------------------------------------

local MENU_WIDTH = 176
local MENU_ROW = 20

function QuestLogUI:BuildMenu()
    if self.menu then return self.menu end
    local menu = CreateFrame("Frame", "BlackthornesEquipmentQuestMenu", UIParent)
    menu:SetFrameStrata("DIALOG")
    menu:SetClampedToScreen(true)
    menu:EnableMouse(true)
    menu:SetWidth(MENU_WIDTH)
    Theme.Fill(menu, "window")
    Theme.Border(menu, "accent", 0.9)
    Theme.Halo(menu, 8, 0.3, "accent")
    menu.title = Theme.CreateLabel(menu, "small", "gilt")
    menu.title:SetPoint("TOPLEFT", 12, -8)
    menu.title:SetWidth(MENU_WIDTH - 24)
    -- A long quest title wraps rather than ending in "...".
    menu.title:SetWordWrap(true)
    menu.title:SetJustifyV("TOP")
    menu.line = menu:CreateTexture(nil, "ARTWORK")
    menu.line:SetPoint("TOPLEFT", 10, -26)
    menu.line:SetSize(MENU_WIDTH - 20, 1)
    menu.line:SetColorTexture(Theme.Unpack("metal", 0.7))
    menu.entries = {}
    -- Escape closes it, as it does the game's menus.
    if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "BlackthornesEquipmentQuestMenu") end
    menu:Hide()
    self.menu = menu
    return menu
end

local function MenuEntry(menu, index)
    local entry = menu.entries[index]
    if entry then return entry end
    entry = CreateFrame("Button", nil, menu)
    entry:SetSize(MENU_WIDTH - 8, MENU_ROW)
    entry.wash = entry:CreateTexture(nil, "BACKGROUND")
    entry.wash:SetAllPoints(entry)
    entry.wash:SetColorTexture(Theme.Unpack("accent", 0.18))
    entry.wash:Hide()
    entry.label = Theme.CreateLabel(entry, "small", "text")
    entry.label:SetPoint("LEFT", 8, 0)
    entry:SetScript("OnEnter", function(self) self.wash:Show() end)
    entry:SetScript("OnLeave", function(self) self.wash:Hide() end)
    entry:SetScript("OnClick", function(self)
        local quest = menu.quest
        QuestLogUI:CloseMenu()
        if quest and self.action then QuestLogUI:Act(self.action, quest) end
    end)
    menu.entries[index] = entry
    return entry
end

--- The menu's lines for a quest: { text, action, color }.
function QuestLogUI:MenuFor(quest)
    local log = ns.QuestLog
    local list = { { L["Show on Map"], "map" } }
    if log.Place(quest) or (ns.Waypoints and quest.zone and ns.Waypoints:MapFor(quest.zone)) then
        list[#list + 1] = { L["Point the arrow here"], "arrow" }
    end
    list[#list + 1] = quest.tracked and { L["Untrack"], "untrack" } or { L["Track"], "track" }
    list[#list + 1] = { L["Open in quest log"], "open" }
    if log:CanShare(quest) then list[#list + 1] = { L["Share with party"], "share" } end
    list[#list + 1] = { L["Abandon quest"], "abandon", "loss" }
    return list
end

function QuestLogUI:OpenMenu(quest)
    local menu = self:BuildMenu()
    menu.quest = quest
    menu.title:SetText(quest.title)
    -- The line and the entries sit under however many lines the title took.
    local okHeight, titleHeight = pcall(menu.title.GetStringHeight, menu.title)
    titleHeight = okHeight and tonumber(titleHeight) or 0
    titleHeight = math.max(titleHeight, Theme.sizes.small or 12)
    menu.line:ClearAllPoints()
    menu.line:SetPoint("TOPLEFT", 10, -(titleHeight + 15))
    local list = self:MenuFor(quest)
    local y = titleHeight + 21
    for index, item in ipairs(list) do
        local entry = MenuEntry(menu, index)
        entry.action = item[2]
        entry.label:SetText(item[1])
        entry.label:SetTextColor(Theme.Unpack(item[3] or "text"))
        entry:ClearAllPoints()
        entry:SetPoint("TOPLEFT", 4, -y)
        entry.wash:Hide()
        entry:Show()
        y = y + MENU_ROW
    end
    for index = #list + 1, #menu.entries do menu.entries[index]:Hide() end
    menu:SetHeight(y + 6)

    -- Where the click was, a little in so the first line is under the cursor.
    menu:ClearAllPoints()
    local cx, cy = GetCursorPosition()
    local okScale, scale = pcall(UIParent.GetEffectiveScale, UIParent)
    if cx and cy and okScale and type(scale) == "number" and scale > 0 then
        menu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", cx / scale - 12, cy / scale + 12)
    else
        menu:SetPoint("CENTER", UIParent, "CENTER")
    end
    menu:Show()
end

function QuestLogUI:CloseMenu()
    if self.menu and self.menu:IsShown() then self.menu:Hide() end
end

--- A click anywhere else closes the menu.
function QuestLogUI:OnMouseDown()
    local menu = self.menu
    if not (menu and menu:IsShown()) then return end
    local over = false
    if type(_G.MouseIsOver) == "function" then
        local ok, value = pcall(_G.MouseIsOver, menu)
        over = ok and value == true
    else
        local ok, value = pcall(menu.IsMouseOver, menu)
        over = ok and value == true
    end
    if not over then menu:Hide() end
end

--------------------------------------------------------------------------------
-- Quest item buttons
--------------------------------------------------------------------------------

local function NewItemButton(index)
    local button = CreateFrame("Button", "BlackthornesEquipmentQuestItem" .. index, UIParent,
        "SecureActionButtonTemplate")
    button:SetSize(ITEM, ITEM)
    button:SetFrameStrata("MEDIUM")
    button:RegisterForClicks("AnyUp", "AnyDown")
    button:SetAttribute("type", "item")
    Theme.Fill(button, "panel")
    Theme.Border(button, "accent", 0.9)
    Theme.Halo(button, 5, 0.3, "accent")
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetPoint("TOPLEFT", 1, -1)
    button.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    button.count = Theme.CreateLabel(button, "tiny", "text", "RIGHT")
    button.count:SetPoint("BOTTOMRIGHT", -2, 2)
    local ok, cooldown = pcall(CreateFrame, "Cooldown", nil, button, "CooldownFrameTemplate")
    if ok and cooldown then
        cooldown:SetAllPoints(button.icon)
        button.cooldown = cooldown
    end
    button:HookScript("OnEnter", function(hovered)
        -- A button faded in combat (PlaceItems) has no row under it.
        if not hovered.link or hovered:GetAlpha() == 0 then return end
        GameTooltip:SetOwner(hovered, "ANCHOR_LEFT")
        pcall(GameTooltip.SetHyperlink, GameTooltip, hovered.link)
        GameTooltip:AddLine(L["Click to use it."], Theme.Unpack("accent"))
        GameTooltip:Show()
    end)
    button:HookScript("OnLeave", function() GameTooltip:Hide() end)
    button:Hide()
    return button
end

--- An item button's cooldown swirl, from the bags' cooldown for the item.
local function ShowCooldown(button)
    local cooldown = rawget(button, "cooldown")
    if not (cooldown and button.itemID) then return end
    local get = (type(_G.C_Container) == "table" and _G.C_Container.GetItemCooldown) or _G.GetItemCooldown
    if type(get) ~= "function" then return end
    local ok, start, duration, enable = pcall(get, button.itemID)
    if ok and tonumber(start) and tonumber(duration) and pcall(cooldown.SetCooldown, cooldown, start, duration,
        enable) then
        return
    end
end

--- Where a row's item button belongs on the screen, or nil when the row is
--- not on screen. In UIParent's units, with the scale to draw it at.
function QuestLogUI:SpotOf(row)
    local panel = ns.QuestPanel
    if not (panel.frame and panel.frame:IsShown() and self.view and self.view:IsShown()) then return nil end
    -- While the panel is dragged its rows move under the buttons: put them
    -- away until it is dropped.
    if self.dragging then return nil end
    if not (row:IsShown() and row.quest and row.quest.item) then return nil end
    -- Only rows wholly inside the scrolled view.
    local top = (row.y or 0) + 5
    if top < (self.offset or 0) or top + ITEM > (self.offset or 0) + (self.viewHeight or 0) then return nil end
    local ok, left, spotTop, scale = pcall(function()
        return row.spot:GetLeft(), row.spot:GetTop(), row.spot:GetEffectiveScale() / UIParent:GetEffectiveScale()
    end)
    if not (ok and type(left) == "number" and type(spotTop) == "number" and type(scale) == "number" and scale > 0) then
        return nil
    end
    return { left = left, top = spotTop, scale = scale }
end

--- Put each quest's item button over its row, and put the others away.
--- In combat nothing secure can move, show or hide: a button whose row has
--- moved fades out instead, until the fight ends.
function QuestLogUI:PlaceItems()
    self.items = self.items or {}
    local wanted = {}
    for _, row in ipairs(self.shown or {}) do
        local spot = self:SpotOf(row)
        if spot then wanted[#wanted + 1] = { row = row, spot = spot } end
        if #wanted >= MOST_ITEMS then break end
    end

    if InCombat() then
        for index, button in ipairs(self.items) do
            local want = wanted[index]
            local same = want and button:IsShown() and button.link == want.row.quest.item.link
                and button.at and math.abs(button.at.left - want.spot.left) < 0.5
                and math.abs(button.at.top - want.spot.top) < 0.5
            pcall(button.SetAlpha, button, same and 1 or 0)
        end
        self.placeAfterCombat = true
        return
    end

    for index, want in ipairs(wanted) do
        local button = self.items[index]
        if not button then
            button = NewItemButton(index)
            self.items[index] = button
        end
        local item = want.row.quest.item
        if button.link ~= item.link then
            button.link = item.link
            button.itemID = item.itemID
            button:SetAttribute("item", item.itemID and ("item:%d"):format(item.itemID) or item.link)
            button.icon:SetTexture(item.texture or (Theme.ItemIcon and Theme.ItemIcon(item.link)))
        end
        button.count:SetText(item.charges and item.charges > 1 and tostring(item.charges) or "")
        button:SetScale(want.spot.scale)
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", want.spot.left, want.spot.top)
        pcall(button.SetFrameLevel, button, (ns.QuestPanel.frame:GetFrameLevel() or 1) + 40)
        button.at = want.spot
        button:SetAlpha(1)
        button:Show()
        ShowCooldown(button)
    end
    for index = #wanted + 1, #self.items do
        local button = self.items[index]
        button:Hide()
        button.at = nil
    end
    self.placeAfterCombat = nil
end

--- Place the buttons now, on the next frame (once the game has laid out
--- what just moved), and once the panel has settled (it rises into place
--- as it opens). Each wait is booked once, however often this is asked.
function QuestLogUI:PlaceItemsSoon()
    self:PlaceItems()
    local after = C_Timer and C_Timer.After
    for _, wait in ipairs({ 0, 0.35 }) do
        local flag = "placing" .. wait
        if not self[flag] then
            self[flag] = true
            local function Later()
                QuestLogUI[flag] = false
                QuestLogUI:PlaceItems()
            end
            if after then after(wait, Later) else Later() end
        end
    end
end

function QuestLogUI:OnCooldowns()
    for _, button in ipairs(self.items or {}) do
        if button:IsShown() then ShowCooldown(button) end
    end
end

--------------------------------------------------------------------------------
-- The game's tracker
--------------------------------------------------------------------------------

-- The tracker on a retail client, and on a classic one.
QuestLogUI.TRACKERS = { "ObjectiveTrackerFrame", "QuestWatchFrame" }

-- The tracker is never hidden with Hide: that would run the game's own
-- OnHide code as this addon, and the tracker is an Edit Mode frame, so the
-- taint ends up in Edit Mode's layout (UI/Veil.lua says more). It is made
-- see-through and stops taking the mouse instead, and the game goes on
-- running it as before.

--- Should the game's tracker be out of sight now: the setting on and the
--- panel up?
function QuestLogUI:WantsTrackerHidden()
    local panel = ns.QuestPanel
    return self:HidesTracker() and panel and panel.frame ~= nil and panel.frame:IsShown() == true
end

--- Is a tracker out of sight through this addon?
function QuestLogUI:TrackerHidden(name)
    local frame = rawget(_G, name)
    return type(frame) == "table" and ns.Veil:Covers(frame)
end

--- Put the game's tracker out of sight or bring it back, as the setting and
--- the panel say.
function QuestLogUI:ApplyTracker()
    local hide = self:WantsTrackerHidden()
    for _, name in ipairs(self.TRACKERS) do
        local frame = rawget(_G, name)
        if type(frame) == "table" then
            local done
            if hide then
                done = ns.Veil:Cover(frame)
            else
                done = ns.Veil:Uncover(frame)
            end
            if not done then self.trackerAfterCombat = true end
        end
    end
end

--- The game may add lines to the tracker while it is out of sight: catch
--- them once the burst of quest events is over.
function QuestLogUI:TrackerChanged()
    if self.trackerPending or not self:WantsTrackerHidden() then return end
    self.trackerPending = true
    local function Later()
        QuestLogUI.trackerPending = false
        QuestLogUI:ApplyTracker()
    end
    if C_Timer and C_Timer.After then C_Timer.After(0.2, Later) else Later() end
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

--- Is the tab on screen?
function QuestLogUI:Showing()
    local panel = ns.QuestPanel
    return panel ~= nil and panel.frame ~= nil and panel.frame:IsShown() and panel:ShowsLog() and not panel.folded
end

--- The log changed: read it again once the burst is over, if the tab is up.
function QuestLogUI:LogChanged()
    self.dirty = true
    if not self:Showing() or self.pending then return end
    self.pending = true
    local function Later()
        QuestLogUI.pending = false
        if QuestLogUI:Showing() then ns.QuestPanel:Refresh() end
    end
    if C_Timer and C_Timer.After then C_Timer.After(0.2, Later) else Later() end
end

--- A quest the arrow points at left the log.
function QuestLogUI:ForgetGone()
    local arrow = ns.QuestArrow
    local free = arrow and arrow:FreeQuest()
    -- An aim with no quest (the weapon master) never came from the log.
    if not (free and free.questID ~= nil and self.data and self.data.how) then return end
    for _, zone in ipairs(self.data.zones) do
        for _, quest in ipairs(zone.quests) do
            if quest.questID == free.questID and quest.title == free.title then return end
        end
    end
    arrow:ForgetQuest(free.questID)
end

--- The panel was shown or hidden (closed, or the upgrade quest turned off).
function QuestLogUI:OnPanelShown(shown)
    if not shown then self:CloseMenu() end
    self:ApplyTracker()
    self:PlaceItems()
end

function QuestLogUI:OnEnable()
    for _, event in ipairs({ "QUEST_LOG_UPDATE", "QUEST_WATCH_LIST_CHANGED", "QUEST_ACCEPTED",
        "UNIT_QUEST_LOG_CHANGED" }) do
        ns.RegisterEvent(self, event, function(_, _, unit)
            if event == "UNIT_QUEST_LOG_CHANGED" and unit ~= "player" then return end
            QuestLogUI:LogChanged()
            QuestLogUI:TrackerChanged()
        end)
    end
    for _, event in ipairs({ "QUEST_REMOVED", "QUEST_TURNED_IN" }) do
        ns.RegisterEvent(self, event, function(_, _, questID)
            local id = tonumber(questID)
            if id and ns.QuestArrow then ns.QuestArrow:ForgetQuest(id) end
            QuestLogUI:LogChanged()
        end)
    end
    ns.RegisterEvent(self, "ZONE_CHANGED_NEW_AREA", function()
        if QuestLogUI:Showing() then QuestLogUI:LogChanged() end
    end)
    -- Just before combat locks secure frames: put the buttons where they
    -- belong. After it: catch up on anything that had to wait.
    ns.RegisterEvent(self, "PLAYER_REGEN_DISABLED", function() QuestLogUI:PlaceItems() end)
    ns.RegisterEvent(self, "PLAYER_REGEN_ENABLED", function()
        if QuestLogUI.placeAfterCombat then QuestLogUI:PlaceItems() end
        if QuestLogUI.trackerAfterCombat then
            QuestLogUI.trackerAfterCombat = nil
            QuestLogUI:ApplyTracker()
        end
    end)
    ns.RegisterEvent(self, "BAG_UPDATE_COOLDOWN", function() QuestLogUI:OnCooldowns() end)
    ns.RegisterEvent(self, "GLOBAL_MOUSE_DOWN", function() QuestLogUI:OnMouseDown() end)
    ns.RegisterEvent(self, "PLAYER_ENTERING_WORLD", function() QuestLogUI:ApplyTracker() end)
    self:ApplyTracker()
end
