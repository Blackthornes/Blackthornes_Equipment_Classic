-- Blackthornes Equipment -- UI/IgnoredWindow.lua
-- The upgrades this character ignored on the upgrade quest panel, each with
-- a Restore button, and Restore all at the foot (the owner asked
-- 2026-10-08). Opened from Settings > Upgrade quest > Ignored, or with
-- /beq quest ignored.
--
-- What is listed is UpgradeQuest:IgnoredList(), read fresh on every
-- refresh, and every restore goes through UpgradeQuest:Restore or
-- RestoreAll, so the window keeps no copy of its own. The list is
-- charDB.upgradeQuestSkipped, the one Skip kept before it was called
-- Ignore. Ten rows show at a time; the mouse wheel scrolls the rest.

local _, ns = ...
local L = ns.L

local IgnoredUI = ns.NewModule("IgnoredUI")

local Theme = ns.Theme
local Widgets = ns.Widgets
local Motion = ns.Motion

local NAME = "BlackthornesEquipmentIgnored"
local WIDTH = 380
local PADDING = 18
-- The metal rim (UI/Titanforged.lua) reaches this far in from the edge.
local RIM = 6
local HEADER = 36
local ROW_HEIGHT = 28
local ROWS = 10
local ICON = 20
local FOOTER = 74

IgnoredUI.ROWS = ROWS

--- A button's tooltip: what it does, in clear white on the dark tooltip.
local function Explain(button, title, text)
    button:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(title, Theme.Unpack("accent"))
        GameTooltip:AddLine(text, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    button:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

--------------------------------------------------------------------------------
-- Building it
--------------------------------------------------------------------------------

function IgnoredUI:Build()
    if self.frame then return self.frame end

    local height = HEADER + 12 + 2 + ROWS * ROW_HEIGHT + 8 + FOOTER
    local frame = CreateFrame("Frame", NAME, UIParent)
    frame:SetSize(WIDTH, height)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    Theme.Fill(frame, "window")

    -- The house frame, as Settings and the stat weights wear it: the gold
    -- rim, the name on a plate and the red close gem, no portrait.
    if ns.Titanforged then
        self.trim = ns.Titanforged:Dress(frame, {
            title = "Blackthornes Equipment",
            close = function() IgnoredUI:Hide() end,
        })
        local left, right, top, bottom = ns.Titanforged.Reach(self.trim)
        if frame.SetClampRectInsets then frame:SetClampRectInsets(-left, right, top, -bottom) end
    else
        Theme.Border(frame, "borderLit")
    end
    Theme.Halo(frame, 12, 0.14)

    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        IgnoredUI:SavePosition()
    end)

    -- The house size grip under the bottom right corner (Widgets.WindowGrip),
    -- saved as `ignoredScale`.
    self.sizeGrip = Widgets.WindowGrip(frame, "ignoredScale", function()
        IgnoredUI:SavePosition()
    end)
    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(_, delta) IgnoredUI:Scroll(-delta) end)

    if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, NAME) end

    self.frame = frame
    self.offset = 0

    -- Under the plate: what this window is, and a gold rule.
    local header = CreateFrame("Frame", nil, frame)
    header:SetPoint("TOPLEFT", RIM, 0)
    header:SetPoint("TOPRIGHT", -RIM, 0)
    header:SetHeight(HEADER)
    local subtitle = Theme.CreateLabel(header, "normal", "muted")
    subtitle:SetPoint("LEFT", PADDING - RIM, -4)
    subtitle:SetText(L["Ignored upgrades"])
    self.count = Theme.CreateLabel(header, "small", "dim", "RIGHT")
    self.count:SetPoint("RIGHT", -(PADDING - RIM), -4)
    local rule = header:CreateTexture(nil, "ARTWORK")
    rule:SetPoint("BOTTOMLEFT")
    rule:SetPoint("BOTTOMRIGHT")
    rule:SetHeight(1)
    Theme.SetGradientAlpha(rule, "HORIZONTAL", "accent", 0.6, 0.05)

    -- The list, sunk in a well.
    local well = Theme.CreatePanel(frame, "panel", "border")
    well:SetPoint("TOPLEFT", PADDING, -(HEADER + 12))
    well:SetPoint("TOPRIGHT", -PADDING, -(HEADER + 12))
    well:SetHeight(ROWS * ROW_HEIGHT + 2)
    Theme.Recess(well)
    self.well = well

    local empty = Theme.CreateLabel(well, "small", "text")
    empty:SetPoint("TOPLEFT", 10, -10)
    empty:SetPoint("TOPRIGHT", -10, -10)
    empty:SetWordWrap(true)
    empty:SetText(L["Nothing ignored. Upgrades you ignore on the quest panel are listed here, where you can restore them."])
    self.empty = empty

    self.rows = {}
    for index = 1, ROWS do self.rows[index] = self:BuildRow(index) end

    local hint = Theme.CreateLabel(frame, "tiny", "dim")
    hint:SetPoint("BOTTOMLEFT", PADDING, 44)
    hint:SetPoint("BOTTOMRIGHT", -PADDING, 44)
    hint:SetWordWrap(true)
    hint:SetHeight(26)
    hint:SetJustifyV("BOTTOM")
    hint:SetText(L["Ignored upgrades are never picked for the upgrade quest on this character. Restore one and it can be picked again."])
    self.hint = hint

    self.restoreAll = Widgets.CreateButton(frame, L["Restore All"], function()
        ns.HandleSlash("quest restore")
    end, { width = 96, height = 22, primary = true })
    self.restoreAll:SetPoint("BOTTOMLEFT", PADDING, 14)
    Explain(self.restoreAll, L["Restore All"],
        L["Lets every ignored upgrade be picked again."])

    frame:Hide()
    return frame
end

--- One ignored upgrade: its icon, its name in its quality colour, and a
--- Restore button. Hover for the item's tooltip; Shift-click links it.
function IgnoredUI:BuildRow(index)
    local row = CreateFrame("Button", nil, self.well)
    row:SetPoint("TOPLEFT", 1, -(1 + (index - 1) * ROW_HEIGHT))
    row:SetPoint("TOPRIGHT", -1, -(1 + (index - 1) * ROW_HEIGHT))
    row:SetHeight(ROW_HEIGHT)
    -- Dark glass, a shade apart row by row, with a fine line under each.
    Theme.Fill(row, index % 2 == 0 and "glassAlt" or "glass")
    row.rule = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    row.rule:SetPoint("BOTTOMLEFT")
    row.rule:SetPoint("BOTTOMRIGHT")
    row.rule:SetHeight(1)
    row.rule:SetColorTexture(Theme.Unpack("border", 0.6))
    -- Under the mouse: the house row light (gold edge and wash).
    Widgets.RowLight(row)

    row.icon = Theme.CreateItemIcon(row, ICON)
    row.icon:SetPoint("LEFT", 8, 0)

    row.restore = Widgets.CreateButton(row, L["Restore"], function()
        if row.entry and ns.UpgradeQuest then
            local entry = row.entry
            if ns.UpgradeQuest:Restore(entry.itemID) then
                ns.Print(L.Format("%s can be picked for the upgrade quest again.", entry.link or entry.name))
            end
        end
    end, { width = 70, height = 20 })
    row.restore:SetPoint("RIGHT", -6, 0)
    Explain(row.restore, L["Restore this upgrade"], L["Let the upgrade quest pick it again on this character."])

    row.name = Theme.CreateLabel(row, "small", "text")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
    row.name:SetPoint("RIGHT", row.restore, "LEFT", -8, 0)
    -- A long name wraps onto a second line rather than being cut.
    row.name:SetWordWrap(true)

    row:SetScript("OnEnter", function(self)
        Motion:Blend(self, "hover", 1, 0.12, function(p) Widgets.SetRowLight(self, p) end)
        local entry = self.entry
        if not entry then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local ok = entry.link and pcall(GameTooltip.SetHyperlink, GameTooltip, entry.link)
        if not ok then GameTooltip:AddLine(entry.name, 1, 1, 1) end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function(self)
        Motion:Blend(self, "hover", 0, 0.18, function(p) Widgets.SetRowLight(self, p) end)
        GameTooltip:Hide()
    end)
    row:SetScript("OnClick", function(self)
        local entry = self.entry
        if entry and entry.link and type(IsModifiedClick) == "function" and IsModifiedClick("CHATLINK") then
            pcall(ChatEdit_InsertLink, entry.link)
        end
    end)

    row:Hide()
    return row
end

--------------------------------------------------------------------------------
-- Filling it in
--------------------------------------------------------------------------------

--- Move the list by `rows` (the mouse wheel: down is +1).
function IgnoredUI:Scroll(rows)
    local total = self.list and #self.list or 0
    local most = math.max(0, total - ROWS)
    self.offset = math.min(most, math.max(0, (self.offset or 0) + rows))
    self:Fill()
end

function IgnoredUI:Refresh()
    if not (self.frame and self.frame:IsShown()) then return end
    self.list = ns.UpgradeQuest and ns.UpgradeQuest:IgnoredList() or {}
    self:Scroll(0)
end

function IgnoredUI:Fill()
    local list = self.list or {}
    local total = #list
    self.empty:SetShown(total == 0)
    self.restoreAll:SetAlpha(total > 0 and 1 or 0.45)
    if total == 0 then
        self.count:SetText("")
    elseif total <= ROWS then
        self.count:SetText(total == 1 and L["1 item"] or L.Format("%d items", total))
    else
        self.count:SetText(L["Scroll for more."])
    end
    for index, row in ipairs(self.rows) do
        local entry = list[self.offset + index]
        row.entry = entry
        if entry then
            Theme.SetItemIcon(row.icon, entry.link or ("item:%d"):format(entry.itemID))
            row.name:SetText(entry.link or entry.name)
            row:Show()
        else
            row:Hide()
        end
    end
end

--- The quest picked, ignored or restored something: show it.
function IgnoredUI:OnUpgradeQuestChanged()
    self:Refresh()
end

--- An item the list was waiting on arrived from the server: its name now.
function IgnoredUI:GET_ITEM_INFO_RECEIVED()
    if not (self.frame and self.frame:IsShown() and self.list) then return end
    for _, entry in ipairs(self.list) do
        if not entry.link then
            self:RefreshSoon()
            return
        end
    end
end

--- Fill again once a burst of answers settles (the finder asks for up to
--- 40 items at a time, and each answer is an event).
function IgnoredUI:RefreshSoon()
    if self.pending then return end
    local after = _G.C_Timer and _G.C_Timer.After
    if type(after) ~= "function" then
        self:Refresh()
        return
    end
    self.pending = true
    after(0.2, function()
        IgnoredUI.pending = false
        if IgnoredUI.frame and IgnoredUI.frame:IsShown() then IgnoredUI:Refresh() end
    end)
end

--------------------------------------------------------------------------------
-- Showing it
--------------------------------------------------------------------------------

function IgnoredUI:SavePosition()
    if not (ns.db and self.frame) then return end
    local point, _, relativePoint, x, y = self.frame:GetPoint()
    ns.db.ignoredPoint, ns.db.ignoredRelativePoint = point, relativePoint
    ns.db.ignoredX, ns.db.ignoredY = x, y
end

function IgnoredUI:RestorePosition()
    if not self.frame then return end
    local db = ns.db or {}
    self.frame:ClearAllPoints()
    self.frame:SetPoint(db.ignoredPoint or "CENTER", UIParent,
        db.ignoredRelativePoint or "CENTER", db.ignoredX or 0, db.ignoredY or 0)
end

function IgnoredUI:Show()
    self:Build()
    if not self.frame:IsShown() then
        self.offset = 0
        self:RestorePosition()
        self.frame:Show()
        if Motion and Motion.Open then Motion:Open(self.frame) end
    end
    self:Refresh()
end

function IgnoredUI:Hide()
    if self.frame then self.frame:Hide() end
end

function IgnoredUI:Toggle()
    if self.frame and self.frame:IsShown() then self:Hide() else self:Show() end
end

function IgnoredUI:OnEnable()
    ns.RegisterEvent(self, "GET_ITEM_INFO_RECEIVED", self.GET_ITEM_INFO_RECEIVED)
end
