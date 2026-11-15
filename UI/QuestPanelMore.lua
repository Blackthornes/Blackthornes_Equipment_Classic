local _, ns = ...
local L = ns.L

-- The upgrade quest panel's extras (the owner said build it, 2026-11-13,
-- from the upgrade quest mockups): your gear's rating (card I), why the
-- quest was picked (A), the next best picks (E), what the quest asks of you
-- (C), the Options count (B) and the Ignored and Done foot (G). Each piece
-- reads only what UpgradeQuest already kept for the last scan, so a redraw
-- works nothing out. UI/QuestPanel.lua builds the panel and calls these.
local More = ns.NewModule("QuestPanelMore")

local Theme = ns.Theme
local Widgets = ns.Widgets
local Motion = ns.Motion

local WIDTH = 384
local PAD = 10
local INNER = WIDTH - PAD * 2
local ROUND = [[Interface\CharacterFrame\TempPortraitAlphaMask]]
local CHECK = [[Interface\RaidFrame\ReadyCheck-Ready]]

More.GEAR_HEIGHT = 13 + 4 + 5 + 3 + 12 + 8
More.CHIP_HEIGHT = 18
More.CHIP_GAP = 4
More.ALSO_ROW = 24
More.FOOT_HEIGHT = 12

local function Colored(key, text)
    local r, g, b = Theme.Unpack(key)
    return ("|cff%02x%02x%02x%s|r"):format(math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5),
        math.floor(b * 255 + 0.5), text)
end

local function Full() return Motion.Level() == "full" end

local function Width(size, text)
    local ok, width = pcall(Theme.TextWidth, size, text or "")
    return ok and type(width) == "number" and width or 0
end

local function Lines(size, text, width)
    local panel = ns.QuestPanel
    if panel and panel.Lines then return panel.Lines(size, text, width) end
    return 1
end

local function Round(parent, size, key, layer)
    local texture = parent:CreateTexture(nil, layer or "ARTWORK")
    texture:SetSize(size, size)
    texture:SetTexture(ROUND)
    texture:SetVertexColor(Theme.Unpack(key))
    return texture
end

--------------------------------------------------------------------------------
-- Card I: Your Gear
--------------------------------------------------------------------------------

-- Where each rating starts and ends, for how far the fill reaches.
local RATING_LOW = { 0.6, 0.85, 0.93, 0.98 }
local RATING_HIGH = { 0.85, 0.93, 0.98, 1 }

--- How far along the bar a score sits, 0 to 1 (a quarter a rating).
function More.GearShare(rating)
    if type(rating) ~= "table" or not rating.index then return 0 end
    local index = rating.index
    local value = (tonumber(rating.score) or 0) / 100
    local low, high = RATING_LOW[index] or 0, RATING_HIGH[index] or 1
    local within = math.max(0, math.min(1, (value - low) / math.max(high - low, 0.001)))
    return math.max(0, math.min(1, ((index - 1) + within) / 4))
end

function More.WaitingText(count)
    count = tonumber(count) or 0
    if count <= 0 then return "" end
    if count == 1 then return L["1 upgrade waiting"] end
    return L.Format("%d upgrades waiting", count)
end

function More.GearText(rating, level)
    return L.Format("Your Gear: %s for level %d", Colored("gilt", rating.rating.label), level or 0)
end

function More:BuildGear(panel)
    local box = CreateFrame("Frame", nil, panel.body)
    box:SetSize(INNER, More.GEAR_HEIGHT - 8)
    local title = Theme.CreateLabel(box, "small", "text")
    title:SetPoint("TOPLEFT", 0, 0)
    box.title = title
    local waiting = Theme.CreateLabel(box, "tiny", "accent", "RIGHT")
    waiting:SetPoint("TOPRIGHT", 0, -1)
    box.waiting = waiting
    local track = box:CreateTexture(nil, "ARTWORK")
    track:SetPoint("TOPLEFT", 0, -17)
    track:SetSize(INNER, 5)
    track:SetColorTexture(Theme.Unpack("row"))
    box.track = track
    local fill = box:CreateTexture(nil, "OVERLAY")
    fill:SetPoint("TOPLEFT", track, "TOPLEFT")
    fill:SetSize(1, 5)
    fill:SetColorTexture(Theme.Unpack("gilt"))
    pcall(Theme.SetGradientAlpha, fill, "HORIZONTAL", "gilt", 0.55, 1)
    box.fill = fill
    box.labels = {}
    local quarter = INNER / 4
    for index, rating in ipairs(ns.UpgradeQuest.RATINGS) do
        local label = Theme.CreateLabel(box, "tiny", "dim", "CENTER")
        label:SetWidth(quarter)
        if label.SetWordWrap then label:SetWordWrap(true) end
        label:SetPoint("TOPLEFT", (index - 1) * quarter, -25)
        label:SetText(rating.label)
        box.labels[index] = label
    end
    local float = Theme.CreateLabel(box, "tiny", "good")
    float:Hide()
    box.float = float
    box:Hide()
    panel.gearBox = box
    return box
end

--- Fill the gear bar at the top of the body; returns the room it takes.
function More:FillGear(panel, top)
    local box = panel.gearBox or self:BuildGear(panel)
    local rating = ns.UpgradeQuest:GearRating()
    if not rating then
        box:Hide()
        return 0
    end
    local level = rating.level or (UnitLevel and UnitLevel("player")) or 0
    box:ClearAllPoints()
    box:SetPoint("TOPLEFT", PAD, -top)
    box.title:SetText(More.GearText(rating, level))
    box.waiting:SetText(More.WaitingText(rating.waiting))
    local share = More.GearShare(rating)
    box.fill:SetWidth(math.max(1, INNER * share))
    for index, label in ipairs(box.labels) do
        label:SetTextColor(Theme.Unpack(index == rating.index and "gilt" or "dim"))
    end
    -- "+4" floats off the fill when the score rises this session.
    local before = self.lastScore
    self.lastScore = rating.score
    if before and rating.score > before and Full() then
        local float = box.float
        float:SetText(L.Format("+%d", rating.score - before))
        float:ClearAllPoints()
        float:SetPoint("BOTTOM", box.fill, "TOPRIGHT", 0, 2)
        float:Show()
        Motion:Run(float, "rise", 1.2, function(p)
            float:SetPoint("BOTTOM", box.fill, "TOPRIGHT", 0, 2 + 14 * p)
            float:SetAlpha(1 - p)
        end, { done = function() float:Hide() end })
    end
    box:Show()
    return More.GEAR_HEIGHT
end

--------------------------------------------------------------------------------
-- Card A: why it was picked
--------------------------------------------------------------------------------

function More:BuildWhy(panel)
    local why = Theme.CreateLabel(panel.item, "tiny", "dim")
    why:SetPoint("TOPLEFT", panel.gain, "BOTTOMLEFT", 0, -2)
    why:SetWordWrap(true)
    panel.why = why
    -- One gold sweep across it when the words change.
    local sweep = panel.item:CreateTexture(nil, "OVERLAY")
    sweep:SetSize(40, 12)
    sweep:SetColorTexture(Theme.Unpack("gilt"))
    pcall(Theme.SetGradientAlpha, sweep, "HORIZONTAL", "gilt", 0, 0.5)
    sweep:Hide()
    panel.whySweep = sweep
    return why
end

--- Fill the why line; returns the room it adds under the gain.
function More:FillWhy(panel, quest, width)
    local why = panel.why or self:BuildWhy(panel)
    local text = ns.UpgradeQuest.WhyText(quest)
    if not text then
        why:Hide()
        panel.whySweep:Hide()
        self.lastWhy = nil
        return 0
    end
    why:SetWidth(width)
    why:SetText(text)
    why:Show()
    if self.lastWhy ~= text then
        self.lastWhy = text
        if Full() then
            local sweep = panel.whySweep
            Motion:Run(why, "fade", 0.4, function(p) why:SetAlpha(p) end)
            sweep:Show()
            Motion:Run(sweep, "sweep", 0.7, function(p)
                sweep:ClearAllPoints()
                sweep:SetPoint("TOPLEFT", why, "TOPLEFT", (width - 40) * p, 0)
                sweep:SetAlpha(1 - p)
            end, { done = function() sweep:Hide() end })
        else
            why:SetAlpha(1)
        end
    end
    return 2 + Lines("tiny", text, width) * 12
end

--------------------------------------------------------------------------------
-- Card E: also good
--------------------------------------------------------------------------------

--- Where an also-good pick comes from: "Quest in Ashenvale", "Vendor,
--- Ironforge" or the kind alone.
function More.SourceText(source)
    if type(source) ~= "table" then return "" end
    local finder = ns.Finder
    local label = finder and finder.Label(source) or ""
    local zone = ns.UpgradeQuest.SourceZone(source)
    zone = zone and finder and finder.ShownZone and finder.ShownZone(zone) or zone
    if not zone or zone == "" then return label end
    if source.kind == "quest" then return L.Format("Quest in %s", zone) end
    return L.Format("%s, %s", label, zone)
end

function More.PercentText(pick)
    local percent = pick and pick.result and tonumber(pick.result.percent)
    if not percent then return "" end
    return L.Format("+%d%%", math.floor(percent + 0.5))
end

local function BuildAlsoRow(panel, index)
    local row = CreateFrame("Button", nil, panel.body)
    row:SetSize(INNER, More.ALSO_ROW)
    row.bg = Theme.Fill(row, index % 2 == 1 and "glass" or "glassAlt")
    local line = row:CreateTexture(nil, "BORDER")
    line:SetPoint("BOTTOMLEFT")
    line:SetPoint("BOTTOMRIGHT")
    line:SetHeight(1)
    line:SetColorTexture(Theme.Unpack("border", 0.6))
    local edge = row:CreateTexture(nil, "ARTWORK")
    edge:SetPoint("TOPLEFT")
    edge:SetPoint("BOTTOMLEFT")
    edge:SetWidth(2)
    edge:SetColorTexture(Theme.Unpack("accentHi"))
    edge:Hide()
    row.edge = edge
    local medal = Round(row, 16, "gilt")
    medal:SetPoint("LEFT", 4, 0)
    local number = Theme.CreateLabel(row, "tiny", "ink", "CENTER")
    number:SetPoint("CENTER", medal, "CENTER", 0, 0)
    number:SetText(tostring(index + 1))
    local gain = Theme.CreateLabel(row, "small", "good", "RIGHT")
    gain:SetPoint("RIGHT", -6, 0)
    gain:SetWidth(56)
    row.gain = gain
    local source = Theme.CreateLabel(row, "tiny", "muted", "RIGHT")
    source:SetPoint("RIGHT", gain, "LEFT", -6, 0)
    source:SetWidth(120)
    source:SetWordWrap(true)
    row.source = source
    local name = Theme.CreateLabel(row, "small", "text")
    name:SetPoint("LEFT", medal, "RIGHT", 6, 0)
    name:SetWidth(INNER - 26 - 56 - 120 - 18)
    name:SetWordWrap(true)
    row.name = name
    row:SetScript("OnEnter", function(self)
        self.bg:SetColorTexture(Theme.Unpack("glassHover"))
        self.edge:Show()
        if not self.pick then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self.pick.link then pcall(GameTooltip.SetHyperlink, GameTooltip, self.pick.link) end
        GameTooltip:AddLine(L["Click to switch to this one."], Theme.Unpack("dim"))
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function(self)
        self.bg:SetColorTexture(Theme.Unpack(index % 2 == 1 and "glass" or "glassAlt"))
        self.edge:Hide()
        GameTooltip:Hide()
    end)
    row:SetScript("OnClick", function(self)
        local quest = ns.UpgradeQuest
        if self.pick and quest.CanFollow(self.pick) then quest:Follow(self.pick) end
    end)
    return row
end

function More:BuildAlso(panel)
    local toggle = CreateFrame("Button", nil, panel.body)
    toggle:SetSize(INNER, 14)
    local text = Theme.CreateLabel(toggle, "tiny", "accent")
    text:SetPoint("LEFT", 0, 0)
    toggle.text = text
    toggle:SetScript("OnClick", function()
        More.alsoOpen = not More.alsoOpen
        if ns.QuestPanel then ns.QuestPanel:Refresh() end
    end)
    toggle:SetScript("OnEnter", function(self) self.text:SetTextColor(Theme.Unpack("accentHi")) end)
    toggle:SetScript("OnLeave", function(self) self.text:SetTextColor(Theme.Unpack("accent")) end)
    toggle:Hide()
    panel.alsoToggle = toggle
    panel.alsoRows = { BuildAlsoRow(panel, 1), BuildAlsoRow(panel, 2) }
    for _, row in ipairs(panel.alsoRows) do row:Hide() end
    return toggle
end

--- The toggle and, while open (this session only), the next best picks;
--- returns the room they take.
function More:FillAlso(panel, quest, y)
    local toggle = panel.alsoToggle or self:BuildAlso(panel)
    local list = ns.UpgradeQuest:AlsoGood(quest)
    for _, row in ipairs(panel.alsoRows) do row:Hide() end
    if #list == 0 then
        toggle:Hide()
        return 0
    end
    toggle:ClearAllPoints()
    toggle:SetPoint("TOPLEFT", PAD, -y)
    toggle.text:SetText(L.Format("Also good: %d more", #list) .. (More.alsoOpen and "  -" or "  +"))
    toggle:Show()
    local used = 14 + 4
    if not More.alsoOpen then return used end
    for index, entry in ipairs(list) do
        local row = panel.alsoRows[index]
        row.pick = entry.pick
        local shown = ns.Items and ns.Items.ShowLink(entry.pick.link) or entry.pick.link or "?"
        row.name:SetText(shown)
        row.source:SetText(More.SourceText(entry.source))
        row.gain:SetText(More.PercentText(entry.pick))
        local tall = math.max(Lines("small", shown, INNER - 220) * 13,
            Lines("tiny", row.source:GetText() or "", 120) * 12)
        row:SetHeight(math.max(More.ALSO_ROW, tall + 8))
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", PAD, -(y + used))
        row:Show()
        used = used + row:GetHeight()
    end
    return used + 4
end

--------------------------------------------------------------------------------
-- Card C: what the quest asks of you
--------------------------------------------------------------------------------

local function BuildChip(panel)
    local chip = CreateFrame("Frame", nil, panel.body)
    chip:SetHeight(More.CHIP_HEIGHT)
    chip.bg = Theme.Fill(chip, "glass")
    chip.edges = Theme.Border(chip, "loss", 0.8)
    local mark = chip:CreateTexture(nil, "ARTWORK")
    mark:SetSize(12, 12)
    mark:SetPoint("LEFT", 4, 0)
    mark:SetTexture(CHECK)
    chip.mark = mark
    local bang = Theme.CreateLabel(chip, "tiny", "loss", "CENTER")
    bang:SetPoint("CENTER", mark, "CENTER", 0, 0)
    bang:SetText("!")
    chip.bang = bang
    local text = Theme.CreateLabel(chip, "tiny", "text")
    text:SetPoint("LEFT", mark, "RIGHT", 4, 0)
    -- Long words wrap onto a second line; they never end in "...".
    text:SetWordWrap(true)
    chip.text = text
    return chip
end

--- Lay the chips out, wrapping onto new lines; returns the room they take.
function More:FillChips(panel, quest, y)
    panel.chips = panel.chips or {}
    for _, chip in ipairs(panel.chips) do chip:Hide() end
    local list = ns.UpgradeQuest:Chips(quest)
    if #list == 0 then return 0 end
    self.chipMet = self.chipMet or {}
    local fresh = self.chipQuest ~= quest.itemID
    self.chipQuest = quest.itemID
    -- The chip's mark and padding take 28; the text gets the rest of a line.
    local most = INNER - 28
    local x, rowTop, rowTall = 0, 0, 0
    for index, entry in ipairs(list) do
        local chip = panel.chips[index]
        if not chip then
            chip = BuildChip(panel)
            panel.chips[index] = chip
        end
        chip.text:SetText(entry.text)
        -- A little more than measured: given its exact width, the game's
        -- font can still cut the last word short ("Part of a 4 quest ch...").
        local textWidth = math.min(most, Width("tiny", entry.text) + 6)
        local lines = math.max(1, Lines("tiny", entry.text, textWidth))
        local width = textWidth + 28
        local height = math.max(More.CHIP_HEIGHT, lines * 12 + 6)
        chip.text:SetWidth(textWidth)
        chip:SetWidth(width)
        chip:SetHeight(height)
        local key = entry.met and "good" or "loss"
        if Theme.SetBorderColor then pcall(Theme.SetBorderColor, chip.edges, key, 0.8) end
        chip.mark:SetShown(entry.met)
        chip.bang:SetShown(not entry.met)
        if x > 0 and x + width > INNER then
            x, rowTop, rowTall = 0, rowTop + rowTall + More.CHIP_GAP, 0
        end
        rowTall = math.max(rowTall, height)
        chip:ClearAllPoints()
        chip:SetPoint("TOPLEFT", PAD + x, -(y + rowTop))
        chip:Show()
        x = x + width + More.CHIP_GAP
        -- Slide in once for a new quest; flip once when one comes true.
        local was = self.chipMet[entry.text]
        self.chipMet[entry.text] = entry.met
        if Full() then
            if fresh then
                Motion:Run(chip, "in", 0.3, function(p) chip:SetAlpha(p) end, { delay = (index - 1) * 0.06 })
            elseif was == false and entry.met then
                Motion:Run(chip, "flip", 0.35, function(p)
                    chip:SetAlpha(0.3 + 0.7 * p)
                    chip:SetScale(0.9 + 0.1 * p)
                end, { ease = Motion.EaseOutBack })
            end
        else
            chip:SetAlpha(1)
        end
    end
    return rowTop + rowTall + More.CHIP_GAP + 4
end

--------------------------------------------------------------------------------
-- Card B: the Options count
--------------------------------------------------------------------------------

function More:BuildOptions(panel)
    local button = panel.optionsButton
    local badge = CreateFrame("Frame", nil, button)
    badge:SetSize(14, 14)
    badge:SetPoint("RIGHT", -4, 0)
    Round(badge, 14, "gilt"):SetPoint("CENTER")
    local count = Theme.CreateLabel(badge, "tiny", "ink", "CENTER")
    count:SetPoint("CENTER", 0, 0)
    badge.count = count
    badge:Hide()
    panel.optionsBadge = badge
    button:HookScript("OnEnter", function(self)
        local on = ns.UpgradeQuest:FiltersOn()
        if #on == 0 then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(L["Filters on:"], Theme.Unpack("accent"))
        for _, text in ipairs(on) do GameTooltip:AddLine(text, 1, 1, 1) end
        GameTooltip:AddLine(L["Click to change them."], Theme.Unpack("dim"))
        GameTooltip:Show()
    end)
    button:HookScript("OnLeave", function() GameTooltip:Hide() end)
    return badge
end

--- The badge on Options says how many filters are on; it pops when the
--- count moves.
function More:FillOptions(panel)
    if not panel.optionsButton then return end
    local badge = panel.optionsBadge or self:BuildOptions(panel)
    local count = #ns.UpgradeQuest:FiltersOn()
    local base = Width("small", L["Options"]) + 24
    panel.optionsButton:SetWidth(count > 0 and base + 18 or base)
    if count == 0 then
        badge:Hide()
    else
        badge.count:SetText(tostring(count))
        badge:Show()
        if self.lastFilters and self.lastFilters ~= count and Full() then
            Motion:Run(badge, "pop", 0.35, function(p) badge:SetScale(1 + 0.4 * (1 - p)) end,
                { ease = Motion.EaseOutBack })
        end
    end
    self.lastFilters = count
end

--------------------------------------------------------------------------------
-- Card G: Ignored and Done
--------------------------------------------------------------------------------

function More:BuildFoot(panel)
    local foot = CreateFrame("Frame", nil, panel.body)
    foot:SetSize(INNER, More.FOOT_HEIGHT)
    local ignored = CreateFrame("Button", nil, foot)
    ignored:SetHeight(More.FOOT_HEIGHT)
    ignored:SetPoint("LEFT", 0, 0)
    local text = Theme.CreateLabel(ignored, "tiny", "accent")
    text:SetPoint("LEFT", 0, 0)
    ignored.text = text
    ignored:SetScript("OnClick", function() if ns.IgnoredUI then ns.IgnoredUI:Show() end end)
    ignored:SetScript("OnEnter", function(self) self.text:SetTextColor(Theme.Unpack("accentHi")) end)
    ignored:SetScript("OnLeave", function(self) self.text:SetTextColor(Theme.Unpack("accent")) end)
    foot.ignored = ignored
    local done = Theme.CreateLabel(foot, "tiny", "muted", "RIGHT")
    done:SetPoint("RIGHT", 0, 0)
    foot.done = done
    foot:Hide()
    panel.foot = foot
    return foot
end

--- How many are ignored on this character.
function More.IgnoredCount()
    local count = 0
    for _ in pairs(ns.UpgradeQuest:Skipped() or {}) do count = count + 1 end
    return count
end

--- Fill the foot under the buttons; returns the room it takes, or 0 when
--- there is nothing to say.
function More:FillFoot(panel, y)
    local foot = panel.foot or self:BuildFoot(panel)
    local ignored, done = More.IgnoredCount(), ns.UpgradeQuest:DoneCount()
    if ignored == 0 and done == 0 then
        foot:Hide()
        return 0
    end
    foot:ClearAllPoints()
    foot:SetPoint("TOPLEFT", PAD, -y)
    if ignored > 0 then
        local words = L.Format("Ignored (%d)", ignored)
        foot.ignored.text:SetText(words)
        foot.ignored:SetWidth(Width("tiny", words) + 8)
        foot.ignored:Show()
    else
        foot.ignored:Hide()
    end
    foot.done:SetText(done > 0 and L.Format("Done: %d", done) or "")
    foot:Show()
    return More.FOOT_HEIGHT + 6
end

--- Everything here goes when the panel shows no quest body.
function More:HideQuestParts(panel)
    for _, key in ipairs({ "gearBox", "alsoToggle" }) do
        if panel[key] then panel[key]:Hide() end
    end
    for _, row in ipairs(panel.alsoRows or {}) do row:Hide() end
    for _, chip in ipairs(panel.chips or {}) do chip:Hide() end
end
