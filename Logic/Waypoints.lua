-- Blackthornes Equipment -- Logic/Waypoints.lua
-- "Show on map": the game's own map pin on where an upgrade comes from.
--
-- The finder's places are a zone name and a spot on that zone's map (from
-- Classic data). The map ID for the zone is found from the client's own map
-- list rather than a table typed here, so a map Forever numbers differently
-- still works: from the map the character is on, up to the top, then down
-- through every zone under it until one carries the name. A client in
-- another language names its maps in that language, so there Classic's map
-- IDs stand in (Waypoints.ZONE_MAPS, below).
--
-- The pin itself is the game's: C_Map.SetUserWaypoint, then tracked so the
-- game draws its arrow to it. Every call is inside a pcall. Era's client
-- takes no pin of its own (the calls may be there, but no map takes one),
-- so there the place is kept as `Waypoints.marked` and UI/MapPins.lua draws
-- it on the world map in Equipment's own gold ring instead. Only with the
-- "Map pins" setting off does it say it couldn't.

local _, ns = ...

local L = ns.L

local Waypoints = ns.NewModule("Waypoints")

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
    local ok, copy = pcall(function() return tonumber(value) end)
    return ok and copy or nil
end

local function Map() return type(_G.C_Map) == "table" and _G.C_Map or nil end

--------------------------------------------------------------------------------
-- Zone names on a client in another language
--
-- The data names zones in English ("Elwynn Forest"); a German client names
-- them in German ("Wald von Elwynn"), so a name alone never matches there.
-- These are Classic's map IDs for the zones the data names, the same IDs
-- the tests and Farmer use (Elwynn Forest 1429, Dun Morogh 1426). They are
-- only asked on a client that is not English, and always after the name:
-- an English client works exactly as before, and an ID Forever numbers
-- differently only means the name is used, as it always was.
--------------------------------------------------------------------------------

Waypoints.ZONE_MAPS = {
    ["Durotar"] = 1411, ["Mulgore"] = 1412, ["The Barrens"] = 1413, ["Kalimdor"] = 1414,
    ["Eastern Kingdoms"] = 1415, ["Alterac Mountains"] = 1416, ["Arathi Highlands"] = 1417,
    ["Badlands"] = 1418, ["Blasted Lands"] = 1419, ["Tirisfal Glades"] = 1420,
    ["Silverpine Forest"] = 1421, ["Western Plaguelands"] = 1422, ["Eastern Plaguelands"] = 1423,
    ["Hillsbrad Foothills"] = 1424, ["The Hinterlands"] = 1425, ["Dun Morogh"] = 1426,
    ["Searing Gorge"] = 1427, ["Burning Steppes"] = 1428, ["Elwynn Forest"] = 1429,
    ["Deadwind Pass"] = 1430, ["Duskwood"] = 1431, ["Loch Modan"] = 1432,
    ["Redridge Mountains"] = 1433, ["Stranglethorn Vale"] = 1434, ["Swamp of Sorrows"] = 1435,
    ["Westfall"] = 1436, ["Wetlands"] = 1437, ["Teldrassil"] = 1438, ["Darkshore"] = 1439,
    ["Ashenvale"] = 1440, ["Thousand Needles"] = 1441, ["Stonetalon Mountains"] = 1442,
    ["Desolace"] = 1443, ["Feralas"] = 1444, ["Dustwallow Marsh"] = 1445, ["Tanaris"] = 1446,
    ["Azshara"] = 1447, ["Felwood"] = 1448, ["Un'Goro Crater"] = 1449, ["Moonglade"] = 1450,
    ["Silithus"] = 1451, ["Winterspring"] = 1452, ["Stormwind City"] = 1453,
    ["Orgrimmar"] = 1454, ["Ironforge"] = 1455, ["Thunder Bluff"] = 1456,
    ["Darnassus"] = 1457, ["Undercity"] = 1458, ["Alterac Valley"] = 1459,
}

-- The game's map type for a zone (Enum.UIMapType.Zone).
local ZONE_TYPE = 3

-- The two continents are never a zone the character is "in".
local CONTINENTS = { [1414] = true, [1415] = true }

--- Is the client English? Nil from GetLocale counts as English, so nothing
--- changes on a client that will not say.
function Waypoints.English()
    local locale = Plain(Read(_G.GetLocale))
    return locale == nil or locale:sub(1, 2) == "en"
end

-- [map ID] = the data's name, and the names the data knows, built once.
local namesByMap, knownNames

local function Known(name)
    if not knownNames then
        knownNames = {}
        for zone in pairs(Waypoints.ZONE_MAPS) do knownNames[zone] = true end
        local dungeons = ns.Sources and ns.Sources.DUNGEONS
        for _, dungeon in pairs(type(dungeons) == "table" and dungeons or {}) do
            if type(dungeon[1]) == "string" then knownNames[dungeon[1]] = true end
            if type(dungeon[4]) == "string" then knownNames[dungeon[4]] = true end
        end
    end
    return knownNames[name] == true
end

local function NameOfMap(mapID)
    if not namesByMap then
        namesByMap = {}
        for zone, id in pairs(Waypoints.ZONE_MAPS) do
            if not CONTINENTS[id] then namesByMap[id] = zone end
        end
    end
    return namesByMap[mapID]
end

--- Can this client put a pin on the map at all?
function Waypoints:CanPin()
    local map = Map()
    return map ~= nil and type(map.SetUserWaypoint) == "function"
        and type(_G.UiMapPoint) == "table" and type(_G.UiMapPoint.CreateFromCoordinates) == "function"
end

--- A map's name and parent.
local function Info(mapID)
    local map = Map()
    local info = map and Read(map.GetMapInfo, mapID)
    if type(info) ~= "table" then return nil end
    local ok, name, parent = pcall(function() return info.name, info.parentMapID end)
    if not ok then return nil end
    return Plain(name), Number(parent)
end

--- The highest map above the one the character is on.
local function TopMap()
    local map = Map()
    local here = map and Number(Read(map.GetBestMapForUnit, "player"))
    if not here then return nil end
    local top = here
    for _ = 1, 10 do
        local _, parent = Info(top)
        if not parent or parent <= 0 then break end
        top = parent
    end
    return top
end

--- The data's name for a map and the maps it sits in (a cave's map sits in
--- its zone), or nil when none of them is a zone the data knows.
function Waypoints:DataNameOfMap(mapID)
    for _ = 1, 8 do
        if not mapID or mapID <= 0 then return nil end
        local name = NameOfMap(mapID)
        if name then return name end
        local _, parent = Info(mapID)
        mapID = parent
    end
    return nil
end

-- What each of the client's own zone names was found to be, for a client
-- that is not English: one name always means the same zone.
local translated = {}

--- The data's name for a zone the client names in its own language
--- (GetRealZoneText, a map's name). `mapID` is the map it names, when the
--- caller has it; else the character's dungeon, or the map they are on and
--- the maps it sits in. On an English client, or for a name the data
--- already knows, the name as given.
function Waypoints:DataZone(name, mapID)
    if type(name) ~= "string" or name == "" then return name end
    if Known(name) or Waypoints.English() then return name end
    local key = mapID and (name .. "|" .. mapID) or name
    if translated[key] then return translated[key] end

    local found
    if mapID then
        -- That very map: a spot on a cave's own map is not one on its zone's.
        found = NameOfMap(mapID)
    else
        -- Inside a dungeon: the instance's own ID, which the data's
        -- dungeons are keyed by ("389" Ragefire Chasm).
        local ok, kind, instanceID = pcall(function()
            local values = { _G.GetInstanceInfo() }
            return values[2], values[8]
        end)
        local dungeons = ns.Sources and ns.Sources.DUNGEONS
        kind = ok and Plain(kind) or nil
        if kind and kind ~= "none" and type(dungeons) == "table" and Number(instanceID) then
            local dungeon = dungeons[tostring(Number(instanceID))]
            found = dungeon and dungeon[1]
        end
        if not found then
            local map = Map()
            found = self:DataNameOfMap(map and Number(Read(map.GetBestMapForUnit, "player")))
        end
    end
    if found then translated[key] = found end
    return found or name
end

--- The map ID of a zone, by its name, or nil. Kept once found.
function Waypoints:MapFor(zone)
    if type(zone) ~= "string" or zone == "" then return nil end
    self.found = self.found or {}
    if self.found[zone] then return self.found[zone] end

    local map = Map()
    local top = TopMap()
    -- A miss is kept for the map it was looked for from: from another
    -- continent (or out of an instance) the zone may well be found.
    local missKey = top and (top .. "|" .. zone)
    if missKey and self.found[missKey] == false then return nil end
    local mapID
    if map and top then
        local name = Info(top)
        if name == zone then mapID = top end
        -- Every map under the top one, zones and continents alike.
        -- A name can be on more than one map (a zone and a cave or a floor
        -- of the same name, which take no pin): the zone's own map wins.
        local children = not mapID and Read(map.GetMapChildrenInfo, top, nil, true)
        if type(children) == "table" then
            local best, bestRank = nil, 0
            for _, child in ipairs(children) do
                local ok, childName, childID, kind = pcall(function()
                    return child.name, child.mapID, child.mapType
                end)
                childID = ok and Number(childID)
                if childID and Plain(childName) == zone then
                    local rank = (childID == Waypoints.ZONE_MAPS[zone] and 3)
                        or (Number(kind) == ZONE_TYPE and 2) or 1
                    if rank > bestRank then best, bestRank = childID, rank end
                end
            end
            mapID = best
        end
    end

    -- A client in another language names its maps in that language: then
    -- Classic's map ID for the zone, when the client knows that map.
    if not mapID and map and Waypoints.ZONE_MAPS[zone] and not Waypoints.English() then
        local id = Waypoints.ZONE_MAPS[zone]
        if type(Read(map.GetMapInfo, id)) == "table" then mapID = id end
    end

    -- Only a search that ran is kept: on a loading screen or a taxi the
    -- client has no map yet, and that must not hide the zone until /reload.
    if map and top then
        if mapID then self.found[zone] = mapID else self.found[missKey] = false end
    end
    return mapID
end

--- Put the map pin on a place { zone, x, y } (x and y 0-100 on the zone's
--- map) and point the game's arrow at it.
-- @return true, or false and why ("nospot", "noclient", "nomap")
-- `link` is the item it is for, the icon on Equipment's own pin.
function Waypoints:Pin(place, link)
    if not (place and place.zone and place.x and place.y) then return false, "nospot" end
    local zoneMap = self:MapFor(place.zone)
    if not self:CanPin() then
        if not zoneMap then return false, "nomap" end
        return self:Mark(place, link, zoneMap)
    end
    if not zoneMap then return false, "nomap" end
    local mapID, x, y = Waypoints.PinnableSpot(zoneMap, place.x / 100, place.y / 100)
    if not mapID then return self:Mark(place, link, zoneMap) end

    local ok = pcall(function()
        local point = _G.UiMapPoint.CreateFromCoordinates(mapID, x, y)
        _G.C_Map.SetUserWaypoint(point)
        local super = _G.C_SuperTrack
        if type(super) == "table" and type(super.SetSuperTrackedUserWaypoint) == "function" then
            super.SetSuperTrackedUserWaypoint(true)
        end
    end)
    if not ok then return self:Mark(place, link, zoneMap) end
    -- The game can turn a pin down without a word: only a pin it kept counts.
    local map = Map()
    if map and type(map.HasUserWaypoint) == "function" and Read(map.HasUserWaypoint) == false then
        return self:Mark(place, link, zoneMap)
    end
    self:Unmark()
    return true, mapID
end

--- Where the game takes no pin: keep the place for Equipment's own pin on
--- the world map (UI/MapPins.lua), one at a time, for the session. Not with
--- the "Map pins" setting off, which hides those pins.
-- @return true and the zone's map, or false and "noclient"
function Waypoints:Mark(place, link, mapID)
    local pins = ns.MapPins
    if not (pins and pins:IsEnabled()) then return false, "noclient" end
    self.marked = { zone = place.zone, x = place.x, y = place.y, name = place.name,
        text = place.text, items = place.items, link = link, area = place.area }
    if pins.OnTrackingChanged then pins:OnTrackingChanged() end
    return true, mapID
end

--- Take Equipment's own pin away (the game's took its place).
function Waypoints:Unmark()
    if not self.marked then return end
    self.marked = nil
    if ns.MapPins and ns.MapPins.OnTrackingChanged then ns.MapPins:OnTrackingChanged() end
end

--- Does the game take its own pin on this map? False on Era.
function Waypoints:GamePins(mapID)
    if not self:CanPin() then return false end
    if not mapID then return true end
    return Waypoints.PinnableSpot(mapID, 0.5, 0.5) ~= nil
end

--- A map the game takes a pin on, and the spot (0-1) on it. Some maps (a
--- city, a cave or a building on some clients) take none: then the map
--- around it, with the spot moved over by where the one map sits on the
--- other. Tradeskills' Waypoints.PinnableSpot, the same lines.
-- @return mapID, x, y, or nil when no map up the line takes a pin
function Waypoints.PinnableSpot(mapID, x, y)
    local map = Map()
    if not (map and type(map.CanSetUserWaypointOnMap) == "function") then return mapID, x, y end
    for _ = 1, 4 do
        if Read(map.CanSetUserWaypointOnMap, mapID) ~= false then return mapID, x, y end
        local _, parent = Info(mapID)
        if not parent or parent <= 0 then return nil end
        local minX, maxX, minY, maxY = Read(map.GetMapRectOnMap, mapID, parent)
        minX, maxX, minY, maxY = Number(minX), Number(maxX), Number(minY), Number(maxY)
        if not (minX and maxX and minY and maxY) then return nil end
        x = minX + x * (maxX - minX)
        y = minY + y * (maxY - minY)
        mapID = parent
    end
    return nil
end

local WHY = {
    nospot = L["no exact spot is known for that one"],
    noclient = L["Couldn't put a pin on the map."],
    nomap = L["the map for that zone could not be found"],
}

--- Pin a place and say so in chat. `what` names it ("Corina Steele"),
--- `link` the item it is for.
---
--- Where the game takes no pin (Era), Equipment's own marker goes on the
--- spot (`Mark`) and the quest arrow shows the way there; the marker goes
--- once you stand on it (UI/MapPins.lua). A place with only a zone gets a
--- "Somewhere in ZONE" marker in the zone's middle and the arrow.
function Waypoints:Show(place, what, link)
    -- Names in the game's own words (Logic/Names.lua); the place keeps the data's.
    local names = ns.Names
    local zone = place and place.zone and names and names:Zone(place.zone) or (place and place.zone)
    if what and names then what = names:NPC(names:Zone(what)) end
    if type(place) == "table" and place.zone and not (place.x and place.y) then
        return self:ShowArea(place, what, zone, link)
    end
    local ok, why = self:Pin(place, link)
    -- No game pin, so no game arrow: the quest arrow points there instead.
    if ok and self.marked then self:AimArrow(place, what or place.name) end
    if ok then
        -- `why` is the map the pin went on, which can be the one around it.
        ns.Print(L.Format("pinned %s on your map: %s (%s, %s)", what or place.name or L["it"],
            zone, place.x, place.y))
        -- Open the map on it, where the game lets an addon. Never in a
        -- fight: the game blocks an addon opening the map then. The pin
        -- stays, so the map shows it when opened after the fight.
        local inFight = false
        if type(_G.InCombatLockdown) == "function" then
            local okFight, fighting = pcall(_G.InCombatLockdown)
            inFight = okFight and fighting == true
        end
        local mapID = Number(why) or self:MapFor(place.zone)
        if not inFight and type(_G.OpenWorldMap) == "function" then pcall(_G.OpenWorldMap, mapID) end
    else
        local reason = WHY[why] or why
        if why == "noclient" then
            -- A whole sentence of its own: no place would help.
            ns.Print(reason)
        elseif place and place.zone then
            ns.Print(L.Format("can't pin %s (%s): %s", what or L["that"], zone, reason))
        else
            ns.Print(L.Format("can't pin %s: %s", what or L["that"], reason))
        end
    end
    return ok
end

--- Never in a fight: the game blocks an addon opening the map then.
function Waypoints.OpenMap(mapID)
    if type(_G.InCombatLockdown) == "function" then
        local okFight, fighting = pcall(_G.InCombatLockdown)
        if okFight and fighting == true then return end
    end
    if mapID and type(_G.OpenWorldMap) == "function" then pcall(_G.OpenWorldMap, mapID) end
end

--- Point the quest arrow at a place the game took no pin for.
function Waypoints:AimArrow(place, name)
    local arrow = ns.QuestArrow
    if not (arrow and arrow.AimAtQuest) then return end
    pcall(arrow.AimAtQuest, arrow, nil, name or place.zone,
        { zone = place.zone, x = place.x, y = place.y, name = name })
end

--- Only a zone is known: "head for ZONE." in chat, a "Somewhere in ZONE"
--- marker in its middle, the arrow toward it, and the map opened on it.
function Waypoints:ShowArea(place, what, zone, link)
    local mapID = self:MapFor(place.zone)
    if not mapID then
        ns.Print(L.Format("can't pin %s (%s): %s", what or L["that"], zone, WHY.nomap))
        return false
    end
    ns.Print(L.Format("head for %s.", zone))
    self:Mark({ zone = place.zone, x = 50, y = 50, area = true,
        name = L.Format("Somewhere in %s", zone) }, link, mapID)
    self:AimArrow({ zone = place.zone }, what or zone)
    Waypoints.OpenMap(mapID)
    return true
end
