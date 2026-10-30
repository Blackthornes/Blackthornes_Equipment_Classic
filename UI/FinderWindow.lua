-- Blackthornes Equipment -- UI/FinderWindow.lua
-- The Equipment window (one window since 2026-10-22: a player asked for
-- fewer windows, the owner approved the mockup). The slots down the left,
-- each with what you wear there and how many upgrades it has, and for the
-- slot picked first what you already own that beats it (in your bags, your
-- bank or on another character), then every piece a vendor
-- sells, a quest gives, a dungeon or raid drops or a crafter makes that
-- beats what is worn, best first, and where to go for it (a player asked,
-- 2026-10-20, for a list per slot and a choice of sources). Tick boxes
-- pick the sources; "Only what I can get now" leaves out gear that waits
-- on a reputation or on a craft nobody of yours can make yet. The stepper
-- looks a few levels ahead; "This zone only" keeps the list to the zone the
-- character is in. Click a row to follow it as the upgrade quest
-- (Logic/UpgradeQuest.lua), right-click to track it (Logic/Tracking.lua),
-- Alt-click to pin its spot on the map (Logic/Waypoints.lua).
--
-- Opened from the minimap button, /beq and /beq find. Hanging tabs under it
-- switch between Upgrades, Enchants and Settings (UI/Settings.lua, which
-- takes the window's place). ns.UI (UI/MainWindow.lua) reads the bags for
-- it. Logic/Finder.lua does the looking; this only lays it out, and scans
-- again as the server answers about items the client had not seen yet.

local _, ns = ...
local L = ns.L

local FinderUI = ns.NewModule("FinderUI")

local Theme = ns.Theme
local Widgets = ns.Widgets
local Motion = ns.Motion
local Finder = ns.Finder
local Weights = ns.Weights

local PADDING = 18
local HEADER = 36

-- The metal rim (UI/Titanforged.lua) reaches this far in from the edge;
-- the header sits inside it.
local RIM = 6
local FILTERS = 30
-- The quest filters' row, under the source buttons.
local QUEST_ROW = 28
-- The shortest a row is; a row grows to show its lines in full (a
-- player's long "where to get it" line was cut, 2026-10-21). The list's
-- height holds VISIBLE rows at their shortest.
local ROW_HEIGHT = 36
-- The list's height at its least: what nine two-line rows took before.
local AREA = 450
-- One row more than the tallest list holds, so a short row never leaves a gap.
local VISIBLE = math.ceil((AREA + 60) / ROW_HEIGHT) + 1
-- Room for the footer line (the count left, the version right).
local FOOTER = 56
-- What the footer uses now the click help is on each row's hover; the
-- rest goes to the list.
local FOOTER_USED = 30
local WIDTH = 1040

-- The slots down the left, with what is worn in each, and the gap between
-- them and the list.
local SLOT_COLUMN = 290
local COLUMN_GAP = 10
-- The list's own heading: the slot, what is worn there, and the order.
local LIST_HEAD = 30
-- The column headings under it, which sort the list.
local COLUMN_HEAD = 20

local GAIN_WIDTH = 120
-- The Level and Where columns, left of the gain.
local LEVEL_WIDTH = 50
local WHERE_WIDTH = 150
local CELL_GAP = 10
-- Queue it, under the gain on crafted rows.
local QUEUE_WIDTH = 64
local ICON = 28
-- How far down a row its first line sits: level with the icon's middle.
local LINE_TOP = 11
local TEXT_X = ICON + 18
local SCROLL_WIDTH = 4

-- Where the list starts, and how wide its rows are.
local LIST_X = PADDING + SLOT_COLUMN + COLUMN_GAP
local INNER = WIDTH - LIST_X - PADDING - SCROLL_WIDTH - 6

-- Where each column ends, from the row's right edge, and how wide the item
-- column is between the icon and the Level column.
local GAIN_RIGHT = 8
local WHERE_RIGHT = GAIN_RIGHT + GAIN_WIDTH + CELL_GAP
local LEVEL_RIGHT = WHERE_RIGHT + WHERE_WIDTH + CELL_GAP
local ITEM_WIDTH = INNER - TEXT_X - LEVEL_RIGHT - LEVEL_WIDTH - CELL_GAP

-- Some gear is sold by a dozen vendors; the tooltip lists this many.
local TOOLTIP_SOURCES = 8

local HEIGHT = HEADER + 10 + FILTERS + QUEST_ROW + 8 + LIST_HEAD + COLUMN_HEAD + AREA + FOOTER

-- The tag in front of a source, in its own colour.
local KIND_COLORS = { vendor = "accent", quest = "quest", dungeon = "dungeon", craft = "craft" }

-- A tick box for each kind of source, in this order. Raids are dungeon
-- drops from a raid (FinderUI.SourceKind).
local SOURCE_BOXES = {
    { "vendor", L["Vendor"] }, { "quest", L["Quest"] }, { "dungeon", L["Dungeons"] },
    { "raid", L["Raids"] }, { "craft", L["Crafted"] },
}
FinderUI.SOURCE_BOXES = SOURCE_BOXES

-- The slots down the left, in character sheet order: { slot, name, the
-- second slot }. Both rings are one line, and both trinkets.
local SLOT_GROUPS = {
    { 1, L["Head"] }, { 2, L["Neck"] }, { 3, L["Shoulder"] }, { 15, L["Back"] },
    { 5, L["Chest"] }, { 9, L["Wrist"] }, { 10, L["Hands"] }, { 6, L["Waist"] },
    { 7, L["Legs"] }, { 8, L["Feet"] }, { 11, L["Rings"], 12 }, { 13, L["Trinkets"], 14 },
    { 16, L["Main hand"] }, { 17, L["Off hand"] }, { 18, L["Ranged"] },
}
FinderUI.SLOT_GROUPS = SLOT_GROUPS

-- The line a slot is shown on, by slot.
local GROUP_OF = {}
for _, group in ipairs(SLOT_GROUPS) do
    GROUP_OF[group[1]] = group[1]
    if group[3] then GROUP_OF[group[3]] = group[1] end
end
FinderUI.GROUP_OF = GROUP_OF

-- The slot column's headings (SLOT, YOU WEAR, UP), then each slot's line,
-- the lines running the list's full height.
local SLOT_HEAD = 20
-- Where what is worn starts on a slot's line, and how wide its name is.
local WORN_X = 88
local WORN_ICON = 18
local WORN_WIDTH = SLOT_COLUMN - WORN_X - WORN_ICON - 4 - 42

-- A heading row in the list (IN YOUR BAGS, TO GO AND GET).
local HEADING_ROW = 24

-- The hanging tabs under the window, and how far in they start.
local TAB_INSET = 18
local TABS = {
    { key = "upgrades", text = L["Upgrades"] },
    { key = "enchant", text = L["Enchants"] },
    { key = "dungeons", text = L["Dungeon Quests"] },
    { key = "loot", text = L["Dungeon Loot"] },
    { key = "settings", text = L["Settings"], right = true },
}

-- The tabs whose window stands in for this one, at the same spot: each
-- hangs the same tabs (HangTabs) and is shown by ShowTab.
local STAND_INS = {
    dungeons = "DungeonQuestsUI",
    loot = "DungeonLootUI",
    settings = "SettingsUI",
}
FinderUI.STAND_INS = STAND_INS

-- Every tab's window is one size and one scale, so the window never jumps
-- as the tabs are clicked (the owner, 2026-10-23): this window's size,
-- or more when a tab needs it (FinderUI:Need), and `finderScale`, which
-- every tab's size grip sets.
FinderUI.WIDTH, FinderUI.HEIGHT = WIDTH, HEIGHT
FinderUI.SCALE_KEY = "finderScale"
-- What each tab needs at least, { width, height }, as it last said.
FinderUI.needs = {}

-- How many levels ahead the stepper can look.
local MOST_AHEAD = 10

--------------------------------------------------------------------------------
-- Text that fits
--------------------------------------------------------------------------------

--- `text` cut back to the last whole word that fits in `width` pixels at
-- `size`, with no "..." (the row's tooltip has the whole line).
-- Measured, never guessed: the game's font runs wider than it looks.
-- Colour codes take no room and are kept whole, so a cut line keeps its
-- green zone, its source colour and its tags; a colour left open by the
-- cut is closed.
function FinderUI.Fit(size, text, width)
    if Theme.TextWidth(size, text) <= width then return text end

    -- The text as pieces: a colour code, a colour end, or one character.
    local pieces, chars = {}, {}
    local index = 1
    while index <= #text do
        local code = text:match("^|c%x%x%x%x%x%x%x%x", index)
        if code then
            pieces[#pieces + 1] = { code, open = true }
            index = index + #code
        elseif text:sub(index, index + 1) == "|r" then
            pieces[#pieces + 1] = { "|r", close = true }
            index = index + 2
        else
            -- A whole character, never half of one ("Zul'Farrak" is plain,
            -- but a name with an accent is two bytes).
            local char = text:match("^[\194-\244][\128-\191]*", index) or text:sub(index, index)
            pieces[#pieces + 1] = { char, char = true }
            chars[#chars + 1] = char
            index = index + #char
        end
    end

    -- The first `count` characters, with every code before them, trailing
    -- spaces and commas taken off and an open colour closed.
    local function Line(count)
        local out, seen, open = {}, 0, false
        for _, piece in ipairs(pieces) do
            if piece.char then
                if seen >= count then break end
                seen = seen + 1
            elseif piece.open then
                open = true
            elseif piece.close then
                open = false
            end
            out[#out + 1] = piece[1]
        end
        local cut = table.concat(out)
        local trimmed
        repeat
            trimmed = cut
            cut = cut:gsub("[%s,;:]+$", ""):gsub("[%s,;:]+(|r)$", "%1")
        until cut == trimmed
        return cut .. (open and "|r" or "")
    end

    local low, high = 0, #chars
    while low < high do
        local mid = math.ceil((low + high) / 2)
        if Theme.TextWidth(size, Line(mid)) <= width then
            low = mid
        else
            high = mid - 1
        end
    end
    -- Back to the last word that ends whole, unless the cut already ends
    -- one or no word fits whole.
    if low < #chars and not chars[low + 1]:match("[%s,;:]") then
        local back = low
        while back > 0 and not chars[back]:match("%s") do back = back - 1 end
        if back > 0 then low = back end
    end
    return Line(low)
end

local function Colored(key, text)
    local r, g, b = Theme.Unpack(key)
    return ("|cff%02x%02x%02x%s|r"):format(math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5),
        math.floor(b * 255 + 0.5), text)
end

--- The zone the character is in, named in green wherever `text` names it
--- as a whole word (a player asked, 2026-10-09: easier to spot what is
--- nearby).
function FinderUI.MarkZone(text, zone)
    if not (zone and text) or zone == "" then return text end
    -- The text names zones in the game's own words (Logic/Names.lua).
    if ns.Names then zone = ns.Names:Zone(zone) end
    local pattern = "%f[%w]" .. zone:gsub("[%%%^%$%(%)%.%[%]%*%+%-%?]", "%%%0") .. "%f[%W]"
    return (text:gsub(pattern, function(found) return Colored("good", found) end))
end

--- A source as one line: the coloured kind, then where, the zone the
--- character is in shown in green.
function FinderUI.SourceLine(source, zone)
    zone = zone or (ns.UpgradeQuest and ns.UpgradeQuest.Zone())
    local line = Colored(KIND_COLORS[source.kind] or "text", Finder.Label(source))
        .. "  " .. FinderUI.MarkZone(Finder:Describe(source), zone)
    -- Classic Era shows no [Forever] tag (docs/CLASSIC_DIFFERENCES.md).
    return line
end

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

local function ShowEnchantTooltip(row, line)
    local Enchants = ns.Enchants
    local pick, source = line.pick, line.source
    local r, g, b = Theme.Unpack("text")
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:AddLine(Enchants:ShownName(pick.recipeID) or "", Theme.Unpack("accent"))
    GameTooltip:AddLine(L.Format("For your %s", line.plan.link or Enchants.SlotName(line.slot)), r, g, b, true)
    GameTooltip:AddLine(L.Format("Gives %s", Enchants:Gives(pick.recipeID) or ""), Theme.Unpack("good"))
    if line.plan.current then
        GameTooltip:AddLine(L.Format("Now: %s", Enchants:EnchantName(line.plan.current)), r, g, b, true)
    else
        GameTooltip:AddLine(L["Nothing on it now"], r, g, b)
    end
    if pick.percent then
        GameTooltip:AddLine(L.Format("%d%% better for your spec", math.floor(pick.percent + 0.5)), Theme.Unpack("good"))
    end
    if line.soon then
        local wr, wg, wb = Theme.Unpack("warn")
        GameTooltip:AddLine(L["A better piece for this slot is in your upgrade list. This is the cheapest enchant still worth having until then."],
            wr, wg, wb, true)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(L["How to get it"], Theme.Unpack("accent"))
    GameTooltip:AddLine(Enchants:Describe(source, Finder.Money), r, g, b, true)
    local materials = Enchants:MaterialsText(pick.recipeID)
    if materials ~= "" then
        GameTooltip:AddLine(L.Format("Materials: %s", materials), r, g, b, true)
    end
    local place = (source and (source.state == "learn" or source.state == "skill"))
        and Enchants:WhereToLearn(pick.recipeID)
    if place and place.name then
        local names = ns.Names
        local who = names and names:NPC(place.name) or place.name
        local zone = place.zone and names and names:Zone(place.zone) or place.zone
        local where = zone and L.Format("Learn it from %s in %s", who, zone)
            or L.Format("Learn it from %s", who)
        GameTooltip:AddLine(where, r, g, b, true)
    end
    if #FinderUI.EnchantMenu(line) > 0 then
        GameTooltip:AddLine(L["Right-click for more."], Theme.Unpack("dim"))
    end
    GameTooltip:Show()
end

--- Gear you own that beats what you wear: its tooltip, and where it is.
local function ShowOwnedTooltip(row, owned)
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    pcall(GameTooltip.SetHyperlink, GameTooltip, owned.link)
    GameTooltip:AddLine(" ")
    if FinderUI.CanPutOn(owned) then
        GameTooltip:AddLine(L["Click to put it on"], Theme.Unpack("good"))
        GameTooltip:AddLine(L["Right-click for more."], Theme.Unpack("dim"))
    elseif owned.where ~= "bags" and ns.UI then
        GameTooltip:AddLine(ns.UI.WhereText(owned.where), Theme.Unpack("accent"))
    end
    GameTooltip:Show()
end

local function ShowTooltip(row)
    if rawget(row, "heading") then return end
    local owned = rawget(row, "owned")
    if owned then return ShowOwnedTooltip(row, owned) end
    local enchant = rawget(row, "enchant")
    if enchant then return ShowEnchantTooltip(row, enchant) end
    local pick = row.pick
    if not pick then return end

    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    pcall(GameTooltip.SetHyperlink, GameTooltip, pick.link)
    GameTooltip:AddLine(" ")
    if pick.needs then
        GameTooltip:AddLine(Finder.NeedsText(pick.needs), Theme.Unpack("warn"))
    end
    if pick.at then
        GameTooltip:AddLine(L.Format("You can wear it from level %d", pick.at), Theme.Unpack("warn"))
    end
    local roll = Finder.RollText(pick)
    if roll then
        local r, g, b = Theme.Unpack("good")
        GameTooltip:AddLine(roll, r, g, b, true)
    end
    GameTooltip:AddLine(L["Where to get it"], Theme.Unpack("accent"))
    for index, source in ipairs(pick.sources) do
        if index > TOOLTIP_SOURCES then
            GameTooltip:AddLine(L.Format("and %d more", #pick.sources - TOOLTIP_SOURCES),
                Theme.Unpack("muted"))
            break
        end
        GameTooltip:AddLine(FinderUI.SourceLine(source), Theme.Unpack("text"))
        if source.after then
            GameTooltip:AddLine(L.Format("    after %s", source.after), Theme.Unpack("muted"))
        end
        if source.kind == "craft" and ns.Crafting then
            -- Light, so it reads on the tooltip's dark background.
            local r, g, b = Theme.Unpack("text")
            GameTooltip:AddLine(L.Format("    Materials: %s", ns.Crafting:MaterialsText(pick.itemID)), r, g, b, true)
        end
    end
    GameTooltip:AddLine(" ")
    local quest = ns.UpgradeQuest
    if quest then
        local _, why = quest.CanFollow(pick)
        -- What a click does, said plainly: players took the green Quest
        -- tag it leaves for a mistake (2026-10-09).
        local r, g, b = Theme.Unpack("text")
        if quest:IsFollowing(pick.itemID) then
            GameTooltip:AddLine(L["Your upgrade quest: click to show it on the quest panel"], Theme.Unpack("good"))
            GameTooltip:AddLine(L["The green Quest tag marks it. To drop it, click Ignore on the quest panel."], r, g, b, true)
        elseif why then
            local wr, wg, wb = Theme.Unpack("warn")
            GameTooltip:AddLine(L.Format("Not a quest yet: %s", why), wr, wg, wb, true)
        else
            GameTooltip:AddLine(L["Click to follow it on the quest panel"], Theme.Unpack("good"))
            GameTooltip:AddLine(L["It becomes your upgrade quest, with steps to get it. A green Quest tag marks it here."], r, g, b, true)
        end
    end
    if FinderUI.Place(pick) then
        GameTooltip:AddLine(L["Alt-click to pin it on your map"], Theme.Unpack("dim"))
    end
    GameTooltip:AddLine(L["Right-click for more."], Theme.Unpack("dim"))
    GameTooltip:Show()
end

function FinderUI:BuildRow(index)
    local inner = INNER
    local row = CreateFrame("Button", nil, self.frame)
    -- Above the well, whatever order the client draws siblings in.
    row:SetFrameLevel(self.well:GetFrameLevel() + 1)
    -- Placed by Draw, which stacks the rows by their own heights.
    row:SetSize(inner, ROW_HEIGHT)
    row:SetPoint("TOPLEFT", LIST_X, self.rowsTop - (index - 1) * ROW_HEIGHT)
    row.restKey = index % 2 == 0 and "glassAlt" or "glass"
    row.background = Theme.Fill(row, row.restKey)

    -- Dark glass: a fine line under each row.
    local line = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    line:SetPoint("BOTTOMLEFT")
    line:SetPoint("BOTTOMRIGHT")
    line:SetHeight(1)
    line:SetColorTexture(Theme.Unpack("border", 0.6))

    -- A gold edge that lights under the mouse, as every list's does.
    local edge = row:CreateTexture(nil, "ARTWORK")
    edge:SetPoint("TOPLEFT")
    edge:SetPoint("BOTTOMLEFT")
    edge:SetWidth(2)
    edge:SetColorTexture(Theme.Unpack("accentHi", 0))
    row.edge = edge

    -- Under the mouse the row lights from the left too: a soft gold wash
    -- fading across it (Titanforged). Hidden at rest.
    local wash = row:CreateTexture(nil, "BACKGROUND", nil, 3)
    wash:SetAllPoints(row)
    wash:Hide()
    row.hoverWash = wash

    -- At the top, level with the name, so a tall row still reads as one.
    local icon = Theme.CreateItemIcon(row, ICON)
    icon:SetPoint("TOPLEFT", 10, -(ROW_HEIGHT - ICON) / 2)
    row.icon = icon

    -- Every line wraps and the row grows to fit, so nothing is cut.
    local item = Theme.CreateLabel(row, "normal", "text")
    item:SetPoint("TOPLEFT", TEXT_X, -LINE_TOP)
    item:SetWidth(ITEM_WIDTH)
    item:SetWordWrap(true)
    row.item = item

    local gain = Theme.CreateLabel(row, "normal", "good", "RIGHT")
    gain:SetPoint("TOPRIGHT", -GAIN_RIGHT, -LINE_TOP)
    gain:SetWidth(GAIN_WIDTH)
    gain:SetWordWrap(true)
    row.gain = gain

    local level = Theme.CreateLabel(row, "small", "text")
    level:SetPoint("TOPRIGHT", -LEVEL_RIGHT, -LINE_TOP - 1)
    level:SetWidth(LEVEL_WIDTH)
    row.level = level

    local where = Theme.CreateLabel(row, "small", "text")
    where:SetPoint("TOPRIGHT", -WHERE_RIGHT, -LINE_TOP - 1)
    where:SetWidth(WHERE_WIDTH)
    where:SetWordWrap(true)
    row.where = where

    local source = Theme.CreateLabel(row, "tiny", "muted")
    source:SetPoint("TOPLEFT", item, "BOTTOMLEFT", 0, -3)
    source:SetWidth(ITEM_WIDTH)
    source:SetWordWrap(true)
    row.source = source
    row.sourceWidth = ITEM_WIDTH
    -- The enchant view has no Level or Where: its lines take the width.
    row.fullSourceWidth = inner - TEXT_X - 8

    -- Queue it, on crafted gear while Tradeskills is loaded: sends the craft,
    -- or what to buy, to Tradeskills' queue (Logic/TradeskillsQueue.lua).
    local queueIt = Widgets.CreateButton(row, L["Queue It"], function(self)
        local enchant = rawget(self, "enchant")
        if enchant and ns.Enchants then
            ns.Enchants:Queue(enchant.pick.recipeID)
            return
        end
        local craft = rawget(self, "source")
        if craft and ns.TradeskillsQueue then
            ns.TradeskillsQueue:Queue(craft)
            FinderUI:Draw()
        end
    end, { width = QUEUE_WIDTH, height = 18 })
    queueIt:SetPoint("BOTTOMRIGHT", -GAIN_RIGHT, 5)
    queueIt:HookScript("OnEnter", function(self)
        local enchant = rawget(self, "enchant")
        if enchant and ns.Enchants then
            local source = enchant.source
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(L["Queue It"], Theme.Unpack("accent"))
            local known = source and (source.state == "known" or source.state == "alt")
            local text = known and L["Puts the enchant in Tradeskills' queue."]
                or (source and source.kit and source.state == "other") and L["Puts it on Tradeskills' shopping list."]
                or L["Puts its materials on Tradeskills' shopping list."]
            GameTooltip:AddLine(text, 1, 1, 1, true)
            GameTooltip:Show()
            return
        end
        local craft = rawget(self, "source")
        if not (craft and ns.TradeskillsQueue) then return end
        local title, text = ns.TradeskillsQueue:Explain(craft)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(title, Theme.Unpack("accent"))
        if text then GameTooltip:AddLine(text, 1, 1, 1, true) end
        GameTooltip:Show()
    end)
    queueIt:HookScript("OnLeave", function() GameTooltip:Hide() end)
    queueIt:Hide()
    row.queueIt = queueIt

    -- Show the way, on enchants still to learn: pins the trainer or vendor
    -- through Tradeskills.
    local showWay = Widgets.CreateButton(row, L["Show the Way"], function(self)
        local enchant = rawget(self, "enchant")
        if not (enchant and ns.Enchants) then return end
        if not ns.Enchants:ShowTheWay(enchant.pick.recipeID) then
            ns.Print(L["Couldn't find where to learn it."])
        end
    end, { width = QUEUE_WIDTH, height = 18 })
    showWay:SetPoint("BOTTOMRIGHT", -8, 5)
    showWay:Hide()
    row.showWay = showWay

    -- Put it on, on an upgrade in your bags: the gold button of the row.
    local putOn = Widgets.CreateButton(row, L["Put It On"], function(self)
        local owned = rawget(self, "owned")
        if owned and ns.Wear then ns.Wear:PutOn(owned.link) end
    end, { width = 78, height = 20, primary = true })
    putOn:SetPoint("BOTTOMRIGHT", -GAIN_RIGHT, 5)
    putOn:Hide()
    row.putOn = putOn

    -- A heading's own label, in place of the item's.
    local headingLabel = Theme.CreateLabel(row, "small", "accent")
    headingLabel:SetPoint("LEFT", 12, 0)
    headingLabel:Hide()
    row.headingLabel = headingLabel

    local function Light(p)
        row.background:SetColorTexture(Motion.Mix(row.restKey, "glassHover", p))
        row.edge:SetColorTexture(Theme.Unpack("accentHi", p))
        Theme.LightGradient(wash, "HORIZONTAL", "accent", 0.10, 0, p)
    end

    row:SetScript("OnEnter", function(self)
        self.over = true
        if rawget(self, "heading") then return end
        Motion:Blend(self, "hover", 1, 0.12, Light)
        ShowTooltip(self)
    end)
    row:SetScript("OnLeave", function(self)
        self.over = false
        Motion:Blend(self, "hover", 0, 0.18, Light)
        GameTooltip:Hide()
    end)
    row:SetScript("OnClick", function(self, button)
        if rawget(self, "heading") then return end
        -- A right-click opens the row's menu (UI/RowMenu.lua), the same in
        -- every Blackthornes list.
        if button == "RightButton" then
            FinderUI:OpenRowMenu(self)
            return
        end
        -- Gear you own: Shift-click links it, a click puts on one in your bags.
        local owned = rawget(self, "owned")
        if owned then
            if type(IsModifiedClick) == "function" and type(ChatEdit_InsertLink) == "function" then
                local ok, chatLink = pcall(IsModifiedClick, "CHATLINK")
                if ok and chatLink then
                    pcall(ChatEdit_InsertLink, owned.link)
                    return
                end
            end
            if button ~= "RightButton" and FinderUI.CanPutOn(owned) and ns.Wear then ns.Wear:PutOn(owned.link) end
            return
        end
        -- An enchant row's buttons do its work; Shift-click links its recipe.
        local enchant = rawget(self, "enchant")
        if enchant then
            if type(IsModifiedClick) == "function" and type(ChatEdit_InsertLink) == "function" then
                local ok, chatLink = pcall(IsModifiedClick, "CHATLINK")
                if ok and chatLink then
                    local okLink, link = pcall(function()
                        local spell = _G.C_Spell and _G.C_Spell.GetSpellLink
                        return spell and spell(enchant.pick.recipeID) or nil
                    end)
                    if okLink and link then pcall(ChatEdit_InsertLink, link) end
                end
            end
            return
        end
        local pick = self.pick
        if not pick then return end
        local okAlt, alt = pcall(function() return IsAltKeyDown() == true end)
        if okAlt and alt then
            local place = FinderUI.Place(pick)
            if place and ns.Waypoints then ns.Waypoints:Show(place, place.name, pick.link) end
            return
        end
        if type(IsModifiedClick) == "function" and type(ChatEdit_InsertLink) == "function" then
            local ok, chatLink = pcall(IsModifiedClick, "CHATLINK")
            if ok and chatLink then
                pcall(ChatEdit_InsertLink, pick.link)
                return
            end
        end
        -- A plain click follows it on the upgrade quest panel (asked 2026-10-06).
        FinderUI:Follow(pick)
        if rawget(self, "over") == true then ShowTooltip(self) end
    end)
    if row.RegisterForClicks then row:RegisterForClicks("LeftButtonUp", "RightButtonUp") end

    row:Hide()
    return row
end

--- The menu lines of an enchant row: Queue It and Show the Way.
function FinderUI.EnchantMenu(line)
    local Enchants = ns.Enchants
    local lines = {}
    if not (Enchants and line) then return lines end
    if Enchants:CanQueue() then
        lines[#lines + 1] = { text = L["Queue It"], run = function() Enchants:Queue(line.pick.recipeID) end }
    end
    local state = line.source and line.source.state
    if (state == "learn" or state == "skill") and Enchants:CanShowTheWay(line.pick.recipeID) then
        lines[#lines + 1] = { text = L["Show the Way"], run = function()
            if not Enchants:ShowTheWay(line.pick.recipeID) then
                ns.Print(L["Couldn't find where to learn it."])
            end
        end }
    end
    return lines
end

--- The menu lines of a gear row: Follow, Track or Stop Tracking, Show on
--- Map and Queue It, the plain click's first.
function FinderUI.PickMenu(pick, sources)
    local lines = {}
    local quest = ns.UpgradeQuest
    if quest then
        local can = quest.CanFollow(pick)
        lines[#lines + 1] = { text = L["Follow"], disabled = not can,
            checked = quest:IsFollowing(pick.itemID), run = function() FinderUI:Follow(pick) end }
    end
    if ns.Tracking then
        local tracked = ns.Tracking:IsTracked(pick.itemID)
        lines[#lines + 1] = { text = tracked and L["Stop Tracking"] or L["Track"], run = function()
            ns.Tracking:Toggle(pick)
            FinderUI:Draw()
        end }
    end
    local place = FinderUI.Place(pick)
    if place and ns.Waypoints then
        lines[#lines + 1] = { text = L["Show on Map"], run = function()
            ns.Waypoints:Show(place, place.name, Theme.ItemIcon(pick.link))
        end }
    end
    local craft = ns.TradeskillsQueue and ns.TradeskillsQueue:Available()
        and ns.TradeskillsQueue.CraftSource(sources or pick.sources) or nil
    if craft then
        lines[#lines + 1] = { text = L["Queue It"], run = function()
            ns.TradeskillsQueue:Queue(craft)
            FinderUI:Draw()
        end }
    end
    return lines
end

--- A right-click on a row: its menu, titled with the item's name.
function FinderUI:OpenRowMenu(row)
    if not ns.RowMenu then return end
    local lines, title
    local owned, enchant, pick = rawget(row, "owned"), rawget(row, "enchant"), rawget(row, "pick")
    if owned then
        lines = {}
        if FinderUI.CanPutOn(owned) and ns.Wear then
            lines[1] = { text = L["Put It On"], run = function() ns.Wear:PutOn(owned.link) end }
        end
        title = owned.link
    elseif enchant then
        lines = FinderUI.EnchantMenu(enchant)
        title = ns.Enchants and ns.Enchants:ShownName(enchant.pick.recipeID)
    elseif pick then
        lines = FinderUI.PickMenu(pick)
        title = pick.link
    end
    if not lines or #lines == 0 then return end
    if type(title) == "string" then title = title:match("%[(.-)%]") or title end
    GameTooltip:Hide()
    ns.RowMenu:Open(lines, { title = title })
end

function FinderUI:Build()
    if self.frame then return self.frame end

    local frame = CreateFrame("Frame", "BlackthornesEquipmentFinder", UIParent)
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    Theme.Fill(frame, "window")

    -- The house frame, as the gear window wears it (UI/Titanforged.lua).
    if ns.Titanforged then
        local trim = ns.Titanforged:Dress(frame, {
            title = "Blackthornes Equipment",
            portrait = true,
            close = function() FinderUI:Hide() end,
        })

        -- Kept on the screen whole: the portrait and plate reach out past
        -- the top left, the close gem past the top right.
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
            if not folded then FinderUI:Refresh() end
        end })
    end

    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if ns.db then ns.db.finderMoved = true end
        FinderUI:SavePosition()
    end)

    -- The house size grip under the bottom right corner (Widgets.WindowGrip),
    -- saved as `finderScale`, the one every tab shares.
    self.sizeGrip = Widgets.WindowGrip(frame, FinderUI.SCALE_KEY, function()
        if ns.db then ns.db.finderMoved = true end
        FinderUI:SavePosition()
        FinderUI:ScaleChanged()
    end)
    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(_, delta) FinderUI:ScrollBy(-delta) end)

    if type(UISpecialFrames) == "table" then
        table.insert(UISpecialFrames, "BlackthornesEquipmentFinder")
    end

    self.frame = frame
    self:BuildHeader()
    self:BuildFilters()

    -- The list takes what the footer no longer uses, and the filters'
    -- second line when they fit on one.
    local twoRows = self.filterRows ~= 1
    self.area = AREA + (FOOTER - FOOTER_USED) + (twoRows and 0 or QUEST_ROW)
    self.listTop = -(HEADER + 10 + FILTERS + (twoRows and QUEST_ROW or 0) + 8)
    self.rowsTop = self.listTop - LIST_HEAD - COLUMN_HEAD
    local listHeight = LIST_HEAD + COLUMN_HEAD + self.area

    self:BuildSlots(listHeight)

    -- The list sits sunk into the window, as the game's inset lists do.
    local well = Theme.CreatePanel(frame, "panel", "border")
    well:SetPoint("TOPLEFT", LIST_X - 3, self.listTop + 3)
    well:SetPoint("TOPRIGHT", -(PADDING - 3), self.listTop + 3)
    well:SetHeight(listHeight + 6)
    Theme.Recess(well)
    self.well = well

    self:BuildListHead()
    self:BuildColumnHeads()

    -- At most VISIBLE rows fit, each at least ROW_HEIGHT tall. One more,
    -- never shown, measures lines for how far the list scrolls.
    self.rows = {}
    for index = 1, VISIBLE do self.rows[index] = self:BuildRow(index) end
    self.measureRow = self:BuildRow(0)

    -- A thin track down the right of the list, and a thumb that shows where
    -- in it the view is. On the well, or the well would hide them.
    local track = well:CreateTexture(nil, "ARTWORK")
    track:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PADDING, self.rowsTop)
    track:SetSize(SCROLL_WIDTH, self.area)
    track:SetColorTexture(Theme.Unpack("rowAlt"))
    self.track = track

    local thumb = well:CreateTexture(nil, "OVERLAY")
    thumb:SetWidth(SCROLL_WIDTH)
    thumb:SetColorTexture(Theme.Unpack("accent", 0.8))
    -- The game's scroll knob in the Blizzard window style (UI/BlizzardLook.lua).
    -- The knob art needs more than the 4 px bar: it takes the 6 px gap
    -- beside the rows too, or it is squeezed to a smear.
    if ns.BlizzardLook and ns.BlizzardLook.Thumb(thumb) then thumb:SetWidth(SCROLL_WIDTH + 6) end
    self.thumb = thumb

    -- An empty list says why, and offers the next step (Widgets.CreateEmpty).
    local empty = Widgets.CreateEmpty(well, { width = INNER - 40 })
    empty:SetPoint("TOP", well, "TOP", 0, -(LIST_HEAD + COLUMN_HEAD + 50))
    empty:Hide()
    self.empty = empty

    -- The footer (card 5 of the unified look): the count on the left, the
    -- version small and faint on the right. How to click is on each row's
    -- hover and each heading's, so the hint line stays empty.
    local hint = Theme.CreateLabel(frame, "tiny", "dim")
    hint:SetPoint("BOTTOMLEFT", PADDING, 10)
    hint:SetText("")
    hint:Hide()
    self.hint = hint

    local version = Theme.CreateLabel(frame, "tiny", "dim", "RIGHT")
    version:SetPoint("BOTTOMRIGHT", -PADDING, 12)
    version:SetText(ns.VersionLabel and ns.VersionLabel() or "")
    self.versionLabel = version

    -- How many upgrades in all: in your bags, and to go and get.
    local summary = Theme.CreateLabel(frame, "small", "good")
    summary:SetPoint("BOTTOMLEFT", PADDING, 12)
    self.summary = summary

    local footer = Theme.CreateLabel(frame, "small", "text")
    footer:SetPoint("BOTTOMLEFT", PADDING, 12)
    self.footer = footer

    -- Upgrades, Enchants, Dungeon Quests, Dungeon Loot and Settings,
    -- hanging under the window.
    self.tabStrip = self:HangTabs(frame, "upgrades")

    frame:Hide()
    -- The gear window's module keeps its parts by their old names.
    if ns.UI and ns.UI.Build then ns.UI:Build() end
    return frame
end

--- The hanging tabs under `frame`, `selected` lit: this window's, and the
--- Settings window's while it stands in for it.
function FinderUI:HangTabs(frame, selected)
    if not Widgets.CreateTabStrip then return nil end
    local ok, frameWidth = pcall(frame.GetWidth, frame)
    if not (ok and type(frameWidth) == "number" and frameWidth > 0) then frameWidth = WIDTH end
    local width = frameWidth - TAB_INSET * 2
    local strip = Widgets.CreateTabStrip(frame, TABS, function(key)
        FinderUI:ShowTab(key)
    end, { hanging = true, width = width })
    strip:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", TAB_INSET, 0)
    strip:Select(selected)
    -- Kept on the frame, so FitTab keeps Settings flush right as it grows.
    frame.blackthornesTabs = strip
    return strip
end

--- The top left corner of `frame` in screen pixels, or nil.
local function Corner(frame)
    local ok, left, top, scale = pcall(function()
        return frame:GetLeft(), frame:GetTop(), frame:GetEffectiveScale()
    end)
    if ok and type(left) == "number" and type(top) == "number" and type(scale) == "number" then
        return left * scale, top * scale
    end
    return nil
end

--- Put `frame`'s top left corner at a spot in screen pixels.
local function PlaceAt(frame, x, y)
    if not x then return end
    local ok, scale = pcall(frame.GetEffectiveScale, frame)
    if not (ok and type(scale) == "number" and scale > 0) then return end
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale, y / scale)
end

--- The window a stand-in tab's module keeps, or nil.
local function StandInFrame(name)
    local module = ns[name]
    return module and rawget(module, "frame") or nil
end

local function Shown(frame)
    if not frame then return false end
    local ok, shown = pcall(frame.IsShown, frame)
    return ok and shown == true
end

--- The size every tab shares: this window's, or the most any tab needs.
function FinderUI:TabSize()
    local width, height = WIDTH, HEIGHT
    for _, need in pairs(self.needs) do
        if type(need[1]) == "number" and need[1] > width then width = need[1] end
        if type(need[2]) == "number" and need[2] > height then height = need[2] end
    end
    return math.ceil(width), math.ceil(height)
end

--- Give one tab's window the shared size and scale.
function FinderUI:FitTab(frame)
    if not frame then return end
    local width, height = self:TabSize()
    local okWidth, oldWidth = pcall(frame.GetWidth, frame)
    frame:SetWidth(width)
    frame:SetHeight(height)
    local strip = rawget(frame, "blackthornesTabs")
    if strip and strip.SetRoom and not (okWidth and oldWidth == width) then
        strip:SetRoom(width - TAB_INSET * 2)
    end
    if Widgets.ApplySize and ns.db then Widgets.ApplySize(frame, ns.db[FinderUI.SCALE_KEY]) end
end

--- Every tab's window built so far, this one first.
function FinderUI:TabFrames()
    local frames = {}
    if self.frame then frames[#frames + 1] = self.frame end
    for _, name in pairs(STAND_INS) do
        local frame = StandInFrame(name)
        if frame then frames[#frames + 1] = frame end
    end
    return frames
end

--- A tab says how much room it needs; nil for either keeps the usual.
--- Every window follows when that moves the shared size.
function FinderUI:Need(key, width, height)
    local beforeWidth, beforeHeight = self:TabSize()
    self.needs[key] = { width, height }
    local afterWidth, afterHeight = self:TabSize()
    if beforeWidth == afterWidth and beforeHeight == afterHeight then return end
    for _, frame in ipairs(self:TabFrames()) do self:FitTab(frame) end
end

--- A size grip dragged on one tab: the others take the same scale.
function FinderUI:ScaleChanged()
    for _, frame in ipairs(self:TabFrames()) do
        if Widgets.ApplySize and ns.db then Widgets.ApplySize(frame, ns.db[FinderUI.SCALE_KEY]) end
    end
end

--- The window of the tabs shown now: this one, or one standing in for it.
function FinderUI:ShownTabWindow()
    if Shown(self.frame) then return self.frame end
    for _, name in pairs(STAND_INS) do
        local frame = StandInFrame(name)
        if Shown(frame) then return frame end
    end
    return nil
end

--- A tab clicked, or a stand-in window opened on its own: Upgrades and
--- Enchants show this window, the others show their own window in its
--- place, at the same spot, and every other window of the tabs goes.
function FinderUI:ShowTab(key)
    local current = self:ShownTabWindow()
    local x, y
    if current then x, y = Corner(current) end
    for other, name in pairs(STAND_INS) do
        if other ~= key and StandInFrame(name) and ns[name].Hide then ns[name]:Hide() end
    end

    local standIn = STAND_INS[key] and ns[STAND_INS[key]]
    if STAND_INS[key] then
        if not (standIn and standIn.Show) then return end
        local wasShown = Shown(StandInFrame(STAND_INS[key]))
        self:Hide()
        standIn:Show()
        local frame = StandInFrame(STAND_INS[key])
        self:FitTab(frame)
        if current and not wasShown and frame then PlaceAt(frame, x, y) end
        standIn.asTab = true
        local strip = rawget(standIn, "tabStrip")
        if strip then strip:Select(key) end
        return
    end

    if ns.db then ns.db.finderShow = key == "enchant" and "enchant" or "all" end
    self.offset = 0
    local wasShown = Shown(self.frame)
    self:Show()
    self:FitTab(self.frame)
    if current and not wasShown then PlaceAt(self.frame, x, y) end
    if self.tabStrip then self.tabStrip:Select(key == "enchant" and "enchant" or "upgrades") end
end

--- The slots down the left: a dark glass line each, its name, what you
--- wear there and how many upgrades it has, the one picked lit gold. A
--- click shows its list.
function FinderUI:BuildSlots(height)
    local frame = self.frame
    local column = Theme.CreatePanel(frame, "panel", "border")
    column:SetPoint("TOPLEFT", PADDING - 3, self.listTop + 3)
    column:SetSize(SLOT_COLUMN + 6, height + 6)
    Theme.Recess(column)
    self.slotWell = column

    -- SLOT, YOU WEAR and UP over the lines.
    local heads = { { 12, L["SLOT"], "LEFT" }, { WORN_X, L["YOU WEAR"], "LEFT" }, { -8, L["UP"], "RIGHT" } }
    for _, head in ipairs(heads) do
        local label = Theme.CreateLabel(frame, "tiny", "muted", head[3])
        if head[3] == "RIGHT" then
            label:SetPoint("TOPRIGHT", frame, "TOPLEFT", PADDING + SLOT_COLUMN + head[1], self.listTop - 5)
        else
            label:SetPoint("TOPLEFT", PADDING + head[1], self.listTop - 5)
        end
        label:SetText(head[2])
    end
    local slotsTop = self.listTop - SLOT_HEAD
    -- The lines share the list's height.
    local SLOT_ROW = math.floor((height - SLOT_HEAD) / #SLOT_GROUPS)

    self.slotButtons = {}
    for index, group in ipairs(SLOT_GROUPS) do
        local button = CreateFrame("Button", nil, frame)
        button:SetFrameLevel(column:GetFrameLevel() + 1)
        button:SetSize(SLOT_COLUMN, SLOT_ROW)
        button:SetPoint("TOPLEFT", PADDING, slotsTop - (index - 1) * SLOT_ROW)
        button.group = group[1]
        button.restKey = index % 2 == 0 and "glassAlt" or "glass"
        button.background = Theme.Fill(button, button.restKey)

        local line = button:CreateTexture(nil, "BACKGROUND", nil, 1)
        line:SetPoint("BOTTOMLEFT")
        line:SetPoint("BOTTOMRIGHT")
        line:SetHeight(1)
        line:SetColorTexture(Theme.Unpack("border", 0.6))

        -- Gold down the left of the one picked, and of the one under the mouse.
        local edge = button:CreateTexture(nil, "ARTWORK")
        edge:SetPoint("TOPLEFT")
        edge:SetPoint("BOTTOMLEFT")
        edge:SetWidth(3)
        edge:SetColorTexture(Theme.Unpack("accentHi"))
        edge:Hide()
        button.edge = edge

        -- How many, on a small gold-edged badge at the right.
        local badge = CreateFrame("Frame", nil, button)
        badge:SetSize(26, 16)
        badge:SetPoint("RIGHT", -8, 0)
        badge.background = Theme.Fill(badge, "glassActive")
        Theme.Border(badge, "metal")
        local count = Theme.CreateLabel(badge, "small", "accent", "CENTER")
        count:SetPoint("CENTER", 0, 0)
        button.badge, button.count = badge, count

        local name = Theme.CreateLabel(button, "small", "text")
        name:SetPoint("LEFT", 12, 0)
        name:SetWidth(WORN_X - 16)
        name:SetText(group[2])
        button.name = name

        -- What you wear there: its icon and its name in its rarity colour,
        -- both for rings and trinkets.
        local wornIcon = Theme.CreateItemIcon(button, WORN_ICON)
        wornIcon:SetPoint("LEFT", WORN_X, 0)
        button.wornIcon = wornIcon
        local worn = Theme.CreateLabel(button, "tiny", "dim")
        worn:SetPoint("LEFT", WORN_X + WORN_ICON + 4, 0)
        worn:SetWidth(WORN_WIDTH)
        worn:SetWordWrap(true)
        button.worn = worn

        button:SetScript("OnEnter", function(self)
            self.over = true
            FinderUI:PaintSlot(self)
            local link = rawget(self, "wornLink")
            if type(link) == "string" then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                pcall(GameTooltip.SetHyperlink, GameTooltip, link)
                GameTooltip:Show()
            end
        end)
        button:SetScript("OnLeave", function(self)
            self.over = false
            FinderUI:PaintSlot(self)
            GameTooltip:Hide()
        end)
        button:SetScript("OnClick", function(self) FinderUI:PickSlot(self.group) end)
        self.slotButtons[index] = button
    end
end

--- One slot's line as it stands: picked, under the mouse, or at rest, and
--- dim when it has nothing.
function FinderUI:PaintSlot(button)
    local picked = button.group == self.slot
    local over = rawget(button, "over") == true
    button.background:SetColorTexture(Theme.Unpack(picked and "glassActive" or over and "glassHover" or button.restKey))
    button.edge:SetShown(picked or over)
    button.edge:SetColorTexture(Theme.Unpack(picked and "accentHi" or "accent"))
    local some = (tonumber(button.count:GetText()) or 0) > 0
    button.name:SetTextColor(Theme.Unpack(picked and "accentHi" or some and "text" or "muted"))
    button.badge.background:SetColorTexture(Theme.Unpack(picked and "accent" or "glassActive"))
    button.count:SetTextColor(Theme.Unpack(picked and "ink" or some and "accent" or "dim"))
end

--- A small gold triangle, pointing down until flipped: which way a sorted
--- column runs.
local function SortArrow(parent)
    local arrow = parent:CreateTexture(nil, "OVERLAY")
    arrow:SetTexture(ns.Titanforged.MEDIA .. "SortArrow")
    arrow:SetSize(10, 10)
    arrow:SetVertexColor(Theme.Unpack("accent"))
    arrow:Hide()
    return arrow
end

--- Point an arrow down (first click) or up (flipped).
local function PointArrow(arrow, flip)
    if flip then arrow:SetTexCoord(0, 1, 1, 0) else arrow:SetTexCoord(0, 1, 0, 1) end
end

-- The headings over the rows, which sort the list: { key, heading, the
-- name the Sort line uses, from the right edge or the left, width }.
local COLUMNS = {
    { key = "item", label = L["ITEM"], name = L["Item"], left = TEXT_X, width = ITEM_WIDTH },
    { key = "level", label = L["LEVEL"], name = L["Level"], right = LEVEL_RIGHT, width = LEVEL_WIDTH },
    { key = "where", label = L["WHERE"], name = L["Where"], right = WHERE_RIGHT, width = WHERE_WIDTH },
    { key = "gain", label = L["GAIN"], name = L["Gain"], right = GAIN_RIGHT, width = GAIN_WIDTH, justify = "RIGHT" },
}
FinderUI.COLUMNS = COLUMNS

--- The column headings: a click sorts by that column, a second flips the
--- order, a third goes back to best first (the house rule, as Pets'
--- compendium does it).
function FinderUI:BuildColumnHeads()
    self.columnHeads = {}
    for _, column in ipairs(COLUMNS) do
        local heading = CreateFrame("Button", nil, self.frame)
        heading:SetFrameLevel(self.well:GetFrameLevel() + 1)
        heading:SetSize(column.width, COLUMN_HEAD)
        local x = column.left or (INNER - column.right - column.width)
        heading:SetPoint("TOPLEFT", LIST_X + x, self.listTop - LIST_HEAD)
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

        heading:SetScript("OnClick", function(self) FinderUI:SortBy(self.key) end)
        heading:SetScript("OnEnter", function(self)
            self.label:SetTextColor(Theme.Unpack("accentHi"))
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(L["Click a heading to sort. Click it again to flip the order, and a third time for best first."],
                0.42, 0.44, 0.48, true)
            GameTooltip:Show()
        end)
        heading:SetScript("OnLeave", function()
            FinderUI:PaintHeadings()
            GameTooltip:Hide()
        end)
        self.columnHeads[#self.columnHeads + 1] = heading
    end
    self:PaintHeadings()
end

--- A click on a heading: the first sorts by it, the second flips the
--- order, the third goes back to best first. Kept while the game runs.
function FinderUI:SortBy(key)
    if self.sortKey ~= key then
        self.sortKey, self.sortFlip = key, false
    elseif not self.sortFlip then
        self.sortFlip = true
    else
        self.sortKey, self.sortFlip = nil, false
    end
    self.offset = 0
    self:PaintHeadings()
    self:Redraw()
end

--- The headings and the Sort line as the order stands.
function FinderUI:PaintHeadings()
    local key, flip = self.sortKey, self.sortFlip == true
    local name = L["Best first"]
    for _, heading in ipairs(self.columnHeads or {}) do
        local on = heading.key == key
        heading.label:SetTextColor(Theme.Unpack(on and "accent" or "muted"))
        heading.arrow:SetShown(on)
        PointArrow(heading.arrow, flip)
    end
    for _, column in ipairs(COLUMNS) do
        if column.key == key then name = column.name end
    end
    if self.sortLabel then
        self.sortLabel:SetText(L.Format("Sort: %s", Colored("accent", name)))
        -- Room for the arrow after it while a column sorts.
        self.sortLabel:SetPoint("RIGHT", key and -24 or -10, 0)
        self.sortArrow:SetShown(key ~= nil and self.sortLabel:IsShown())
        PointArrow(self.sortArrow, flip)
    end
end

--- The heading over the list: the slot's name, what is worn there, and the
--- order the list runs in.
function FinderUI:BuildListHead()
    local well = self.well
    local head = CreateFrame("Frame", nil, self.frame)
    head:SetFrameLevel(well:GetFrameLevel() + 1)
    head:SetPoint("TOPLEFT", LIST_X, self.listTop)
    head:SetSize(INNER + SCROLL_WIDTH + 6, LIST_HEAD)

    local rule = head:CreateTexture(nil, "ARTWORK")
    rule:SetPoint("BOTTOMLEFT")
    rule:SetPoint("BOTTOMRIGHT")
    rule:SetHeight(1)
    Theme.SetGradientAlpha(rule, "HORIZONTAL", "accent", 0.5, 0.05)

    local title = Theme.CreateLabel(head, "large", "accentHi")
    title:SetPoint("LEFT", 12, 0)
    self.listTitle = title

    local sort = Theme.CreateLabel(head, "small", "muted", "RIGHT")
    sort:SetPoint("RIGHT", -10, 0)
    sort:SetText(L.Format("Sort: %s", Colored("accent", L["Best first"])))
    self.sortLabel = sort
    self.sortArrow = SortArrow(head)
    self.sortArrow:SetPoint("LEFT", sort, "RIGHT", 4, 0)

    local worn = Theme.CreateLabel(head, "small", "muted")
    worn:SetPoint("LEFT", title, "RIGHT", 12, 0)
    worn:SetPoint("RIGHT", sort, "LEFT", -12, 0)
    -- A long name wraps onto a second line rather than being cut.
    worn:SetWordWrap(true)
    self.wornLabel = worn
end

function FinderUI:BuildHeader()
    local frame = self.frame

    -- The window's name is on the plate and the close gem on the top right
    -- corner (UI/Titanforged.lua), so the header holds the spec line, clear
    -- of the portrait on the left and a little low, under the plate.
    local header = CreateFrame("Frame", nil, frame)
    header:SetPoint("TOPLEFT", RIM, 0)
    header:SetPoint("TOPRIGHT", -RIM, 0)
    header:SetHeight(HEADER)

    -- Upgrade quest and Training, right to left, clear of the close gem.
    -- Dungeon Quests and Dungeon Loot are tabs under the window.
    -- Closes the upgrade quest, or brings it back with its quests as they
    -- were. Its label is green while the quest is up.
    local quest = Widgets.CreateButton(header, L["Upgrade quest"], function()
        if ns.UpgradeQuest then ns.UpgradeQuest:Toggle() end
    end, { width = 104, height = 20 })
    quest:SetPoint("RIGHT", -(PADDING + 16 - RIM), -4)
    quest:HookScript("OnEnter", function(self)
        local on = ns.UpgradeQuest and ns.UpgradeQuest:IsEnabled()
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L["Upgrade quest"], Theme.Unpack("accent"))
        GameTooltip:AddLine(on and L["Closes the upgrade quest. Your quests stay saved."]
            or L["Brings back the upgrade quest, with the steps to your next upgrade."], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    quest:HookScript("OnLeave", function() GameTooltip:Hide() end)
    self.questButton = quest

    -- Opens the Training drawer beside the window (UI/TrainingDrawer.lua):
    -- class spells to train and what they cost. It says how many wait.
    local training = Widgets.CreateButton(header, L["Training"], function()
        if ns.TrainingDrawer then ns.TrainingDrawer:Toggle() end
    end, { width = 80, height = 20 })
    training:SetPoint("RIGHT", quest, "LEFT", -6, 0)
    training:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L["Class training"], Theme.Unpack("accent"))
        GameTooltip:AddLine(L["Spells you can train, what they cost and where your trainer is."], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    training:HookScript("OnLeave", function() GameTooltip:Hide() end)
    self.trainingButton = training

    -- The gear window's module paints these (ns.UI).
    if ns.UI then
        ns.UI.questButton, ns.UI.trainingButton = quest, training
        ns.UI:OnUpgradeQuestToggled()
        ns.UI:OnTrainingToggled()
    end

    -- Judge Gear As: a drop-down past the portrait (card 20 of the unified
    -- look, 2026-10-29), the same choices and key as Settings > Gear. What
    -- the old spec line said (level, planning for) is its hover.
    local judge = Theme.CreateLabel(header, "small", "muted")
    judge:SetPoint("LEFT", 58 - RIM, -4)
    judge:SetText(L["Judge Gear As:"])
    self.judgeLabel = judge
    local spec = Widgets.CreateChoice(header, {
        min = 1, max = math.max(1, #FinderUI.SpecChoices()), step = 1, value = 1,
        format = function(index) return FinderUI.SpecText(index) end,
        onChange = function(index)
            local choices = FinderUI.SpecChoices()
            if ns.SettingsUI and ns.SettingsUI.SetSpec then
                ns.SettingsUI:SetSpec(choices[index] or "auto")
            end
        end,
    })
    spec:SetWidth(150)
    spec:SetPoint("LEFT", judge, "RIGHT", 8, 0)
    spec:HookScript("OnEnter", function(self)
        local text = FinderUI.specLabel and FinderUI.specLabel:GetText()
        if not text or text == "" then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(L["Judge Gear As:"], Theme.Unpack("accent"))
        GameTooltip:AddLine(text, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    spec:HookScript("OnLeave", function() GameTooltip:Hide() end)
    self.specChoice = spec

    -- What the old spec line said, kept for the drop-down's hover.
    local specLine = Theme.CreateLabel(header, "small", "muted")
    specLine:SetPoint("LEFT", spec, "RIGHT", 10, 0)
    specLine:Hide()
    self.specLabel = specLine

    -- Plan ahead: "Now", or a level up to MOST_AHEAD past the character's.
    -- A tool of the tab, so it sits with the buttons on the right.
    local ahead = Widgets.CreateChoice(header, {
        min = 0, max = MOST_AHEAD, step = 1, value = self:Ahead(),
        format = function(value) return FinderUI.AheadText(value) end,
        onChange = function(value)
            if ns.db then ns.db.finderAhead = value end
            FinderUI.offset = 0
            FinderUI:Refresh()
        end,
    })
    ahead:SetPoint("RIGHT", training, "LEFT", -10, 0)
    self.ahead = ahead

    -- A gold rule under it, bright at the left and fading out to the right.
    local rule = header:CreateTexture(nil, "ARTWORK")
    rule:SetPoint("BOTTOMLEFT")
    rule:SetPoint("BOTTOMRIGHT")
    rule:SetHeight(1)
    Theme.SetGradientAlpha(rule, "HORIZONTAL", "accent", 0.6, 0.05)
end

--- The spec keys this character can pick from, "auto" first (Settings'
--- list, so both drop-downs match).
function FinderUI.SpecChoices()
    if ns.SettingsUI and ns.SettingsUI.SpecChoices then return ns.SettingsUI:SpecChoices() end
    return { "auto" }, nil
end

--- A spec choice's words: "Auto", or the spec's name.
function FinderUI.SpecText(index)
    local choices, specs = FinderUI.SpecChoices()
    local key = choices[index]
    if key == "auto" or not key or not specs or not specs[key] then return L["Auto"] end
    return Weights.Label(specs[key].name)
end

--- The header's drop-down as the character's choice stands; its list
--- built again when the class's specs came in after the window was built.
function FinderUI:SyncSpec()
    local choice = self.specChoice
    if not choice then return end
    local choices = FinderUI.SpecChoices()
    local options = rawget(choice, "options")
    if type(options) == "table" and #options ~= #choices then
        for index = #options, 1, -1 do options[index] = nil end
        for index = 1, #choices do options[index] = { text = FinderUI.SpecText(index), value = index } end
    end
    local picked = ns.charDB and ns.charDB.spec
    local index = 1
    for i, key in ipairs(choices) do
        if key == picked then index = i end
    end
    choice:SetValue(index, true)
end

--- The filter row under the header (card 7 of the unified look): the
--- source chips, then the tick boxes, then Quest Level at the right. When
--- they don't all fit on one line (German runs longer), the tick boxes and
--- Quest Level take a second; one line gives the list that row.
function FinderUI:BuildFilters()
    -- A few pixels lower than the header's foot, clear of the round
    -- portrait above it.
    local topY = -(HEADER + 13)
    local frame = self.frame

    -- The sources, a chip each: any mix of them, saved as the ones turned
    -- off (`finderSourcesOff`), so a new kind shows until unticked.
    self.sourceBoxes = {}
    local x = PADDING
    for _, entry in ipairs(SOURCE_BOXES) do
        local kind = entry[1]
        local chip = Widgets.CreateChip(frame, entry[2], function(picked)
            FinderUI:SetSource(kind, not picked:IsSelected())
        end, { selected = self:SourceOn(kind), height = 20 })
        -- The tick boxes' names, so every caller reads a chip the same way.
        chip.kind = kind
        chip.GetChecked = chip.IsSelected
        chip.SetChecked = chip.SetSelected
        chip:SetPoint("TOPLEFT", x, topY - 3)
        x = x + (chip:GetWidth() or 60) + 4
        self.sourceBoxes[#self.sourceBoxes + 1] = chip
    end
    local chipsEnd = x + 14

    -- Leave out gear that waits on a reputation not reached yet, or on a
    -- craft nobody of yours can make yet.
    local now = Widgets.CreateCheckbox(frame, L["Only What I Can Get Now"], function(checked)
        FinderUI:SetGetNowOnly(checked)
    end, self:GetNowOnly())
    self.getNow = now

    -- Only gear from the zone the character is in, as the upgrade quest
    -- panel's box of the same name does (each keeps its own setting).
    local zone = Widgets.CreateCheckbox(frame, L["This Zone Only"], function(checked)
        FinderUI:SetZoneOnly(checked)
    end, self:ZoneOnly())
    zone:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(L["This Zone Only"], Theme.Unpack("accent"))
        GameTooltip:AddLine(L["Only upgrades from the zone you're in, plus gear you can make. The list changes as you travel."], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    zone:HookScript("OnLeave", function() GameTooltip:Hide() end)
    self.zone = zone

    -- Hide quests that need a group, a dungeon, a raid or a battleground.
    -- The same switch as in Settings.
    local solo = Widgets.CreateCheckbox(frame, L["Solo Quests Only"], function(checked)
        Finder:SetSoloOnly(checked)
    end, Finder:SoloOnly())
    solo:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(L["Solo Quests Only"], Theme.Unpack("accent"))
        GameTooltip:AddLine(L["Hides quests that need a group, and the quests after them. Elite kills count as group quests."],
            1, 1, 1, true)
        GameTooltip:Show()
    end)
    solo:HookScript("OnLeave", function() GameTooltip:Hide() end)
    self.solo = solo

    local questLevels = Widgets.CreateChoice(frame, {
        min = 0, max = Finder.QUEST_LEVELS_ANY, step = 1, value = self:QuestLevelsValue(),
        format = function(value) return FinderUI.QuestLevelsText(value) end,
        onChange = function(value) Finder:SetQuestLevelsAbove(value) end,
    })
    questLevels:SetWidth(150)
    questLevels:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(L["Quest Level:"], Theme.Unpack("accent"))
        GameTooltip:AddLine(L["How far above your level a quest can be."], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    questLevels:HookScript("OnLeave", function() GameTooltip:Hide() end)
    self.questLevels = questLevels

    local levelLabel = Theme.CreateLabel(frame, "small", "muted", "RIGHT")
    levelLabel:SetPoint("RIGHT", questLevels, "LEFT", -10, 0)
    levelLabel:SetText(L["Quest Level:"])
    self.levelLabel = levelLabel

    -- How wide each tick box is: its box and its words.
    local function Wide(box)
        local label = rawget(box, "label")
        local words = label and label.GetText and label:GetText() or ""
        return 24 + Theme.TextWidth("small", words)
    end
    local ticks = Wide(now) + 24 + Wide(zone) + 24 + Wide(solo)
    local levelWide = 150 + 10 + Theme.TextWidth("small", L["Quest Level:"]) + 18
    local room = WIDTH - PADDING * 2
    self.filterRows = (chipsEnd - PADDING) + ticks + levelWide <= room and 1 or 2

    local rowY = self.filterRows == 1 and topY or -(HEADER + 13 + FILTERS + 1)
    local tickX = self.filterRows == 1 and chipsEnd or PADDING
    now:SetPoint("TOPLEFT", tickX, rowY - 1)
    zone:SetPoint("LEFT", now, "RIGHT", 24, 0)
    solo:SetPoint("LEFT", zone, "RIGHT", 24, 0)
    questLevels:SetPoint("TOPRIGHT", -PADDING, rowY)
end

--- Is "Only what I can get now" ticked? Saved account wide as
--- `finderGetNow`, off unless ticked.
function FinderUI:GetNowOnly()
    return ns.db ~= nil and ns.db.finderGetNow == true
end

function FinderUI:SetGetNowOnly(on)
    if not ns.db then return end
    ns.db.finderGetNow = on and true or false
    if self.getNow then self.getNow:SetChecked(ns.db.finderGetNow) end
    self.offset = 0
    self:Redraw()
end

--- Can this source be used now? Not for gear that waits on a reputation
--- not reached, nor a craft that you or your other characters can't make
--- yet (one still to learn, or someone else's).
function FinderUI.GetsNow(source, pick)
    if pick.needs then return false end
    if source.kind == "craft" then return source.state == "known" or source.state == "alt" end
    return true
end

--- The tick box a source counts under: "raid" for a raid's drop, else its
--- kind.
function FinderUI.SourceKind(source)
    if source.kind == "dungeon" and source.raid then return "raid" end
    return source.kind
end

--- Is this kind of source ticked? Every kind is until unticked.
function FinderUI:SourceOn(kind)
    local off = ns.db and ns.db.finderSourcesOff
    return not (type(off) == "table" and off[kind] == true)
end

function FinderUI:SetSource(kind, on)
    if not ns.db then return end
    if type(ns.db.finderSourcesOff) ~= "table" then ns.db.finderSourcesOff = {} end
    ns.db.finderSourcesOff[kind] = (not on) or nil
    for _, box in ipairs(self.sourceBoxes or {}) do
        if box.kind == kind then box:SetChecked(on) end
    end
    self.offset = 0
    self:Redraw()
end

--- Draw again from the last scan, for a change that needs no new look (a
--- tick box, a slot): the scan holds every source, so only the lines move.
function FinderUI:Redraw()
    if not (self.frame and self.frame:IsShown()) then return end
    if self:ShowingEnchants() or not self.found then
        self:Refresh()
    else
        self:Present(self.found)
    end
end

--- Is "This zone only" ticked? Saved account wide as `finderZoneOnly`,
--- off unless ticked.
function FinderUI:ZoneOnly()
    return ns.db ~= nil and ns.db.finderZoneOnly == true
end

function FinderUI:SetZoneOnly(on)
    if not ns.db then return end
    ns.db.finderZoneOnly = on and true or false
    if self.zone then self.zone:SetChecked(ns.db.finderZoneOnly) end
    self.offset = 0
    self:Refresh()
end

--- The zone the list keeps to, or nil for anywhere.
function FinderUI:Here(found)
    if not self:ZoneOnly() then return nil end
    local quest = ns.UpgradeQuest
    return quest and quest.Zone() or (found and found.player and found.player.zone) or nil
end

--- "Solo quests only" changed, here or in Settings.
function FinderUI:OnQuestFilterChanged()
    if self.solo then self.solo:SetChecked(Finder:SoloOnly()) end
    if self.questLevels then self.questLevels:SetValue(self:QuestLevelsValue(), true) end
    self.offset = 0
    self:Refresh()
end

--- The quest level stepper's place: 0 to 10 levels up, or 11 for any.
function FinderUI:QuestLevelsValue()
    return Finder:QuestLevelsAbove() or Finder.QUEST_LEVELS_ANY
end

--- Its words: "Up to my level", "Up to +4" or "Any".
function FinderUI.QuestLevelsText(value)
    if (value or 0) >= Finder.QUEST_LEVELS_ANY then return L["Any"] end
    if (value or 0) <= 0 then return L["Up to my level"] end
    return L.Format("Up to +%d", value)
end

--- How many levels ahead the window looks (0 for now).
function FinderUI:Ahead()
    local value = tonumber(ns.db and ns.db.finderAhead) or 0
    return math.max(0, math.min(MOST_AHEAD, math.floor(value)))
end

--- The stepper's words: "Now", or "Level 27".
function FinderUI.AheadText(value)
    if (value or 0) <= 0 then return L["Now"] end
    local level = ns.Items and ns.Items:PlayerLevel()
    if not level then return L.Format("+%d levels", value) end
    return L.Format("Level %d", math.min(60, level + value))
end

--- Where a pick's first source with an exact spot is, for the map.
function FinderUI.Place(pick)
    for _, source in ipairs(pick and pick.sources or {}) do
        if source.zone and source.x and source.y then return source end
    end
    return nil
end

--------------------------------------------------------------------------------
-- Filling it in
--------------------------------------------------------------------------------

--- The view showing: "enchant", or nil for gear. An older saved choice of
--- one source ("vendor" and the like) reads as gear: the tick boxes have
--- taken its place.
function FinderUI:Filter()
    if ns.db and ns.db.finderShow == "enchant" then return "enchant" end
    return nil
end

--- Is the Enchants view showing? It lists enchants for what you wear, not
--- gear, so it has no scan, no stepper and no quest filters.
function FinderUI:ShowingEnchants()
    return self:Filter() == "enchant"
end

--- Show enchants ("enchant") or gear (nil).
function FinderUI:SetFilter(kind)
    if ns.db then ns.db.finderShow = kind == "enchant" and "enchant" or "all" end
    self.offset = 0
    self:Refresh()
end

--- Each slot's lines, by the key of its line on the left (SLOT_GROUPS):
--- `{ lines, total }`, `total` every upgrade found for it and `lines` those
--- with a source the tick boxes, "Only what I can get now" and "This zone
--- only" let through, best first. Every pick, not only the few best: the
--- list for one slot runs as long as it needs.
function FinderUI:Groups(found)
    local groups = {}
    local here = self:Here(found)
    local inZone = ns.UpgradeQuest and ns.UpgradeQuest.InZone
    local getNow = self:GetNowOnly()
    local on = {}
    for _, entry in ipairs(SOURCE_BOXES) do on[entry[1]] = self:SourceOn(entry[1]) end
    local all = type(found.all) == "table" and found.all or found.slots or {}
    -- Better gear you own already: in your bags, your bank or on another
    -- of your characters (UI:ReadBags).
    local ownedBySlot = ns.UI and ns.UI.ReadBags and ns.UI:ReadBags() or {}
    for _, group in ipairs(SLOT_GROUPS) do
        -- Both rings, or both trinkets, as one list: each item once.
        local picks, seen = {}, {}
        for _, slot in ipairs({ group[1], group[3] }) do
            for _, pick in ipairs(all[slot] or {}) do
                if not seen[pick.itemID] then
                    seen[pick.itemID] = true
                    picks[#picks + 1] = pick
                end
            end
        end
        if group[3] then table.sort(picks, Finder.Order) end
        local lines = {}
        for _, pick in ipairs(picks) do
            local sources = {}
            for _, source in ipairs(pick.sources or {}) do
                local kind = FinderUI.SourceKind(source)
                if on[kind] ~= false and (not getNow or FinderUI.GetsNow(source, pick))
                    and (not here or not inZone or inZone(source, here)) then
                    sources[#sources + 1] = source
                end
            end
            if #sources > 0 then lines[#lines + 1] = { pick = pick, sources = sources } end
        end
        local owned, links = {}, {}
        for _, slot in ipairs({ group[1], group[3] }) do
            for _, entry in ipairs(ownedBySlot[slot] or {}) do
                if not links[entry.link] then
                    links[entry.link] = true
                    owned[#owned + 1] = entry
                end
            end
        end
        groups[group[1]] = { lines = lines, total = #picks, owned = owned }
    end
    return groups
end

--- The slot to show: the one clicked this time the window is open, else the
--- one last clicked while it has something, else the first that does.
function FinderUI:ChooseSlot(groups)
    local saved = tonumber(ns.db and ns.db.finderSlot)
    if saved and GROUP_OF[saved] ~= saved then saved = nil end
    local slot = self.slot or saved
    local function Has(key)
        local group = groups[key]
        return group and (#group.lines > 0 or (group.owned and #group.owned > 0))
    end
    if not self.slotChosen and not (slot and Has(slot)) then
        for _, group in ipairs(SLOT_GROUPS) do
            if Has(group[1]) then
                slot = group[1]
                break
            end
        end
    end
    self.slot = slot or SLOT_GROUPS[1][1]
    return self.slot
end

--- A click on a slot down the left: show its list, and keep it for next time.
function FinderUI:PickSlot(key)
    if GROUP_OF[key] ~= key then return end
    self.slot = key
    self.slotChosen = true
    if ns.db then ns.db.finderSlot = key end
    self.offset = 0
    self:Redraw()
end

--- An item's name in its rarity colour, from its link: plain text, so it
--- can be cut to fit.
function FinderUI.ItemText(link)
    if type(link) ~= "string" then return "" end
    local name = link:match("%[(.-)%]") or link
    local color = link:match("|c(%x%x%x%x%x%x%x%x)")
    return color and ("|c" .. color .. name .. "|r") or name
end

--- Can a click put this owned piece on? Only one in the bags, and never
--- a weapon whose skill is not trained yet.
function FinderUI.CanPutOn(owned)
    return type(owned) == "table" and owned.where == "bags"
        and not (owned.result and owned.result.skill)
end

--- What a slot's line says you wear: one name, or both rings or trinkets,
--- each on its own line and cut to fit.
function FinderUI:PaintWorn(button)
    local slots = { button.group }
    for _, group in ipairs(SLOT_GROUPS) do
        if group[1] == button.group and group[3] then slots[2] = group[3] end
    end
    local Items = ns.Items
    local texts, first = {}, nil
    for _, slot in ipairs(slots) do
        local link = Items and Items:Equipped(slot)
        if link then
            first = first or link
            local text = FinderUI.ItemText(link)
            texts[#texts + 1] = #slots > 1 and FinderUI.Fit("tiny", text, WORN_WIDTH) or text
        end
    end
    button.wornLink = first or false
    Theme.SetItemIcon(button.wornIcon, first)
    button.worn:SetText(#texts > 0 and table.concat(texts, "\n") or "-")
end

--- The slots' counts, what is worn in each and which is picked. `groups`
--- nil blanks the counts.
function FinderUI:PaintSlots(groups)
    for _, button in ipairs(self.slotButtons or {}) do
        local group = groups and groups[button.group]
        button.count:SetText(tostring(group and ((group.owned and #group.owned or 0) + #group.lines) or 0))
        self:PaintWorn(button)
        self:PaintSlot(button)
    end
end

--- The list's heading: the slot's name and what is worn there.
function FinderUI:SetListHead(lines)
    local name, slot = "", self.slot
    for _, group in ipairs(SLOT_GROUPS) do
        if group[1] == slot then name = group[2] end
    end
    self.listTitle:SetText(name)
    -- For rings and trinkets, the one the best pick would replace.
    local first = lines and lines[1]
    local pick = first and (first.pick or (first.enchant and { result = { slot = first.enchant.slot } }))
    local wornSlot = pick and pick.result and pick.result.slot or slot
    local link = slot and ns.Items and ns.Items:Equipped(wornSlot)
    if link then
        self.wornLabel:SetText(L.Format("You wear: %s", ns.Items.ShowLink(link)))
    else
        self.wornLabel:SetText("")
    end
    self.sortLabel:SetShown(not self:ShowingEnchants())
    self:PaintHeadings()
end

local function Gain(result)
    if result.empty then return L["empty slot"] end
    if result.percent then return ("%+d%%"):format(math.floor(result.percent + 0.5)) end
    return L["better"]
end

--- How tall a label's text runs, wrapped at its width: the client's own
--- answer, else a measure of its words.
local function TextHeight(label, size)
    local text = label:GetText() or ""
    if text == "" then return 0 end
    local ok, height = pcall(label.GetStringHeight, label)
    if ok and type(height) == "number" and height > 0 then return height end
    local width = math.max(1, label:GetWidth() or 1)
    local lines = math.max(1, math.ceil(Theme.TextWidth(size, text) / width))
    return lines * ((Theme.sizes[size] or 10) + 2)
end

--- Grow a filled row to show its lines in full: the name and the line under
--- it, the Where column, and the gain with Queue it under it.
function FinderUI:FitRow(row, gear)
    -- Gear rows are one line; the detail is on the hover. Enchant rows keep
    -- the line under the name: it is how to get the enchant.
    local under = row.source:IsShown() and (3 + TextHeight(row.source, "tiny")) or 0
    local height = LINE_TOP + TextHeight(row.item, "normal") + under + 8
    if gear then height = math.max(height, LINE_TOP + 1 + TextHeight(row.where, "small") + 8) end
    local buttons = row.queueIt:IsShown() or row.showWay:IsShown()
    height = math.max(height, LINE_TOP + TextHeight(row.gain, "normal") + (buttons and (4 + 18 + 5) or 8))
    height = math.max(ROW_HEIGHT, math.ceil(height))
    row:SetHeight(height)
    return height
end

--- The level a pick can be worn from: the level it waits for, else the
--- client's, else the data's. Nil when it asks for none.
function FinderUI.LevelOf(pick)
    if pick.at then return pick.at end
    local info = (_G.C_Item and _G.C_Item.GetItemInfo) or _G.GetItemInfo
    if type(info) == "function" then
        local ok, _, _, _, _, level = pcall(info, pick.link or pick.itemID)
        if ok and tonumber(level) and level > 0 then return level end
    end
    local item = ns.Sources and ns.Sources.ITEMS and ns.Sources.ITEMS[pick.itemID]
    if item and tonumber(item[1]) and item[1] > 0 then return item[1] end
    local craft = ns.Crafts and ns.Crafts.ITEMS and ns.Crafts.ITEMS[pick.itemID]
    if craft and tonumber(craft[4]) and craft[4] > 0 then return craft[4] end
    return nil
end

--- Where a line's first source is: the dungeon for a drop, the profession
--- for a craft, else the zone. Nil when it has no place.
function FinderUI.WhereOf(line)
    local source = line.sources and line.sources[1]
    if not source then return nil end
    -- In the game's own words (Logic/Names.lua).
    local names = ns.Names
    if source.kind == "dungeon" then
        local where = source.dungeon or source.zone
        return names and names:Zone(where) or where
    end
    if source.kind == "craft" then
        return names and names:Profession(source.profession) or source.profession
    end
    return names and names:Zone(source.zone) or source.zone
end

--- A pick's name, for sorting.
function FinderUI.ItemName(pick)
    local name = type(pick.link) == "string" and pick.link:match("%[(.-)%]")
    if not name then
        local info = (_G.C_Item and _G.C_Item.GetItemNameByID) or nil
        local ok, found = pcall(function() return info and info(pick.itemID) end)
        name = ok and found or nil
    end
    return name or tostring(pick.link or pick.itemID or "")
end

--- What a line sorts by under a heading: nil sorts last.
function FinderUI.SortValue(line, key)
    local pick = line.pick
    if key == "item" then return FinderUI.ItemName(pick):lower() end
    if key == "level" then return FinderUI.LevelOf(pick) end
    if key == "where" then
        local where = FinderUI.WhereOf(line)
        return where and where:lower() or nil
    end
    if key == "gain" then
        if pick.result and pick.result.empty then return math.huge end
        return pick.result and Finder.Shown(pick.result) or nil
    end
    return nil
end

--- `lines` sorted by a heading (`key` "item", "level", "where" or "gain"),
--- the order flipped when `flip`; best first when `key` is nil. A new table:
--- the slot's own list keeps its best-first order.
function FinderUI.SortLines(lines, key, flip)
    if not key then return lines end
    local keyed = {}
    for index, line in ipairs(lines) do
        keyed[index] = { line = line, index = index, value = FinderUI.SortValue(line, key) }
    end
    table.sort(keyed, function(a, b)
        local va, vb = a.value, b.value
        if va ~= vb then
            if va == nil then return false end
            if vb == nil then return true end
            -- The biggest gain first; names, levels and places A to Z, low to high.
            if key == "gain" then return va > vb end
            return va < vb
        end
        return a.index < b.index
    end)
    local sorted = {}
    for index, entry in ipairs(keyed) do sorted[index] = entry.line end
    if flip then
        local flipped = {}
        for index = #sorted, 1, -1 do flipped[#flipped + 1] = sorted[index] end
        sorted = flipped
    end
    return sorted
end

--- Fill a row with a line, or hide it for none.
-- @return the row's height, 0 for none
function FinderUI:FillRow(row, line)
    row.enchant = nil
    row.heading, row.owned = false, false
    row.showWay:Hide()
    row.putOn:Hide()
    row.putOn.owned = nil
    row.headingLabel:Hide()
    row.queueIt.enchant = nil
    if not line then
        row.pick = nil
        row:Hide()
        return 0
    end
    row.background:SetColorTexture(Theme.Unpack(row.restKey))
    if line.heading then return self:FillHeadingRow(row, line.heading) end
    if line.owned then return self:FillOwnedRow(row, line.owned) end
    if line.enchant then return self:FillEnchantRow(row, line.enchant) end

    row.pick = {
        link = line.pick.link, sources = line.sources, itemID = line.pick.itemID,
        needs = line.pick.needs, result = line.pick.result, roll = line.pick.roll, at = line.pick.at,
        gain = line.pick.gain,
    }
    Theme.SetItemIcon(row.icon, line.pick.link)
    row.item:SetWidth(ITEM_WIDTH)
    local gain = Gain(line.pick.result)
    -- A weapon whose skill is not learned yet says "Train" in red, so the
    -- weapon master comes first (a player asked, 2026-10-10).
    local train = ns.WeaponSkills and ns.WeaponSkills:NeedsTraining(line.pick.link)
    if train and line.pick.at then
        gain = L.Format("at %d, Train: %s", line.pick.at, gain)
    elseif train then
        gain = L.Format("Train: %s", gain)
    elseif line.pick.at then
        gain = L.Format("at %d: %s", line.pick.at, gain)
    end
    -- A long gain ("at 23, Train: empty slot") wraps in its column.
    row.gain:SetWidth(GAIN_WIDTH)
    row.gain:SetText(gain)
    -- Gear that waits on a reputation, a level or a crafter is shown in
    -- amber, not green; gear that waits on a weapon trainer in red.
    row.edgeKey = (line.pick.needs or line.pick.at or line.pick.remote) and "warn" or "good"
    row.gain:SetTextColor(Theme.Unpack(train and "loss" or row.edgeKey))

    local level = FinderUI.LevelOf(line.pick)
    row.level:SetText(level and tostring(level) or "")
    row.level:Show()
    local where = FinderUI.WhereOf(line)
    row.where:SetText(where and FinderUI.MarkZone(where, ns.UpgradeQuest and ns.UpgradeQuest.Zone()) or "")
    row.where:Show()

    -- One line a row (the house rule, 2026-10-29): where to get it is on
    -- the hover; only the small tags stay, after the name.
    local name = ns.Items.ShowLink(line.pick.link)
    if ns.UpgradeQuest and ns.UpgradeQuest:IsFollowing(line.pick.itemID) then
        name = name .. "  " .. Colored("good", L["Following"])
    end
    if ns.Tracking and ns.Tracking:IsTracked(line.pick.itemID) then
        name = name .. "  " .. Colored("accent", L["Tracking"])
    end
    row.item:SetText(name)
    local text = FinderUI.SourceLine(line.sources[1])
    if line.pick.needs then
        text = Colored("warn", L.Format("Needs %s with %s", line.pick.needs.standing,
            line.pick.needs.faction)) .. "  " .. text
    end
    -- Queue it on crafted gear, under the gain.
    local craft = ns.TradeskillsQueue and ns.TradeskillsQueue:Available()
        and ns.TradeskillsQueue.CraftSource(line.sources) or nil
    row.queueIt.source = craft
    if craft then
        row.queueIt:SetText(ns.TradeskillsQueue:Label(craft.itemID))
        row.queueIt:Show()
    else
        row.queueIt:Hide()
    end
    row.sourceWidth = ITEM_WIDTH
    row.source:SetWidth(row.sourceWidth)

    -- Kept for the hover's first line, never drawn on the row.
    local more = #line.sources - 1
    local tail = more > 0 and L.Format("  +%d more", more) or ""
    row.source:SetText(text .. Colored("dim", tail))
    row.source:Hide()
    row:Show()
    return self:FitRow(row, true)
end

--- A heading across the list: IN YOUR BAGS, or TO GO AND GET.
-- @return the row's height
function FinderUI:FillHeadingRow(row, text)
    row.pick = nil
    row.heading = true
    Theme.SetItemIcon(row.icon, nil)
    for _, label in ipairs({ row.item, row.gain, row.level, row.where, row.source }) do label:SetText("") end
    row.queueIt:Hide()
    row.headingLabel:SetText(text)
    row.headingLabel:Show()
    row:SetHeight(HEADING_ROW)
    row:Show()
    return HEADING_ROW
end

--- Where a piece you own is, in a few words.
function FinderUI.OwnedWhere(where)
    if where == "bags" then return L["Your bags"] end
    if where == "bank" then return L["Your bank"] end
    local name = ns.Alts and ns.Alts:NameOf(where) or nil
    return L.Format("On %s", name or L["another of your characters"])
end

--- A piece you own that beats what you wear: in your bags with Put it on,
--- or in your bank or on another character.
-- @return the row's height
function FinderUI:FillOwnedRow(row, owned)
    row.pick = nil
    row.owned = owned
    Theme.SetItemIcon(row.icon, owned.link)
    row.item:SetWidth(ITEM_WIDTH)
    row.item:SetText(ns.Items.ShowLink(owned.link))
    local result = owned.result or {}
    local gain = Gain(result)
    if result.skill then gain = L.Format("Train: %s", gain) end
    row.gain:SetWidth(GAIN_WIDTH)
    row.gain:SetText(gain)
    row.edgeKey = "good"
    row.gain:SetTextColor(Theme.Unpack(result.skill and "loss" or "good"))
    local level = FinderUI.LevelOf({ link = owned.link })
    row.level:SetText(level and tostring(level) or "")
    row.level:Show()
    row.where:SetText(FinderUI.OwnedWhere(owned.where))
    row.where:Show()
    row.queueIt:Hide()
    row.sourceWidth = ITEM_WIDTH
    row.source:SetWidth(ITEM_WIDTH)
    local canPutOn = FinderUI.CanPutOn(owned)
    -- What a click does and where it is are on the hover.
    row.source:SetText("")
    row.source:Hide()
    row.putOn.owned = owned
    row.putOn:SetShown(canPutOn)
    row:Show()
    local height = self:FitRow(row, true)
    if canPutOn then
        height = math.max(height, LINE_TOP + TextHeight(row.gain, "normal") + 4 + 20 + 5)
        row:SetHeight(height)
    end
    return height
end

--- One row of the Enchants view: the slot, the piece you wear, the enchant
--- to get, how much better, and how to get it.
-- @return the row's height
function FinderUI:FillEnchantRow(row, line)
    local Enchants = ns.Enchants
    local pick, source = line.pick, line.source
    row.pick = nil
    row.enchant = line
    row.level:Hide()
    row.where:Hide()
    Theme.SetItemIcon(row.icon, line.plan.link)
    row.item:SetWidth(row.fullSourceWidth - GAIN_WIDTH - 8)
    row.item:SetText(Enchants:ShownName(pick.recipeID) or "")

    local gain = pick.percent and ("%+d%%"):format(math.floor(pick.percent + 0.5)) or L["better"]
    row.gain:SetWidth(GAIN_WIDTH)
    row.gain:SetText(gain)
    -- Amber while it needs more skill or someone else to make it.
    local state = source and source.state
    row.edgeKey = (state == "skill" or state == "other") and "warn" or "good"
    row.gain:SetTextColor(Theme.Unpack(row.edgeKey))

    local text = Enchants:Describe(source, Finder.Money)
    local now = line.plan.current and Enchants:EnchantName(line.plan.current) or nil
    text = text .. "  " .. (now and L.Format("Now: %s", now) or L["Nothing on it now"])
    if line.soon then
        text = Colored("warn", L["A better piece is coming, so this is a cheap one"]) .. "  " .. text
    end

    -- Queue it and Show the way, right to left, with the line kept clear.
    local used = 0
    if Enchants:CanQueue() then
        row.queueIt.enchant = line
        row.queueIt:SetText(L["Queue It"])
        row.queueIt:Show()
        used = math.max(QUEUE_WIDTH, row.queueIt:GetWidth() or 0) + 8
    else
        row.queueIt:Hide()
    end
    row.queueIt.source = nil
    if (state == "learn" or state == "skill") and Enchants:CanShowTheWay(pick.recipeID) then
        row.showWay:ClearAllPoints()
        if used > 0 then
            row.showWay:SetPoint("RIGHT", row.queueIt, "LEFT", -6, 0)
        else
            row.showWay:SetPoint("BOTTOMRIGHT", -GAIN_RIGHT, 5)
        end
        row.showWay.enchant = line
        row.showWay:Show()
        used = used + (row.showWay:GetWidth() or QUEUE_WIDTH) + 6
    end
    row.sourceWidth = row.fullSourceWidth - used
    row.source:SetWidth(row.sourceWidth)
    row.source:SetText(text)
    row.source:Show()
    row:Show()
    return self:FitRow(row, false)
end

--- The furthest the list scrolls: the first line from which every line
--- left fits. Measured on a row kept out of sight, once per list.
function FinderUI:MostOffset()
    local lines = self.lines or {}
    if self.mostFor == lines then return self.most end
    local used, index = 0, #lines
    while index >= 1 do
        local height = self:FillRow(self.measureRow, lines[index])
        if used + height > (self.area or AREA) then break end
        used = used + height
        index = index - 1
    end
    self.measureRow:Hide()
    self.mostFor, self.most = lines, math.max(0, math.min(index, #lines - 1))
    return self.most
end

function FinderUI:ScrollBy(steps)
    local most = self:MostOffset()
    self.offset = math.max(0, math.min(most, (self.offset or 0) + steps))
    self:Draw()
end

--- Draw the list from `offset` on: each row as tall as its lines, stacked
--- until the list is full. A row that would run past the foot waits for a
--- scroll.
function FinderUI:Draw()
    local lines = self.lines or {}
    local offset = self.offset or 0
    local used, shown, full = 0, 0, false
    for index, row in ipairs(self.rows) do
        local line = not full and lines[offset + index] or nil
        local height = self:FillRow(row, line)
        if line and index > 1 and used + height > (self.area or AREA) then
            row.pick, row.enchant = nil, nil
            row:Hide()
            full = true
        elseif line then
            row:SetPoint("TOPLEFT", LIST_X, self.rowsTop - used)
            used = used + height
            shown = shown + 1
        end
        -- Scrolled under a still mouse: the tooltip follows the new item.
        if rawget(row, "over") == true then
            if row:IsShown() and (rawget(row, "pick") or rawget(row, "enchant") or rawget(row, "owned")) then
                ShowTooltip(row)
            else
                GameTooltip:Hide()
            end
        end
    end
    self.shownCount = shown

    -- The thumb only shows when there is more than fits.
    local total = #lines
    local most = self:MostOffset()
    if most > 0 then
        local area = self.area or AREA
        local size = math.max(16, area * shown / math.max(1, total))
        local top = (area - size) * math.min(1, offset / most)
        self.thumb:SetHeight(size)
        self.thumb:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", -PADDING, self.rowsTop - top)
        self.thumb:Show()
        self.track:Show()
    else
        self.thumb:Hide()
        self.track:Hide()
    end
end


--- Look again and redraw, at once: for opening the window and for clicks.
-- @return the scan, or nil when there was nothing to look with
function FinderUI:Refresh()
    if not (self.frame and self.frame:IsShown()) then return nil end
    -- A slower scan still under way would only draw something older.
    Finder.sliced = nil
    if self:ShowingEnchants() then return self:PresentEnchants() end
    return self:Present(Finder:Scan(nil, self:Ahead()))
end

--- Look again a slice per frame and redraw once done, keeping what shows
--- meanwhile: for the events that come in bursts while the window is open.
function FinderUI:RefreshInBackground()
    if not (self.frame and self.frame:IsShown()) then return end
    -- Enchants are kept by Logic/Enchants.lua: drawing them is cheap.
    if self:ShowingEnchants() then
        self:PresentEnchants()
        return
    end
    local ahead = self:Ahead()
    Finder:ScanSliced(nil, ahead, function(found, why)
        -- The window closed, or the view or the stepper moved, meanwhile.
        if not (FinderUI.frame and FinderUI.frame:IsShown()) then return end
        if FinderUI:ShowingEnchants() or FinderUI:Ahead() ~= ahead then return end
        FinderUI:Present(found, why)
    end)
end

--- The tab lit for the view showing, and the controls only gear uses.
function FinderUI:MarkFilters()
    local enchants = self:ShowingEnchants()
    if self.tabStrip then self.tabStrip:Select(enchants and "enchant" or "upgrades") end
    if self.summary then self.summary:SetShown(not enchants) end
    local gear = not enchants
    local controls = { self.getNow, self.ahead, self.levelLabel, self.questLevels, self.solo, self.zone }
    for _, box in ipairs(self.sourceBoxes) do controls[#controls + 1] = box end
    for _, heading in ipairs(self.columnHeads or {}) do controls[#controls + 1] = heading end
    for _, control in ipairs(controls) do control:SetShown(gear) end
end

--- Every source ticked again and "Only What I Can Get Now" off: the empty
--- block's Show All.
function FinderUI:ShowAll()
    if not ns.db then return end
    ns.db.finderSourcesOff = nil
    for _, box in ipairs(self.sourceBoxes or {}) do box:SetChecked(true) end
    self:SetGetNowOnly(false)
end

--- The filters' note after the summary, on the same line, or alone.
function FinderUI:PlaceFooter()
    local footer, summary = self.footer, self.summary
    footer:ClearAllPoints()
    local text = summary:IsShown() and summary:GetText() or ""
    if type(text) == "string" and text ~= "" then
        footer:SetPoint("LEFT", summary, "RIGHT", 12, 0)
    else
        footer:SetPoint("BOTTOMLEFT", PADDING, 12)
    end
end

--- Draw a scan.
function FinderUI:Present(found, why)
    self:MarkFilters()

    if not found then
        self.lines, self.groups = {}, nil
        self:Draw()
        self:PaintSlots(nil)
        self:SetListHead(nil)
        if why == "noweights" then
            self.empty:SetText(L.Format("There are no stat weights for %s yet.",
                Weights:PlayerClass() or L["this class"]))
        else
            self.empty:SetText(L["Your level and faction aren't known yet. Try again in a moment."])
        end
        self.empty:Show()
        self.footer:SetText("")
        self.summary:SetText("")
        self:PlaceFooter()
        self.specLabel:SetText("")
        return nil
    end

    local spec, _, class = Weights:CurrentSpec()
    local specName = spec and Weights:SpecName(class, spec) or ""
    if found.reach > found.player.level then
        self.specLabel:SetText(L.Format("Judging gear as %s, level %d, planning for %d", specName, found.player.level, found.reach))
    else
        self.specLabel:SetText(L.Format("Judging gear as %s, level %d", specName, found.player.level))
    end
    if self.ahead then self.ahead:SetValue(self:Ahead(), true) end
    self:SyncSpec()

    local groups = self:Groups(found)
    self.groups = groups
    local group = groups[self:ChooseSlot(groups)]
    -- What you own first, under IN YOUR BAGS, then TO GO AND GET.
    local gear = FinderUI.SortLines(group.lines, self.sortKey, self.sortFlip)
    local lines = {}
    if group.owned and #group.owned > 0 then
        lines[1] = { heading = L["IN YOUR BAGS"] }
        for _, entry in ipairs(group.owned) do lines[#lines + 1] = { owned = entry } end
        if #gear > 0 then lines[#lines + 1] = { heading = L["TO GO AND GET"] } end
    end
    for _, line in ipairs(gear) do lines[#lines + 1] = line end
    self.lines = lines
    self.mostFor = nil
    self.offset = math.min(self.offset or 0, self:MostOffset())
    self:Draw()
    self:PaintSlots(groups)
    self:SetListHead(self.lines)

    local shown = #gear
    if #self.lines == 0 then
        local here = self:Here(found)
        if ns.Alts and ns.Alts:PlayerSkipped() then
            self.empty:SetText(L["Upgrades are skipped for this character. Untick it in Settings, or type /beq skip off."])
        elseif found.count == 0 and found.waiting > 0 then
            self.empty:SetText(L["Asking the server about the gear on offer..."])
        elseif here then
            self.empty:Set(L.Format("Nothing in %s beats what you wear.", here), L["Show All"], function()
                FinderUI:SetZoneOnly(false)
            end)
        elseif (group.total or 0) > 0 then
            local hiding = group.total or 0
            self.empty:Set(hiding == 1 and L["Your filters hide 1 more."]
                or L.Format("Your filters hide %d more.", hiding), L["Show All"], function()
                FinderUI:ShowAll()
            end)
        else
            self.empty:SetText(L["Nothing on offer beats what you wear right now."])
        end
        self.empty:Show()
    else
        self.empty:Hide()
    end

    -- Only when the tick boxes hide some: how many more there are.
    local hidden = math.max(0, (group.total or 0) - shown)
    local text = hidden == 1 and L["Your filters hide 1 more."]
        or hidden > 1 and L.Format("Your filters hide %d more.", hidden) or ""
    if found.waiting > 0 then
        local asking = L.Format("  Still asking the server about %d items.", found.waiting):gsub("^%s+", "")
        text = text ~= "" and (text .. "  " .. Colored("muted", asking)) or Colored("muted", asking)
    end
    self.footer:SetText(text)

    -- How many upgrades in all, every slot: in your bags, to go and get.
    local inBags, toGet = 0, 0
    for _, entry in pairs(groups) do
        for _, owned in ipairs(entry.owned or {}) do
            if owned.where == "bags" then inBags = inBags + 1 end
        end
        toGet = toGet + #entry.lines
    end
    local parts = {}
    if inBags == 1 then parts[#parts + 1] = L["1 upgrade in your bags."]
    elseif inBags > 1 then parts[#parts + 1] = L.Format("%d upgrades in your bags.", inBags) end
    if toGet == 1 then parts[#parts + 1] = L["1 upgrade you can go and get."]
    elseif toGet > 1 then parts[#parts + 1] = L.Format("%d upgrades you can go and get.", toGet) end
    self.summary:SetText(table.concat(parts, " "))
    self:PlaceFooter()

    self.found = found
    return found
end

--- Draw the Enchants view: for the slot picked, the enchant that would make
--- the piece worn there better (Logic/Enchants.lua). The slots down the
--- left count 1 where one would.
function FinderUI:PresentEnchants()
    self:MarkFilters()
    local Enchants = ns.Enchants
    local plans = Enchants and Enchants:Plans()

    local spec, _, class = Weights:CurrentSpec()
    local specName = spec and Weights:SpecName(class, spec) or ""
    local level = ns.Items and ns.Items:PlayerLevel()
    self.specLabel:SetText(level and L.Format("Judging gear as %s, level %d", specName, level) or specName)
    self:SyncSpec()

    local groups, count = {}, 0
    for _, group in ipairs(SLOT_GROUPS) do groups[group[1]] = { lines = {}, total = 0 } end
    if plans then
        for _, line in ipairs(Enchants:Lines()) do
            local group = groups[GROUP_OF[line.slot] or -1]
            if group then
                group.lines[#group.lines + 1] = { enchant = line }
                group.total = group.total + 1
                count = count + 1
            end
        end
    end
    self.groups = groups
    self.lines = groups[self:ChooseSlot(groups)].lines
    self.mostFor = nil
    self.offset = math.min(self.offset or 0, self:MostOffset())
    self:Draw()
    self:PaintSlots(groups)
    self:SetListHead(self.lines)

    if #self.lines == 0 then
        if not plans then
            self.empty:SetText(L.Format("There are no stat weights for %s yet.",
                Weights:PlayerClass() or L["this class"]))
        elseif Enchants.missing then
            self.empty:SetText(L["Asking the server about the gear you wear..."])
        else
            self.empty:SetText(L["No enchant beats what's on your gear now."])
        end
        self.empty:Show()
    else
        self.empty:Hide()
    end

    if count == 1 then
        self.footer:SetText(L["1 piece you wear could use a better enchant."])
    elseif count > 1 then
        self.footer:SetText(L.Format("%d pieces you wear could use a better enchant.", count))
    else
        self.footer:SetText("")
    end
    self:PlaceFooter()
    self.found = nil
    return self.lines
end

--- Look again once a burst of events settles.
function FinderUI:RefreshSoon()
    if not (self.frame and self.frame:IsShown()) or self.pending then return end
    self.pending = true
    if C_Timer and C_Timer.After then
        C_Timer.After(0.5, function()
            FinderUI.pending = false
            FinderUI:RefreshInBackground()
        end)
    else
        self.pending = false
        self:RefreshInBackground()
    end
end

--------------------------------------------------------------------------------
-- Position and visibility
--------------------------------------------------------------------------------

function FinderUI:SavePosition()
    if not (ns.db and self.frame) then return end
    local point, _, relativePoint, x, y = self.frame:GetPoint()
    ns.db.finderPoint, ns.db.finderRelativePoint = point, relativePoint
    ns.db.finderX, ns.db.finderY = x, y
end

function FinderUI:RestorePosition()
    if not self.frame then return end
    local db = ns.db or {}
    self.frame:ClearAllPoints()
    -- Where it was left; else where the old gear window was; else the middle.
    if db.finderPoint then
        self.frame:SetPoint(db.finderPoint, UIParent, db.finderRelativePoint or db.finderPoint,
            db.finderX or 0, db.finderY or 0)
    elseif db.point then
        self.frame:SetPoint(db.point, UIParent, db.relativePoint or db.point, db.x or 0, db.y or 0)
    else
        self.frame:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    end
end

function FinderUI:Show()
    self:Build()
    if not self.frame:IsShown() then
        self:FitTab(self.frame)
        self:RestorePosition()
        self.offset = 0
        -- A new look: the slot last clicked if it has something, else the
        -- first that does.
        self.slot, self.slotChosen = nil, false
        self.frame:Show()
        Motion:Open(self.frame)
        -- And a light runs round the portrait.
        if ns.Titanforged then ns.Titanforged:Opened(self.frame) end
    end
    -- Asked for again while folded: open it full.
    if ns.FoldWindow then ns.FoldWindow:Unfold(self.frame) end
    self:Refresh()
    if ns.TrainingDrawer then ns.TrainingDrawer:WindowShown() end
end

function FinderUI:Hide()
    if self.frame then self.frame:Hide() end
end

function FinderUI:Toggle()
    if self.frame and self.frame:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end

function FinderUI:OnTrackingChanged()
    if self.frame and self.frame:IsShown() then self:Draw() end
end

function FinderUI:OnUpgradeQuestChanged()
    self:OnTrackingChanged()
end

--- Follow a row's pick on the upgrade quest panel, or say why it cannot be.
function FinderUI:Follow(pick)
    local logic = ns.UpgradeQuest
    if not logic then return nil end
    local quest, why = logic:Follow(pick)
    if quest then
        ns.Print(L.Format("following %s on the upgrade quest panel.", ns.Items.ShowLink(pick.link or quest.link)))
    else
        ns.Print(L.Format("%s can't be an upgrade quest yet: %s.", pick.link and ns.Items.ShowLink(pick.link) or L["that"], why or L["unknown"]))
    end
    return quest
end

local EVENTS = {
    "PLAYER_EQUIPMENT_CHANGED", "PLAYER_LEVEL_UP",
    "QUEST_TURNED_IN", "TRAIT_CONFIG_UPDATED", "BAG_UPDATE_DELAYED",
    "CHARACTER_POINTS_CHANGED", "PLAYER_TALENT_UPDATE",
}

function FinderUI:OnEnable()
    for _, event in ipairs(EVENTS) do
        ns.RegisterEvent(self, event, self.RefreshSoon)
    end
    -- Only answers the finder asked for: the client loads items for chat
    -- links, the auction house and other addons all the time.
    ns.RegisterEvent(self, "GET_ITEM_INFO_RECEIVED", function(_, _, itemID)
        if Finder:Asked(itemID) then FinderUI:RefreshSoon() end
    end)
    -- A new zone has its own list while "This zone only" is ticked, and
    -- always its own green zone names and nearest-first order.
    ns.RegisterEvent(self, "ZONE_CHANGED_NEW_AREA", function()
        FinderUI:RefreshSoon()
    end)
    -- A name drawn plain (a material, a recipe) takes its rarity colour
    -- once the client sends it: redraw, no rescan.
    ns.Items:WatchNames(function()
        if FinderUI.frame and FinderUI.frame:IsShown() then FinderUI:Draw() end
    end)
    -- Only the "need ... more" on vendor rows changes: redraw, no rescan.
    ns.RegisterEvent(self, "PLAYER_MONEY", function()
        if FinderUI.frame and FinderUI.frame:IsShown() then FinderUI:Draw() end
    end)
end
