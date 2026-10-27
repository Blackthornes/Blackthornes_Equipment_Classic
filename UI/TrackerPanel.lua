-- Blackthornes Equipment -- UI/TrackerPanel.lua
-- A small panel of the upgrades being hunted, like the quest tracker: each
-- with its icon, where to get it, and a green "in your bags" once it is got.
--
-- Click a hunt to pin its spot on the map, shift-click to link it in chat,
-- right-click to stop tracking it. The header's Done button swaps the list
-- for the hunts already finished. The panel shows itself while anything is
-- tracked, unless the "Upgrade tracker" setting (`showTracker`) is off, and
-- folds down to its header with the "-" button. It can be dragged anywhere;
-- the spot is kept with the other window positions.

local _, ns = ...
local L = ns.L

local TrackerPanel = ns.NewModule("TrackerPanel")

local Theme = ns.Theme
local Widgets = ns.Widgets
local Motion = ns.Motion

local WIDTH = 260
local HEADER = 26
local ROW_HEIGHT = 44
local ICON = 24
local MOST_ROWS = 8
local PAD = 8

local function Colored(key, text)
    local r, g, b = Theme.Unpack(key)
    return ("|cff%02x%02x%02x%s|r"):format(math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5),
        math.floor(b * 255 + 0.5), text)
end

function TrackerPanel:IsEnabled()
    return not (ns.db and ns.db.showTracker == false)
end

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

local function ShowTooltip(row)
    local hunt = row.hunt
    if not hunt then return end
    GameTooltip:SetOwner(row, "ANCHOR_LEFT")
    pcall(GameTooltip.SetHyperlink, GameTooltip, hunt.link)
    GameTooltip:AddLine(" ")
    if hunt.done then
        GameTooltip:AddLine(L["Hunt done"], Theme.Unpack("good"))
    else
        if hunt.place and hunt.place.text then
            GameTooltip:AddLine(ns.Tracking.PlaceText(hunt.place), Theme.Unpack("text"))
        end
        if hunt.place and hunt.place.x then
            GameTooltip:AddLine(L["Click to pin it on your map"], Theme.Unpack("muted"))
        end
        GameTooltip:AddLine(L["Right-click to stop tracking"], Theme.Unpack("muted"))
    end
    GameTooltip:Show()
end

function TrackerPanel:BuildRow(index)
    local row = CreateFrame("Button", nil, self.frame)
    row:SetSize(WIDTH - PAD * 2, ROW_HEIGHT)
    row:SetPoint("TOPLEFT", PAD, -(HEADER + 4 + (index - 1) * ROW_HEIGHT))
    -- Dark glass, a shade apart row by row, with a fine line under each.
    row.restKey = index % 2 == 0 and "glassAlt" or "glass"
    row.background = Theme.Fill(row, row.restKey)
    row.rule = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    row.rule:SetPoint("BOTTOMLEFT")
    row.rule:SetPoint("BOTTOMRIGHT")
    row.rule:SetHeight(1)
    row.rule:SetColorTexture(Theme.Unpack("border", 0.6))

    local icon = Theme.CreateItemIcon(row, ICON)
    icon:SetPoint("LEFT", 2, 0)
    row.icon = icon

    local item = Theme.CreateLabel(row, "small", "text")
    item:SetPoint("TOPLEFT", ICON + 10, -3)
    item:SetWidth(WIDTH - PAD * 2 - ICON - 14)
    row.item = item

    local where = Theme.CreateLabel(row, "tiny", "muted")
    where:SetPoint("TOPLEFT", ICON + 10, -18)
    where:SetWidth(WIDTH - PAD * 2 - ICON - 14)
    -- Two lines rather than a cut.
    where:SetWordWrap(true)
    pcall(where.SetMaxLines, where, 2)
    row.where = where
    row.textWidth = WIDTH - PAD * 2 - ICON - 14

    -- Under the mouse: the house row light (gold edge and wash).
    Widgets.RowLight(row)
    local function Light(p) Widgets.SetRowLight(row, p) end
    row:SetScript("OnEnter", function(self)
        Motion:Blend(self, "hover", 1, 0.12, Light)
        ShowTooltip(self)
    end)
    row:SetScript("OnLeave", function(self)
        Motion:Blend(self, "hover", 0, 0.18, Light)
        GameTooltip:Hide()
    end)
    row:SetScript("OnClick", function(self, button)
        local hunt = self.hunt
        if not hunt then return end
        if button == "RightButton" then
            if not hunt.done and ns.Tracking then ns.Tracking:Untrack(hunt.itemID) end
            return
        end
        if type(IsModifiedClick) == "function" and type(ChatEdit_InsertLink) == "function" then
            local ok, chatLink = pcall(IsModifiedClick, "CHATLINK")
            if ok and chatLink then
                pcall(ChatEdit_InsertLink, hunt.link)
                return
            end
        end
        if hunt.place and ns.Waypoints then ns.Waypoints:Show(hunt.place, hunt.place.name, hunt.link) end
    end)
    if row.RegisterForClicks then row:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
    row:Hide()
    return row
end

function TrackerPanel:Build()
    if self.frame then return self.frame end

    local frame = CreateFrame("Frame", "BlackthornesEquipmentTracker", UIParent)
    frame:SetSize(WIDTH, HEADER)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    Theme.Window(frame)
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        TrackerPanel:SavePosition()
    end)

    local header = Theme.CreatePanel(frame, "header", false)
    header:SetPoint("TOPLEFT")
    header:SetPoint("TOPRIGHT")
    header:SetHeight(HEADER)
    Theme.HouseHeader(header, 14)
    header:EnableMouse(false)

    local fold = Widgets.CreateButton(header, "-", function() TrackerPanel:ToggleFold() end,
        { width = 18, height = 16 })
    fold:SetPoint("RIGHT", -5, 0)
    self.foldButton = fold

    local done = Widgets.CreateButton(header, L["Done"], function() TrackerPanel:ToggleDone() end,
        { width = 40, height = 16 })
    done:SetPoint("RIGHT", fold, "LEFT", -4, 0)
    self.doneButton = done

    local title = Theme.CreateLabel(header, "small", "accent")
    title:SetPoint("LEFT", 10, 0)
    title:SetPoint("RIGHT", done, "LEFT", -6, 0)
    self.title = title

    local empty = Theme.CreateLabel(frame, "tiny", "muted")
    empty:SetPoint("TOPLEFT", PAD + 2, -(HEADER + 8))
    empty:SetWidth(WIDTH - PAD * 2)
    self.empty = empty

    self.frame = frame
    self.rows = {}
    for index = 1, MOST_ROWS do self.rows[index] = self:BuildRow(index) end

    self:RestorePosition()
    frame:Hide()
    return frame
end

--------------------------------------------------------------------------------
-- Filling it in
--------------------------------------------------------------------------------

local function Fit(size, text, width)
    if ns.FinderUI and ns.FinderUI.Fit then return ns.FinderUI.Fit(size, text, width) end
    return text
end

--- What a row shows under the item: where to get it, or that it is got.
function TrackerPanel.WhereText(hunt)
    if hunt.done then return Colored("good", L["Done"]) end
    if hunt.got then return Colored("good", L["In your bags: put it on"]) end
    if hunt.place and hunt.place.text then return ns.Tracking.PlaceText(hunt.place) end
    return L["Open Where to get upgrades for the details"]
end

function TrackerPanel:Lines()
    if self.showingDone then
        local lines = {}
        for _, done in ipairs(ns.Tracking:Done()) do
            lines[#lines + 1] = { itemID = done.itemID, link = done.link, done = true }
        end
        return lines
    end
    return ns.Tracking:List()
end

function TrackerPanel:Refresh()
    if not ns.Tracking then return end
    local count = ns.Tracking:Count()
    if not self:IsEnabled() or (count == 0 and not self.showingDone) then
        if self.frame then self.frame:Hide() end
        return
    end
    self:Build()

    local lines = self:Lines()
    if self.showingDone then
        self.title:SetText(L.Format("Finished hunts (%d)", #lines))
    else
        self.title:SetText(L.Format("Upgrade hunts (%d)", count))
    end
    self.doneButton:SetText(self.showingDone and L["Hunts"] or L["Done"])
    self.foldButton:SetText(self.folded and "+" or "-")

    local shown = 0
    for index, row in ipairs(self.rows) do
        local hunt = not self.folded and lines[index] or nil
        row.hunt = hunt
        if hunt then
            shown = shown + 1
            Theme.SetItemIcon(row.icon, hunt.link)
            row.item:SetText(ns.Items.ShowLink(hunt.link) or "?")
            row.where:SetText(Fit("tiny", TrackerPanel.WhereText(hunt), row.textWidth * 2 - 50))
            row:Show()
        else
            row:Hide()
        end
    end

    local empty = not self.folded and shown == 0
    self.empty:SetShown(empty)
    self.empty:SetText(self.showingDone and L["No hunts finished yet."] or "")
    local height = HEADER
    if not self.folded then height = HEADER + 8 + math.max(shown, empty and 1 or 0) * ROW_HEIGHT end
    self.frame:SetHeight(height)

    if not self.frame:IsShown() then
        self.frame:Show()
        Motion:Open(self.frame)
    end
end

function TrackerPanel:ToggleFold()
    self.folded = not self.folded
    self:Refresh()
end

function TrackerPanel:ToggleDone()
    self.showingDone = not self.showingDone
    self.folded = false
    self:Refresh()
end

function TrackerPanel:OnTrackingChanged()
    self:Refresh()
end

--------------------------------------------------------------------------------
-- Position
--------------------------------------------------------------------------------

function TrackerPanel:SavePosition()
    if not (ns.db and self.frame) then return end
    local point, _, relativePoint, x, y = self.frame:GetPoint()
    ns.db.trackerPoint, ns.db.trackerRelativePoint = point, relativePoint
    ns.db.trackerX, ns.db.trackerY = x, y
end

function TrackerPanel:RestorePosition()
    if not self.frame then return end
    local db = ns.db or {}
    self.frame:ClearAllPoints()
    self.frame:SetPoint(db.trackerPoint or "RIGHT", UIParent, db.trackerRelativePoint or "RIGHT",
        db.trackerX or -40, db.trackerY or 120)
end

function TrackerPanel:OnEnable()
    self:Refresh()
    -- A name drawn plain takes its rarity colour once the client sends it.
    ns.Items:WatchNames(function()
        if TrackerPanel.frame and TrackerPanel.frame:IsShown() then TrackerPanel:Refresh() end
    end)
end
