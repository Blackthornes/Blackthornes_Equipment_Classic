-- Blackthornes Equipment -- UI/DungeonLootWindow.lua
-- Dungeon Loot (the owner said build it, 2026-10-22, from a mockup whose
-- words he approved): the dungeons down the left, and the one picked shows
-- what its bosses drop: the item, its slot, the boss and, for an upgrade
-- for the character playing, how much better it is. Armor and Stat chips
-- and Upgrades Only narrow the list; the headings sort it. Follow points
-- the quest arrow at the door, Show the Way puts the game's map pin there.
-- Opened with /beq loot, the gear window's Dungeon Loot tab or
-- Settings.
--
-- The list is DungeonLoot:Rows(), laid out again only when the window
-- opens, a dungeon or a chip is picked, gear changes, or a burst of items
-- the window asked for comes in. Rows are filled again only on a redraw.

local _, ns = ...
local L = ns.L

local DLUI = ns.NewModule("DungeonLootUI")

local Theme = ns.Theme
local Widgets = ns.Widgets
local Motion = ns.Motion

local NAME = "BlackthornesEquipmentDungeonLoot"
-- The size every tab of the gear window shares (UI/FinderWindow.lua), so
-- the window never jumps as the tabs are clicked.
local WIDTH = ns.FinderUI and ns.FinderUI.WIDTH or 840
local HEIGHT = ns.FinderUI and ns.FinderUI.HEIGHT or 560
local PADDING = 18
local TOP = 44
local LEFT_WIDTH = 220
local DUNGEON_ROW = 40
local LIST_ROW = 38
local HEAD = 50
local CHIP_ROW = 28
local COLUMN_HEAD = 20
local FOOT = 42
-- As many rows as the wells hold at that size.
local DUNGEON_ROWS = math.floor((HEIGHT - TOP - PADDING - COLUMN_HEAD - 2) / DUNGEON_ROW)
local LIST_ROWS = math.floor((HEIGHT - TOP - PADDING - (HEAD + 8 + CHIP_ROW * 2 + COLUMN_HEAD) - FOOT) / LIST_ROW)
local ICON = 26
local SLOT_WIDTH, BOSS_WIDTH, GAIN_WIDTH = 130, 150, 84

DLUI.DUNGEON_ROWS, DLUI.LIST_ROWS = DUNGEON_ROWS, LIST_ROWS

-- The chips: { key, label }.
local ARMORS = {
    { "all", L["All"] }, { "cloth", L["Cloth"] }, { "leather", L["Leather"] }, { "mail", L["Mail"] },
}
local STATS = {
    { "all", L["All"] }, { "strength", L["Strength"] }, { "agility", L["Agility"] },
    { "stamina", L["Stamina"] }, { "intellect", L["Intellect"] }, { "spirit", L["Spirit"] },
}
DLUI.ARMORS, DLUI.STATS = ARMORS, STATS

-- The headings over the rows, which sort the list.
local COLUMNS = {
    { key = "item", label = L["ITEM"] },
    { key = "slot", label = L["SLOT"] },
    { key = "boss", label = L["BOSS"] },
    { key = "gain", label = L["GAIN"], justify = "RIGHT" },
}
DLUI.COLUMNS = COLUMNS

local function Paint(texture, key, alpha)
    texture:SetColorTexture(Theme.Unpack(key, alpha))
end

--- The house list row: dark glass by place, a fine line under it, the gold
--- light under the mouse, and the picked one lit with a gold left edge.
local function GlassRow(parent, index, height)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(height)
    row.index = index
    row.background = Theme.Fill(row, index % 2 == 0 and "glassAlt" or "glass")
    row.rule = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    row.rule:SetPoint("BOTTOMLEFT")
    row.rule:SetPoint("BOTTOMRIGHT")
    row.rule:SetHeight(1)
    row.rule:SetColorTexture(Theme.Unpack("border", 0.6))
    row.edge = row:CreateTexture(nil, "ARTWORK")
    row.edge:SetPoint("TOPLEFT")
    row.edge:SetPoint("BOTTOMLEFT")
    row.edge:SetWidth(3)
    Paint(row.edge, "accentHi")
    row.edge:Hide()
    Widgets.RowLight(row)
    row:SetScript("OnEnter", function(self)
        Motion:Blend(self, "hover", 1, 0.12, function(p) Widgets.SetRowLight(self, p) end)
        if self.onHover then self.onHover(self) end
    end)
    row:SetScript("OnLeave", function(self)
        Motion:Blend(self, "hover", 0, 0.18, function(p) Widgets.SetRowLight(self, p) end)
        GameTooltip:Hide()
    end)
    return row
end

local function SetPicked(row, picked)
    if row.background and row.background.SetColorTexture then
        row.background:SetColorTexture(Theme.Unpack(picked and "glassActive"
            or (row.index % 2 == 0 and "glassAlt" or "glass")))
    end
    row.edge:SetShown(picked == true)
end

--- A chip: gold with dark lettering while picked, dark metal with a gold
--- label otherwise.
local function Chip(parent, text, onClick)
    local chip = CreateFrame("Button", nil, parent)
    chip:SetHeight(22)
    chip.background = Theme.Fill(chip, "row")
    Theme.Border(chip, "metal")
    chip.label = Theme.CreateLabel(chip, "small", "accent", "CENTER")
    chip.label:SetPoint("CENTER")
    chip.label:SetText(text)
    chip:SetWidth(Theme.TextWidth("small", text) + 22)
    chip:SetScript("OnClick", onClick)
    chip:SetScript("OnEnter", function(self)
        if not self.on then self.label:SetTextColor(Theme.Unpack("accentHi")) end
    end)
    chip:SetScript("OnLeave", function(self) DLUI.PaintChip(self, self.on) end)
    return chip
end

function DLUI.PaintChip(chip, on)
    chip.on = on == true
    chip.background:SetColorTexture(Theme.Unpack(on and "accent" or "row"))
    Theme.SetBorderColor(chip, on and "accentHi" or "metal")
    chip.label:SetTextColor(Theme.Unpack(on and "ink" or "accent"))
end

local function Levels(dungeon)
    if not dungeon.low then return "" end
    return L.Format("Levels %d to %d", dungeon.low, dungeon.high or dungeon.low)
end

--- The line under the dungeon's name: where its door is and its levels.
function DLUI.Where(dungeon)
    local zone = dungeon.door
    if not dungeon.low then return zone and L.Format("Door in %s.", zone) or "" end
    if not zone then return Levels(dungeon) .. "." end
    if ns.DungeonQuests.CITIES[zone] then
        return L.Format("%s. Levels %d to %d.", zone, dungeon.low, dungeon.high or dungeon.low)
    end
    return L.Format("Door in %s. Levels %d to %d.", zone, dungeon.low, dungeon.high or dungeon.low)
end

--- The foot's line: how many show and how many are upgrades.
function DLUI.FootText(shown, upgrades)
    if upgrades == 1 then return L.Format("%d shown. 1 is an upgrade for you.", shown) end
    return L.Format("%d shown. %d are upgrades for you.", shown, upgrades)
end

--------------------------------------------------------------------------------
-- Building it
--------------------------------------------------------------------------------

function DLUI:Build()
    if self.frame then return self.frame end
    local frame = CreateFrame("Frame", NAME, UIParent)
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    Theme.Fill(frame, "window")
    if ns.Titanforged then
        local trim = ns.Titanforged:Dress(frame, {
            title = L["Dungeon Loot"],
            portrait = true,
            close = function() DLUI:Hide() end,
        })
        local left, right, top, bottom = ns.Titanforged.Reach(trim)
        if frame.SetClampRectInsets then frame:SetClampRectInsets(-left, right, top, -bottom) end
    else
        Theme.Border(frame, "borderLit")
    end
    Theme.Halo(frame, 12, 0.14)
    -- The fold gem beside the close gem folds the window down to its plate
    -- (UI/FoldWindow.lua, a player asked, 2026-10-24).
    if ns.FoldWindow then
        ns.FoldWindow:Add(frame, { onToggle = function(folded)
            if not folded then DLUI:Refresh() end
        end })
    end
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        DLUI:SavePosition()
    end)

    -- The house size grip under the bottom right corner, saved as the one
    -- scale every tab shares (`dungeonLootScale`, from before the tabs,
    -- stays in the save unread).
    self.sizeGrip = Widgets.WindowGrip(frame, ns.FinderUI and ns.FinderUI.SCALE_KEY or "finderScale", function()
        DLUI:SavePosition()
        if ns.FinderUI then ns.FinderUI:ScaleChanged() end
    end)
    if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, NAME) end
    self.frame = frame
    self.dungeonOffset, self.offset = 0, 0
    self.armor, self.stat, self.upgradesOnly = "all", "all", false

    self:BuildDungeons()
    self:BuildList()
    -- The gear window's tabs hang under it too, Dungeon Loot lit, so the
    -- two read as one window.
    self.tabStrip = ns.FinderUI and ns.FinderUI:HangTabs(frame, "loot")
    frame:Hide()
    return frame
end

local function Well(parent)
    local well = Theme.CreatePanel(parent, "panel", "border")
    Theme.Recess(well)
    return well
end

local function Heading(parent, text)
    local label = Theme.CreateLabel(parent, "tiny", "muted")
    label:SetText(text)
    return label
end

function DLUI:BuildDungeons()
    local well = Well(self.frame)
    well:SetPoint("TOPLEFT", PADDING, -TOP)
    well:SetPoint("BOTTOMLEFT", PADDING, PADDING)
    well:SetWidth(LEFT_WIDTH)
    well:EnableMouseWheel(true)
    well:SetScript("OnMouseWheel", function(_, delta) DLUI:ScrollDungeons(-delta) end)
    local title = Heading(well, L["DUNGEONS"])
    title:SetPoint("TOPLEFT", 12, -8)
    self.dungeonWell = well

    self.dungeonRows = {}
    for index = 1, DUNGEON_ROWS do
        local row = GlassRow(well, index, DUNGEON_ROW)
        row:SetPoint("TOPLEFT", 1, -(COLUMN_HEAD + 2 + (index - 1) * DUNGEON_ROW))
        row:SetPoint("TOPRIGHT", -1, -(COLUMN_HEAD + 2 + (index - 1) * DUNGEON_ROW))
        row.name = Theme.CreateLabel(row, "normal", "text")
        row.name:SetPoint("TOPLEFT", 12, -5)
        row.name:SetPoint("RIGHT", -10, 0)
        row.levels = Theme.CreateLabel(row, "tiny", "muted")
        row.levels:SetPoint("BOTTOMLEFT", 12, 6)
        row:SetScript("OnClick", function(self)
            if self.dungeon then DLUI:Pick(self.dungeon.key) end
        end)
        row:Hide()
        self.dungeonRows[index] = row
    end
end

function DLUI:BuildList()
    local frame = self.frame
    local well = Well(frame)
    well:SetPoint("TOPLEFT", PADDING + LEFT_WIDTH + 12, -TOP)
    well:SetPoint("BOTTOMRIGHT", -PADDING, PADDING)
    well:EnableMouseWheel(true)
    well:SetScript("OnMouseWheel", function(_, delta) DLUI:Scroll(-delta) end)
    self.well = well

    local name = Theme.CreateLabel(well, "large", "accentHi")
    name:SetPoint("TOPLEFT", 14, -10)
    self.dungeonName = name
    local where = Theme.CreateLabel(well, "small", "muted")
    where:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -4)
    where:SetPoint("RIGHT", -14, 0)
    self.dungeonWhere = where
    local rule = well:CreateTexture(nil, "ARTWORK")
    rule:SetPoint("TOPLEFT", 1, -HEAD)
    rule:SetPoint("TOPRIGHT", -1, -HEAD)
    rule:SetHeight(1)
    Paint(rule, "border", 0.8)

    -- The chips: Armor and Upgrades Only on one line, Stat on the next.
    local function ChipLine(y, label, list, field)
        local title = Theme.CreateLabel(well, "small", "muted")
        title:SetPoint("TOPLEFT", 14, -(y + 5))
        title:SetText(label)
        local chips, x = {}, 14 + math.max(56, Theme.TextWidth("small", label) + 8)
        for _, entry in ipairs(list) do
            local key = entry[1]
            local chip = Chip(well, entry[2], function() DLUI:SetChip(field, key) end)
            chip:SetPoint("TOPLEFT", x, -y)
            chip.key = key
            x = x + chip:GetWidth() + 6
            chips[#chips + 1] = chip
        end
        return chips
    end
    self.armorChips = ChipLine(HEAD + 6, L["Armor:"], ARMORS, "armor")
    self.statChips = ChipLine(HEAD + 6 + CHIP_ROW, L["Stat:"], STATS, "stat")
    local upgrades = Widgets.CreateCheckbox(well, L["Upgrades Only"], function(checked)
        DLUI.upgradesOnly = checked == true
        DLUI.offset = 0
        DLUI:Refresh()
    end, false)
    -- On the Armor line, which has room to spare in every language.
    upgrades:SetPoint("TOPRIGHT", -14, -(HEAD + 6 + 2))
    self.upgradesBox = upgrades

    local columnsTop = HEAD + 8 + CHIP_ROW * 2
    self:BuildColumnHeads(columnsTop)
    local first = columnsTop + COLUMN_HEAD

    self.rows = {}
    for index = 1, LIST_ROWS do
        local row = GlassRow(well, index, LIST_ROW)
        row:SetPoint("TOPLEFT", 1, -(first + (index - 1) * LIST_ROW))
        row:SetPoint("TOPRIGHT", -1, -(first + (index - 1) * LIST_ROW))
        row.icon = Theme.CreateItemIcon(row, ICON)
        row.icon:SetPoint("LEFT", 12, 0)
        row.gain = Theme.CreateLabel(row, "normal", "upgrade", "RIGHT")
        row.gain:SetPoint("RIGHT", -13, 0)
        row.gain:SetWidth(GAIN_WIDTH)
        row.gain:SetWordWrap(true)
        row.boss = Theme.CreateLabel(row, "small", "muted")
        row.boss:SetPoint("RIGHT", row.gain, "LEFT", -6, 0)
        row.boss:SetWidth(BOSS_WIDTH)
        row.boss:SetWordWrap(true)
        row.slot = Theme.CreateLabel(row, "small", "text")
        row.slot:SetPoint("RIGHT", row.boss, "LEFT", -6, 0)
        row.slot:SetWidth(SLOT_WIDTH)
        row.slot:SetWordWrap(true)
        row.name = Theme.CreateLabel(row, "normal", "text")
        row.name:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
        row.name:SetPoint("RIGHT", row.slot, "LEFT", -6, 0)
        row.name:SetWordWrap(true)
        row.onHover = function(self)
            if not self.line then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            pcall(GameTooltip.SetHyperlink, GameTooltip, self.line.link)
            GameTooltip:Show()
        end
        row:Hide()
        self.rows[index] = row
    end

    -- The foot: how many show, and the two buttons for the door.
    local follow = Widgets.CreateButton(well, L["Follow"], function()
        local dungeon = DLUI:Picked()
        if dungeon then ns.DungeonLoot:Follow(dungeon) end
    end, { width = 80, height = 24, primary = true })
    follow:SetPoint("BOTTOMRIGHT", -12, 10)
    self.followButton = follow
    local way = Widgets.CreateButton(well, L["Show the Way"], function()
        local dungeon = DLUI:Picked()
        if dungeon then ns.DungeonLoot:ShowTheWay(dungeon) end
    end, { width = 110, height = 24 })
    way:SetPoint("RIGHT", follow, "LEFT", -8, 0)
    self.wayButton = way
    local foot = Theme.CreateLabel(well, "small", "muted")
    foot:SetPoint("BOTTOMLEFT", 14, 16)
    foot:SetPoint("RIGHT", way, "LEFT", -10, 0)
    foot:SetWordWrap(true)
    self.foot = foot
    local footRule = well:CreateTexture(nil, "ARTWORK")
    footRule:SetPoint("BOTTOMLEFT", 1, FOOT)
    footRule:SetPoint("BOTTOMRIGHT", -1, FOOT)
    footRule:SetHeight(1)
    Paint(footRule, "border", 0.8)

    local empty = Theme.CreateLabel(well, "normal", "muted", "CENTER")
    empty:SetPoint("TOPLEFT", 14, -(first + 24))
    empty:SetPoint("RIGHT", -14, 0)
    empty:SetWordWrap(true)
    self.empty = empty
end

--- A small gold triangle, pointing down until flipped.
local function SortArrow(parent)
    local arrow = parent:CreateTexture(nil, "OVERLAY")
    arrow:SetTexture(ns.Titanforged.MEDIA .. "SortArrow")
    arrow:SetSize(10, 10)
    arrow:SetVertexColor(Theme.Unpack("accent"))
    arrow:Hide()
    return arrow
end

function DLUI:BuildColumnHeads(top)
    local well = self.well
    local places = {
        item = { "TOPLEFT", 12 + ICON + 8, 140 },
        slot = { "TOPRIGHT", -(13 + GAIN_WIDTH + 6 + BOSS_WIDTH + 6 + SLOT_WIDTH), SLOT_WIDTH },
        boss = { "TOPRIGHT", -(13 + GAIN_WIDTH + 6 + BOSS_WIDTH), BOSS_WIDTH },
        gain = { "TOPRIGHT", -13 - GAIN_WIDTH, GAIN_WIDTH },
    }
    self.columnHeads = {}
    for _, column in ipairs(COLUMNS) do
        local place = places[column.key]
        local heading = CreateFrame("Button", nil, well)
        heading:SetSize(place[3], COLUMN_HEAD)
        if place[1] == "TOPLEFT" then
            heading:SetPoint("TOPLEFT", place[2], -top)
        else
            heading:SetPoint("TOPLEFT", well, "TOPRIGHT", place[2], -top)
        end
        heading.key = column.key
        local label = Theme.CreateLabel(heading, "tiny", "muted", column.justify)
        label:SetText(column.label)
        local arrow = SortArrow(heading)
        if column.justify == "RIGHT" then
            label:SetPoint("RIGHT", 0, 0)
            arrow:SetPoint("RIGHT", label, "LEFT", -3, 0)
        else
            label:SetPoint("LEFT", 0, 0)
            arrow:SetPoint("LEFT", label, "RIGHT", 3, 0)
        end
        heading.label, heading.arrow = label, arrow
        heading:SetScript("OnClick", function(self) DLUI:SortBy(self.key) end)
        heading:SetScript("OnEnter", function(self) self.label:SetTextColor(Theme.Unpack("accentHi")) end)
        heading:SetScript("OnLeave", function() DLUI:PaintHeadings() end)
        self.columnHeads[#self.columnHeads + 1] = heading
    end
    self:PaintHeadings()
end

--- A click on a heading: the first sorts by it, the second flips the
--- order, the third goes back to best first. Kept while the game runs.
function DLUI:SortBy(key)
    if self.sortKey ~= key then
        self.sortKey, self.sortFlip = key, false
    elseif not self.sortFlip then
        self.sortFlip = true
    else
        self.sortKey, self.sortFlip = nil, false
    end
    self.offset = 0
    self:PaintHeadings()
    self:FillList()
end

function DLUI:PaintHeadings()
    for _, heading in ipairs(self.columnHeads or {}) do
        local on = heading.key == self.sortKey
        heading.label:SetTextColor(Theme.Unpack(on and "accent" or "muted"))
        heading.arrow:SetShown(on)
        if self.sortFlip then heading.arrow:SetTexCoord(0, 1, 1, 0) else heading.arrow:SetTexCoord(0, 1, 0, 1) end
    end
end

--------------------------------------------------------------------------------
-- Filling it in
--------------------------------------------------------------------------------

function DLUI:Showing()
    return self.frame ~= nil and self.frame:IsShown()
end

function DLUI:Picked()
    local key = ns.db and ns.db.dungeonLootPick
    for _, dungeon in ipairs(self.dungeons or {}) do
        if dungeon.key == key then return dungeon end
    end
    return nil
end

--- The dungeons and the picked one's rows, laid out again.
function DLUI:Refresh()
    if not self:Showing() then return end
    local player = ns.Finder and ns.Finder:Player()
    local ok, dungeons = pcall(ns.DungeonLoot.Dungeons, ns.DungeonLoot, player)
    self.dungeons = ok and dungeons or {}
    local picked = self:Picked()
    if not picked and self.dungeons[1] then
        -- The first one at or past the character's level, else the first.
        local level = player and player.level or 0
        for _, dungeon in ipairs(self.dungeons) do
            if (dungeon.high or 0) >= level and not dungeon.raid then picked = dungeon break end
        end
        picked = picked or self.dungeons[1]
        if ns.db then ns.db.dungeonLootPick = picked.key end
    end
    local built
    if picked then
        local okRows, data = pcall(ns.DungeonLoot.Rows, ns.DungeonLoot, picked.key,
            self.armor, self.stat, self.upgradesOnly)
        built = okRows and data or nil
    end
    self.data = built or { rows = {}, waiting = 0, upgrades = 0 }
    for _, chip in ipairs(self.armorChips) do DLUI.PaintChip(chip, chip.key == self.armor) end
    for _, chip in ipairs(self.statChips) do DLUI.PaintChip(chip, chip.key == self.stat) end
    if self.upgradesBox.SetChecked then self.upgradesBox:SetChecked(self.upgradesOnly) end
    self:FillDungeons()
    self:FillList()
end

function DLUI:Pick(key)
    if ns.db then ns.db.dungeonLootPick = key end
    self.offset = 0
    self:Refresh()
end

function DLUI:SetChip(field, key)
    self[field] = key
    self.offset = 0
    self:Refresh()
end

function DLUI:ScrollDungeons(rows)
    local total = self.dungeons and #self.dungeons or 0
    self.dungeonOffset = math.min(math.max(0, total - DUNGEON_ROWS), math.max(0, self.dungeonOffset + rows))
    self:FillDungeons()
end

function DLUI:Scroll(rows)
    local total = self.data and #self.data.rows or 0
    self.offset = math.min(math.max(0, total - LIST_ROWS), math.max(0, self.offset + rows))
    self:FillList()
end

function DLUI:FillDungeons()
    local picked = self:Picked()
    for index, row in ipairs(self.dungeonRows) do
        local dungeon = self.dungeons[self.dungeonOffset + index]
        row.dungeon = dungeon
        if dungeon then
            local on = picked ~= nil and dungeon.key == picked.key
            row.name:SetText(dungeon.name)
            row.name:SetTextColor(Theme.Unpack(on and "accentHi" or "text"))
            row.levels:SetText(Levels(dungeon))
            SetPicked(row, on)
            row:Show()
        else
            row:Hide()
        end
    end
end

function DLUI:FillList()
    local dungeon = self:Picked()
    self.dungeonName:SetText(dungeon and dungeon.name or "")
    self.dungeonWhere:SetText(dungeon and DLUI.Where(dungeon) or "")
    local rows = ns.DungeonLoot.SortRows(self.data.rows, self.sortKey, self.sortFlip)
    for index, row in ipairs(self.rows) do
        local line = rows[self.offset + index]
        row.line = line
        if line then
            Theme.SetItemIcon(row.icon, line.link)
            local name = line.name ~= "" and line.name or ns.DungeonLoot.NameOf(line.itemID)
            local r, g, b = Theme.QualityColor(line.link)
            if r then row.name:SetTextColor(r, g, b) else row.name:SetTextColor(Theme.Unpack("text")) end
            row.name:SetText(name)
            row.slot:SetText(line.slot)
            row.boss:SetText(line.boss)
            if line.gain then
                row.gain:SetText(("%+d%%"):format(line.gain))
            elseif line.upgrade then
                row.gain:SetText(L["empty slot"])
            else
                row.gain:SetText("")
            end
            SetPicked(row, false)
            row:Show()
        else
            row:Hide()
        end
    end
    local shown = #self.data.rows
    self.empty:SetText(shown == 0 and dungeon and self.data.waiting == 0
        and L["Nothing here matches. Try fewer picks."] or "")
    self.foot:SetText(DLUI.FootText(shown, self.data.upgrades))
    local door = dungeon and ns.DungeonLoot.Door(dungeon)
    for _, button in ipairs({ self.followButton, self.wayButton }) do
        button:SetAlpha(door and 1 or 0.45)
        if button.SetEnabled then button:SetEnabled(door ~= nil) end
    end
end

--------------------------------------------------------------------------------
-- Showing it
--------------------------------------------------------------------------------

function DLUI:SavePosition()
    if not (ns.db and self.frame) then return end
    local point, _, relativePoint, x, y = self.frame:GetPoint()
    ns.db.dungeonLootPoint, ns.db.dungeonLootRelPoint = point, relativePoint
    ns.db.dungeonLootX, ns.db.dungeonLootY = x, y
end

function DLUI:RestorePosition()
    local db = ns.db or {}
    self.frame:ClearAllPoints()
    self.frame:SetPoint(db.dungeonLootPoint or "CENTER", UIParent,
        db.dungeonLootRelPoint or "CENTER", db.dungeonLootX or 0, db.dungeonLootY or 0)
end

function DLUI:Show()
    self:Build()
    if not self.frame:IsShown() then
        if ns.FinderUI then ns.FinderUI:FitTab(self.frame) end
        self:RestorePosition()
        self.frame:Show()
        if Motion and Motion.Open then Motion:Open(self.frame) end
    end
    if ns.FoldWindow then ns.FoldWindow:Unfold(self.frame) end
    self:Refresh()
end

function DLUI:Hide()
    if self.frame then self.frame:Hide() end
end

--- Opened as a tab of the gear window, in its place (FinderUI:ShowTab).
function DLUI:Toggle()
    if self:Showing() then
        self:Hide()
    elseif ns.FinderUI and ns.FinderUI.ShowTab then
        ns.FinderUI:ShowTab("loot")
    else
        self:Show()
    end
end

--- Lay the list out again a moment after a burst (items arriving, gear).
function DLUI:RefreshSoon()
    if not self:Showing() or self.pending then return end
    self.pending = true
    local after = _G.C_Timer and _G.C_Timer.After
    if type(after) ~= "function" then
        self.pending = false
        self:Refresh()
        return
    end
    after(0.3, function()
        DLUI.pending = false
        if DLUI:Showing() then DLUI:Refresh() end
    end)
end

function DLUI:OnEnable()
    for _, event in ipairs({ "GET_ITEM_INFO_RECEIVED", "PLAYER_EQUIPMENT_CHANGED", "PLAYER_LEVEL_UP" }) do
        ns.RegisterEvent(self, event, function() DLUI:RefreshSoon() end)
    end
end
