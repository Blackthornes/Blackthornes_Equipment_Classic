-- Blackthornes Equipment -- UI/Tooltip.lua
-- One line on a piece of gear's tooltip: an upgrade or not, for the spec the
-- character is judged as, and by how much. Under it, for a weapon the class
-- can learn but the character has not, where its weapon master is.
--
-- Hooked the way Tradeskills' UI/ItemTooltip.lua is. Its measurement on
-- Forever (docs/FOREVER_API_FINDINGS.md there) is that retail's
-- TooltipDataProcessor is what fires; the older OnTooltipSetItem script is
-- installed too, in case, and a guard stops the line going on twice.
--
-- Blizzard's tooltips are appended to, never replaced, and only the game's
-- main tooltip and the one a chat link opens are touched. The comparison
-- tooltips beside them show what is worn, which needs no verdict.

local _, ns = ...
local L = ns.L

local Tooltip = ns.NewModule("Tooltip")

local Compare = ns.Compare
local Items = ns.Items
local WeaponSkills = ns.WeaponSkills

local TOOLTIP_NAMES = { "GameTooltip", "ItemRefTooltip" }

-- Each line's key for Off, Shift or Always (UI/TooltipShift.lua): the
-- verdict and the weapon master under it ("upgrade", tooltipLine), a random
-- roll's name ("suffix", suffixLine), an alt's upgrade ("alt",
-- altTooltipLine), the best enchant ("enchant", enchantTooltip) and the
-- boss that drops it ("drops", dropsTooltip). A line
-- carries its key as `line.key`; the Shift answer is asked as the lines go
-- on the tooltip, never kept with them.
if ns.TooltipShift then
    ns.TooltipShift.KEYS = { "upgrade", "suffix", "alt", "enchant", "drops" }
end

local function Field(object, key)
    if type(object) ~= "table" then return nil end
    local ok, value = pcall(function() return object[key] end)
    if ok then return value end
    return nil
end

function Tooltip:IsEnabled()
    return not (ns.db and ns.db.tooltipLine == false)
end

--- Is this one of the tooltips the line belongs on?
function Tooltip:Wanted(tooltip)
    for _, name in ipairs(TOOLTIP_NAMES) do
        if _G[name] ~= nil and _G[name] == tooltip then return true end
    end
    return false
end

--- The link of the item a tooltip shows, however this client offers it.
function Tooltip:LinkFor(tooltip, data)
    -- A bag button's own slot first: its link always carries the roll.
    local fromBag = self:BagLink(tooltip)
    if fromBag then return fromBag end

    local fromData = Items.PlainLink(Field(data, "hyperlink"))
    if fromData then return fromData end

    local displayed = Field(_G.TooltipUtil, "GetDisplayedItem")
    if type(displayed) == "function" then
        local ok, _, link = pcall(displayed, tooltip)
        link = ok and Items.PlainLink(link)
        if link then return link end
    end

    local getItem = Field(tooltip, "GetItem")
    if type(getItem) == "function" then
        local ok, _, link = pcall(getItem, tooltip)
        link = ok and Items.PlainLink(link)
        if link then return link end
    end

    -- Last, the bare id: good enough for the item's base stats.
    local id = Field(data, "id")
    if type(id) == "number" then
        local ok, text = pcall(function() if id > 0 then return "item:" .. id end end)
        if ok and text then return text end
    end
    return nil
end

--- The link in the bag slot whose button owns the tooltip, or nil.
function Tooltip:BagLink(tooltip)
    local getOwner = Field(tooltip, "GetOwner")
    if type(getOwner) ~= "function" then return nil end
    local ok, owner = pcall(getOwner, tooltip)
    if not ok or type(owner) ~= "table" then return nil end
    local okSlot, bag, slot = pcall(function()
        local bagID = owner.GetBagID and owner:GetBagID()
        if type(bagID) ~= "number" then
            local name = owner.GetName and owner:GetName()
            if type(name) ~= "string" or not name:find("^ContainerFrame%d+Item%d+$") then return nil end
            local parent = owner:GetParent()
            bagID = parent and parent:GetID()
        end
        return bagID, owner:GetID()
    end)
    if not okSlot or type(bag) ~= "number" or type(slot) ~= "number" then return nil end
    local getLink = Field(_G.C_Container, "GetContainerItemLink") or _G.GetContainerItemLink
    if type(getLink) ~= "function" then return nil end
    local okLink, link = pcall(getLink, bag, slot)
    return okLink and Items.PlainLink(link) or nil
end

--- Is the tooltip showing an item from one of the game's bag buttons? Only
--- a button that says its bag (retail) or is named as a bag slot (classic)
--- counts; the character sheet's buttons never do.
function Tooltip:FromBag(tooltip)
    local getOwner = Field(tooltip, "GetOwner")
    if type(getOwner) ~= "function" then return false end
    local ok, owner = pcall(getOwner, tooltip)
    if not ok or type(owner) ~= "table" then return false end

    local getBag = Field(owner, "GetBagID")
    if type(getBag) == "function" then
        local okBag, bag = pcall(getBag, owner)
        if okBag and type(bag) == "number" then return true end
    end
    local getName = Field(owner, "GetName")
    if type(getName) == "function" then
        local okName, name = pcall(getName, owner)
        if okName and type(name) == "string" then
            local okMatch, found = pcall(string.find, name, "^ContainerFrame%d+Item%d+$")
            return okMatch and found ~= nil
        end
    end
    return false
end

-- Which tooltip already carries the line, for which item and at what length.
-- Cleared when the tooltip is, so the next showing gets it again.
local decorated = setmetatable({}, { __mode = "k" })

function Tooltip.Forget(tooltip)
    decorated[tooltip] = nil
end

local function LineCount(tooltip)
    local numLines = Field(tooltip, "NumLines")
    if type(numLines) ~= "function" then return nil end
    local ok, count = pcall(numLines, tooltip)
    if ok and type(count) == "number" then return count end
    return nil
end

--- The extra lines: a random roll's name
--- and stats, which Forever's own tooltip leaves off ("of the Monkey: +5
--- Agility, +5 Stamina"), and who on the account can make a crafted piece.
function Tooltip:MoreLines(link)
    local lines = {}
    if not (ns.db and ns.db.suffixLine == false) and ns.Rolls and ns.Rolls.RollOf(link) then
        local name, stats = ns.Rolls:Describe(link)
        if stats then
            lines[#lines + 1] = { name and (name .. ": " .. stats) or L.Format("Random roll: %s", stats), "accent",
                key = "suffix" }
        end
    end
    local itemID = tonumber(link:match("item:(%d+)"))
    if itemID and not (ns.db and ns.db.dropsTooltip == false) then
        local drop = Tooltip.DropLine(itemID)
        if drop then lines[#lines + 1] = { drop, "muted", key = "drops" } end
    end
    if itemID and ns.Crafting then
        local text, color = ns.Crafting:TooltipLine(itemID)
        if text then lines[#lines + 1] = { text, color } end
    end
    return lines
end

-- While the pointer rests on a bag slot the game draws its tooltip again
-- several times a second, and each draw used to judge the item from scratch.
-- The last item's lines are kept for a moment instead, and dropped at once
-- when gear, level, talents or weights change.
local LINES_KEPT = 1
local lastLines = nil

local function Now()
    local clock = rawget(_G, "GetTime")
    if type(clock) ~= "function" then return nil end
    local ok, now = pcall(clock)
    if ok and type(now) == "number" then return now end
    return nil
end

function Tooltip.ForgetLines()
    lastLines = nil
end

--- "Upgrade for Ana Smith: +9%" when the item is no upgrade for the
--- character playing but is for another of the player's characters on this
--- realm and side (Alts:BestFor, the same answer Butler mails by), or nil.
function Tooltip:AltLine(link, result)
    if ns.db and ns.db.altTooltipLine == false then return nil end
    if not ns.Alts or type(result) ~= "table" or result.verdict == "upgrade"
        or result.verdict == "equipped" then return nil end
    local alt = ns.Alts:BestFor(link)
    if not alt then return nil end
    local name = ns.Alts:NameOf(alt.key) or L["another of your characters"]
    local how = alt.gain and ("%+d%%"):format(alt.gain) or L["fills an empty slot"]
    if alt.level then return L.Format("Upgrade for %s at level %d: %s", name, alt.level, how) end
    return L.Format("Upgrade for %s: %s", name, how)
end

--- "Drops from BOSS in DUNGEON" for gear a dungeon drops, or nil (the
--- owner picked it, 2026-10-22). What Farmer saw drop on Forever comes
--- first, the best rate leading; else Classic's boss with the best chance.
function Tooltip.DropLine(itemID)
    local S = ns.Sources
    if not S then return nil end
    local DQ = ns.DungeonQuests
    local function DungeonName(key)
        local dungeon = DQ and DQ.Dungeon and DQ.Dungeon(key)
        if dungeon then return dungeon.name end
        local row = S.DUNGEONS and S.DUNGEONS[key]
        return type(row) == "table" and row[1] or nil
    end
    local best, bestRate
    for _, drop in ipairs(S.FOREVER and S.FOREVER[itemID] or {}) do
        local where = type(drop) == "table" and DungeonName(drop[2])
        local rate = type(drop) == "table" and tonumber(drop[3]) or 0
        if where and drop[1] and (not best or rate > bestRate) then
            best, bestRate = { drop[1], where }, rate
        end
    end
    if not best then
        local item = S.ITEMS and S.ITEMS[itemID]
        local drops = type(item) == "table" and item.d or {}
        for i = 1, #drops, 2 do
            local boss = S.BOSSES and S.BOSSES[drops[i]]
            local where = boss and DungeonName(boss[2])
            local rate = tonumber(drops[i + 1]) or 0
            if where and (not best or rate > bestRate) then
                best, bestRate = { boss[1], where }, rate
            end
        end
    end
    if not best then return nil end
    return L.Format("Drops from %s in %s", best[1], best[2])
end

--- The lines for one item, worked out afresh.
function Tooltip:WorkOutLines(link, carried)
    local lines = {}
    -- An item shown from a bag slot is a carried copy, so a second copy of a
    -- worn ring is judged against the other ring, as its bag arrow is.
    local judge = carried and Compare.JudgeCarried or Compare.Judge
    local result = judge(Compare, link)
    local text, color = Compare:Describe(result)
    if text then lines[#lines + 1] = { text, color, key = "upgrade" } end
    -- No use to you, but an upgrade for another of your characters.
    local okAlt, altLine = pcall(Tooltip.AltLine, Tooltip, link, result)
    if okAlt and altLine then lines[#lines + 1] = { altLine, "accent", key = "alt" } end
    local okTrainer, trainer, trainerColor = pcall(WeaponSkills.Describe, WeaponSkills, link)
    if okTrainer and trainer then lines[#lines + 1] = { trainer, trainerColor, true, key = "upgrade" } end
    -- On a piece you wear: the best enchant for it (Logic/Enchants.lua).
    if ns.Enchants then
        local okEnchant, enchantLine = pcall(ns.Enchants.TooltipLine, ns.Enchants, link)
        if okEnchant and enchantLine then lines[#lines + 1] = { enchantLine, "accent", key = "enchant" } end
    end
    local okMore, more = pcall(Tooltip.MoreLines, Tooltip, link)
    if okMore then
        for _, line in ipairs(more) do lines[#lines + 1] = line end
    end
    return lines
end

--- The lines for one item, kept for LINES_KEPT seconds.
function Tooltip:LinesFor(link, carried)
    local now = Now()
    local generation = ns.Weights and ns.Weights.generation or 0
    local kept = lastLines
    if now and kept and kept.link == link and kept.carried == carried and kept.generation == generation
        and now >= kept.at and now - kept.at < LINES_KEPT then
        return kept.lines
    end
    local lines = self:WorkOutLines(link, carried)
    lastLines = now and { link = link, carried = carried, generation = generation, at = now, lines = lines } or nil
    return lines
end

--- Put the line on a tooltip.
-- @return "added", "quiet" (nothing to say), "duplicate" or "noitem"
function Tooltip:Decorate(tooltip, data)
    if not self:IsEnabled() then return "quiet" end
    if not self:Wanted(tooltip) then return "quiet" end
    if self.writing then return "duplicate" end

    local link = self:LinkFor(tooltip, data)
    if not link then return "noitem" end

    local mark = decorated[tooltip]
    if mark and mark.link == link then
        local now = LineCount(tooltip)
        if not now or now >= mark.lines then return "duplicate" end
    end

    -- A random roll's stats ("+3 Agility") as this tooltip shows them,
    -- in case no other read of the link gave them.
    if Items:NoteShownTooltip(link, tooltip) then
        local compare = ns.Compare
        if compare and compare.ForgetScores then compare:ForgetScores() end
        Tooltip.ForgetLines()
        local bags = ns.BagIcons
        if bags and bags.RefreshSoon then pcall(bags.RefreshSoon, bags) end
    end

    local lines = self:LinesFor(link, self:FromBag(tooltip))
    if #lines == 0 then return "quiet" end

    local addLine = Field(tooltip, "AddLine")
    if type(addLine) ~= "function" then return "noitem" end

    self.writing = true
    local shift = ns.TooltipShift
    local held = false
    for _, line in ipairs(lines) do
        -- A line on Shift waits while Shift is up.
        if line.key and shift and not shift:Shows(line.key) then
            held = true
        else
            -- The trainer line wraps, so a list of cities folds onto a
            -- second line rather than stretching the tooltip.
            pcall(addLine, tooltip, ("|c%s%s|r"):format(ns.COLORS[line[2]] or ns.COLORS.text, line[1]),
                nil, nil, nil, line[3])
        end
    end
    if held then pcall(shift.Held, shift, tooltip) end

    -- Adding a line needs the tooltip resized, which Show does; on a client
    -- where that re-enters the hook, `writing` is what stops it.
    local show = Field(tooltip, "Show")
    if type(show) == "function" then pcall(show, tooltip) end
    self.writing = false

    decorated[tooltip] = { link = link, lines = LineCount(tooltip) or 0 }
    return "added"
end

--- Every hook comes through here, so one bad item costs its line and never a
--- Lua error on hover.
function Tooltip:OnTooltip(tooltip, data, source)
    local ok, outcome = pcall(self.Decorate, self, tooltip, data)
    if not ok then
        self.writing = false
        return "noitem"
    end
    if outcome == "added" then
        self.fired[source] = (self.fired[source] or 0) + 1
    end
    return outcome
end

function Tooltip:InstallDataProcessor()
    local processor = _G.TooltipDataProcessor
    local dataType = Field(Field(_G.Enum, "TooltipDataType"), "Item")
    local add = Field(processor, "AddTooltipPostCall")
    if type(add) ~= "function" or dataType == nil then return false end

    return (pcall(add, dataType, function(tooltip, data)
        Tooltip:OnTooltip(tooltip, data, "TooltipDataProcessor")
    end))
end

function Tooltip:InstallScriptHooks()
    local installed = false
    for _, name in ipairs(TOOLTIP_NAMES) do
        local tooltip = _G[name]
        local hook = Field(tooltip, "HookScript")
        if type(hook) == "function" then
            if pcall(hook, tooltip, "OnTooltipSetItem", function(shown)
                Tooltip:OnTooltip(shown, nil, "OnTooltipSetItem")
            end) then
                installed = true
            end
            pcall(hook, tooltip, "OnTooltipCleared", function(shown)
                Tooltip.Forget(shown)
            end)
        end
    end
    return installed
end

function Tooltip:OnEnable()
    for _, event in ipairs({ "PLAYER_EQUIPMENT_CHANGED", "PLAYER_LEVEL_UP", "TRAIT_CONFIG_UPDATED",
        "SKILL_LINES_CHANGED", "GET_ITEM_INFO_RECEIVED", "CHARACTER_POINTS_CHANGED", "PLAYER_TALENT_UPDATE" }) do
        ns.RegisterEvent(self, event, Tooltip.ForgetLines)
    end
    self.fired = {}
    self.installed = {
        TooltipDataProcessor = self:InstallDataProcessor(),
        OnTooltipSetItem = self:InstallScriptHooks(),
    }
end
