-- Blackthornes Equipment -- Data/Items.lua
-- Everything this addon reads about an item: what it is, where it goes, the
-- level it needs, its stats, and what is worn or sitting in a bag slot.
--
-- Read only, and every call is in a pcall. Forever is a retail engine, so the
-- C_Item and C_Container calls come first and the older globals are the
-- fallback. /beq probe says which of them this client has.

local _, ns = ...

local Items = ns.NewModule("Items")

-- Each path split into its parts once, not on every call.
local partsOf = {}

local function Resolve(path)
    local parts = partsOf[path]
    if not parts then
        parts = {}
        for part in path:gmatch("[^.]+") do parts[#parts + 1] = part end
        partsOf[path] = parts
    end
    local fn = _G
    for i = 1, #parts do
        fn = type(fn) == "table" and fn[parts[i]] or nil
    end
    return fn
end

--- Call the first of `paths` the client has, inside a pcall, and hand back
--- everything it returned (nothing if none answered).
-- Everything is read through here (each bag slot, each worn item, each item
-- judged), so it makes no table or function per call: the returns are held
-- in locals, enough for the longest the client gives (GetItemInfo's 18).
local function Call(paths, ...)
    for i = 1, #paths do
        local fn = Resolve(paths[i])
        if type(fn) == "function" then
            local ok, r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, r11, r12, r13, r14, r15,
                r16, r17, r18, r19, r20 = pcall(fn, ...)
            if ok then
                return r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, r11, r12, r13, r14, r15,
                    r16, r17, r18, r19, r20
            end
        end
    end
end

-- The paths read most, made once.
local INSTANT = { "C_Item.GetItemInfoInstant", "GetItemInfoInstant" }
local ITEM_INFO = { "C_Item.GetItemInfo", "GetItemInfo" }
local ITEM_STATS = { "C_Item.GetItemStats", "GetItemStats" }
local WORN_LINK = { "GetInventoryItemLink" }
local BAG_LINK = { "C_Container.GetContainerItemLink", "GetContainerItemLink" }
local BAG_SLOTS = { "C_Container.GetContainerNumSlots", "GetContainerNumSlots" }
local SLOT_INFO = { "C_Container.GetContainerItemInfo" }
local OLD_SLOT_INFO = { "GetContainerItemInfo" }

local function CopyLink(link)
    if link:find("item:", 1, true) then return link .. "" end
end

--- A link or item string as a plain Lua string, or nil. Links the game will
--- not let an addon read (in an instance) raise when touched, so the copy is
--- made inside a pcall.
function Items.PlainLink(link)
    if type(link) ~= "string" then return nil end
    local ok, copy = pcall(CopyLink, link)
    if ok then return copy end
    return nil
end

--- What kind of item a link is.
-- @return a table { equipLoc, classID, subclassID, minLevel }, or nil when the
--         client does not know the item yet. minLevel is nil until the item is
--         in the client's cache; GET_ITEM_INFO_RECEIVED says when it arrives.
function Items:Info(link)
    link = self.PlainLink(link)
    if not link then return nil end

    local _, _, _, equipLoc, _, classID, subclassID =
        Call(INSTANT, link)

    local name, _, _, _, minLevel, _, _, _, fullLoc, _, _, fullClass, fullSub =
        Call(ITEM_INFO, link)

    equipLoc = equipLoc or fullLoc
    classID = classID or fullClass
    subclassID = subclassID or fullSub

    if type(equipLoc) ~= "string" then return nil end

    return {
        equipLoc = equipLoc,
        classID = tonumber(classID),
        subclassID = tonumber(subclassID),
        minLevel = name and tonumber(minLevel) or nil,
    }
end

--------------------------------------------------------------------------------
-- Spell damage for one school ("Increases damage done by Frost spells and
-- effects by up to 10.")
--
-- Classic's school damage is an Equip: line, not one of the stats
-- GetItemStats hands back, so it is read off the item's tooltip. Kept per
-- link, because the finder judges hundreds of items a scan.
--------------------------------------------------------------------------------

local SCHOOLS = {
    arcane = "arcaneDamage", fire = "fireDamage", frost = "frostDamage",
    nature = "natureDamage", shadow = "shadowDamage", holy = "holyDamage",
}
Items.SCHOOLS = SCHOOLS

local schoolCache = {}
local NO_SCHOOLS = {}

--- The school a line names and by how much, or nil for any other line.
function Items.SchoolLine(text)
    if type(text) ~= "string" then return nil end
    local school, amount = text:match("[Ii]ncreases damage done by (%a+) spells and effects by up to (%d+)")
    local stat = school and SCHOOLS[school:lower()]
    if stat then return stat, tonumber(amount) end
    return nil
end

-- A hidden tooltip of our own, made the first time it is needed, for a
-- client without C_TooltipInfo. Never shown; it only lays out the lines.
local SCAN_NAME = "BlackthornesEquipmentScanTip"
local scanTip

local function ScanTip()
    if scanTip ~= nil then return scanTip or nil end
    local ok, tip = pcall(CreateFrame, "GameTooltip", SCAN_NAME, nil, "GameTooltipTemplate")
    scanTip = ok and tip or false
    return scanTip or nil
end

-- An item string with nothing round it ("item:123:0:..."), which the
-- hidden tooltip takes on every client, where a full link can be refused.
local function ItemString(item)
    if type(item) == "string" then return item:match("item:[%-%d:]+") end
    if tonumber(item) then return "item:" .. tonumber(item) end
    return nil
end

--- An item's tooltip read off our own hidden tooltip, as { lines = {
--- { leftText }, ... } }, or nil when it can't be laid out.
function Items.ScanTooltip(item)
    local link = ItemString(item)
    local tip = link and ScanTip()
    if not tip then return nil end
    local ok, lines = pcall(function()
        tip:SetOwner(_G.WorldFrame or UIParent, "ANCHOR_NONE")
        tip:ClearLines()
        tip:SetHyperlink(link)
        local found = {}
        for i = 1, tip:NumLines() or 0 do
            local left = _G[SCAN_NAME .. "TextLeft" .. i]
            local text = left and left:GetText()
            found[#found + 1] = { leftText = type(text) == "string" and text or nil }
        end
        tip:Hide()
        return found
    end)
    if not ok or type(lines) ~= "table" or #lines == 0 then return nil end
    return { lines = lines }
end

-- Older tooltip data keeps each line's words in its args until the game's
-- own TooltipUtil lays them out.
local function Surface(data)
    local surface = Resolve("TooltipUtil.SurfaceArgs")
    if type(surface) ~= "function" or type(data) ~= "table" then return data end
    pcall(surface, data)
    if type(data.lines) == "table" then
        for _, line in ipairs(data.lines) do pcall(surface, line) end
    end
    return data
end

--- An item's tooltip as { lines = { { leftText }, ... } }: the client's own
--- tooltip data when it has C_TooltipInfo, else read off the hidden
--- tooltip. Nil when neither can say. `item` is a link or an item ID.
function Items.TooltipData(item)
    local data
    if type(item) == "string" then
        data = Call({ "C_TooltipInfo.GetHyperlink" }, item)
        if type(data) ~= "table" then
            local itemID = tonumber(item:match("item:(%d+)"))
            if itemID then data = Call({ "C_TooltipInfo.GetItemByID" }, itemID) end
        end
    elseif tonumber(item) then
        data = Call({ "C_TooltipInfo.GetItemByID" }, tonumber(item))
    end
    if type(data) == "table" then return Surface(data) end
    if Resolve("C_TooltipInfo.GetHyperlink") or Resolve("C_TooltipInfo.GetItemByID") then return nil end
    return Items.ScanTooltip(item)
end

--- What one tooltip line says, inside a pcall: in an instance the text can
--- be a secret value that raises when read.
local function LineText(line)
    local ok, text = pcall(function()
        if type(line) ~= "table" then return nil end
        local left = line.leftText
        if type(left) ~= "string" and type(line.args) == "table" then
            for _, arg in ipairs(line.args) do
                if type(arg) == "table" and arg.field == "leftText" and type(arg.stringVal) == "string" then
                    left = arg.stringVal
                    break
                end
            end
        end
        if type(left) ~= "string" then return nil end
        -- Colour codes off, so "|cffffffff+3 Agility|r" reads as "+3 Agility".
        left = left:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        return (left:gsub("^%s+", ""):gsub("%s+$", ""))
    end)
    return ok and text or nil
end

--- The random roll a link carries ("of the Monkey"), its eighth field, or
--- nil for none.
function Items.RollID(link)
    if type(link) ~= "string" then return nil end
    local itemString = link:match("item:[%-%d:]*")
    if not itemString then return nil end
    local field = 0
    for value in (itemString .. ":"):gmatch("([^:]*):") do
        field = field + 1
        if field == 8 then
            local roll = tonumber(value)
            if roll and roll ~= 0 then return roll end
            return nil
        end
    end
    return nil
end

-- The stats a random roll can add, as the tooltip shows them.
local ROLL_STATS = {
    "ITEM_MOD_STRENGTH", "ITEM_MOD_AGILITY", "ITEM_MOD_STAMINA",
    "ITEM_MOD_INTELLECT", "ITEM_MOD_SPIRIT",
}
local ENGLISH_ROLL_STATS = {
    ITEM_MOD_STRENGTH = "Strength", ITEM_MOD_AGILITY = "Agility", ITEM_MOD_STAMINA = "Stamina",
    ITEM_MOD_INTELLECT = "Intellect", ITEM_MOD_SPIRIT = "Spirit",
}

-- "+3 Agility" read as a pattern from the client's own words for it
-- ("%c%d Agility"), else the English.
local rollPatterns

-- The stat's name as this client writes it, lower case: the game's short
-- name, its character sheet name (SPELL_STAT1_NAME is Strength, in the
-- ROLL_STATS order), our own translation and the English. A German "+5
-- Stärke" is matched by name when the client's format line differs.
local function RollNames(key, index)
    local names = {}
    local function Add(name)
        local ok, copy = pcall(function()
            if type(name) == "string" and name ~= "" and not name:find("%%") then
                return name:lower() .. ""
            end
        end)
        if ok and copy then names[copy] = true end
    end
    Add(_G[key .. "_SHORT"])
    Add(_G["SPELL_STAT" .. index .. "_NAME"])
    local L = ns.L
    if L then Add(L[ENGLISH_ROLL_STATS[key]]) end
    Add(ENGLISH_ROLL_STATS[key])
    return names
end

local function RollPatterns()
    if rollPatterns then return rollPatterns end
    rollPatterns = {}
    for i, key in ipairs(ROLL_STATS) do
        local format = _G[key]
        local list = {}
        if type(format) == "string" and format:find("%%") then
            -- Every magic character escaped, "%" first among them, then the
            -- format's %c (the sign) and %d or %s (the amount) made captures.
            local pattern = format:gsub("([%%%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
            pattern = pattern:gsub("%%%%c", "([%%+%%-])"):gsub("%%%%[ds]", "(%%d+)")
            list[#list + 1] = "^" .. pattern .. "$"
        end
        list[#list + 1] = "^([%+%-])(%d+) " .. ENGLISH_ROLL_STATS[key] .. "$"
        rollPatterns[#rollPatterns + 1] = { key = key .. "_SHORT", patterns = list, names = RollNames(key, i) }
    end
    return rollPatterns
end

--- One tooltip line as a stat and amount ("+3 Agility" is
--- ITEM_MOD_AGILITY_SHORT, 3), or nil for any other line.
function Items.StatLine(text)
    if type(text) ~= "string" then return nil end
    -- A no-break space reads as a plain one.
    text = text:gsub("\194\160", " ")
    for _, each in ipairs(RollPatterns()) do
        for _, pattern in ipairs(each.patterns) do
            local sign, amount = text:match(pattern)
            amount = tonumber(amount)
            if sign and amount then
                return each.key, sign == "-" and -amount or amount
            end
        end
    end
    -- "+5 Stärke" by the stat's name, whatever the client's format line says.
    local sign, amount, name = text:match("^([%+%-])%s*(%d+)%s+(.-)%s*$")
    amount = tonumber(amount)
    if sign and amount and name and name ~= "" then
        name = name:lower()
        for _, each in ipairs(RollPatterns()) do
            if each.names[name] then
                return each.key, sign == "-" and -amount or amount
            end
        end
    end
    return nil
end

local rollStatCache = {}

-- The stat lines among a tooltip's lines, as ITEM_MOD_* keys, and how
-- many lines could be read at all.
local function StatsFromLines(lines)
    local found, read = {}, 0
    if type(lines) ~= "table" then return found, read end
    for _, line in ipairs(lines) do
        local text = LineText(line)
        if text then read = read + 1 end
        local key, amount = Items.StatLine(text)
        if key then found[key] = (found[key] or 0) + amount end
    end
    return found, read
end

-- How the last roll was read, for /beq probe: "tooltip data", "hidden
-- tooltip", "shown tooltip" or "none", with the lines read.
Items.rollRead = { how = "none", lines = 0 }

--- The primary stats a rolled link's tooltip shows, as ITEM_MOD_* keys,
--- or nil while the tooltip can't be read. On Era the game's stats for a
--- link leave out what its roll adds, so the tooltip is read for them:
--- the client's tooltip data first, then our own hidden tooltip.
function Items:TooltipStats(link)
    local known = rollStatCache[link]
    if known then return known end
    local readAny = false
    local data = Items.TooltipData(link)
    if type(data) == "table" then
        local found, read = StatsFromLines(data.lines)
        Items.rollRead = { how = "tooltip data", lines = read }
        if next(found) then
            rollStatCache[link] = found
            return found
        end
        readAny = read > 1
    end
    local scanned = Items.ScanTooltip(link)
    if type(scanned) == "table" then
        local found, read = StatsFromLines(scanned.lines)
        Items.rollRead = { how = "hidden tooltip", lines = read }
        if next(found) then
            rollStatCache[link] = found
            return found
        end
        readAny = readAny or read > 1
    end
    if readAny then return {} end
    return nil
end

--- Note what a tooltip on screen shows for a rolled link, so the stats
--- it lists are counted even when no other read gave them. True when it
--- found any.
function Items:NoteShownTooltip(link, tooltip)
    link = self.PlainLink(link)
    if not link or not Items.RollID(link) or rollStatCache[link] then return false end
    local ok, lines = pcall(function()
        local name = tooltip:GetName()
        if type(name) ~= "string" then return nil end
        local found = {}
        for i = 1, tooltip:NumLines() or 0 do
            local left = _G[name .. "TextLeft" .. i]
            local text = left and left:GetText()
            found[#found + 1] = { leftText = type(text) == "string" and text or nil }
        end
        return found
    end)
    if not ok then return false end
    local found, read = StatsFromLines(lines)
    if not next(found) then return false end
    rollStatCache[link] = found
    Items.rollRead = { how = "shown tooltip", lines = read }
    return true
end

--- The raw stats table for a link (ITEM_MOD_* keys), or nil.
--- Gear with a random roll also counts every stat its tooltip shows, so
--- "of the Monkey" is judged with its Agility and Stamina.
function Items:Stats(link)
    link = self.PlainLink(link)
    if not link then return nil end

    local stats = Call(ITEM_STATS, link)
    if type(stats) ~= "table" then return nil end
    if not Items.RollID(link) then return stats end

    local shown = self:TooltipStats(link)
    if not shown or next(shown) == nil then return stats end
    local merged = {}
    for key, value in pairs(stats) do merged[key] = value end
    for key, amount in pairs(shown) do
        if amount > (tonumber(merged[key]) or 0) then merged[key] = amount end
    end
    return merged
end

--- School spell damage on an item, as { frostDamage = 10 }, or nil when the
--- tooltip cannot be read. An empty table when it has none.
function Items:SchoolDamage(link)
    link = self.PlainLink(link)
    if not link then return nil end
    local known = schoolCache[link]
    if known then return known end

    -- By link first, so a random roll's own line is read; by item ID when
    -- the client has only that (Tradeskills reads sell prices that way).
    local data = Items.TooltipData(link)
    if type(data) ~= "table" or type(data.lines) ~= "table" then return nil end

    local found, lines = {}, 0
    for _, line in ipairs(data.lines) do
        lines = lines + 1
        local stat, amount = Items.SchoolLine(LineText(line))
        if stat then found[stat] = (found[stat] or 0) + amount end
    end
    -- Most gear has none, and the finder reads thousands of links, so they
    -- all share one empty table rather than keeping one each. Read only.
    if next(found) == nil then found = NO_SCHOOLS end
    -- A tooltip for an item the client has not loaded yet is one line
    -- ("Retrieving item information"); that is not "none", so not kept.
    if lines > 1 then schoolCache[link] = found end
    return found
end

-- The classes an item's tooltip names on its "Classes:" line, by item ID:
-- a set of lower case names, or false when it names none. Only kept once
-- the whole tooltip was read.
local classLines = {}

--- The class names on an item's "Classes: Hunter" line, as a set of lower
--- case names; false when the tooltip has no such line; nil while the
--- client has not loaded the item. For gear none of the data knows.
function Items:ClassesOnTooltip(itemID)
    itemID = tonumber(itemID)
    if not itemID then return nil end
    local known = classLines[itemID]
    if known ~= nil then return known end

    local format = type(_G.ITEM_CLASSES_ALLOWED) == "string" and _G.ITEM_CLASSES_ALLOWED or "Classes: %s"
    local pattern = "^" .. format:gsub("([%%%(%)%.%+%-%*%?%[%]%^%$])", "%%%1"):gsub("%%%%s", "(.+)") .. "$"
    local data = Items.TooltipData(itemID)
    if type(data) ~= "table" or type(data.lines) ~= "table" then return nil end

    local found, lines = false, 0
    for _, line in ipairs(data.lines) do
        lines = lines + 1
        local list = LineText(line)
        list = list and list:match(pattern)
        if list then
            found = {}
            -- Chinese clients part the names with a wide comma or 、.
            list = list:gsub("\239\188\140", ","):gsub("\227\128\129", ",")
            for name in list:gmatch("[^,]+") do
                name = name:match("^%s*(.-)%s*$")
                if name ~= "" then found[name:lower()] = true end
            end
        end
    end
    if lines > 1 then classLines[itemID] = found end
    return found
end

--- True once SchoolDamage has read `link`'s whole tooltip and kept it.
function Items:SchoolDamageKnown(link)
    link = self.PlainLink(link)
    return link ~= nil and schoolCache[link] ~= nil
end

-- The tooltip line type retail gives "Sell Price:"; 11 where the client
-- has no enum to say.
local function SellPriceLineType()
    local ok, kind = pcall(function() return _G.Enum.TooltipDataLineType.SellPrice end)
    return ok and tonumber(kind) or 11
end

--- What a vendor pays for one of an item, in copper, or nil when it cannot
--- be told. The tooltip's Sell Price wins: Forever changed some prices and
--- only the tooltip has the new one (Tradeskills found it first). Then the
--- item info's.
function Items:SellPrice(link)
    link = self.PlainLink(link)
    if not link then return nil end
    local data = Call({ "C_TooltipInfo.GetHyperlink" }, link)
    if type(data) ~= "table" then
        local itemID = tonumber(link:match("item:(%d+)"))
        if itemID then data = Call({ "C_TooltipInfo.GetItemByID" }, itemID) end
    end
    local sellType = SellPriceLineType()
    local ok, price = pcall(function()
        for _, line in ipairs(type(data) == "table" and type(data.lines) == "table" and data.lines or {}) do
            if type(line) == "table" and line.type == sellType and type(line.price) == "number" then
                return line.price + 0
            end
        end
        return nil
    end)
    if ok and price then return price end
    local name, _, _, _, _, _, _, _, _, _, sellPrice = Call(ITEM_INFO, link)
    ok, price = pcall(function()
        if name and type(sellPrice) == "number" then return sellPrice + 0 end
        return nil
    end)
    return ok and price or nil
end

--- The link of what is worn in an inventory slot, or nil when it is empty.
function Items:Equipped(slot)
    return self.PlainLink(Call(WORN_LINK, "player", slot))
end

--- The link of the item in a bag slot, or nil.
function Items:InBag(bag, slot)
    if type(bag) ~= "number" or type(slot) ~= "number" then return nil end
    return self.PlainLink(Call(BAG_LINK, bag, slot))
end

--- The quality of the item in a bag slot (0 grey, 1 white, 2 green and up),
--- or nil when the client cannot say.
function Items:SlotQuality(bag, slot, link)
    local info = Call(SLOT_INFO, bag, slot)
    local ok, quality = pcall(function()
        if type(info) == "table" and type(info.quality) == "number" then return info.quality + 0 end
    end)
    if ok and quality then return quality end
    link = self.PlainLink(link)
    if not link then return nil end
    local name, _, itemQuality = Call(ITEM_INFO, link)
    ok, quality = pcall(function()
        if name and type(itemQuality) == "number" then return itemQuality + 0 end
    end)
    return ok and quality or nil
end

--- Is the item in a bag slot soulbound? False when the client cannot say.
function Items:SlotBound(bag, slot)
    local info = Call(SLOT_INFO, bag, slot)
    local ok, bound = pcall(function()
        if type(info) == "table" and info.isBound ~= nil then return info.isBound == true end
    end)
    if ok and bound ~= nil then return bound end
    local make = Resolve("ItemLocation.CreateFromBagAndSlot")
    if type(make) ~= "function" then return false end
    local made, location = pcall(make, _G.ItemLocation, bag, slot)
    if not made or not location then return false end
    local answer = Call({ "C_Item.IsBound" }, location)
    local same, yes = pcall(function() return answer == true end)
    return same and yes or false
end

--- How many slots a bag has (0 when there is no bag there).
function Items:BagSize(bag)
    local size = Call(BAG_SLOTS, bag)
    return tonumber(size) or 0
end

--- The player's level, or nil.
function Items:PlayerLevel()
    return tonumber((Call({ "UnitLevel" }, "player")))
end

--------------------------------------------------------------------------------
-- What the bags and gear hold, to tell a real change from an arrow shot
--
-- Every shot a hunter fires spends ammo, and the client says the bags (and
-- the ammo slot) changed each time. Looking again at every upgrade on each
-- of those hangs the game, so the events are only passed on when what is
-- carried or worn has really changed (Core/Init.lua).
--------------------------------------------------------------------------------

--- Is a link arrows or bullets?
function Items.IsAmmo(link)
    local _, _, _, equipLoc, _, classID = Call(INSTANT, link)
    return equipLoc == "INVTYPE_AMMO" or tonumber(classID) == 6
end

--- How many are in a bag slot (1 when the client cannot say).
function Items:SlotCount(bag, slot)
    local info = Call(SLOT_INFO, bag, slot)
    if type(info) == "table" then return tonumber(info.stackCount) or 1 end
    local _, count = Call(OLD_SLOT_INFO, bag, slot)
    return tonumber(count) or 1
end

--- Everything in the bags with how many, ammo without its count, as one
--- string: the same string means nothing changed but the ammo spent.
function Items:BagSignature()
    local parts = {}
    for bag = 0, 4 do
        for slot = 1, self:BagSize(bag) do
            local link = self:InBag(bag, slot)
            if link then
                local count = self.IsAmmo(link) and "" or ("x" .. self:SlotCount(bag, slot))
                parts[#parts + 1] = bag .. ":" .. slot .. "=" .. link .. count
            end
        end
    end
    return table.concat(parts, ";")
end

--- The skills the character has, without their points, as one string:
--- the weapon skills it knows (WeaponSkills:ReadKnown) and its professions
--- by name. nil when the client names none, so nothing is held back.
function Items:SkillSignature()
    local parts = {}
    local weapons = ns.WeaponSkills
    local known = weapons and weapons.ReadKnown and weapons:ReadKnown()
    if type(known) == "table" then
        for subclassID in pairs(known) do parts[#parts + 1] = "w" .. tostring(subclassID) end
    end

    local lines = Call({ "C_TradeSkillUI.GetAllProfessionTradeSkillLines" })
    if type(lines) == "table" then
        for _, skillLineID in ipairs(lines) do
            local info = Call({ "C_TradeSkillUI.GetProfessionInfoBySkillLineID" }, skillLineID)
            local ok, name = pcall(function()
                if type(info) == "table" and type(info.professionName) == "string" then
                    return info.professionName .. ""
                end
            end)
            if ok and name and name ~= "" then parts[#parts + 1] = "p" .. name end
        end
    end
    local count = tonumber((Call({ "GetNumSkillLines" }))) or 0
    for index = 1, count do
        local name = Call({ "GetSkillLineInfo" }, index)
        local ok, copy = pcall(function()
            if type(name) == "string" then return name .. "" end
        end)
        if ok and copy then parts[#parts + 1] = "s" .. copy end
    end

    if #parts == 0 then return nil end
    table.sort(parts)
    return table.concat(parts, ";")
end

--- Everything worn, leaving out the ammo slot, as one string.
function Items:WornSignature()
    local parts = {}
    for slot = 1, 19 do parts[slot] = self:Equipped(slot) or "-" end
    return table.concat(parts, ";")
end

Items.Call = Call

--------------------------------------------------------------------------------
-- Item names in their quality colour
--
-- The owner (2026-10-18): an item's name always shows its rarity colour,
-- grey, white, green, blue, purple or orange, wherever it is drawn. Saved
-- data and anything compared or put in a macro stays plain; only the text
-- put on screen is coloured, at the moment it is drawn. A quality is kept
-- per item once the client has said it; until then the item is asked for
-- once (GET_ITEM_INFO_RECEIVED says when it arrives, and the windows that
-- show names already draw again then) and the name keeps the colour of
-- the line it sits in.
--------------------------------------------------------------------------------

local qualityOf = {}       -- [itemID] = quality, once known
local qualityByName = {}   -- [name] = quality, for a name with no ID
local hexOf = {}           -- [quality] = "ffrrggbb"
local asked = {}           -- [itemID] = true once asked for this session

local function ItemIDOf(item)
    if type(item) == "number" then return item end
    if type(item) ~= "string" then return nil end
    local ok, id = pcall(function() return tonumber(item:match("item:(%d+)")) end)
    return ok and id or nil
end
Items.ItemIDOf = ItemIDOf

local function Hex(r, g, b)
    local ok, hex = pcall(function()
        return ("ff%02x%02x%02x"):format(math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5),
            math.floor(b * 255 + 0.5))
    end)
    return ok and hex or nil
end

--- The colour code of a quality ("ff1eff00" for green), or nil.
function Items.QualityHex(quality)
    if type(quality) ~= "number" then return nil end
    if hexOf[quality] then return hexOf[quality] end
    local hex
    local colors = rawget(_G, "ITEM_QUALITY_COLORS")
    local color = type(colors) == "table" and colors[quality] or nil
    if type(color) == "table" and type(color.r) == "number" then
        hex = Hex(color.r, color.g, color.b)
    end
    if not hex then
        local r, g, b, h = Call({ "C_Item.GetItemQualityColor", "GetItemQualityColor" }, quality)
        if type(h) == "string" and h:match("^%x%x%x%x%x%x%x%x$") then
            hex = h:lower()
        elseif type(r) == "number" and type(g) == "number" and type(b) == "number" then
            hex = Hex(r, g, b)
        end
    end
    if hex then hexOf[quality] = hex end
    return hex
end

--- Ask the server about an item once a session, so its quality comes in.
local function Ask(id)
    if asked[id] then return end
    asked[id] = true
    local C = rawget(_G, "C_Item")
    if type(C) == "table" and type(C.RequestLoadItemDataByID) == "function" then
        pcall(C.RequestLoadItemDataByID, id)
    end
end

--- An item's quality (0 grey to 5 orange and up), or nil while not known.
--- `item` is an ID, a link or item string, or (with no ID to go on) a name,
--- which the client answers only once it has that item.
function Items:Quality(item)
    local id = ItemIDOf(item)
    if id and qualityOf[id] then return qualityOf[id] end
    local name = not id and type(item) == "string" and item ~= "" and item or nil
    if name and qualityByName[name] then return qualityByName[name] end
    local key = id or name
    if not key then return nil end
    -- A link carries its own colour; the client's answer is the same.
    local _, _, quality = Call(ITEM_INFO, type(item) == "string" and item or key)
    local ok, number = pcall(function()
        local value = tonumber(quality)
        if value and value >= 0 and value <= 9 then return value end
    end)
    if ok and number then
        if id then qualityOf[id] = number else qualityByName[name] = number end
        return number
    end
    if id then Ask(id) end
    return nil
end

--- `name` in the quality colour of `item` (an ID, link or the name itself),
--- or `name` as it is while the quality is not known. Text that already
--- carries a colour is left alone.
function Items.ColorName(item, name)
    if type(name) ~= "string" or name == "" then return name end
    if name:find("|c", 1, true) then return name end
    local hex = Items.QualityHex(Items:Quality(item or name))
    if not hex then return name end
    return "|c" .. hex .. name .. "|r"
end

--- A link to show: a real link (coloured by the game) as it is; an item
--- string ("item:123", kept while the client had not sent the item) as the
--- item's link once the client has it, else as it was.
function Items.ShowLink(link)
    if type(link) ~= "string" then return link end
    if link:find("|H", 1, true) then return link end
    local id = ItemIDOf(link)
    if not id then return Items.ColorName(nil, link) end
    local _, real = Call(ITEM_INFO, id)
    real = Items.PlainLink(real)
    if real and real:find("|H", 1, true) then return real end
    Ask(id)
    return link
end

--- Is a name drawn plain while its item's quality is on its way?
function Items:Waiting(itemID)
    local ok, id = pcall(function() return tonumber(itemID) end)
    return ok and id ~= nil and asked[id] == true and qualityOf[id] == nil
end

-- Windows that draw names again when an item they showed plain arrives.
-- One redraw for a burst of answers, never for items nobody here asked for.
local watchers = {}
local redrawSoon = false

--- Call `fn` (in a pcall) a moment after items whose names were drawn
--- plain arrive, once for a burst.
function Items:WatchNames(fn)
    if type(fn) == "function" then watchers[#watchers + 1] = fn end
end

local function Redraw()
    redrawSoon = false
    for _, fn in ipairs(watchers) do pcall(fn) end
end

function Items:OnItemInfo(_, itemID)
    if not self:Waiting(itemID) or redrawSoon then return end
    redrawSoon = true
    local timer = rawget(_G, "C_Timer")
    if type(timer) == "table" and type(timer.After) == "function" then
        timer.After(0.2, Redraw)
    else
        Redraw()
    end
end

function Items:OnEnable()
    ns.RegisterEvent(self, "GET_ITEM_INFO_RECEIVED", self.OnItemInfo)
end
