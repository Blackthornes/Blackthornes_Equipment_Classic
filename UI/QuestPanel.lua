-- Blackthornes Equipment -- UI/QuestPanel.lua
-- The upgrade quest's panel, in the house frame (UI/Titanforged.lua): a
-- gold rim, its name on a plate and a red gem that closes it (turning the
-- upgrade quest off; Settings or /beq quest brings it back). Under the
-- header, a tab for each kind of source (Vendor, Quest, Dungeons and Raids,
-- Crafted), each with its own upgrade; click one to show it, and a fifth,
-- Quest log, with the character's quests as the game's tracker shows them
-- (UI/QuestLogTab.lua). Under the tabs,
-- what the quest may pick from: "This zone only" (only upgrades from the
-- zone the character is in), "Solo quests only" and the "Quest level" limit
-- (the same two as in Where to get upgrades, so both follow one setting),
-- and a Settings button. Then, like a
-- quest in the quest tracker: the item
-- with how much better it is, a progress bar, and the steps to get it, the
-- one to do now lit gold and the ones done ticked green. When the step to
-- do now is a quest in the log, it shows that quest as the game's tracker
-- does: a tick box to track it, its title (click to open it in the quest
-- log) and its objectives with their counts.
--
-- Show on map pins the next place to go; Arrow shows the quest arrow
-- (UI/QuestArrow.lua), which points the way there, and a click on a step
-- with a place aims the arrow at it. Ignore leaves this upgrade for good
-- for the next best (Settings lists what was ignored, to bring back);
-- Change (Pick one while the tab has nothing) opens Where to get upgrades,
-- where a click on a row follows that upgrade instead. When a level up opens
-- an upgrade clearly more worth the trip, a gold box at the top offers it:
-- Switch follows it instead, Keep current leaves the quest as it is. Shift-click the item
-- to link it in chat. The panel is there while the "Upgrade quest" setting
-- (`upgradeQuest`, off unless turned on) is, folds to its plate with the
-- house fold gem (UI/FoldWindow.lua, 2026-10-29), and can be dragged
-- anywhere; the spot is kept with the other window positions. Its choices
-- (This Zone Only, Change on a New Zone, Solo Quests Only, Current Step
-- Only, Quest Level and Settings) sit behind one Options button, in the
-- house row menu (card 20 of the unified look). Transparent is
-- `questPanelSeeThrough` (UI/SeeThrough.lua).

local _, ns = ...
local L = ns.L

local QuestPanel = ns.NewModule("QuestPanel")

local Theme = ns.Theme
local Widgets = ns.Widgets
local Motion = ns.Motion

-- 384 rather than 340 since the Quest log tab (the owner asked 2026-10-10,
-- picking the wider panel so all five tabs fit).
local WIDTH = 384
-- The plate sits across the top edge and the close gem on the top right
-- corner; the header's row starts below them.
local HEADER_ROW = 24
local HEADER = HEADER_ROW + 22 + 4
local TAB_HEIGHT = 24
local TAB_GAP = 4
local TABS_HEIGHT = TAB_HEIGHT + 8
-- The filters went behind the Options button (2026-10-29): no rows of their own.
local FILTERS_HEIGHT = 0
local PAD = 10
local ICON = 36
local MARK = 14
local STEP_GAP = 6
local MOST_STEPS = 10
-- Objectives shown under the step to do now, as in the Quest log tab.
local MOST_OBJECTIVES = 10
local FOOTER = 34
local BAR = 4
-- Queue it, beside a crafted upgrade's name.
local QUEUE_WIDTH = 64
local OFFER_ICON = 24
local OFFER_PAD = 8
local OFFER_TEXT = WIDTH - PAD * 2 - OFFER_PAD * 2 - OFFER_ICON - 8

-- How big the panel can be drawn, as a share of its normal size: dragged by
-- the gold grip below its bottom right corner, picked in Settings or typed
-- with /beq quest size (the owner asked 2026-10-07, after Tradeskills' window
-- got the same). Drawn smaller or larger as a whole, so its layout and text
-- stay as they are. Saved as `questScale`, account wide.
local SCALE_MIN = 0.5
local SCALE_MAX = 1.5
QuestPanel.SIZES = {
    { key = "small", text = L["Small"], scale = 0.8 },
    { key = "normal", text = L["Normal"], scale = 1 },
    { key = "large", text = L["Large"], scale = 1.2 },
}
local GRIP_SIZE = 20

local QUEST_ICON = [[Interface\GossipFrame\AvailableQuestIcon]]
local DONE_ICON = [[Interface\RaidFrame\ReadyCheck-Ready]]
local NOW_ICON = [[Interface\GossipFrame\AvailableQuestIcon]]
-- A quest ready to hand in wears the game's yellow ?, as over a quest giver.
local TURN_IN_ICON = [[Interface\GossipFrame\ActiveQuestIcon]]
QuestPanel.QUEST_ICON, QuestPanel.TURN_IN_ICON = QUEST_ICON, TURN_IN_ICON

-- The colour each kind of source is tagged in, as in the upgrade finder.
local KIND_COLOR = { vendor = "accent", quest = "quest", dungeon = "dungeon", craft = "craft" }

local function Colored(key, text)
    local r, g, b = Theme.Unpack(key)
    return ("|cff%02x%02x%02x%s|r"):format(math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5),
        math.floor(b * 255 + 0.5), text)
end

function QuestPanel:IsEnabled()
    return ns.UpgradeQuest ~= nil and ns.UpgradeQuest:IsEnabled()
end

--------------------------------------------------------------------------------
-- Measuring wrapped text
--------------------------------------------------------------------------------

--- How many lines `text` wraps to in `width` pixels at a label size,
--- measured word by word the way the game wraps it.
function QuestPanel.Lines(size, text, width)
    if type(text) ~= "string" or text == "" then return 0 end
    -- A link's hidden part takes no room; its [Name] does.
    local plain = text:gsub("|H.-|h", ""):gsub("|h", "")
    local lines, line = 1, ""
    for word in plain:gmatch("%S+") do
        local try = line == "" and word or (line .. " " .. word)
        if line ~= "" and Theme.TextWidth(size, try) > width then
            lines = lines + 1
            line = word
        else
            line = try
        end
    end
    return lines
end

local LINE_HEIGHT = { tiny = 12, small = 13, normal = 14 }

-- For the Quest log tab (UI/QuestLogTab.lua), which lays itself out the
-- same way.
QuestPanel.WIDTH = WIDTH
QuestPanel.PAD = PAD
QuestPanel.LINE_HEIGHT = LINE_HEIGHT

-- The fifth tab: the quest log, not a kind of source, so it is not one of
-- UpgradeQuest.TABS. Shown while the character's `questLogTab` is set.
QuestPanel.LOG_TAB = { key = "log", name = L["Quest log"], color = "warn", log = true }

--- Is the panel showing the Quest log tab?
function QuestPanel:ShowsLog()
    return ns.charDB ~= nil and ns.charDB.questLogTab == true
end

--- Show the Quest log tab, or go back to the source tabs.
function QuestPanel:ShowLog(on)
    if not ns.charDB then return end
    ns.charDB.questLogTab = on and true or nil
    if ns.QuestLogUI then ns.QuestLogUI:CloseMenu() end
    self:Refresh()
    if ns.SettingsUI and ns.SettingsUI.Refresh then ns.SettingsUI:Refresh() end
end

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

--- A button's tooltip: what it does, in clear white on the dark tooltip.
local function Explain(button, title, text)
    button:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(title, Theme.Unpack("accent"))
        if text then GameTooltip:AddLine(text, 1, 1, 1, true) end
        GameTooltip:Show()
    end)
    button:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

function QuestPanel:BuildStep(index)
    local row = CreateFrame("Frame", nil, self.body)
    row:SetWidth(WIDTH - PAD * 2)
    -- Dark glass, as the gear window's and finder's rows (asked
    -- 2026-10-10): every other step a shade apart, with a fine line under
    -- each, so the steps read as separate rows.
    row.band = row:CreateTexture(nil, "BACKGROUND", nil, -1)
    row.band:SetAllPoints(row)
    row.band:SetColorTexture(Theme.Unpack(index % 2 == 0 and "glassAlt" or "glass"))
    row.line = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    row.line:SetPoint("BOTTOMLEFT")
    row.line:SetPoint("BOTTOMRIGHT")
    row.line:SetHeight(1)
    row.line:SetColorTexture(Theme.Unpack("border", 0.6))
    row.background = Theme.Fill(row, "rowActive", 0)
    -- The step to do now glows gold round its edge.
    Theme.Halo(row, 4, 0)

    local mark = row:CreateTexture(nil, "ARTWORK")
    mark:SetSize(MARK, MARK)
    mark:SetPoint("TOPLEFT", 4, -3)
    row.mark = mark

    local number = Theme.CreateLabel(row, "small", "muted", "CENTER")
    number:SetPoint("TOPLEFT", 2, -3)
    number:SetWidth(MARK + 4)
    row.number = number

    local text = Theme.CreateLabel(row, "small", "text")
    text:SetPoint("TOPLEFT", MARK + 10, -3)
    text:SetWidth(WIDTH - PAD * 2 - MARK - 16)
    text:SetWordWrap(true)
    row.text = text

    local note = Theme.CreateLabel(row, "tiny", "muted")
    note:SetWidth(WIDTH - PAD * 2 - MARK - 16)
    note:SetWordWrap(true)
    row.note = note
    row.textWidth = WIDTH - PAD * 2 - MARK - 16

    -- The step to do now on a quest in the log: the quest as the game's
    -- tracker shows it (the owner asked 2026-10-13). A tick box tracks it,
    -- a click on its title opens it in the quest log, and its objectives
    -- follow with their counts.
    row.track = Widgets.CreateCheckbox(row, "", function(checked)
        local quest = row.quest
        if quest and ns.QuestLog then
            ns.QuestLog:SetTracked(quest, checked)
            if ns.UpgradeQuest then ns.UpgradeQuest:UpdateSoon(0.2) end
        end
    end, false)
    row.track:SetWidth(MARK)
    Explain(row.track, L["Track"], L["Tracks this quest in the game's quest tracker."])
    row.track:Hide()

    local title = CreateFrame("Button", nil, row)
    title:RegisterForClicks("LeftButtonUp")
    title.label = Theme.CreateLabel(title, "small", "text")
    title.label:SetPoint("TOPLEFT")
    title.label:SetWordWrap(true)
    title:SetScript("OnEnter", function(self)
        self.label:SetAlpha(0.8)
        local quest = row.quest
        if not quest then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(quest.title, Theme.Unpack("accent"))
        GameTooltip:AddLine(L["Click to open it in your quest log."], 1, 1, 1, true)
        GameTooltip:AddLine(L["Shift-click to link it in chat."], 0.9, 0.9, 0.9, true)
        GameTooltip:Show()
    end)
    title:SetScript("OnLeave", function(self)
        self.label:SetAlpha(1)
        GameTooltip:Hide()
    end)
    title:SetScript("OnClick", function()
        local quest = row.quest
        if not (quest and ns.QuestLog) then return end
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
        ns.QuestLog:Open(quest)
    end)
    title:Hide()
    row.questTitle = title

    row.objectives = {}
    for which = 1, MOST_OBJECTIVES do
        local label = Theme.CreateLabel(row, "small", "text")
        label:SetWordWrap(true)
        label:Hide()
        row.objectives[which] = label
    end

    -- A step with a place: a click points the quest arrow there.
    row:SetScript("OnEnter", function(self)
        if not self.place then return end
        Theme.SetHalo(self, 0.45, "accentHi")
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["Point the quest arrow here"], Theme.Unpack("accent"))
        GameTooltip:AddLine(L.Format("Click to point the arrow at %s.",
            self.place.name or self.place.zone or L["this place"]), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function(self)
        Theme.SetHalo(self, self.now and 0.28 or 0, "accent")
        GameTooltip:Hide()
    end)
    row:SetScript("OnMouseUp", function(self, button)
        if button ~= "LeftButton" or not self.place then return end
        if ns.QuestArrow and ns.QuestArrow:Aim(self.index) then
            if type(_G.PlaySound) == "function" then
                pcall(_G.PlaySound, _G.SOUNDKIT and _G.SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or 856)
            end
        end
    end)

    row:Hide()
    return row
end

--------------------------------------------------------------------------------
-- Tabs
--------------------------------------------------------------------------------

--- One tab: raised metal in the source's colour along its foot, solid gold
--- with dark lettering while it is the one shown.
-- Made while the panel is built, before self.frame is set, so the panel's
-- frame is handed in: a tab with no parent floats at the screen's corner.
function QuestPanel:BuildTab(frame, tab)
    local button = CreateFrame("Button", nil, frame)
    button:SetHeight(TAB_HEIGHT)
    button.key = tab.key
    button.background = Theme.Fill(button, "row")
    Theme.Border(button, "metal")
    button.sheen = Theme.TopSheen(button, 0.10)
    if Theme.Bevel then Theme.Bevel(button) end
    Theme.Halo(button, 5, 0, "accent")

    -- The source's colour, as the finder tags it.
    local stripe = button:CreateTexture(nil, "OVERLAY")
    stripe:SetPoint("BOTTOMLEFT", 1, 1)
    stripe:SetPoint("BOTTOMRIGHT", -1, 1)
    stripe:SetHeight(2)
    stripe:SetColorTexture(Theme.Unpack(tab.color))
    button.stripe = stripe

    local label = Theme.CreateLabel(button, "small", "gilt", "CENTER")
    label:SetPoint("CENTER", 0, 1)
    label:SetText(tab.name)
    button.label = label

    --- How lit: 0 at rest, 1 under the mouse.
    function button.Light(p)
        local shown = rawget(button, "shown") == true
        if shown then
            button.background:SetColorTexture(Motion.Mix("accent", "accentHi", p))
            for _, edge in ipairs(button.borderTextures or {}) do edge:SetColorTexture(Theme.Unpack("accentHi")) end
            label:SetTextColor(Theme.Unpack("ink"))
            Theme.SetHalo(button, 0.3 + 0.2 * p, "accent")
        else
            button.background:SetColorTexture(Motion.Mix("row", "rowActive", p))
            local r, g, b, a = Motion.Mix("metal", "accentHi", p)
            for _, edge in ipairs(button.borderTextures or {}) do edge:SetColorTexture(r, g, b, a) end
            local rest = rawget(button, "empty") == true and "muted" or "gilt"
            label:SetTextColor(Motion.Mix(rest, { 1, 0.953, 0.784 }, p))
            Theme.SetHalo(button, 0.4 * p, "accent")
        end
    end

    button:SetScript("OnEnter", function(self)
        Motion:Blend(self, "hover", 1, 0.12, self.Light)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(tab.name, Theme.Unpack(tab.color))
        local logic = ns.UpgradeQuest
        local quest = not tab.log and logic and logic:QuestOn(tab.key)
        if tab.log then
            GameTooltip:AddLine(L["Every quest in your log."], 1, 1, 1, true)
        elseif quest then
            GameTooltip:AddLine(ns.Items.ShowLink(quest.link), 1, 1, 1, true)
        else
            GameTooltip:AddLine(logic and logic.NONE[tab.key] or "", 1, 1, 1, true)
        end
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function(self)
        Motion:Blend(self, "hover", 0, 0.18, self.Light)
        GameTooltip:Hide()
    end)
    button:SetScript("OnClick", function()
        if tab.log then
            QuestPanel:ShowLog(true)
        elseif ns.UpgradeQuest then
            ns.UpgradeQuest:SelectTab(tab.key)
        end
    end)

    button.Light(0)
    return button
end

--- Lay the tabs along one row, as wide as their names and sharing what is
--- left over; in the smaller letters if the names would not fit.
function QuestPanel:LayoutTabs(frame)
    local room = WIDTH - PAD * 2 - TAB_GAP * (#self.tabs - 1)
    local size = "small"
    local function Widths()
        local widths, total = {}, 0
        for index, button in ipairs(self.tabs) do
            widths[index] = Theme.TextWidth(size, button.label:GetText()) + 14
            total = total + widths[index]
        end
        return widths, total
    end
    local widths, total = Widths()
    if total > room then
        size = "tiny"
        for _, button in ipairs(self.tabs) do button.label:SetFont(Theme.FONT, Theme.sizes.tiny, "") end
        widths, total = Widths()
    end
    local extra = math.max(0, room - total) / #self.tabs
    local x = PAD
    for index, button in ipairs(self.tabs) do
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -HEADER)
        button:SetWidth(widths[index] + extra)
        x = x + widths[index] + extra + TAB_GAP
    end
    self.tabFont = size
end

--- Light the tab shown, and dim the names of tabs with nothing on them.
function QuestPanel:FillTabs()
    local logic = ns.UpgradeQuest
    local shownTab = logic:Tab()
    local log = self:ShowsLog()
    for _, button in ipairs(self.tabs) do
        if button.key == QuestPanel.LOG_TAB.key then
            button.shown = log
            button.empty = false
        else
            button.shown = not log and button.key == shownTab
            button.empty = logic:QuestOn(button.key) == nil
        end
        button.Light(Motion:Value(button, "hover") or 0)
        button:SetShown(not self.folded)
    end
end

--------------------------------------------------------------------------------
-- Filters
--------------------------------------------------------------------------------

--- A tick box's or stepper's tooltip, below it so it never covers the tabs.
local function ExplainBelow(control, title, text)
    control:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(title, Theme.Unpack("accent"))
        GameTooltip:AddLine(text, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    control:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

--- The quest level stepper's place: 0 to 10 levels up, or 11 for any.
function QuestPanel.QuestLevelsValue()
    local finder = ns.Finder
    if not finder then return 4 end
    return finder:QuestLevelsAbove() or finder.QUEST_LEVELS_ANY
end

--- Its words, as Where to get upgrades says them.
function QuestPanel.QuestLevelsText(value)
    if ns.FinderUI and ns.FinderUI.QuestLevelsText then return ns.FinderUI.QuestLevelsText(value) end
    return tostring(value)
end

--- The Options menu's lines: the same choices as Where to get upgrades and
--- Settings, each ticked as it stands. A click changes it.
function QuestPanel:OptionLines()
    local quest, finder = ns.UpgradeQuest, ns.Finder
    local lines = {}
    if quest then
        local zoneOnly = quest:ZoneOnly()
        lines[#lines + 1] = { text = L["This Zone Only"], checked = zoneOnly,
            run = function() quest:SetZoneOnly(not zoneOnly) end }
        local swap = quest:ZoneSwap()
        lines[#lines + 1] = { text = L["Change on a New Zone"], checked = swap, disabled = not zoneOnly,
            run = function() quest:SetZoneSwap(not swap) end }
    end
    if finder then
        local solo = finder:SoloOnly()
        lines[#lines + 1] = { text = L["Solo Quests Only"], checked = solo,
            run = function() finder:SetSoloOnly(not solo) end }
    end
    if quest then
        local stepOnly = quest:StepOnly()
        lines[#lines + 1] = { text = L["Current Step Only"], checked = stepOnly,
            run = function() quest:SetStepOnly(not stepOnly) end }
    end
    if finder then
        lines[#lines + 1] = { text = L["Quest Level:"] .. " " .. QuestPanel.QuestLevelsText(QuestPanel.QuestLevelsValue()),
            run = function() QuestPanel:OpenLevels() end }
    end
    lines[#lines + 1] = { text = L["Settings"], run = function()
        -- Opened on the Upgrade quest page (UI/SettingsPages.lua).
        if ns.db then ns.db.settingsPage = "quest" end
        if ns.SettingsUI then ns.SettingsUI:Show() end
    end }
    return lines
end

function QuestPanel:OpenOptions()
    if not ns.RowMenu then return end
    return ns.RowMenu:Open(self:OptionLines(), { title = L["Options"] })
end

--- Quest Level's choices, the one set ticked.
function QuestPanel:LevelLines()
    local finder = ns.Finder
    if not finder then return {} end
    local now = QuestPanel.QuestLevelsValue()
    local lines = {}
    for value = 0, finder.QUEST_LEVELS_ANY or 11 do
        lines[#lines + 1] = { text = QuestPanel.QuestLevelsText(value), checked = value == now,
            run = function() finder:SetQuestLevelsAbove(value) end }
    end
    return lines
end

function QuestPanel:OpenLevels()
    if not ns.RowMenu then return end
    -- The menu closes as a line runs; open the levels once it has.
    local function Open() ns.RowMenu:Open(QuestPanel:LevelLines(), { title = L["Quest Level:"] }) end
    if C_Timer and C_Timer.After then C_Timer.After(0, Open) else Open() end
end

--- The close gem: the upgrade quest goes off, its quests kept.
function QuestPanel:Close()
    if ns.UpgradeQuest then ns.UpgradeQuest:TurnOff() end
end

--- The close gem says what closing does and how to bring it back.
function QuestPanel:ExplainClose(trim)
    local close = trim and rawget(trim, "closeButton")
    if not close then return end
    close:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L["Close the upgrade quest"], Theme.Unpack("accent"))
        GameTooltip:AddLine(L["Your quests stay saved. Bring it back with Upgrade quest in the gear window, or Shift-click the minimap button."], 1, 1, 1, true)
        GameTooltip:Show()
    end)
end

function QuestPanel:Build()
    if self.frame then return self.frame end

    local frame = CreateFrame("Frame", "BlackthornesEquipmentQuest", UIParent)
    frame:SetSize(WIDTH, HEADER)
    frame:SetScale(self:GetScale())
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame.fill = Theme.Fill(frame, "window")

    -- The house frame, as the gear window wears it: the plate names the
    -- panel and the close gem turns the upgrade quest off.
    if ns.Titanforged then
        local trim = ns.Titanforged:Dress(frame, {
            title = L["Upgrade quest"],
            close = function() QuestPanel:Close() end,
        })
        self.trim = trim
        self:ExplainClose(trim)
        -- The house fold gem, left of the close gem: folds to the plate.
        if ns.FoldWindow then
            ns.FoldWindow:Add(frame, {
                onToggle = function(folded)
                    QuestPanel.folded = folded and true or false
                    QuestPanel:Refresh()
                end,
            })
        end
        local left, right, top, bottom = ns.Titanforged.Reach(trim)
        if frame.SetClampRectInsets then frame:SetClampRectInsets(-left, right, top, -bottom) end
    else
        Theme.Border(frame, "borderLit")
    end
    Theme.Halo(frame, 10, 0.14)

    frame:SetScript("OnDragStart", function(self)
        self:StartMoving()
        if ns.QuestLogUI then
            ns.QuestLogUI.dragging = true
            ns.QuestLogUI:PlaceItems()
        end
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        QuestPanel:SavePosition()
        if ns.QuestLogUI then
            ns.QuestLogUI.dragging = nil
            ns.QuestLogUI:PlaceItemsSoon()
        end
    end)
    -- The Quest log tab hides the game's tracker while the panel is up, and
    -- its item buttons go with the panel.
    frame:HookScript("OnShow", function()
        if ns.QuestLogUI then ns.QuestLogUI:OnPanelShown(true) end
    end)
    frame:HookScript("OnHide", function()
        if ns.QuestLogUI then ns.QuestLogUI:OnPanelShown(false) end
    end)

    -- The header's row: the quest mark and how far along on the left, fold
    -- on the right, all below the plate and the close gem.
    local header = CreateFrame("Frame", nil, frame)
    header:SetPoint("TOPLEFT", 0, -HEADER_ROW)
    header:SetPoint("TOPRIGHT", 0, -HEADER_ROW)
    header:SetHeight(22)
    header:EnableMouse(false)

    local badge = header:CreateTexture(nil, "ARTWORK")
    badge:SetSize(18, 18)
    badge:SetPoint("LEFT", PAD, 0)
    badge:SetTexture(QUEST_ICON)
    self.badge = badge
    self.badgeTexture = QUEST_ICON

    local optionsText = L["Options"]
    local options = Widgets.CreateButton(header, optionsText, function() QuestPanel:OpenOptions() end,
        { width = Theme.TextWidth("small", optionsText) + 24, height = 20 })
    options:SetPoint("RIGHT", -PAD, 0)
    self.optionsButton = options

    local title = Theme.CreateLabel(header, "small", "gilt")
    title:SetPoint("LEFT", badge, "RIGHT", 6, 0)
    self.title = title

    local progress = Theme.CreateLabel(header, "tiny", "text", "RIGHT")
    progress:SetPoint("RIGHT", options, "LEFT", -8, 0)
    self.progress = progress

    -- A tab for each kind of source.
    self.tabs = {}
    for index, tab in ipairs(ns.UpgradeQuest.TABS) do self.tabs[index] = self:BuildTab(frame, tab) end
    self.tabs[#self.tabs + 1] = self:BuildTab(frame, QuestPanel.LOG_TAB)
    self:LayoutTabs(frame)
    -- The Quest log tab's own list, filters and buttons, in place of the
    -- source tabs' (UI/QuestLogTab.lua).
    if ns.QuestLogUI then ns.QuestLogUI:Build(frame, HEADER + TABS_HEIGHT) end

    -- Everything under the filters, hidden when folded.
    local body = CreateFrame("Frame", nil, frame)
    body:SetPoint("TOPLEFT", 0, -(HEADER + TABS_HEIGHT + FILTERS_HEIGHT))
    body:SetPoint("TOPRIGHT", 0, -(HEADER + TABS_HEIGHT + FILTERS_HEIGHT))
    body:SetHeight(1)
    self.body = body

    -- The quest sits sunk into the panel, as the finder's list does.
    local well = Theme.CreatePanel(body, "panel", "border")
    well:SetPoint("TOPLEFT", PAD - 4, 0)
    well:SetPoint("TOPRIGHT", -(PAD - 4), 0)
    Theme.Recess(well)
    pcall(well.SetFrameLevel, well, math.max(0, (body:GetFrameLevel() or 1) - 1))
    self.well = well
    if ns.SeeThrough then
        ns.SeeThrough:AddGlass("quest", frame.fill)
        ns.SeeThrough:AddGlass("quest", well.background)
    end

    -- A level up opened something better: offered, never swapped in.
    local offer = CreateFrame("Frame", nil, body)
    offer:SetPoint("TOPLEFT", PAD, -PAD)
    offer:SetWidth(WIDTH - PAD * 2)
    Theme.Fill(offer, "rowActive", 0.75)
    Theme.Border(offer, "accent", 0.9)
    Theme.Halo(offer, 6, 0.3, "accent")
    offer:Hide()
    self.offerBox = offer

    local offerTitle = Theme.CreateLabel(offer, "small", "accent")
    offerTitle:SetPoint("TOPLEFT", OFFER_PAD, -OFFER_PAD)
    offerTitle:SetWidth(WIDTH - PAD * 2 - OFFER_PAD * 2)
    offerTitle:SetWordWrap(true)
    self.offerTitle = offerTitle

    local offerItem = CreateFrame("Button", nil, offer)
    offerItem:SetSize(WIDTH - PAD * 2 - OFFER_PAD * 2, OFFER_ICON)
    offerItem:SetScript("OnEnter", function(self)
        local on = ns.UpgradeQuest and ns.UpgradeQuest:Offer()
        if not on then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        pcall(GameTooltip.SetHyperlink, GameTooltip, on.pick.link)
        GameTooltip:Show()
    end)
    offerItem:SetScript("OnLeave", function() GameTooltip:Hide() end)
    self.offerItem = offerItem

    local offerIcon = Theme.CreateItemIcon(offerItem, OFFER_ICON)
    offerIcon:SetPoint("TOPLEFT", 0, 0)
    self.offerIcon = offerIcon

    local offerName = Theme.CreateLabel(offerItem, "small", "text")
    offerName:SetPoint("TOPLEFT", OFFER_ICON + 8, -1)
    offerName:SetWidth(OFFER_TEXT)
    offerName:SetWordWrap(true)
    self.offerName = offerName

    local offerGain = Theme.CreateLabel(offerItem, "tiny", "good")
    offerGain:SetPoint("TOPLEFT", offerName, "BOTTOMLEFT", 0, -2)
    offerGain:SetWidth(OFFER_TEXT)
    offerGain:SetWordWrap(true)
    self.offerGain = offerGain

    local switch = Widgets.CreateButton(offer, L["Switch"], function()
        if ns.UpgradeQuest then ns.UpgradeQuest:SwitchToOffer() end
    end, { width = 72, height = 22, primary = true })
    switch:SetPoint("BOTTOMLEFT", OFFER_PAD, OFFER_PAD)
    Explain(switch, L["Switch to it"], L["Follow this upgrade instead."])
    self.switchButton = switch

    local keep = Widgets.CreateButton(offer, L["Keep current"], function()
        if ns.UpgradeQuest then ns.UpgradeQuest:KeepCurrent() end
    end, { width = 96, height = 22 })
    keep:SetPoint("LEFT", switch, "RIGHT", 10, 0)
    Explain(keep, L["Keep current"], L["Stay on your upgrade. This one won't come up again until you next log in."])
    self.keepButton = keep

    -- The item: hover for its tooltip, shift-click to link it.
    local item = CreateFrame("Button", nil, body)
    item:SetPoint("TOPLEFT", PAD, -PAD)
    item:SetSize(WIDTH - PAD * 2, ICON)
    item:SetScript("OnEnter", function(self)
        local quest = ns.UpgradeQuest and ns.UpgradeQuest:Current()
        if not quest then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        pcall(GameTooltip.SetHyperlink, GameTooltip, quest.link)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["Shift-click to link it in chat"], 1, 1, 1)
        GameTooltip:Show()
    end)
    item:SetScript("OnLeave", function() GameTooltip:Hide() end)
    item:SetScript("OnClick", function()
        local quest = ns.UpgradeQuest and ns.UpgradeQuest:Current()
        if not quest then return end
        if type(IsModifiedClick) == "function" and type(ChatEdit_InsertLink) == "function" then
            local ok, chatLink = pcall(IsModifiedClick, "CHATLINK")
            if ok and chatLink then pcall(ChatEdit_InsertLink, quest.link) end
        end
    end)
    self.item = item

    -- Queue it, at the top right of a crafted upgrade while Tradeskills is
    -- loaded (Logic/TradeskillsQueue.lua).
    local queueIt = Widgets.CreateButton(item, L["Queue It"], function()
        local quest = ns.UpgradeQuest and ns.UpgradeQuest:Current()
        if quest and quest.source and ns.TradeskillsQueue then
            ns.TradeskillsQueue:Queue(quest.source)
            QuestPanel:Refresh()
        end
    end, { width = QUEUE_WIDTH, height = 20 })
    queueIt:SetPoint("TOPRIGHT", 0, 0)
    queueIt:HookScript("OnEnter", function(self)
        local quest = ns.UpgradeQuest and ns.UpgradeQuest:Current()
        if not (quest and ns.TradeskillsQueue) then return end
        local title, text = ns.TradeskillsQueue:Explain(quest.source)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(title, Theme.Unpack("accent"))
        if text then GameTooltip:AddLine(text, 1, 1, 1, true) end
        GameTooltip:Show()
    end)
    queueIt:HookScript("OnLeave", function() GameTooltip:Hide() end)
    queueIt:Hide()
    self.queueButton = queueIt

    local icon = Theme.CreateItemIcon(item, ICON)
    icon:SetPoint("LEFT", 0, 0)
    -- A green glow behind the upgrade's icon.
    Theme.Halo(icon, 6, 0.35, "good")
    self.icon = icon

    local name = Theme.CreateLabel(item, "normal", "text")
    name:SetPoint("TOPLEFT", ICON + 10, -2)
    name:SetWidth(WIDTH - PAD * 2 - ICON - 12)
    name:SetWordWrap(true)
    self.name = name

    local gain = Theme.CreateLabel(item, "tiny", "good")
    gain:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -3)
    gain:SetWidth(WIDTH - PAD * 2 - ICON - 12)
    self.gain = gain

    -- How far along: gold filling to green.
    local track = body:CreateTexture(nil, "ARTWORK")
    track:SetPoint("TOPLEFT", item, "BOTTOMLEFT", 0, -8)
    track:SetSize(WIDTH - PAD * 2, BAR)
    track:SetColorTexture(Theme.Unpack("row"))
    self.track = track
    local fill = body:CreateTexture(nil, "OVERLAY")
    fill:SetPoint("TOPLEFT", track, "TOPLEFT")
    fill:SetSize(1, BAR)
    fill:SetColorTexture(Theme.Unpack("good"))
    pcall(Theme.SetGradientAlpha, fill, "HORIZONTAL", "good", 0.55, 1)
    self.fill = fill

    local empty = Theme.CreateLabel(body, "small", "text")
    empty:SetPoint("TOPLEFT", PAD, -PAD)
    empty:SetWidth(WIDTH - PAD * 2)
    empty:SetWordWrap(true)
    self.empty = empty

    self.steps = {}
    for index = 1, MOST_STEPS do self.steps[index] = self:BuildStep(index) end

    local map = Widgets.CreateButton(body, L["Show on Map"], function() QuestPanel:ShowOnMap() end,
        { width = 96, height = 22, primary = true })
    Explain(map, L["Show on Map"], L["Pins the next place to go on your map."])
    self.mapButton = map

    -- The quest arrow: lit green while it is up.
    local arrow = Widgets.CreateButton(body, L["Arrow"], function()
        if ns.QuestArrow then ns.HandleSlash(ns.QuestArrow.IsOn() and "arrow off" or "arrow on") end
    end, { width = 60, height = 22 })
    Explain(arrow, L["Quest arrow"], L["Points the way to the quest's next place. Click a step to aim it."])
    self.arrowButton = arrow

    -- Was "Other ways" (renamed 2026-10-08, the owner asked): it opens Where to
    -- get upgrades to pick a different one. Reads "Pick one" on an empty tab.
    local other = Widgets.CreateButton(body, L["Change"], function()
        if ns.FinderUI then ns.FinderUI:Show() end
    end, { width = 80, height = 22 })
    Explain(other, L["Pick a different upgrade"], L["Opens Where to get upgrades. Click one there to follow it."])
    self.otherButton = other

    -- Ignore was Skip, and keeps its saved list and its name in the code.
    local skip = Widgets.CreateButton(body, L["Ignore"], function()
        if ns.UpgradeQuest then ns.HandleSlash("quest ignore") end
    end, { width = 60, height = 22 })
    Explain(skip, L["Ignore this upgrade"], L["Skips it on this character and picks the next best one. Bring it back with Ignored in Settings."])
    self.skipButton = skip

    self.frame = frame
    self:BuildSizeGrip()
    self:RestorePosition()
    if ns.SeeThrough then ns.SeeThrough:Attach("quest", frame) end
    frame:Hide()
    return frame
end

--------------------------------------------------------------------------------
-- Filling it in
--------------------------------------------------------------------------------

--- The words under the item's name: how much better, and from where.
function QuestPanel.GainText(quest)
    local parts = {}
    if quest.howMuch then parts[#parts + 1] = L.Format("%s over what you wear", quest.howMuch) end
    if ns.WeaponSkills and ns.WeaponSkills:NeedsTraining(quest.link) then
        parts[#parts + 1] = Colored("loss", L["Train"])
    end
    local source = quest.source
    if source and source.kind and ns.Finder then
        local label = ns.Finder.Label(source)
        if label ~= "" then parts[#parts + 1] = Colored(KIND_COLOR[source.kind] or "accent", label) end
    end
    return table.concat(parts, "  ")
end

--- Lay out one step, and say how tall it came out.
function QuestPanel:FillStep(row, index, step, current, place)
    row:ClearAllPoints()
    -- Dark glass by place in the list, so one step shown alone still reads right.
    row.band:SetColorTexture(Theme.Unpack((place or index) % 2 == 0 and "glassAlt" or "glass"))
    row.text:SetText(step.text)
    local lines = QuestPanel.Lines("small", step.text, row.textWidth)
    local height = 6 + lines * LINE_HEIGHT.small
    local now = index == current and not step.done

    if step.note and (now or not step.done) then
        row.note:SetText(step.note)
        row.note:SetPoint("TOPLEFT", MARK + 10, -(4 + lines * LINE_HEIGHT.small))
        row.note:Show()
        height = height + QuestPanel.Lines("tiny", step.note, row.textWidth) * LINE_HEIGHT.tiny + 2
    else
        row.note:Hide()
    end

    height = height + self:FillProgress(row, now and step.progress or nil, height)

    if step.done then
        row.mark:SetTexture(DONE_ICON)
        row.mark:Show()
        row.number:Hide()
        row.text:SetTextColor(Theme.Unpack("muted"))
    elseif now then
        row.mark:SetTexture(step.turnIn and TURN_IN_ICON or NOW_ICON)
        row.mark:Show()
        row.number:Hide()
        row.text:SetTextColor(Theme.Unpack("text"))
    else
        row.mark:Hide()
        row.number:SetText(("%d."):format(index))
        row.number:Show()
        row.text:SetTextColor(Theme.Unpack("muted"))
    end
    row.background:SetColorTexture(Theme.Unpack("rowActive", now and 0.55 or 0))
    Theme.SetHalo(row, now and 0.28 or 0, "accent")
    row.now = now
    -- Done steps keep their place for the map, but the arrow is for what
    -- is left.
    row.index = index
    row.place = not step.done and type(step.place) == "table" and step.place.zone and step.place or nil
    row:EnableMouse(row.place ~= nil)

    row:SetHeight(height)
    row:Show()
    return height
end

--- The quest a step is on, as the log shows it, under the step's words:
--- the track box and its title, then its objectives with their counts.
--- Hidden with no quest. Returns how much taller the row grew.
function QuestPanel:FillProgress(row, quest, top)
    row.quest = quest
    if not quest then
        row.track:Hide()
        row.questTitle:Hide()
        for _, label in ipairs(row.objectives) do label:Hide() end
        return 0
    end
    local indent = MARK + 10
    local width = row.textWidth - MARK - 4
    local y = top + 2
    row.track:ClearAllPoints()
    row.track:SetPoint("TOPLEFT", indent, -(y - 2))
    row.track:SetChecked(quest.tracked == true)
    row.track:Show()

    local title = ns.QuestLog.TitleText(quest)
    local titleLines = QuestPanel.Lines("small", title, width)
    local button = row.questTitle
    button:ClearAllPoints()
    button:SetPoint("TOPLEFT", indent + MARK + 4, -y)
    button:SetSize(width, titleLines * LINE_HEIGHT.small)
    button.label:SetWidth(width)
    button.label:SetText(title)
    button:Show()
    y = y + titleLines * LINE_HEIGHT.small + 2

    local lines = ns.QuestLog.ObjectiveLines(quest)
    for which, label in ipairs(row.objectives) do
        local line = lines[which]
        if line then
            label:ClearAllPoints()
            label:SetPoint("TOPLEFT", indent + MARK + 10, -y)
            label:SetWidth(width - 6)
            label:SetText(line.text)
            label:SetTextColor(Theme.Unpack(line.color))
            label:Show()
            y = y + QuestPanel.Lines("small", line.text, width - 6) * LINE_HEIGHT.small + 1
        else
            label:Hide()
        end
    end
    return y - top + 2
end

function QuestPanel:Refresh()
    if not self:IsEnabled() then
        if self.frame then self.frame:Hide() end
        return
    end
    self:Build()

    local logic = ns.UpgradeQuest
    self:FillTabs()

    -- The Quest log tab: its own list in place of the quest's.
    if self:ShowsLog() and ns.QuestLogUI and ns.QuestLogUI.view then
        self:SetBadge(QUEST_ICON)
        self.title:SetText(QuestPanel.LOG_TAB.name)
        self.body:Hide()
        local height = HEADER
        if self.folded then
            ns.QuestLogUI:Hide()
        else
            height = height + TABS_HEIGHT + ns.QuestLogUI:Fill()
        end
        self.progress:SetText(ns.QuestLogUI:Progress())
        self.frame:SetHeight(height)
        if not self.frame:IsShown() then
            self.frame:Show()
            Motion:Open(self.frame)
        end
        if logic.stepDone then
            logic.stepDone = nil
            self:Cheer()
        end
        return
    end
    if ns.QuestLogUI then ns.QuestLogUI:Hide() end

    local quest = logic:Current()
    self.body:SetShown(not self.folded)
    local shownTab = logic:Tab()
    for _, tab in ipairs(logic.TABS) do
        if tab.key == shownTab then self.title:SetText(tab.name) end
    end

    local steps, current = {}, 0
    if quest then steps, current = logic:Steps(quest) end
    local done = 0
    for _, step in ipairs(steps) do
        if step.done then done = done + 1 end
    end
    -- How many steps are still to do, the one under way among them.
    local left = math.max(0, #steps - done)
    self.progress:SetText(quest and (left == 1 and L["1 step left"] or L.Format("%d steps left", left)) or "")
    local now = steps[current]
    self:SetBadge(now and not now.done and now.turnIn and TURN_IN_ICON or QUEST_ICON)

    local height = HEADER
    if not self.folded then
        height = height + TABS_HEIGHT + FILTERS_HEIGHT + self:FillBody(quest, steps, current, done)
    end
    self.frame:SetHeight(height)

    if not self.frame:IsShown() then
        self.frame:Show()
        Motion:Open(self.frame)
    end

    -- A step just ticked off: the panel's edge flares green.
    if logic.stepDone then
        logic.stepDone = nil
        self:Cheer()
    end
end

--- The header's mark: ! for a quest to do, ? once the step to do now is
--- handing one in. Set only when it changes.
function QuestPanel:SetBadge(texture)
    if not self.badge or self.badgeTexture == texture then return end
    self.badgeTexture = texture
    self.badge:SetTexture(texture)
end

--- Fill everything under the header; returns how tall it is.
function QuestPanel:FillBody(quest, steps, current, done)
    for _, row in ipairs(self.steps) do row:Hide() end

    if not quest then
        self.offerBox:Hide()
        self.item:Hide()
        self.track:Hide()
        self.fill:Hide()
        self.mapButton:Hide()
        self.arrowButton:Hide()
        self.skipButton:Hide()
        local state = ns.UpgradeQuest.state
        local text
        if state == "waiting" then
            text = L["Looking for your next upgrade..."]
        elseif ns.UpgradeQuest:ZoneOnly() then
            text = L.Format("%s Only this zone is searched. Untick This zone only to look everywhere, or try another tab.",
                ns.UpgradeQuest.NONE[ns.UpgradeQuest:Tab()] or L["No upgrade to chase right now."])
        else
            text = L.Format("%s A new one comes up as you level. Try another tab, or click Pick one to choose from every upgrade on offer, including gear from a reputation you've already reached.",
                ns.UpgradeQuest.NONE[ns.UpgradeQuest:Tab()] or L["No upgrade to chase right now."])
        end
        self.empty:SetText(text)
        self.empty:Show()
        local lines = QuestPanel.Lines("small", text, WIDTH - PAD * 2)
        local y = PAD + lines * LINE_HEIGHT.small + 10
        self.well:SetHeight(y - 4)
        self.otherButton:ClearAllPoints()
        self.otherButton:SetPoint("TOPLEFT", PAD, -y)
        self.otherButton:SetText(L["Pick one"])
        self.otherButton:Show()
        local height = y + 22 + PAD
        self.body:SetHeight(height)
        return height
    end

    self.empty:Hide()
    local top = PAD + self:FillOffer(ns.UpgradeQuest:Offer())
    self.item:ClearAllPoints()
    self.item:SetPoint("TOPLEFT", PAD, -top)
    self.item:Show()
    Theme.SetItemIcon(self.icon, quest.link)
    -- Queue it on crafted gear, the name and gain kept clear of it.
    local textWidth = WIDTH - PAD * 2 - ICON - 12
    local source = quest.source
    if source and source.kind == "craft" and ns.TradeskillsQueue and ns.TradeskillsQueue:Available() then
        self.queueButton:SetText(ns.TradeskillsQueue:Label(quest.itemID or source.itemID))
        self.queueButton:Show()
        -- The button grows to fit its words (German runs longer).
        local okWidth, queueWidth = pcall(self.queueButton.GetWidth, self.queueButton)
        if not (okWidth and type(queueWidth) == "number" and queueWidth >= QUEUE_WIDTH) then queueWidth = QUEUE_WIDTH end
        textWidth = textWidth - queueWidth - 6
    else
        self.queueButton:Hide()
    end
    self.name:SetWidth(textWidth)
    self.gain:SetWidth(textWidth)
    -- In its rarity colour, even for a quest saved before the client sent it.
    local shown = ns.Items.ShowLink(quest.link) or "?"
    self.name:SetText(shown)
    local nameLines = math.min(2, QuestPanel.Lines("normal", shown, textWidth))
    self.gain:SetText(QuestPanel.GainText(quest))
    local itemHeight = math.max(ICON, 4 + nameLines * LINE_HEIGHT.normal + 3 + LINE_HEIGHT.tiny)
    self.item:SetHeight(itemHeight)

    self.track:Show()
    self.fill:Show()
    local share = #steps > 0 and done / #steps or 0
    self.fill:SetWidth(math.max(1, (WIDTH - PAD * 2) * share))

    local y = top + itemHeight + 8 + BAR + 10
    -- "Current step only": just the step to do now, the panel shrinking to
    -- fit. With none left to do, the last step stands in.
    local only = ns.UpgradeQuest:StepOnly() and (steps[current] and current or #steps) or nil
    local place = 0
    for index, step in ipairs(steps) do
        -- A long chain can have more steps than were built up front.
        local row = self.steps[index]
        if not row then
            row = self:BuildStep(index)
            self.steps[index] = row
        end
        if not only or index == only then
            place = place + 1
            local stepHeight = self:FillStep(row, index, step, current, place)
            row:SetPoint("TOPLEFT", PAD, -y)
            y = y + stepHeight + STEP_GAP
        end
    end

    -- Buttons along the bottom, under the well: Show on map only when there
    -- is a place.
    self.well:SetHeight(y)
    y = y + 8
    local place = ns.UpgradeQuest:NextPlace()
    self.mapButton:ClearAllPoints()
    self.arrowButton:ClearAllPoints()
    self.otherButton:ClearAllPoints()
    self.skipButton:ClearAllPoints()
    self.skipButton:SetPoint("TOPRIGHT", -PAD, -y)
    self.skipButton:Show()
    self.otherButton:SetPoint("RIGHT", self.skipButton, "LEFT", -6, 0)
    self.otherButton:SetText(L["Change"])
    self.otherButton:Show()
    if place then
        self.mapButton:SetPoint("TOPLEFT", PAD, -y)
        self.mapButton:Show()
        self.arrowButton:SetPoint("LEFT", self.mapButton, "RIGHT", 6, 0)
        self.arrowButton:SetLabelColor(ns.QuestArrow and ns.QuestArrow.IsOn() and "good" or "gilt")
        self.arrowButton:Show()
    else
        self.mapButton:Hide()
        self.arrowButton:Hide()
    end

    local height = y + FOOTER - 4
    self.body:SetHeight(height)
    return height
end

--- The box offering what a level up opened, or nothing; returns how much
--- room it takes, gap below included.
function QuestPanel:FillOffer(offer)
    if not offer then
        self.offerBox:Hide()
        return 0
    end
    local title = offer.level and L.Format("New upgrade on offer at level %d", offer.level)
        or L["New upgrade on offer"]
    self.offerTitle:SetText(title)
    local titleLines = QuestPanel.Lines("small", title, WIDTH - PAD * 2 - OFFER_PAD * 2)

    local link = offer.pick.link or "?"
    Theme.SetItemIcon(self.offerIcon, link)
    self.offerName:SetText(ns.Items.ShowLink(link))
    local parts = {}
    if offer.howMuch then parts[#parts + 1] = L.Format("%s over what you wear", offer.howMuch) end
    local source = offer.source
    if source and source.kind and ns.Finder then
        local label = ns.Finder.Label(source)
        if label ~= "" then parts[#parts + 1] = Colored(KIND_COLOR[source.kind] or "accent", label) end
    end
    local gain = table.concat(parts, "  ")
    self.offerGain:SetText(gain)
    local itemHeight = math.max(OFFER_ICON, 2 + QuestPanel.Lines("small", link, OFFER_TEXT) * LINE_HEIGHT.small
        + 2 + QuestPanel.Lines("tiny", gain, OFFER_TEXT) * LINE_HEIGHT.tiny)

    local y = OFFER_PAD + titleLines * LINE_HEIGHT.small + 6
    self.offerItem:ClearAllPoints()
    self.offerItem:SetPoint("TOPLEFT", OFFER_PAD, -y)
    self.offerItem:SetHeight(itemHeight)
    self.offerItem:Show()
    self.switchButton:Show()
    self.keepButton:Show()
    local height = y + itemHeight + 8 + 22 + OFFER_PAD
    self.offerBox:SetHeight(height)
    if not self.offerBox:IsShown() then
        self.offerBox:Show()
        Motion:Run(self.offerBox, "offer", 0.9, function(p)
            Theme.SetHalo(self.offerBox, 0.7 + (0.3 - 0.7) * p, "accent")
        end)
    end
    return height + 12
end

--- The panel's edge flares green and settles back, with the quest sound.
function QuestPanel:Cheer()
    if not self.frame then return end
    local rest = self.frame.haloRest or 0.14
    Motion:Run(self.frame, "cheer", 0.9, function(p)
        Theme.SetHalo(self.frame, 0.6 + (rest - 0.6) * p, p < 1 and "good" or "accent")
    end)
    if type(_G.PlaySound) == "function" then
        local kit = _G.SOUNDKIT and _G.SOUNDKIT.UI_QUEST_OBJECTIVE_COMPLETE
        pcall(_G.PlaySound, kit or 6197, "Master")
    end
end

function QuestPanel:ShowOnMap()
    local place = ns.UpgradeQuest and ns.UpgradeQuest:NextPlace()
    if not (place and ns.Waypoints) then return false end
    -- A spot gets the marker on it; only a zone, a "Somewhere in ZONE"
    -- marker in its middle. Either way the arrow shows the way.
    local quest = ns.UpgradeQuest:Current()
    return ns.Waypoints:Show(place, place.name, quest and quest.link)
end

function QuestPanel:ToggleFold()
    if self.frame and ns.FoldWindow and rawget(self.frame, "blackthornesFold")
        and ns.FoldWindow:Toggle(self.frame) then
        return
    end
    -- Where the gem can't (a window not placed yet): folded to its header.
    self.folded = not self.folded
    self:Refresh()
end

function QuestPanel:Unfold()
    if self.frame and ns.FoldWindow and self.folded then
        ns.FoldWindow:Unfold(self.frame)
    end
    self.folded = false
    self:Refresh()
end

function QuestPanel:OnUpgradeQuestChanged()
    self:Refresh()
end

function QuestPanel:OnQuestArrowChanged()
    self:Refresh()
end

--------------------------------------------------------------------------------
-- Position
--------------------------------------------------------------------------------

function QuestPanel:SavePosition()
    if not (ns.db and self.frame) then return end
    local point, _, relativePoint, x, y = self.frame:GetPoint()
    ns.db.questPoint, ns.db.questRelativePoint = point, relativePoint
    ns.db.questX, ns.db.questY = x, y
    -- The offsets are in the panel's own units, which change with its
    -- size, so the size they were taken at goes with them.
    ns.db.questScaleAt = QuestPanel.ScaleOf(self.frame)
end

function QuestPanel:RestorePosition()
    if not self.frame then return end
    local db = ns.db or {}
    self.frame:ClearAllPoints()
    -- Saved at another size (or before there were sizes, at 1): the same
    -- spot on the screen, in the units of the size it is now. The starting
    -- spot is in screen units, so it is divided by the size too.
    local factor = QuestPanel.PositionFactor(db.questX and db.questScaleAt or 1,
        QuestPanel.ScaleOf(self.frame))
    -- Below the upgrade tracker's starting spot, so the two do not overlap.
    self.frame:SetPoint(db.questPoint or "RIGHT", UIParent, db.questRelativePoint or "RIGHT",
        (db.questX or -40) * factor, (db.questY or -120) * factor)
end

--------------------------------------------------------------------------------
-- Size
--------------------------------------------------------------------------------

--- A frame's own scale, or 1 when it cannot say.
function QuestPanel.ScaleOf(frame)
    local ok, scale = pcall(function() return frame:GetScale() end)
    if ok and type(scale) == "number" and scale > 0 then return scale end
    return 1
end

--- How much to multiply a saved offset by, taken at `saved` size and put
--- back at `now`.
function QuestPanel.PositionFactor(saved, now)
    saved = tonumber(saved) or 1
    now = tonumber(now) or 1
    if saved <= 0 or now <= 0 then return 1 end
    return saved / now
end

--- A size kept within bounds and to a whole percent.
function QuestPanel.ClampScale(value)
    value = tonumber(value)
    if not value or value ~= value then return 1 end
    value = math.max(SCALE_MIN, math.min(SCALE_MAX, value))
    return math.floor(value * 100 + 0.5) / 100
end

--- The largest size at which the whole panel, rim and plate included,
--- still fits on the screen; never under the normal size for a panel that
--- fits at it, and SCALE_MAX when the screen cannot be measured.
function QuestPanel:FitScale()
    local ok, width, height = pcall(function()
        return UIParent:GetWidth(), UIParent:GetHeight()
    end)
    if not (ok and type(width) == "number" and type(height) == "number"
        and width > 0 and height > 0) then
        return SCALE_MAX
    end
    local tall = HEADER
    local frame = self.frame
    if frame then
        local okHeight, now = pcall(frame.GetHeight, frame)
        if okHeight and type(now) == "number" and now > tall then tall = now end
    end
    -- The plate reaches above the top edge and the grip hangs below.
    local fit = math.min(width / (WIDTH + 20), height / (tall + 20 + GRIP_SIZE + 10))
    return math.max(SCALE_MIN, math.min(SCALE_MAX, math.floor(fit * 100) / 100))
end

--- The size the panel is drawn at: the saved one, kept on the screen.
function QuestPanel:GetScale()
    local saved = ns.db and ns.db.questScale
    return math.min(QuestPanel.ClampScale(saved or 1), self:FitScale())
end

--- The name of a size, "Small (80%)", or "87%" for one dragged to.
function QuestPanel.ScaleText(scale)
    local percent = math.floor((tonumber(scale) or 1) * 100 + 0.5)
    for _, size in ipairs(QuestPanel.SIZES) do
        if math.floor(size.scale * 100 + 0.5) == percent then
            return ("%s (%d%%)"):format(size.text, percent)
        end
    end
    return ("%d%%"):format(percent)
end

--- "small", "normal", "large", "80", "80%" or "0.8" as a size, or nil.
function QuestPanel.ParseSize(text)
    text = (text or ""):lower():gsub("%s", ""):gsub("%%$", "")
    if text == "" then return nil end
    for _, size in ipairs(QuestPanel.SIZES) do
        if size.key == text then return size.scale end
    end
    local number = tonumber(text)
    if not number or number <= 0 then return nil end
    -- 80 means 80%; 0.8 means the same.
    if number > 5 then number = number / 100 end
    return number
end

--- Draw the panel at `scale` with its top left corner where it was, so it
--- grows and shrinks toward the bottom right, as it does from the grip.
function QuestPanel:ApplyScale(scale)
    local frame = self.frame
    if not frame then return end

    scale = math.min(QuestPanel.ClampScale(scale or self:GetScale()), self:FitScale())
    local old = QuestPanel.ScaleOf(frame)
    if math.abs(old - scale) < 0.001 then return end

    -- Still rising into place from opening: land it first.
    if Motion and Motion.Stop then pcall(Motion.Stop, Motion, frame, "open", true) end

    local left, top = frame:GetLeft(), frame:GetTop()
    frame:SetScale(scale)
    if type(left) == "number" and type(top) == "number" then
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left * old / scale, top * old / scale)
        self:SavePosition()
        if ns.QuestLogUI then ns.QuestLogUI:PlaceItemsSoon() end
    else
        self:RestorePosition()
    end
end

--- Save a size and draw the panel at it. Returns the size it ended up at.
function QuestPanel:SetPanelScale(value)
    local scale = QuestPanel.ClampScale(value)
    if ns.db then ns.db.questScale = scale end
    self:ApplyScale(scale)
    if ns.SettingsUI and ns.SettingsUI.Refresh then ns.SettingsUI:Refresh() end
    return math.min(scale, self:FitScale())
end

--- The grip below the bottom right corner: drag it to make the panel bigger
--- or smaller, right-click it for the normal size.
function QuestPanel:BuildSizeGrip()
    local frame = self.frame
    local below = 3
    if self.trim and ns.Titanforged and ns.Titanforged.Reach then
        local _, _, _, bottom = ns.Titanforged.Reach(self.trim)
        if type(bottom) == "number" then below = bottom + 3 end
    end

    local grip = Theme.CreatePanel(frame, "panel", "borderLit")
    grip:SetSize(GRIP_SIZE, GRIP_SIZE)
    grip:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", -6, -below)
    grip:SetFrameLevel((frame:GetFrameLevel() or 0) + 20)
    grip:EnableMouse(true)
    Theme.TopSheen(grip)
    self.sizeGrip = grip

    -- Six gold dots in a stair down to the bottom right corner, the shape
    -- every resizable window in the game wears, drawn from plain colour.
    local dots = {}
    for row = 0, 2 do
        for column = 2 - row, 2 do
            local dot = grip:CreateTexture(nil, "ARTWORK")
            dot:SetSize(3, 3)
            dot:SetPoint("BOTTOMRIGHT", grip, "BOTTOMRIGHT", -3 - (2 - column) * 5, 3 + (2 - row) * 5)
            dot:SetColorTexture(Theme.Unpack("accent"))
            dots[#dots + 1] = dot
        end
    end

    local function Light(on)
        Theme.SetBorderColor(grip, on and "accent" or "borderLit")
        for _, dot in ipairs(dots) do
            dot:SetColorTexture(Theme.Unpack(on and "accentHi" or "accent"))
        end
    end

    local function Track(self)
        local cx, cy = GetCursorPosition()
        local uiScale = UIParent:GetEffectiveScale()
        if not (cx and cy and type(uiScale) == "number" and uiScale > 0) then return end
        cx, cy = cx / uiScale, cy / uiScale

        -- Where the corner would be for the cursor to sit on the grip as it
        -- did when the drag began, then the size that puts it there: the
        -- width's and the height's answers averaged, so a drag off the
        -- diagonal still feels right.
        local width = cx - self.grabX - self.anchorLeft
        local height = self.anchorTop - (cy + self.grabY)
        local scale = QuestPanel.ClampScale((width / WIDTH + height / self.tall) / 2)
        scale = math.min(scale, self.fit)
        if math.abs(scale - QuestPanel.ScaleOf(frame)) < 0.005 then return end

        frame:SetScale(scale)
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", self.anchorLeft / scale, self.anchorTop / scale)

        if GameTooltip:IsOwned(self) then
            GameTooltip:SetText(QuestPanel.ScaleText(scale), Theme.Unpack("accentHi"))
            GameTooltip:Show()
        end
    end

    local function StopSizing(self)
        if not self.sizing then return end
        self.sizing = false
        self:SetScript("OnUpdate", nil)
        if ns.db then ns.db.questScale = QuestPanel.ClampScale(QuestPanel.ScaleOf(frame)) end
        QuestPanel:SavePosition()
        if ns.QuestLogUI then ns.QuestLogUI:PlaceItemsSoon() end
        if ns.SettingsUI and ns.SettingsUI.Refresh then ns.SettingsUI:Refresh() end
    end

    grip:SetScript("OnMouseDown", function(self, button)
        if button == "RightButton" then
            QuestPanel:SetPanelScale(1)
            return
        end
        if button ~= "LeftButton" then return end

        if Motion and Motion.Stop then pcall(Motion.Stop, Motion, frame, "open", true) end

        local scale = QuestPanel.ScaleOf(frame)
        local left, top = frame:GetLeft(), frame:GetTop()
        local cx, cy = GetCursorPosition()
        local uiScale = UIParent:GetEffectiveScale()
        if not (type(left) == "number" and type(top) == "number" and cx and cy
            and type(uiScale) == "number" and uiScale > 0) then
            return
        end

        -- The panel is as tall as its quest, so its height at the start of
        -- the drag is the one to size by.
        local okHeight, tall = pcall(frame.GetHeight, frame)
        self.tall = (okHeight and type(tall) == "number" and tall > 0) and tall or HEADER

        -- All in the screen's units, which do not change with the panel's.
        self.anchorLeft, self.anchorTop = left * scale, top * scale
        self.grabX = cx / uiScale - (self.anchorLeft + WIDTH * scale)
        self.grabY = (self.anchorTop - self.tall * scale) - cy / uiScale
        self.fit = QuestPanel:FitScale()

        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)

        self.sizing = true
        self:SetScript("OnUpdate", Track)
    end)
    grip:SetScript("OnMouseUp", StopSizing)
    grip:SetScript("OnHide", StopSizing)

    grip:SetScript("OnEnter", function(self)
        Light(true)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(QuestPanel.ScaleText(QuestPanel.ScaleOf(frame)), Theme.Unpack("accentHi"))
        GameTooltip:AddLine(L["Drag to make the panel bigger or smaller."], 1, 1, 1, true)
        GameTooltip:AddLine(L["Right-click to go back to normal size."], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    grip:SetScript("OnLeave", function()
        Light(false)
        GameTooltip:Hide()
    end)

    return grip
end

--- Refresh once, a moment from now, while the panel shows: for money
--- changes and prices learned at a merchant.
function QuestPanel:RefreshSoon()
    if not (self.frame and self.frame:IsShown()) or self.pending then return end
    self.pending = true
    if C_Timer and C_Timer.After then
        C_Timer.After(0.5, function()
            QuestPanel.pending = false
            QuestPanel:Refresh()
        end)
    else
        self.pending = false
        self:Refresh()
    end
end

--- Money only matters to a vendor quest that is shown and not yet bought.
function QuestPanel:OnMoney()
    if self.folded or not self:IsEnabled() then return end
    local quest = ns.UpgradeQuest:Current()
    if quest and quest.source and quest.source.kind == "vendor" then self:RefreshSoon() end
end

function QuestPanel:OnEnable()
    self:Refresh()
    ns.RegisterEvent(self, "PLAYER_MONEY", function() QuestPanel:OnMoney() end)
    -- A name drawn plain takes its rarity colour once the client sends it.
    ns.Items:WatchNames(function() QuestPanel:RefreshSoon() end)
end
