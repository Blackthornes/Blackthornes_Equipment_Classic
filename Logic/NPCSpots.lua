-- Blackthornes Equipment -- Logic/NPCSpots.lua
-- Where vendors and trainers really stand on WoW: Forever.
--
-- The finder's vendor and trainer spots come from Classic data, and Forever
-- has moved some of them. So whenever a merchant or trainer window opens,
-- the NPC's ID (from its GUID), the map the character is on and where the
-- character stands are kept, account wide, in `BlackthornesEquipmentDB.npcSpots`
-- [npcID] = { name, zone, x, y }. Talking to an NPC means standing next to
-- it, so the character's spot is the NPC's spot to within a step.
--
-- A spot seen in game wins over the shipped one: this file's Get is asked
-- first wherever a place is made from an NPC ID. Before a release, the spots
-- in the owner's save are folded into Data/ForeverNPCs.lua by
-- tools/forever_npcs.py (NPC IDs, map names and numbers only), so every
-- player gets them.
--
-- What vendors charge is learned the same way: when a merchant window opens,
-- the gold price of every piece of gear the finder knows a vendor for is
-- kept, account wide, in `BlackthornesEquipmentDB.vendorPrices[itemID]` =
-- copper. A price seen in game wins over Classic's (`Price`), and the latest
-- one seen wins, so a reputation discount or a Forever price change is
-- followed. Items that cost tokens or honor are not kept.
--
-- Gear a vendor sells that the data does not list for it is learned too
-- (see "What vendors sell" below).
--
-- Every client value is read inside a pcall and copied: in an instance the
-- game hands out secret values that raise when touched. One merchant window
-- is one read, so nothing here runs on bag events.

local _, ns = ...

local NPCSpots = ns.NewModule("NPCSpots")

local function Read(fn, ...)
    if type(fn) ~= "function" then return nil end
    local result = { pcall(fn, ...) }
    if not result[1] then return nil end
    return unpack(result, 2)
end

local function Plain(value)
    local ok, copy = pcall(function()
        if type(value) == "string" and value ~= "" then return value .. "" end
    end)
    return ok and copy or nil
end

local function Number(value)
    local ok, copy = pcall(function()
        local n = tonumber(value)
        if n and n == n then return n + 0 end
    end)
    return ok and copy or nil
end

--- The NPC ID in a creature's GUID ("Creature-0-1-2-3-3079-0000A1B2C3"),
--- or nil for players, pets and anything unreadable.
function NPCSpots.IDFromGUID(guid)
    local ok, id = pcall(function()
        if type(guid) ~= "string" then return nil end
        local parts = {}
        for part in guid:gmatch("[^-]+") do parts[#parts + 1] = part end
        if parts[1] ~= "Creature" and parts[1] ~= "Vehicle" then return nil end
        return tonumber(parts[6])
    end)
    return ok and id or nil
end

local function Round(n) return math.floor(n * 1000 + 0.5) / 10 end

--- Where the character stands: the map's name, and x, y on it from 0 to
--- 100 as the finder shows them. Nil inside an instance or when unreadable.
function NPCSpots:Here()
    local map = type(_G.C_Map) == "table" and _G.C_Map or nil
    if not map then return nil end
    local mapID = Number(Read(map.GetBestMapForUnit, "player"))
    if not mapID then return nil end
    local position = Read(map.GetPlayerMapPosition, mapID, "player")
    if position == nil then return nil end
    local ok, x, y = pcall(function()
        local px, py = position:GetXY()
        return px + 0, py + 0
    end)
    if not ok or not x or not y or x <= 0 or y <= 0 or x >= 1 or y >= 1 then return nil end
    local info = Read(map.GetMapInfo, mapID)
    local name
    if type(info) == "table" then
        local read, value = pcall(function() return info.name end)
        name = read and Plain(value) or nil
    end
    if not name then return nil end
    -- Kept by the data's name, on a client in another language too.
    if ns.Waypoints then name = ns.Waypoints:DataZone(name, mapID) or name end
    return name, Round(x), Round(y), mapID
end

--- What the game says about the NPC behind an open window, without keeping
--- it: ID, name, and where it stands. Nil when any part is unreadable.
function NPCSpots:Read(unit)
    unit = unit or "npc"
    local npcID = self.IDFromGUID(Plain(Read(_G.UnitGUID, unit)))
    if not npcID then return nil end
    local zone, x, y = self:Here()
    if not zone then return nil end
    return { npcID = npcID, name = Plain(Read(_G.UnitName, unit)), zone = zone, x = x, y = y }
end

--- Keep where the NPC behind an open merchant or trainer window stands.
--- The latest sighting wins, so an NPC Forever moves is followed.
function NPCSpots:Learn(unit)
    local db = ns.db
    if type(db) ~= "table" then return nil end
    local seen = self:Read(unit)
    if not seen then return nil end
    if type(db.npcSpots) ~= "table" then db.npcSpots = {} end
    db.npcSpots[seen.npcID] = { seen.name or "", seen.zone, seen.x, seen.y }
    return seen
end

--- How many spots this account has learned.
function NPCSpots:Count()
    local n = 0
    for _ in pairs(type(ns.db) == "table" and type(ns.db.npcSpots) == "table" and ns.db.npcSpots or {}) do
        n = n + 1
    end
    return n
end

local function Valid(spot)
    return type(spot) == "table" and type(spot[2]) == "string" and spot[2] ~= ""
        and type(spot[3]) == "number" and type(spot[4]) == "number"
end

--- Where an NPC stands on Forever, as { name, zone, x, y }: learned on this
--- account first, then shipped in Data/ForeverNPCs.lua. Nil when neither
--- knows it, and the Classic spot stands. The name is "" when not known.
function NPCSpots:Get(npcID)
    local learned = type(ns.db) == "table" and type(ns.db.npcSpots) == "table" and ns.db.npcSpots[npcID]
    if Valid(learned) then return learned end
    local shipped = ns.ForeverNPCs and ns.ForeverNPCs[npcID]
    if Valid(shipped) then return shipped end
    return nil
end

--- A place made from Classic data, moved to where the NPC stands on
--- Forever when that is known: name, zone, x, y.
function NPCSpots:Place(npcID, name, zone, x, y)
    local spot = self:Get(npcID)
    if not spot then return name, zone, x, y end
    local seenName = type(spot[1]) == "string" and spot[1] ~= "" and spot[1] or name
    return seenName, spot[2], spot[3], spot[4]
end

--------------------------------------------------------------------------------
-- What vendors charge
--------------------------------------------------------------------------------

local function ItemIDFromLink(link)
    local ok, id = pcall(function()
        if type(link) ~= "string" then return nil end
        return tonumber(link:match("item:(%d+)"))
    end)
    return ok and id or nil
end

--- One merchant slot as item ID, gold price in copper, stack size and
--- whether the vendor has only a few (true or false), or nil when it is
--- unreadable or costs something besides gold. Asks the newer
--- C_MerchantFrame.GetItemInfo first, then GetMerchantItemInfo.
function NPCSpots.MerchantItem(index)
    local itemID = Number(Read(_G.GetMerchantItemID, index))
        or ItemIDFromLink(Plain(Read(_G.GetMerchantItemLink, index)))
    if not itemID then return nil end
    local price, stack, extended, available
    local frame = type(_G.C_MerchantFrame) == "table" and _G.C_MerchantFrame or nil
    local info = frame and Read(frame.GetItemInfo, index)
    if type(info) == "table" then
        local ok = pcall(function()
            price, stack = Number(info.price), Number(info.stackCount)
            extended = info.hasExtendedCost and true or false
            available = Number(info.numAvailable)
        end)
        if not ok then return nil end
    else
        local result = { pcall(_G.GetMerchantItemInfo or error, index) }
        if not result[1] then return nil end
        local ok = pcall(function()
            price, stack = Number(result[4]), Number(result[5])
            extended = result[9] and true or false
            available = Number(result[6])
        end)
        if not ok then return nil end
    end
    if extended or not price or price <= 0 then return nil end
    return itemID, price, stack or 1, available ~= nil and available >= 0
end

--- Keep what the open merchant charges for the gear the finder knows a
--- vendor for. Returns how many prices changed.
function NPCSpots:LearnPrices()
    local db = ns.db
    local items = ns.Sources and ns.Sources.ITEMS
    if type(db) ~= "table" or type(items) ~= "table" then return 0 end
    local count = Number(Read(_G.GetMerchantNumItems)) or 0
    local changed = 0
    for index = 1, math.min(count, 200) do
        local itemID, price, stack = self.MerchantItem(index)
        local known = itemID and items[itemID]
        if known and known.v and stack == 1 then
            if type(db.vendorPrices) ~= "table" then db.vendorPrices = {} end
            if db.vendorPrices[itemID] ~= price then
                db.vendorPrices[itemID] = price
                changed = changed + 1
            end
        end
    end
    if changed > 0 and ns.QuestPanel and ns.QuestPanel.RefreshSoon then ns.QuestPanel:RefreshSoon() end
    return changed
end

--- What a vendor charges for an item on Forever, in copper, when a merchant
--- window has shown it on this account; nil when not seen.
function NPCSpots:Price(itemID)
    local prices = type(ns.db) == "table" and type(ns.db.vendorPrices) == "table" and ns.db.vendorPrices
    local price = prices and itemID and prices[itemID]
    if type(price) == "number" and price > 0 then return price end
    return nil
end

--- How many vendor prices this account has learned.
function NPCSpots:PriceCount()
    local n = 0
    for _ in pairs(type(ns.db) == "table" and type(ns.db.vendorPrices) == "table" and ns.db.vendorPrices or {}) do
        n = n + 1
    end
    return n
end

--------------------------------------------------------------------------------
-- What vendors sell that the data does not know
--------------------------------------------------------------------------------

-- Gear a vendor sells that Classic's data does not list for that vendor
-- (a vendor Forever added, on Zephras Isle say) is kept, account wide, in
-- `BlackthornesEquipmentDB.learnedVendors[npcID]` (never rename it):
--
--   { name =, zone =, x =, y =, side =,
--     items = { [itemID] = { price, req, ilvl, limited } }, at = }
--
-- `side` is who the vendor serves: "A", "H", or "AH" for a vendor of
-- neither side. `ilvl` is 0 until the client has loaded the item. What is
-- learned (and what ships in Data/ForeverVendors.lua, folded in from the
-- owner's save by tools/forever_vendors.py) is laid over Sources.NPCS and
-- Sources.ITEMS, so the finder and the upgrade quest's Vendor tab offer it.
-- Nothing Classic says is replaced.

--- The side a vendor serves: "A", "H" or "AH".
function NPCSpots.VendorSide(unit)
    local faction = Plain(Read(_G.UnitFactionGroup, unit or "npc"))
    if faction == "Alliance" then return "A" end
    if faction == "Horde" then return "H" end
    return "AH"
end

local function JoinSides(a, b)
    if a == nil or a == b then return b end
    if b == nil then return a end
    return "AH"
end

--- Does the data already list this vendor for this item?
local function Listed(item, npcID)
    local v = item and item.v
    for i = 1, #(v or {}), 2 do
        if v[i] == npcID then return true end
    end
    return false
end

--- Lay one learned vendor over the data. Returns true when it added anything.
function NPCSpots:LayVendor(npcID, rec)
    local S = ns.Sources
    if type(S) ~= "table" or type(S.NPCS) ~= "table" or type(S.ITEMS) ~= "table" then return false end
    if type(npcID) ~= "number" or type(rec) ~= "table" or type(rec.items) ~= "table" then return false end
    local added = false
    local npc = S.NPCS[npcID]
    if not npc then
        local zone = ns.QuestLearn and ns.QuestLearn.ZoneID and ns.QuestLearn.ZoneID(rec.zone) or 0
        npc = { type(rec.name) == "string" and rec.name or "", zone, tonumber(rec.x) or 0, tonumber(rec.y) or 0,
            type(rec.side) == "string" and rec.side or "AH", learned = true }
        S.NPCS[npcID] = npc
        added = true
    elseif npc.learned and type(rec.side) == "string" and npc[5] ~= rec.side then
        npc[5] = rec.side
        added = true
    end
    for itemID, row in pairs(rec.items) do
        local notWorn = ns.QuestLearn and ns.QuestLearn.NotWorn
        if type(itemID) == "number" and type(row) == "table" and not (notWorn and notWorn(itemID)) then
            local item = S.ITEMS[itemID]
            if not item then
                local ilvl = tonumber(row[3]) or 0
                -- An item level not known yet keeps it in every scan; the
                -- game's stats judge it anyway.
                item = { tonumber(row[2]) or 0, ilvl > 0 and ilvl or 999, 0, 0, tonumber(row[1]) or 0, learned = true }
                S.ITEMS[itemID] = item
            elseif item.learned and (tonumber(row[3]) or 0) > 0 and item[2] == 999 then
                item[2] = tonumber(row[3])
            end
            if not Listed(item, npcID) then
                item.v = item.v or {}
                item.v[#item.v + 1] = npcID
                item.v[#item.v + 1] = row[4] and 1 or 0
                added = true
            end
        end
    end
    return added
end

--- Lay every shipped and learned vendor. Done at login, once.
function NPCSpots:LayAllVendors()
    -- A false stands in for a missing shipped list, so ipairs still reaches the
    -- learned ones (on Classic Era the shipped list is left out).
    local added = false
    for _, source in ipairs({ ns.ForeverVendors or false, type(ns.db) == "table" and ns.db.learnedVendors or nil }) do
        if type(source) == "table" then
            for npcID, rec in pairs(source) do
                if self:LayVendor(npcID, rec) then added = true end
            end
        end
    end
    if added and ns.Finder and ns.Finder.MarkStale then pcall(ns.Finder.MarkStale, ns.Finder) end
    return added
end

--- Keep the gear the open merchant sells that the data does not list for
--- it. Returns how many items were new.
function NPCSpots:LearnStock()
    local db = ns.db
    local S = ns.Sources
    local QL = ns.QuestLearn
    if type(db) ~= "table" or type(S) ~= "table" or type(S.ITEMS) ~= "table" or not (QL and QL.Gear) then return 0 end
    local count = Number(Read(_G.GetMerchantNumItems)) or 0
    if count <= 0 then return 0 end
    local npcID
    local fresh = {}
    for index = 1, math.min(count, 200) do
        local itemID, price, stack, limited = self.MerchantItem(index)
        if itemID and stack == 1 then
            local req, ilvl = QL.Gear(itemID)
            if req then
                npcID = npcID or self.IDFromGUID(Plain(Read(_G.UnitGUID, "npc")))
                if not npcID then return 0 end
                local rec = type(db.learnedVendors) == "table" and db.learnedVendors[npcID]
                local have = rec and rec.items and rec.items[itemID]
                if not Listed(S.ITEMS[itemID], npcID) or (have and have[3] == 0 and ilvl > 0) then
                    fresh[itemID] = { price, req, ilvl, limited and true or false }
                end
            end
        end
    end
    if not next(fresh) then return 0 end
    local seen = self:Read("npc")
    if not seen then return 0 end
    if type(db.learnedVendors) ~= "table" then db.learnedVendors = {} end
    local rec = db.learnedVendors[npcID]
    if not rec then
        rec = { items = {}, at = Number(Read(_G.time)) or 0 }
        db.learnedVendors[npcID] = rec
    end
    rec.name = seen.name or rec.name
    rec.zone, rec.x, rec.y = seen.zone, seen.x, seen.y
    rec.side = JoinSides(rec.side, self.VendorSide("npc"))
    local n = 0
    for itemID, row in pairs(fresh) do
        rec.items[itemID] = row
        n = n + 1
    end
    if self:LayVendor(npcID, rec) and ns.Finder and ns.Finder.MarkStale then
        pcall(ns.Finder.MarkStale, ns.Finder)
    end
    return n
end

--- How many vendors this account has learned gear from.
function NPCSpots:VendorCount()
    local n = 0
    for _ in pairs(type(ns.db) == "table" and type(ns.db.learnedVendors) == "table" and ns.db.learnedVendors or {}) do
        n = n + 1
    end
    return n
end

function NPCSpots:OnEnable()
    pcall(self.LayAllVendors, self)
    ns.RegisterEvent(self, "MERCHANT_SHOW", function()
        NPCSpots:Learn("npc")
        NPCSpots:LearnStock()
        NPCSpots:LearnPrices()
    end)
    -- Item details can arrive after the window opens.
    ns.RegisterEvent(self, "MERCHANT_UPDATE", function()
        NPCSpots:LearnStock()
        NPCSpots:LearnPrices()
    end)
    ns.RegisterEvent(self, "TRAINER_SHOW", function() NPCSpots:Learn("npc") end)
end
