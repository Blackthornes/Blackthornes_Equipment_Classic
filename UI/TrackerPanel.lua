-- Blackthornes Equipment -- UI/TrackerPanel.lua
-- A small panel of the upgrades being hunted, like the quest tracker: each
-- with its icon, where to get it, and a green "in your bags" once it is got.
--
-- Click a hunt to pin its spot on the map, shift-click to link it in chat,
-- right-click for its menu. The Hunts and Done tabs (the house view tabs,
-- 2026-10-29) swap the list for the hunts already finished. The panel shows
-- itself while anything is tracked, unless the "Upgrade tracker" setting
-- (`showTracker`) is off. Its header is the house panel header: gold title,
-- a count chip, the fold gem (down to its header) and the close gem (put
-- away until a hunt is tracked or changed). Transparent is
-- `huntsSeeThrough` (UI/SeeThrough.lua). It can be dragged anywhere; the
-- spot is kept with the other window positions.

local _, ns = ...
local L = ns.L

local TrackerPanel = ns.NewModule("TrackerPanel")

local Theme = ns.Theme
local Widgets = ns.Widgets
local Motion = ns.Motion

local WIDTH = 260
local HEADER = 26
local TABS = 20
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
            GameTooltip:AddLine(L["Click to pin it on your map"], Theme.Unpack("dim"))
        end
        GameTooltip:AddLine(L["Right-click to stop tracking"], Theme.Unpack("dim"))
    end
    GameTooltip:Show()
end

function TrackerPanel:BuildRow(index)
    local row = CreateFrame("Button", nil, self.frame)
    row:SetSize(WIDTH - PAD * 2, ROW_HEIGHT)
    row:SetPoint("TOPLEFT", PAD, -(HEADER + TABS + 6 + (index - 1) * ROW_HEIGHT))
    -- Dark glass, a shade apart row by row, with a fine line under each.
    row.restKey = index % 2 == 0 and "glassAlt" or "glass"
    row.background = Theme.Fill(row, row.restKey)
    if ns.SeeThrough then ns.SeeThrough:AddGlass("hunts", row.background) end
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
            TrackerPanel:OpenMenu(hunt)
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
    frame.fill = Theme.Fill(frame, "window")
    Theme.Border(frame, "borderLit")
    Theme.Halo(frame, 10, 0.14)
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

    -- The house panel header: fold gem, close gem, a count chip, the title.
    local gems = Widgets.CreatePanelGems(header, {
        onFold = function(folded)
            TrackerPanel.folded = folded
            TrackerPanel:Refresh()
        end,
        onClose = function() TrackerPanel:Close() end,
    })
    self.gems = gems

    local chip = Widgets.CreateChip(header, "0", nil, { height = 16, selected = true })
    chip:SetPoint("RIGHT", gems.fold, "LEFT", -6, 0)
    chip:EnableMouse(false)
    self.countChip = chip

    local title = Theme.CreateLabel(header, "small", "accent")
    title:SetPoint("LEFT", 10, 0)
    title:SetPoint("RIGHT", chip, "LEFT", -6, 0)
    title:SetText(L["Upgrade Hunts"])
    self.title = title

    -- Hunts and Done, the house view tabs on top of the list.
    local tabs = Widgets.CreateViewTabs(frame, {
        { key = "hunts", text = L["Hunts"] },
        { key = "done", text = L["Done"] },
    }, function(key)
        TrackerPanel.showingDone = key == "done"
        TrackerPanel:Refresh()
    end, { selected = "hunts", height = TABS })
    tabs:SetPoint("TOPLEFT", PAD, -(HEADER + 4))
    tabs:SetPoint("TOPRIGHT", -PAD, -(HEADER + 4))
    self.tabs = tabs

    local empty = Theme.CreateLabel(frame, "tiny", "muted")
    empty:SetPoint("TOPLEFT", PAD + 2, -(HEADER + TABS + 10))
    empty:SetWidth(WIDTH - PAD * 2)
    self.empty = empty

    self.frame = frame
    self.rows = {}
    for index = 1, MOST_ROWS do self.rows[index] = self:BuildRow(index) end

    self:RestorePosition()
    if ns.SeeThrough then
        ns.SeeThrough:AddGlass("hunts", frame.fill)
        ns.SeeThrough:AddGlass("hunts", header.background)
        ns.SeeThrough:Attach("hunts", frame)
    end
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
    if not self:IsEnabled() or self.closed or (count == 0 and not self.showingDone) then
        if self.frame then self.frame:Hide() end
        return
    end
    self:Build()

    local lines = self:Lines()
    self.countChip.label:SetText(tostring(self.showingDone and #lines or count))
    self.countChip:SetText(tostring(self.showingDone and #lines or count))
    self.countChip:SetSelected(true)
    self.tabs:Select(self.showingDone and "done" or "hunts", true)
    self.tabs:SetShown(not self.folded)
    self.gems:SetFolded(self.folded)

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
    if not self.folded then height = HEADER + TABS + 10 + math.max(shown, empty and 1 or 0) * ROW_HEIGHT end
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

--- The close gem: put away until a hunt is tracked or changed.
function TrackerPanel:Close()
    self.closed = true
    if self.frame then self.frame:Hide() end
end

--- A hunt's right-click menu (the house row menu).
function TrackerPanel:OpenMenu(hunt)
    if not (hunt and ns.RowMenu) then return end
    local lines = {}
    if hunt.place and hunt.place.x and ns.Waypoints then
        lines[#lines + 1] = { text = L["Show on Map"], run = function()
            ns.Waypoints:Show(hunt.place, hunt.place.name)
        end }
    end
    if not hunt.done and ns.Tracking then
        lines[#lines + 1] = { text = L["Stop Tracking"], run = function()
            ns.Tracking:Untrack(hunt.itemID)
        end }
    end
    return ns.RowMenu:Open(lines, { title = ns.Items and ns.Items.ShowLink(hunt.link) or nil })
end

function TrackerPanel:ToggleDone()
    self.showingDone = not self.showingDone
    self.folded = false
    self:Refresh()
end

function TrackerPanel:OnTrackingChanged()
    self.closed = nil
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
