-- Blackthornes Equipment -- UI/TrainingDrawer.lua
-- The Training drawer beside the gear window (the owner said build it
-- 2026-10-13): the class spells the character can train now and what they
-- cost, the next level's, untrained weapons that are waiting as upgrades,
-- and the other characters' spells. Logic/ClassTraining.lua works it out;
-- this only draws it.
--
-- It opens from the gear window's Training button, sits against the
-- window's right edge and moves with it, and draws only while shown, again
-- only when ClassTraining.version, the level or the gear window's picks
-- move. Rows are dark glass. Show the way points the quest arrow at the
-- class trainer (ClassTraining.Guide, set below).

local _, ns = ...
local L = ns.L

local Drawer = ns.NewModule("TrainingDrawer")

local Theme = ns.Theme
local Widgets = ns.Widgets
local Motion = ns.Motion

local WIDTH = 300
local PADDING = 14
local ROW = 20
local ICON = 16
local FOOT = 50

-- How many lines the drawer holds; past that, one says how many more. Its
-- well is 384 pixels tall, so 19 rows of 20 fit and a 20th spilled over the
-- footer and the Show the way button.
Drawer.MAX_LINES = 19

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

local function CreateLine(parent, index)
    local restKey = index % 2 == 0 and "glassAlt" or "glass"
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row.background = Theme.Fill(row, restKey)

    local rule = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    rule:SetPoint("BOTTOMLEFT")
    rule:SetPoint("BOTTOMRIGHT")
    rule:SetHeight(1)
    rule:SetColorTexture(Theme.Unpack("border", 0.6))
    row.rule = rule

    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(ICON, ICON)
    icon:SetPoint("LEFT", 6, 0)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.icon = icon

    local text = Theme.CreateLabel(row, "small", "text")
    text:SetPoint("LEFT", 6 + ICON + 6, 0)
    row.text = text

    local right = Theme.CreateLabel(row, "small", "muted", "RIGHT")
    right:SetPoint("RIGHT", -6, 0)
    row.right = right
    text:SetPoint("RIGHT", right, "LEFT", -6, 0)

    local hoverWash = row:CreateTexture(nil, "BACKGROUND", nil, 3)
    hoverWash:SetAllPoints(row)
    hoverWash:Hide()
    local hoverEdge = row:CreateTexture(nil, "OVERLAY")
    hoverEdge:SetPoint("TOPLEFT")
    hoverEdge:SetPoint("BOTTOMLEFT")
    hoverEdge:SetWidth(2)
    hoverEdge:SetColorTexture(Theme.Unpack("accentHi"))
    hoverEdge:SetAlpha(0)

    function row.Light(p)
        local key = row.heading and "panel" or restKey
        row.background:SetColorTexture(Motion.Mix(key, row.heading and "panel" or "glassHover", p))
        Theme.LightGradient(hoverWash, "HORIZONTAL", "accent", 0.10, 0, row.heading and 0 or p)
        hoverEdge:SetAlpha(row.heading and 0 or p)
    end
    function row.Rest(heading)
        row.heading = heading
        row.background:SetColorTexture(Theme.Unpack(heading and "panel" or restKey))
        row.rule:SetColorTexture(Theme.Unpack(heading and "accent" or "border", heading and 0.35 or 0.6))
    end

    row:SetScript("OnEnter", function(self)
        Motion:Blend(self, "hover", 1, 0.12, self.Light)
        if self.spell then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local ok = Drawer.SpellTooltip(self.spell)
            if not ok then GameTooltip:AddLine(self.text:GetText() or "", 1, 1, 1) end
            local line
            if not self.spell.cost then
                line = L["No price yet. Visit a class trainer once to see it."]
            elseif self.spell.guess then
                line = L.Format("Usually %s. Visit your trainer once for the real price.", ns.ClassTraining.Money(self.spell.cost))
            else
                line = L.Format("Costs %s at the trainer", ns.ClassTraining.Money(self.spell.cost))
            end
            GameTooltip:AddLine(line, Theme.Unpack("muted"))
            GameTooltip:AddLine(self.skipped and L["Right-click to bring it back."]
                or L["Right-click to skip this spell."], Theme.Unpack("good"))
            GameTooltip:Show()
        elseif self.link then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            pcall(GameTooltip.SetHyperlink, GameTooltip, self.link)
            GameTooltip:AddLine(L["Click to show the weapon master."], Theme.Unpack("good"))
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function(self)
        Motion:Blend(self, "hover", 0, 0.18, self.Light)
        GameTooltip:Hide()
    end)
    row:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            if self.spell then Drawer:Skip(self.spell, not self.skipped) end
            return
        end
        if self.link and ns.WeaponSkills then ns.WeaponSkills:ShowMaster(self.link) end
    end)
    return row
end

--- Skip a spell (a right-click on it), or bring a skipped one back. It
--- leaves the lists and costs here and in Butler; nothing is bought or
--- forgotten.
function Drawer:Skip(spell, on)
    local training = ns.ClassTraining
    if not (training and spell and spell.id) then return end
    training:SetSkipped(spell.id, on)
    GameTooltip:Hide()
    self.key = nil
    self:Refresh()
end

--- The game's own spell tooltip, where the client has the call.
function Drawer.SpellTooltip(spell)
    if type(GameTooltip.SetSpellByID) ~= "function" then return false end
    local ok = pcall(GameTooltip.SetSpellByID, GameTooltip, spell.id)
    return ok
end

function Drawer:Build()
    if self.frame then return self.frame end
    local window = ns.UI and ns.UI.frame
    if not window then return nil end

    local frame = CreateFrame("Frame", "BlackthornesEquipmentTraining", window)
    frame:SetWidth(WIDTH)
    frame:SetPoint("TOPLEFT", window, "TOPRIGHT", 4, -24)
    frame:SetPoint("BOTTOMLEFT", window, "BOTTOMRIGHT", 4, 24)
    frame:EnableMouse(true)
    Theme.Fill(frame, "window")
    -- The gold rim and the red close gem, as the gear window beside it.
    if ns.Titanforged then
        self.trim = ns.Titanforged:Dress(frame, { close = function() Drawer:Hide() end })
    else
        Theme.Border(frame, "borderLit")
    end
    Theme.Halo(frame, 10, 0.12)

    local title = Theme.CreateLabel(frame, "normal", "accent")
    title:SetPoint("TOPLEFT", PADDING, -12)
    title:SetText(L["CLASS TRAINING"])
    self.title = title

    local sub = Theme.CreateLabel(frame, "small", "muted")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    sub:SetPoint("RIGHT", -PADDING, 0)
    self.sub = sub

    local well = Theme.CreatePanel(frame, "panel", "border")
    well:SetPoint("TOPLEFT", PADDING - 3, -50)
    well:SetPoint("BOTTOMRIGHT", -(PADDING - 3), FOOT)
    Theme.Recess(well)
    self.well = well

    self.lines = {}
    for index = 1, self.MAX_LINES do
        local row = CreateLine(frame, index)
        row:SetFrameLevel(well:GetFrameLevel() + 1)
        row:SetPoint("TOPLEFT", well, "TOPLEFT", 3, -3 - (index - 1) * ROW)
        row:SetPoint("RIGHT", well, "RIGHT", -3, 0)
        row:Hide()
        self.lines[index] = row
    end

    local way = Widgets.CreateButton(frame, L["Show the Way"], function()
        if ns.ClassTraining then ns.ClassTraining:ShowTheWay() end
    end, { width = 100, height = 22, primary = true })
    way:SetPoint("BOTTOMRIGHT", -PADDING, 12)
    self.wayButton = way

    local hint = Theme.CreateLabel(frame, "small", "dim")
    hint:SetPoint("BOTTOMLEFT", PADDING, 10)
    hint:SetPoint("RIGHT", way, "LEFT", -8, 0)
    hint:SetWordWrap(true)
    hint:SetJustifyV("BOTTOM")
    hint:SetHeight(34)
    self.hint = hint

    frame:Hide()
    self.frame = frame
    return frame
end

--------------------------------------------------------------------------------
-- Filling it in
--------------------------------------------------------------------------------

--- The lines the drawer shows, top to bottom: { heading, text, right,
--- icon, spell, link, color }.
function Drawer:Lines()
    local training = ns.ClassTraining
    local lines = {}
    local plan = training:Plan()

    if #plan.ready > 0 then
        lines[#lines + 1] = { heading = true, text = L["READY NOW"],
            right = training.CostText(plan.cost, plan.unknown, #plan.ready) }
        for _, spell in ipairs(plan.ready) do
            lines[#lines + 1] = { text = training.Label(spell.entry), icon = training.Icon(spell.entry), spell = spell,
                right = spell.cost and training.Money(spell.cost) or L["Not priced yet"] }
        end
    else
        lines[#lines + 1] = { heading = true, text = L["READY NOW"] }
        lines[#lines + 1] = { text = L["Nothing to train at your level."], color = "muted" }
    end

    if plan.nextLevel then
        lines[#lines + 1] = { heading = true, text = L.Format("AT LEVEL %d", plan.nextLevel),
            right = training.CostText(plan.nextCost, plan.nextUnknown, #plan.next) }
        for _, spell in ipairs(plan.next) do
            lines[#lines + 1] = { text = training.Label(spell.entry), icon = training.Icon(spell.entry), spell = spell,
                right = spell.cost and training.Money(spell.cost) or L["Not priced yet"], color = "muted" }
        end
    end

    local untrained = ns.UI and ns.UI.untrained or {}
    if #untrained > 0 then
        lines[#lines + 1] = { heading = true, text = L["WEAPON SKILLS"] }
        for _, weapon in ipairs(untrained) do
            lines[#lines + 1] = { text = L.Format("Learn %s", weapon.skill), link = weapon.link,
                icon = Theme.ItemIcon and Theme.ItemIcon(weapon.link) or nil, right = L["Show the trainer"], color = "warn" }
        end
    end

    if plan.skipped and #plan.skipped > 0 then
        lines[#lines + 1] = { heading = true, text = L["SKIPPED"] }
        for _, spell in ipairs(plan.skipped) do
            lines[#lines + 1] = { text = training.Label(spell.entry), icon = training.Icon(spell.entry), spell = spell,
                skipped = true, color = "muted" }
        end
    end

    local others = training:Others()
    if #others > 0 then
        lines[#lines + 1] = { heading = true, text = L["YOUR OTHER CHARACTERS"] }
        for _, other in ipairs(others) do
            -- The whole name on a line of its own, with the cost beside it,
            -- so a long first and last name is never cut short.
            lines[#lines + 1] = {
                text = other.name or "?",
                right = training.CostText(other.cost, other.unknown, other.count), color = "text",
            }
            lines[#lines + 1] = {
                text = other.count == 1 and L.Format("1 spell at level %d", other.level or 0)
                    or L.Format("%d spells at level %d", other.count, other.level or 0),
                color = "muted", indent = true,
            }
        end
    end
    return lines
end

function Drawer:Refresh()
    if not (self.frame and self.frame:IsShown()) then return end
    local training = ns.ClassTraining
    local player = training.Player()
    local ui = ns.UI
    local key = ("%d:%d:%s"):format(training.version, player.level, tostring(ui and ui.untrainedKey))
    if self.key == key then return end
    self.key = key

    self.sub:SetText(L.Format("Level %d %s", player.level, player.className or ""))
    local lines = self:Lines()
    local shown = math.min(#lines, self.MAX_LINES)
    if #lines > self.MAX_LINES then
        shown = self.MAX_LINES - 1
    end
    for index, row in ipairs(self.lines) do
        local line = lines[index]
        if index == self.MAX_LINES and #lines > self.MAX_LINES then
            line = { text = L.Format("and %d more", #lines - shown), color = "muted" }
        end
        if line then
            row.Rest(line.heading)
            row.spell, row.link, row.skipped = line.spell, line.link, line.skipped == true
            row.text:SetText(line.text)
            row.text:SetTextColor(Theme.Unpack(line.heading and "accent" or line.color or "text"))
            row.right:SetText(line.right or "")
            row.right:SetTextColor(Theme.Unpack(line.heading and "accent" or "muted"))
            row.icon:SetShown(line.icon ~= nil)
            if line.icon then row.icon:SetTexture(line.icon) end
            row.text:SetPoint("LEFT", (line.icon or line.indent) and (6 + ICON + 6) or 6, 0)
            row:Show()
        else
            row:Hide()
        end
    end

    local spot = training:Nearest()
    local where = training.Where(spot)
    self.wayButton:SetDimmed(spot == nil)
    if where then
        self.hint:SetText(L.Format("Your trainer: %s, %s.", spot.name or "?", where))
    else
        self.hint:SetText(L["Open a class trainer once and its prices and location are remembered."])
    end
    if not training:IsOn() then
        self.hint:SetText(L["Class training is turned off in Settings."])
    end
end

--------------------------------------------------------------------------------
-- Showing
--------------------------------------------------------------------------------

function Drawer:IsShown()
    return self.frame ~= nil and self.frame:IsShown()
end

function Drawer:Show()
    if not self:Build() then return end
    self.key = nil
    self.frame:Show()
    if ns.db then ns.db.trainingDrawer = true end
    self:Refresh()
    if ns.UI and ns.UI.OnTrainingToggled then ns.UI:OnTrainingToggled() end
end

function Drawer:Hide()
    if self.frame then self.frame:Hide() end
    if ns.db then ns.db.trainingDrawer = false end
    if ns.UI and ns.UI.OnTrainingToggled then ns.UI:OnTrainingToggled() end
end

function Drawer:Toggle()
    if self:IsShown() then self:Hide() else self:Show() end
end

--- The gear window opened: the drawer comes back if it was left open.
function Drawer:WindowShown()
    if ns.db and ns.db.trainingDrawer == true and ns.ClassTraining:IsOn() then
        self:Show()
    else
        self:Refresh()
    end
end

--- The quest arrow points at the class trainer, as it does at a weapon
--- master (WeaponSkills:ShowMaster). The arrow keeps zones in the data's
--- English and spots in percent.
function Drawer.Guide(spot, title)
    local arrow = ns.QuestArrow
    if not (arrow and arrow.AimAtQuest and spot.zone) then return false end
    local zone = spot.zone
    if ns.Waypoints and ns.Waypoints.DataZone then
        local ok, english = pcall(ns.Waypoints.DataZone, ns.Waypoints, zone)
        if ok and english then zone = english end
    end
    local ok, done = pcall(arrow.AimAtQuest, arrow, nil, title, {
        zone = zone, x = spot.x and spot.x * 100, y = spot.y and spot.y * 100, name = spot.name,
    })
    return ok and done
end

function Drawer:OnEnable()
    local training = ns.ClassTraining
    if not training then return end
    training.Guide = Drawer.Guide
    training.OnChanged = function()
        if Drawer:IsShown() then Drawer:Refresh() end
        if ns.UI and ns.UI.OnTrainingToggled then ns.UI:OnTrainingToggled() end
    end
end
