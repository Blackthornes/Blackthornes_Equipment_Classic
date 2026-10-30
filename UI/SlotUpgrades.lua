-- Blackthornes Equipment -- UI/SlotUpgrades.lua
-- Upgrades on the character sheet: hover a gear slot and its tooltip lists
-- the best upgrades on offer for it and where they come from; Alt-click the
-- slot for a panel of them with Track and Map buttons. The panel wears the
-- house frame: gold rim, the slot's name on the plate, the red close gem.
--
-- The picks are the upgrade finder's (Finder:Latest, scanned again only
-- when the gear, level or bags change), so the sheet, the finder window and
-- the bag arrows always agree. A ring or trinket slot shows the picks for
-- both of the pair. Only the slot buttons' scripts are hooked, after the
-- game's own, so nothing the game does with a slot (equipping, using a
-- trinket) changes. Switched off with the "Character sheet" setting
-- (`slotUpgrades`).

local _, ns = ...
local L = ns.L

local SlotUpgrades = ns.NewModule("SlotUpgrades")

local Theme = ns.Theme
local Widgets = ns.Widgets
local Motion = ns.Motion

local SLOT_BUTTONS = {
    "CharacterHeadSlot", "CharacterNeckSlot", "CharacterShoulderSlot", "CharacterBackSlot",
    "CharacterChestSlot", "CharacterWristSlot", "CharacterHandsSlot", "CharacterWaistSlot",
    "CharacterLegsSlot", "CharacterFeetSlot", "CharacterFinger0Slot", "CharacterFinger1Slot",
    "CharacterTrinket0Slot", "CharacterTrinket1Slot", "CharacterMainHandSlot",
    "CharacterSecondaryHandSlot", "CharacterRangedSlot",
}

-- Rings and trinkets are a pair: either slot shows the picks for both.
local PAIRS = { [11] = { 11, 12 }, [12] = { 11, 12 }, [13] = { 13, 14 }, [14] = { 13, 14 } }

local SLOT_NAMES = {
    [1] = L["Head"], [2] = L["Neck"], [3] = L["Shoulder"], [5] = L["Chest"], [6] = L["Waist"], [7] = L["Legs"],
    [8] = L["Feet"], [9] = L["Wrist"], [10] = L["Hands"], [11] = L["Rings"], [12] = L["Rings"], [13] = L["Trinkets"],
    [14] = L["Trinkets"], [15] = L["Back"], [16] = L["Main hand"], [17] = L["Off hand"], [18] = L["Ranged"],
}

local SHOWN = 3
local WIDTH = 380
local ROW_HEIGHT = 54
local PAD = 12

function SlotUpgrades:IsEnabled()
    return not (ns.db and ns.db.slotUpgrades == false)
end

local function Colored(key, text)
    local r, g, b = Theme.Unpack(key)
    return ("|cff%02x%02x%02x%s|r"):format(math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5),
        math.floor(b * 255 + 0.5), text)
end

--- How much better, short: "+12%", "empty slot", "better", with the level
--- it waits on when planning ahead.
function SlotUpgrades.Gain(pick)
    local result = pick.result or {}
    local text = L["better"]
    if result.empty then
        text = L["empty slot"]
    elseif result.percent then
        text = ("%+d%%"):format(math.floor(result.percent + 0.5))
    end
    if SlotUpgrades.Train(pick) then text = L.Format("Train: %s", text) end
    return text
end

--- Does a pick need a weapon skill not learned yet? Then its gain is red.
function SlotUpgrades.Train(pick)
    return ns.WeaponSkills ~= nil and ns.WeaponSkills:NeedsTraining(pick.link)
end

--- The colour key for a pick's gain.
function SlotUpgrades.GainKey(pick)
    if SlotUpgrades.Train(pick) then return "loss" end
    return (pick.needs or pick.remote) and "warn" or "good"
end

--- The best picks for an inventory slot (both of a pair), best first.
function SlotUpgrades:PicksFor(slot)
    local found = ns.Finder and ns.Finder:Latest()
    if not found then return {} end
    local picks = {}
    for _, each in ipairs(PAIRS[slot] or { slot }) do
        for _, pick in ipairs(found.slots[each] or {}) do picks[#picks + 1] = pick end
    end
    table.sort(picks, function(a, b)
        if (a.needs == nil) ~= (b.needs == nil) then return a.needs == nil end
        if a.remote ~= b.remote then return not a.remote end
        return a.gain > b.gain
    end)
    for i = #picks, SHOWN + 1, -1 do picks[i] = nil end
    return picks
end

--------------------------------------------------------------------------------
-- The slot's tooltip
--------------------------------------------------------------------------------

local function LineCount(tooltip)
    local ok, count = pcall(tooltip.NumLines, tooltip)
    return ok and tonumber(count) or 0
end

--- Add the slot's upgrades to its tooltip. `picks` are the ones worked out
--- when the slot was hovered; the game redraws a slot's tooltip several
--- times a second, and the same lines go back on each time.
function SlotUpgrades:AddLines(tooltip, slot, picks)
    if not self:IsEnabled() or not SLOT_NAMES[slot] then return end
    if not picks then
        local ok, found = pcall(self.PicksFor, self, slot)
        if not ok then return end
        picks = found
    end

    tooltip:AddLine(" ")
    if #picks == 0 then
        local latest = ns.Finder and ns.Finder.latest
        if not latest and ns.Finder and ns.Finder:Scanning() then
            tooltip:AddLine(L["Looking for upgrades. Hover again in a moment"], Theme.Unpack("muted"))
        elseif latest and (latest.waiting or 0) > 0 then
            tooltip:AddLine(L["Still loading gear. Hover again in a moment"],
                Theme.Unpack("muted"))
        else
            tooltip:AddLine(L["Nothing on offer beats this yet"], Theme.Unpack("muted"))
        end
    else
        tooltip:AddLine(L["Upgrades on offer"], Theme.Unpack("accent"))
        for _, pick in ipairs(picks) do
            local gainKey = SlotUpgrades.GainKey(pick)
            if type(tooltip.AddDoubleLine) == "function" then
                local r, g, b = Theme.Unpack(gainKey)
                tooltip:AddDoubleLine(pick.link, SlotUpgrades.Gain(pick), 1, 1, 1, r, g, b)
            else
                tooltip:AddLine(ns.Items.ShowLink(pick.link) .. "  " .. Colored(gainKey, SlotUpgrades.Gain(pick)))
            end
            local source = pick.sources and pick.sources[1]
            if source and ns.FinderUI then
                tooltip:AddLine("    " .. ns.FinderUI.SourceLine(source), Theme.Unpack("muted"))
            end
        end
    end
    tooltip:AddLine(L["Alt-click for upgrades you can track"], Theme.Unpack("dim"))
    pcall(tooltip.Show, tooltip)
end

--- A slot was hovered: work out its upgrades once and put them on.
function SlotUpgrades:OnSlotEnter(tooltip, button, slot)
    local ok, picks = pcall(self.PicksFor, self, slot)
    self.tip = { tooltip = tooltip, owner = button, slot = slot, picks = ok and picks or {} }
    self:AddLines(tooltip, slot, self.tip.picks)
    self.tip.lines = LineCount(tooltip)
end

--- Every frame the tooltip shows: when the game has redrawn the slot's
--- tooltip (which wipes added lines), put the upgrades back on.
function SlotUpgrades:Keep(tooltip)
    local tip = self.tip
    if not tip or tip.tooltip ~= tooltip or self.keeping then return end
    local okOwner, owner = pcall(tooltip.GetOwner, tooltip)
    local okShown, shown = pcall(tooltip.IsShown, tooltip)
    if not (okOwner and owner == tip.owner and okShown and shown) then
        self.tip = nil
        return
    end
    if LineCount(tooltip) >= (tip.lines or 0) then return end
    self.keeping = true
    pcall(self.AddLines, self, tooltip, tip.slot, tip.picks)
    self.keeping = false
    tip.lines = LineCount(tooltip)
end

--------------------------------------------------------------------------------
-- The Alt-click panel
--------------------------------------------------------------------------------

function SlotUpgrades:BuildRow(index)
    local row = CreateFrame("Frame", nil, self.frame)
    row:SetSize(WIDTH - PAD * 2, ROW_HEIGHT)
    row:SetPoint("TOPLEFT", PAD, -(40 + (index - 1) * ROW_HEIGHT))
    -- Dark glass, a shade apart row by row, with a fine line under each.
    row.background = Theme.Fill(row, index % 2 == 0 and "glassAlt" or "glass")
    row.rule = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    row.rule:SetPoint("BOTTOMLEFT")
    row.rule:SetPoint("BOTTOMRIGHT")
    row.rule:SetHeight(1)
    row.rule:SetColorTexture(Theme.Unpack("border", 0.6))
    -- Under the mouse: the house row light (gold edge and wash).
    Widgets.RowLight(row)
    row:EnableMouse(true)

    local icon = Theme.CreateItemIcon(row, 30)
    icon:SetPoint("LEFT", 6, 0)
    row.icon = icon

    local track = Widgets.CreateButton(row, L["Track"], function()
        local pick = row.pick
        if pick and ns.Tracking then ns.Tracking:Toggle(pick) end
        SlotUpgrades:Fill()
    end, { width = 58, height = 18 })
    track:SetPoint("TOPRIGHT", -6, -5)
    row.track = track

    local map = Widgets.CreateButton(row, L["Map"], function()
        local source = row.pick and row.pick.sources and row.pick.sources[1]
        if source and ns.Waypoints then ns.Waypoints:Show(source, source.name, row.pick.link) end
    end, { width = 58, height = 18 })
    map:SetPoint("TOPRIGHT", track, "BOTTOMRIGHT", 0, -2)
    row.map = map

    -- The buttons grow to fit their words (German runs longer); the text
    -- keeps clear of them.
    local buttons = math.max(70, (tonumber(track:GetWidth()) or 0) + 12, (tonumber(map:GetWidth()) or 0) + 12)
    local textWidth = WIDTH - PAD * 2 - 6 - 30 - 8 - buttons
    local item = Theme.CreateLabel(row, "normal", "text")
    item:SetPoint("TOPLEFT", 44, -6)
    item:SetWidth(textWidth - 60)
    row.item = item

    -- The gain sits at the right of the item's line and grows leftward to
    -- fit ("Train: empty slot"), the item's name giving it the room.
    local gain = Theme.CreateLabel(row, "normal", "good", "RIGHT")
    gain:SetPoint("TOPRIGHT", row, "TOPLEFT", 44 + textWidth - 2, -6)
    gain:SetWidth(54)
    row.gain = gain
    row.textWidth = textWidth

    local source = Theme.CreateLabel(row, "tiny", "muted")
    source:SetPoint("TOPLEFT", 44, -26)
    source:SetWidth(textWidth)
    -- Two lines rather than a cut.
    source:SetWordWrap(true)
    pcall(source.SetMaxLines, source, 2)
    row.source = source
    row.sourceWidth = textWidth

    local function Lit(p) Widgets.SetRowLight(row, p) end
    row:SetScript("OnEnter", function(self)
        Motion:Blend(self, "hover", 1, 0.12, Lit)
        if not self.pick then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        pcall(GameTooltip.SetHyperlink, GameTooltip, self.pick.link)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function(self)
        Motion:Blend(self, "hover", 0, 0.18, Lit)
        GameTooltip:Hide()
    end)
    -- Hidden under the mouse, no leave comes: start dark next time.
    row:SetScript("OnHide", function(self)
        Motion:Stop(self, "hover")
        Motion:SetValue(self, "hover", 0)
        Lit(0)
    end)
    row:Hide()
    return row
end

function SlotUpgrades:Build()
    if self.frame then return self.frame end
    local frame = CreateFrame("Frame", "BlackthornesEquipmentSlotUpgrades", UIParent)
    frame:SetSize(WIDTH, 40 + SHOWN * ROW_HEIGHT + 40)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    Theme.Fill(frame, "window")
    if type(UISpecialFrames) == "table" then
        table.insert(UISpecialFrames, "BlackthornesEquipmentSlotUpgrades")
    end

    -- The house frame: the gold rim, the slot's name on the plate and the
    -- red close gem, as the other windows wear it.
    if ns.Titanforged then
        self.trim = ns.Titanforged:Dress(frame, {
            title = L.Format("Upgrades: %s", L["this slot"]),
            close = function() frame:Hide() end,
        })
        local left, right, top, bottom = ns.Titanforged.Reach(self.trim)
        if frame.SetClampRectInsets then frame:SetClampRectInsets(-left, right, top, -bottom) end
    else
        Theme.Border(frame, "borderLit")
        local title = Theme.CreateLabel(frame, "title", "accent")
        title:SetPoint("TOPLEFT", PAD, -10)
        title:SetPoint("TOPRIGHT", -PAD, -10)
        self.title = title
    end
    Theme.Halo(frame, 12, 0.14)

    local empty = Theme.CreateLabel(frame, "normal", "muted", "CENTER")
    empty:SetPoint("TOP", 0, -70)
    empty:SetWidth(WIDTH - PAD * 2)
    self.empty = empty

    local all = Widgets.CreateButton(frame, L["All upgrades"], function()
        frame:Hide()
        if ns.FinderUI then ns.FinderUI:Show() end
    end, { width = 110, height = 22, primary = true })
    all:SetPoint("BOTTOMRIGHT", -PAD, 10)

    self.frame = frame
    self.rows = {}
    for index = 1, SHOWN do self.rows[index] = self:BuildRow(index) end
    frame:Hide()
    return frame
end

function SlotUpgrades:Fill()
    if not (self.frame and self.slot) then return end
    local heading = L.Format("Upgrades: %s", SLOT_NAMES[self.slot] or L["this slot"])
    local plate = self.trim and rawget(self.trim, "plate")
    if plate then plate:SetTitle(heading) elseif self.title then self.title:SetText(heading) end
    local picks = self:PicksFor(self.slot)
    for index, row in ipairs(self.rows) do
        local pick = picks[index]
        row.pick = pick
        if pick then
            Theme.SetItemIcon(row.icon, pick.link)
            row.item:SetText(ns.Items.ShowLink(pick.link))
            local gainText = SlotUpgrades.Gain(pick)
            row.gain:SetText(gainText)
            local gainWidth = math.max(54, math.ceil(Theme.TextWidth("normal", gainText or "")) + 4)
            row.gain:SetWidth(gainWidth)
            row.item:SetWidth(row.textWidth - gainWidth - 6)
            row.gain:SetTextColor(Theme.Unpack(SlotUpgrades.GainKey(pick)))
            local source = pick.sources and pick.sources[1]
            local text = source and ns.FinderUI and ns.FinderUI.SourceLine(source) or ""
            row.source:SetText(ns.FinderUI and ns.FinderUI.Fit("tiny", text, row.sourceWidth * 2 - 60) or text)
            local tracked = ns.Tracking and ns.Tracking:IsTracked(pick.itemID)
            row.track:SetText(tracked and L["Untrack"] or L["Track"])
            row.track:SetLabelColor(tracked and "accent" or "text")
            row.map:SetShown(source ~= nil and source.x ~= nil)
            row:Show()
        else
            row:Hide()
        end
    end
    self.empty:SetShown(#picks == 0)
    self.empty:SetText(L["Nothing on offer beats what you wear here."])
end

function SlotUpgrades:Open(slot, anchor)
    self:Build()
    self.slot = slot
    self.frame:ClearAllPoints()
    if anchor then
        self.frame:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 8, 0)
    else
        self.frame:SetPoint("CENTER", UIParent, "CENTER")
    end
    self:Fill()
    self.frame:Show()
    Motion:Open(self.frame)
end

function SlotUpgrades:OnTrackingChanged()
    if self.frame and self.frame:IsShown() then self:Fill() end
end

--------------------------------------------------------------------------------
-- Hooks
--------------------------------------------------------------------------------

local function SlotOf(button)
    local ok, id = pcall(button.GetID, button)
    return ok and tonumber(id) or nil
end

local function AltDown()
    local ok, down = pcall(function() return IsAltKeyDown() == true end)
    return ok and down
end

function SlotUpgrades:Hook()
    self.hooked = self.hooked or {}
    for _, name in ipairs(SLOT_BUTTONS) do
        local button = _G[name]
        if type(button) == "table" and not self.hooked[button] and type(button.HookScript) == "function" then
            self.hooked[button] = true
            button:HookScript("OnEnter", function(slotButton)
                local slot = SlotOf(slotButton)
                if slot and GameTooltip and GameTooltip:IsShown() then
                    pcall(SlotUpgrades.OnSlotEnter, SlotUpgrades, GameTooltip, slotButton, slot)
                end
            end)
            button:HookScript("OnClick", function(slotButton)
                if not (SlotUpgrades:IsEnabled() and AltDown()) then return end
                local slot = SlotOf(slotButton)
                if slot then pcall(SlotUpgrades.Open, SlotUpgrades, slot, slotButton) end
            end)
        end
    end
end

function SlotUpgrades:OnEnable()
    self:Hook()
    local tooltip = _G.GameTooltip
    if type(tooltip) == "table" and type(tooltip.HookScript) == "function" then
        pcall(tooltip.HookScript, tooltip, "OnUpdate", function(shown) SlotUpgrades:Keep(shown) end)
    end
    -- The character sheet may be made later on some clients.
    local frame = _G.CharacterFrame
    if type(frame) == "table" and type(frame.HookScript) == "function" then
        frame:HookScript("OnShow", function() SlotUpgrades:Hook() end)
    end
end
