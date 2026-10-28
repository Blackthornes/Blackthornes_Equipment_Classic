-- Blackthornes Equipment -- Logic/QuestArrow.lua
-- The quest arrow: which way to walk to the next place in the upgrade
-- quest's steps (the owner asked 2026-10-08: "bring our arrow we used in
-- Farmer to Equipment quest as well"). Farmer's goal arrow
-- (Logic/Arrow.lua there) is where this comes from; the addons ship apart,
-- so it is a copy, not a call.
--
-- It follows the quest on the tab the panel shows, and points at the
-- places its steps name, from the step to do now on:
--
--   * A spot with coordinates (a vendor, a quest giver, a trainer): the
--     arrow points at it, with the distance in yards. Where the player has
--     met the NPC on Forever, that spot is the one the steps carry already
--     (Logic/NPCSpots.lua lays it over Classic's).
--   * A zone with no spot (a dungeon's entrance zone, "Travel to"): the
--     middle of the zone, and it says so. In that zone already, there is
--     nothing to point at, so it says the step is about this zone.
--   * A zone whose map the client cannot find, or on the other continent:
--     no arrow, only the zone.
--
-- A spot followed by a zone step for the same zone is the better of the
-- two, so "Travel to Westfall" gives way to the vendor standing there.
-- Nothing here makes up a coordinate: a place without one is a zone.
--
-- Direction and distance come from the game's world coordinates
-- (C_Map.GetWorldPosFromMapPos), which run across a continent in yards. A
-- client without them still gets an arrow to spots on the map the player is
-- on, measured with the map's size. Everything the client is asked is read
-- only and inside a pcall; inside a dungeon, where the game keeps the
-- player's position to itself, the arrow hides.

local _, ns = ...
local L = ns.L

local QuestArrow = ns.NewModule("QuestArrow")

-- How close counts as there, in yards: an NPC stands still, more or less.
local ARRIVED = 15
QuestArrow.ARRIVED = ARRIVED

-- How often the places are worked out again from the steps, seconds, when
-- nothing said they changed. The upgrade quest re-lists them at once after
-- every bag, quest log, zone or gear change it hears (OnUpgradeQuestChanged),
-- so this only catches what no event told it; reading the steps every two
-- seconds while the dial was up was work for nothing. The pointing and the
-- distance are redone every time the dial draws.
QuestArrow.REFRESH = 10
-- A quest from the quest log is one cheap read of the log, and nothing tells
-- the arrow when its objectives move on, so it keeps the old pace.
QuestArrow.REFRESH_FREE = 2

-- Map types, as the client numbers them (Enum.UIMapType).
local CONTINENT = 2

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
        local number = tonumber(value)
        if number and number == number then return number + 0 end
    end)
    return ok and copy or nil
end

local function Map() return type(_G.C_Map) == "table" and _G.C_Map or nil end

--------------------------------------------------------------------------------
-- The switch
--------------------------------------------------------------------------------

function QuestArrow.IsOn()
    return ns.db ~= nil and ns.db.questArrow == true
end

function QuestArrow:SetOn(on)
    ns.db.questArrow = on and true or false
    if not on then self.free = nil end
    -- Turned on, it goes over any other Blackthornes arrow (UI/QuestArrow.lua).
    if on and ns.QuestArrowUI and ns.QuestArrowUI.Claim then ns.QuestArrowUI:Claim() end
    self:Changed(true)
    for _, name in ipairs({ "QuestPanel", "SettingsUI" }) do
        local module = ns[name]
        if module and module.OnQuestArrowChanged then pcall(module.OnQuestArrowChanged, module) end
    end
end

--- Something the arrow shows changed: work it out again on the next draw.
function QuestArrow:Changed(reset)
    self.listedAt = nil
    if reset then self.pinned, self.choice = nil, nil end
    if ns.QuestArrowUI and ns.QuestArrowUI.Refresh then ns.QuestArrowUI:Refresh() end
end

--- The upgrade quest picked, finished or moved on: a new list.
function QuestArrow:OnUpgradeQuestChanged()
    self:Changed(false)
end

--------------------------------------------------------------------------------
-- What it follows
--------------------------------------------------------------------------------

--- The quest the arrow follows: a quest from the quest log it was pointed
--- at (AimAtQuest), else the one on the tab the panel shows, while the
--- upgrade quest is on.
function QuestArrow:Quest()
    if self.free then return self.free end
    local quest = ns.UpgradeQuest
    if not (quest and quest:IsEnabled()) then return nil end
    return quest:Current()
end

--- A quest's item name, plain: "Thick Leather Tunic".
function QuestArrow.ItemName(quest)
    if type(quest) ~= "table" then return nil end
    if quest.free then return quest.title end
    local name = type(quest.link) == "string" and quest.link:match("|h%[(.-)%]|h")
        or type(quest.link) == "string" and quest.link:match("^%[(.-)%]$")
    if not name and quest.itemID then
        local items = ns.Items
        local item = type(quest.link) == "string" and quest.link or ("item:%d"):format(quest.itemID)
        name = items and items.Call and Plain((items.Call({ "C_Item.GetItemInfo", "GetItemInfo" }, item)))
    end
    return name
end

--- What tells one quest from another, so a place picked for one is not
--- kept for the next.
local function Stamp(quest)
    if not quest then return nil end
    if quest.free then return ("log|%s|%s"):format(tostring(quest.questID), tostring(quest.title)) end
    return ("%s|%s"):format(tostring(quest.itemID), tostring(ns.UpgradeQuest and ns.UpgradeQuest:Tab()))
end

--- What tells one place from another across a fresh list.
function QuestArrow.Key(place)
    return ("%s|%s|%s"):format(place.zone or "?", tostring(place.x), tostring(place.y))
end

--- Where a quest from the quest log is worked on now: its objective, or
--- whoever takes it back once it is ready, read again each time so the
--- arrow moves on when the last objective is done. The place it was aimed
--- with when the data knows nothing better.
function QuestArrow.FreePlace(quest)
    local log, upgrade = ns.QuestLog, ns.UpgradeQuest
    if quest.questID and log and log.Place and upgrade and upgrade.QuestReady then
        local ok, ready = pcall(function() return upgrade.QuestReady(quest.questID) == true end)
        local found, place = pcall(log.Place, { questID = quest.questID, complete = ok and ready or nil })
        if found and type(place) == "table" and type(place.zone) == "string" then return place end
    end
    return quest.place
end

--- The places the quest's steps name, from the step to do now on, each
--- once: { zone, x, y, name, step, text }. A zone-only place gives way to a
--- spot in the same zone further on. Also the steps they came from.
function QuestArrow:Places(quest)
    quest = quest or self:Quest()
    -- A quest from the quest log: its one place.
    if type(quest) == "table" and quest.free then
        local place = QuestArrow.FreePlace(quest)
        return { { zone = place.zone, x = tonumber(place.x), y = tonumber(place.y), name = place.name,
            text = quest.title, forQuest = quest.title } }
    end
    local upgrade = ns.UpgradeQuest
    if not (quest and upgrade) then return {} end
    local ok, steps, current = pcall(upgrade.Steps, upgrade, quest)
    if not ok or type(steps) ~= "table" then return {} end

    local list, seen = {}, {}
    current = tonumber(current)
    for index = math.max(current or 1, 1), #steps do
        local step = steps[index]
        local place = step.place
        if type(place) == "table" and type(place.zone) == "string" and not step.done then
            local x, y = tonumber(place.x), tonumber(place.y)
            local entry = { zone = place.zone, x = x, y = y, name = place.name, step = index, text = step.text }
            local key = QuestArrow.Key(entry)
            if not seen[key] then
                seen[key] = true
                list[#list + 1] = entry
            end
        end
    end

    -- "Travel to Westfall" then "Find Kirsta Deepshadow (56, 31)": the spot.
    local spotIn = {}
    for _, place in ipairs(list) do
        if place.x and place.y then spotIn[place.zone] = true end
    end
    local kept = {}
    for _, place in ipairs(list) do
        if place.x and place.y or not spotIn[place.zone] then kept[#kept + 1] = place end
    end
    return kept, steps, current
end

--- Does a place picked on the panel still stand? Only while its step reads
--- as it did when it was clicked: once that step is done, or turns into
--- the next thing to do (the objective met, now hand it in), the arrow goes
--- back to following the steps by itself.
local function Uncoloured(text)
    if type(text) ~= "string" then return text end
    return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

function QuestArrow.PinHolds(pinned, steps)
    if type(steps) ~= "table" then return true end
    local step = steps[pinned.place.step]
    if not step then return false end
    -- An item's name taking its colour once the client sends it is the
    -- same step.
    return Uncoloured(step.text) == Uncoloured(pinned.text) and (step.done and true or false) == (pinned.done and true or false)
end

--- Point at the place on step `index` of the quest shown (a click on that
--- step in the quest panel). Turns the arrow on. False when that step has
--- no place.
function QuestArrow:Aim(index)
    self.free = nil
    local quest = self:Quest()
    if not quest then return false end
    local ok, steps = pcall(ns.UpgradeQuest.Steps, ns.UpgradeQuest, quest)
    local step = ok and type(steps) == "table" and steps[index]
    local place = step and step.place
    if not (type(place) == "table" and place.zone) then return false end

    -- On first: turning it on forgets any earlier pick.
    if not QuestArrow.IsOn() then
        self:SetOn(true)
        ns.Print(L["quest arrow on. To hide it, click its red gem, type /beq arrow off or use Settings."])
    end
    self.pinned = { stamp = Stamp(quest), key = QuestArrow.Key({ zone = place.zone,
        x = tonumber(place.x), y = tonumber(place.y) }), place = {
        zone = place.zone, x = tonumber(place.x), y = tonumber(place.y), name = place.name,
        step = index, text = step.text }, text = step.text, done = step.done }
    self.choice = nil
    if ns.QuestArrowUI and ns.QuestArrowUI.Claim then ns.QuestArrowUI:Claim() end
    self:Changed(false)
    return true
end

--- Point at a quest in the quest log (the Quest log tab's "Point the arrow
--- here"): its place, not a step of the upgrade quest. Kept until a step is
--- aimed at, the arrow is clicked for the next tab or turned off, or the
--- quest leaves the log. Turns the arrow on.
function QuestArrow:AimAtQuest(questID, title, place)
    if not (type(place) == "table" and type(place.zone) == "string") then return false end
    self.free = { free = true, questID = questID, title = title or L["Quest"],
        place = { zone = place.zone, x = tonumber(place.x), y = tonumber(place.y), name = place.name } }
    self.pinned, self.choice = nil, nil
    if not QuestArrow.IsOn() then
        ns.db.questArrow = true
        ns.Print(L["quest arrow on. To hide it, click its red gem, type /beq arrow off or use Settings."])
        for _, name in ipairs({ "QuestPanel", "SettingsUI" }) do
            local module = ns[name]
            if module and module.OnQuestArrowChanged then pcall(module.OnQuestArrowChanged, module) end
        end
    end
    if ns.QuestArrowUI and ns.QuestArrowUI.Claim then ns.QuestArrowUI:Claim() end
    self:Changed(false)
    return true
end

--- The quest log quest the arrow points at, if any: { questID, title }.
function QuestArrow:FreeQuest()
    return self.free
end

--- A quest left the log (handed in or abandoned): stop pointing at it.
function QuestArrow:ForgetQuest(questID)
    if questID ~= nil and self.free and self.free.questID == questID then
        self.free = nil
        self:Changed(true)
    end
end

--- The next tab along that has a quest; it shows on the panel too. Nil when
--- no other tab has one.
function QuestArrow:NextTab()
    local upgrade = ns.UpgradeQuest
    if not upgrade then return nil end
    -- Pointing at a quest from the log: back to the upgrade quests.
    if self.free then
        self.free = nil
        self:Changed(true)
        if upgrade:Current() then return { key = upgrade:Tab() } end
    end
    local tabs = upgrade.TABS
    local at = 1
    for index, tab in ipairs(tabs) do
        if tab.key == upgrade:Tab() then at = index end
    end
    for step = 1, #tabs - 1 do
        local tab = tabs[(at - 1 + step) % #tabs + 1]
        if upgrade:QuestOn(tab.key) then
            upgrade:SelectTab(tab.key)
            self:Changed(true)
            return tab
        end
    end
    return nil
end

--- The next place for the same quest. Nil when there is no other.
function QuestArrow:NextPlace()
    local count = #(self.targets or {})
    if count <= 1 then return nil end
    self.pinned = nil
    self.index = (self.index or 1) % count + 1
    local target = self.targets[self.index]
    self.choice = QuestArrow.Key(target)
    return target
end

--------------------------------------------------------------------------------
-- Where the player is
--------------------------------------------------------------------------------

local function MapInfo(mapID)
    local map = Map()
    if not (map and mapID) then return nil end
    local info = Read(map.GetMapInfo, mapID)
    if type(info) ~= "table" then return nil end
    local ok, name, kind, parent = pcall(function()
        return info.name, info.mapType, info.parentMapID
    end)
    if not ok then return nil end
    return { name = Plain(name), mapType = Number(kind), parent = Number(parent) }
end

--- A point on a map as world coordinates: continent, north, west (yards).
--- Nil when the client will not say.
function QuestArrow.WorldPos(mapID, x, y)
    local map = Map()
    if not (map and mapID and x and y) then return nil end
    if type(map.GetWorldPosFromMapPos) ~= "function" or type(_G.CreateVector2D) ~= "function" then
        return nil
    end
    local ok, continent, position = pcall(map.GetWorldPosFromMapPos, mapID, _G.CreateVector2D(x, y))
    if not ok or type(position) ~= "table" then return nil end
    local read, north, west = pcall(position.GetXY, position)
    if not read then return nil end
    continent, north, west = Number(continent), Number(north), Number(west)
    if not (continent and north and west) then return nil end
    return continent, north, west
end

local mapSizes = {}

--- How big a map is, in yards: width, height. Nil when the client will not
--- say. Kept once read.
function QuestArrow.MapSize(mapID)
    local kept = mapSizes[mapID]
    if kept then return kept[1], kept[2] end
    if kept == false then return nil end
    local map = Map()
    if not (map and mapID) then return nil end

    local width, height
    local ok, w, h = pcall(map.GetMapWorldSize, mapID)
    if ok then width, height = Number(w), Number(h) end

    -- The older way round: where the map's two corners are in the world.
    -- Across a map is along the world's west axis, down it along north.
    if not (width and height and width > 0 and height > 0) then
        local _, ax, ay = QuestArrow.WorldPos(mapID, 0, 0)
        local _, bx, by = QuestArrow.WorldPos(mapID, 1, 1)
        if ax and ay and bx and by then
            width, height = math.abs(ay - by), math.abs(ax - bx)
        end
    end

    if width and height and width > 0 and height > 0 then
        mapSizes[mapID] = { width, height }
        return width, height
    end
    mapSizes[mapID] = false
    return nil
end

--- Which way the player faces, radians anticlockwise from north. Nil if
--- not read.
function QuestArrow.Facing()
    return Number(Read(_G.GetPlayerFacing))
end

--- Where the player stands: { map, x, y (0-1), continent, north, west,
--- zone }, or nil when the client will not say (inside an instance,
--- usually).
function QuestArrow:Here()
    local map = Map()
    if not map then return nil end
    local mapID = Number(Read(map.GetBestMapForUnit, "player"))
    if not mapID then return nil end
    local position = Read(map.GetPlayerMapPosition, mapID, "player")
    if position == nil then return nil end
    local ok, x, y = pcall(function()
        if type(position) == "table" and position.GetXY then
            local px, py = position:GetXY()
            return px + 0, py + 0
        end
        return position + 0, nil
    end)
    if not ok or not x or not y or (x == 0 and y == 0) then return nil end

    local here = { map = mapID, x = x, y = y }
    here.continent, here.north, here.west = QuestArrow.WorldPos(mapID, x, y)
    here.zone = ns.UpgradeQuest and ns.UpgradeQuest.Zone() or nil
    return here
end

--- Inside a dungeon, raid or battleground: the game keeps the position to
--- itself there.
function QuestArrow.Inside()
    local ok, inside = pcall(function()
        return type(_G.IsInInstance) == "function" and _G.IsInInstance() and true or false
    end)
    return ok and inside or false
end

--- The continent map the map `mapID` sits on, or nil.
function QuestArrow.ContinentOf(mapID)
    for _ = 1, 8 do
        local info = MapInfo(mapID)
        if not info then return nil end
        if info.mapType == CONTINENT then return mapID end
        if not info.parent or info.parent <= 0 then return nil end
        mapID = info.parent
    end
    return nil
end

--------------------------------------------------------------------------------
-- Measuring
--------------------------------------------------------------------------------

--- Yards north and west from `here` to a point `x`, `y` (0-1) on map
--- `mapID`, or nil when the two cannot be put on one grid. A target's world
--- position is read once and kept on it.
function QuestArrow.Offset(here, mapID, x, y, target)
    if not (here and mapID and x and y) then return nil end

    if here.continent then
        local continent, north, west
        if target and target.world then
            continent, north, west = target.world[1], target.world[2], target.world[3]
        else
            continent, north, west = QuestArrow.WorldPos(mapID, x, y)
            if target and continent then target.world = { continent, north, west } end
        end
        if continent and continent == here.continent then
            return north - here.north, west - here.west
        end
        if continent then return nil end
    end

    -- No world coordinates: only the map the player is on can be measured.
    if mapID ~= here.map then return nil end
    local width, height = QuestArrow.MapSize(mapID)
    if not (width and height) then return nil end

    -- Map x runs east, map y runs south.
    return (here.y - y) * height, (here.x - x) * width
end

--- How far, in yards, and which way: radians anticlockwise from north.
function QuestArrow.Measure(north, west)
    return math.sqrt(north * north + west * west), math.atan2(west, north)
end

--- Which way the arrow turns on screen: the bearing less the facing,
--- anticlockwise, as a texture's rotation reads it. North up without a
--- facing.
function QuestArrow.Turn(bearing, facing)
    local turn = bearing - (facing or 0)
    while turn > math.pi do turn = turn - 2 * math.pi end
    while turn < -math.pi do turn = turn + 2 * math.pi end
    return turn
end

local COMPASS = { "north", "northwest", "west", "southwest", "south", "southeast", "east", "northeast" }

--- A bearing as a word: "northwest".
function QuestArrow.Compass(bearing)
    local step = math.floor((bearing / (math.pi / 4)) + 0.5) % 8
    return COMPASS[step + 1]
end

--- Rounded yards: "8 yd", "140 yd", "1,250 yd".
function QuestArrow.Yards(yards)
    local whole = math.floor(yards + 0.5)
    if whole >= 1000 then
        return L.Format("%d,%03d yd", math.floor(whole / 1000), whole % 1000)
    end
    if whole >= 100 then whole = math.floor(whole / 10 + 0.5) * 10 end
    return L.Format("%d yd", whole)
end

--------------------------------------------------------------------------------
-- The targets
--------------------------------------------------------------------------------

--- The quest's places as targets from `here`, in step order: each is a
--- place with { map, exact, area, here, far } worked out.
function QuestArrow:Targets(quest, here)
    local list = {}
    local pinned = self.pinned
    if pinned and pinned.stamp ~= Stamp(quest) then
        pinned, self.pinned = nil, nil
    end

    local places, steps, current = self:Places(quest)
    -- Kept for the dial's step line, so the steps are read once a listing.
    self.readSteps, self.readCurrent = steps, current
    if pinned and not QuestArrow.PinHolds(pinned, steps) then
        pinned, self.pinned = nil, nil
    end
    -- A place picked on the panel goes first, even one before the step to
    -- do now, until that step moves on.
    if pinned then
        for index, place in ipairs(places) do
            if QuestArrow.Key(place) == pinned.key then
                table.remove(places, index)
                break
            end
        end
        table.insert(places, 1, pinned.place)
    end

    for _, place in ipairs(places) do
        local target = {
            zone = place.zone, name = place.name, step = place.step, text = place.text,
            x = place.x, y = place.y, forQuest = place.forQuest,
        }
        local mapID = ns.Waypoints and ns.Waypoints:MapFor(place.zone)
        target.map = mapID
        if mapID and place.x and place.y then
            target.mx, target.my = place.x / 100, place.y / 100
            if QuestArrow.Offset(here, mapID, target.mx, target.my, target) then
                target.exact = true
            else
                target.far = true
            end
        elseif mapID and here and place.zone == here.zone then
            target.here = true
        elseif mapID then
            target.mx, target.my, target.area = 0.5, 0.5, true
            if not QuestArrow.Offset(here, mapID, 0.5, 0.5, target) then
                target.area, target.far = nil, true
            end
        else
            target.far = true
        end
        list[#list + 1] = target
    end
    return list
end

--------------------------------------------------------------------------------
-- What the dial shows
--------------------------------------------------------------------------------

--- Where a place is, in a line: "Corina Steele, Elwynn Forest".
function QuestArrow.Place(target, here)
    local name = target.name
    -- The game's own names, on a client in another language; the target
    -- keeps the data's.
    local names = ns.Names
    local zone = target.zone and names and names:Zone(target.zone) or target.zone
    if not name or name == target.zone then return zone or "?" end
    if names then name = names:NPC(names:Zone(name)) end
    if target.zone and not (here and here.zone == target.zone) then
        return L.Format("%s, %s", name, zone)
    end
    return name
end

--- The note under a place: what the step is, or why there is no spot.
function QuestArrow.Note(target)
    if target.far then
        local zone = target.zone and ns.Names and ns.Names:Zone(target.zone) or target.zone
        return L.Format("Far from here: head for %s", zone or L["it"]), "muted"
    end
    if target.here then return L["No exact spot known in this zone"], "accent" end
    if target.area then return L["The middle of the zone, since no exact spot is known"], "accent" end
    if target.forQuest then return target.forQuest, "good" end
    return L.Format("Step %d", target.step or 1), "good"
end

--- Everything the dial needs for this moment:
---   { mode, quest, name, target, index, count, turn, yards, distance,
---     place, note, noteColor }
--- `mode` is "off", "inside", "none" (no quest), "blind" (no position),
--- "nowhere" (no place in the steps left), "point", "arrived", "here" or
--- "far".
function QuestArrow:State(clock)
    if not QuestArrow.IsOn() then return { mode = "off" } end
    if QuestArrow.Inside() then return { mode = "inside" } end

    local quest = self:Quest()
    if not quest then return { mode = "none" } end

    local here = self:Here()
    local state = { quest = quest, name = QuestArrow.ItemName(quest) }

    -- The places are worked out again now and then (the steps read the
    -- quest log and bags), or at once for a new quest. A place picked with a
    -- right-click stays picked while it is still listed.
    clock = clock or 0
    local stamp = Stamp(quest)
    local every = quest.free and QuestArrow.REFRESH_FREE or QuestArrow.REFRESH
    -- A list made while the client would not say where you are (just after
    -- a loading screen) calls every spot far; it is made again as soon as
    -- the position is back, not after REFRESH.
    if self.stamp ~= stamp or not self.listedAt or clock - self.listedAt >= every
        or clock < self.listedAt or (here and self.listedBlind) then
        self.listedBlind = here == nil
        if self.stamp ~= stamp then self.choice = nil end
        self.targets = self:Targets(quest, here)
        self.listedAt = clock
        self.stamp = stamp
        -- With no place to point at, the dial names the step to do instead.
        -- Read here, with the places, rather than 33 times a second.
        self.stepText = nil
        if #self.targets == 0 and not quest.free then
            local steps, current = self.readSteps, self.readCurrent
            local step = type(steps) == "table" and current and steps[current]
            self.stepText = type(step) == "table" and step.text or nil
        end

        self.index = 1
        if self.choice then
            local found = false
            for index, target in ipairs(self.targets) do
                if QuestArrow.Key(target) == self.choice then
                    self.index, found = index, true
                    break
                end
            end
            if not found then self.choice = nil end
        end
    end

    if not here then
        state.mode = "blind"
        return state
    end

    local targets = self.targets or {}
    state.count = #targets
    if #targets == 0 then
        state.mode = "nowhere"
        state.step = self.stepText
        return state
    end

    if (self.index or 1) > #targets then self.index = 1 end
    state.index = self.index or 1
    local target = targets[state.index]
    state.target = target
    state.place = QuestArrow.Place(target, here)
    state.note, state.noteColor = QuestArrow.Note(target)

    -- A place in another zone or on the other continent: the way there,
    -- step by step, the arrow on the next stop (Logic/Travel.lua).
    local trip = ns.Travel and ns.Travel:Use(target, here, clock)
    if trip then return self:TripState(state, trip, here) end

    -- The zone in the game's own words (Logic/Names.lua).
    local zoneShown = target.zone and ns.Names and ns.Names:Zone(target.zone) or target.zone
    if target.far then
        state.mode = "far"
        state.distance = zoneShown or L["Far away"]
        return state
    end
    if target.here then
        state.mode = "here"
        state.distance = L.Format("In %s", zoneShown or L["this zone"])
        return state
    end

    -- Measured again for this frame.
    local north, west = QuestArrow.Offset(here, target.map, target.mx, target.my, target)
    if not north then
        state.mode = "far"
        state.distance = zoneShown or L["Far away"]
        return state
    end

    local yards, bearing = QuestArrow.Measure(north, west)
    local facing = QuestArrow.Facing()
    state.yards, state.bearing = yards, bearing
    state.turn = QuestArrow.Turn(bearing, facing)
    state.facing = facing ~= nil

    if not target.area and yards <= ARRIVED then
        state.mode = "arrived"
        state.distance = L["You're there"]
        return state
    end

    state.mode = "point"
    if target.area then
        state.distance = L.Format("%s, %s", zoneShown or "?", QuestArrow.Yards(yards))
    else
        state.distance = QuestArrow.Yards(yards)
    end
    return state
end

--- The dial's words and turn for a step of a trip.
function QuestArrow:TripState(state, trip, here)
    state.trip = trip
    state.distance = L.Format("Step %d of %d", trip.index, trip.count)
    state.place = trip.line
    state.note, state.noteColor = trip.small, "muted"

    if trip.continent and trip.continent == here.continent and not trip.onTaxi then
        local yards, bearing = QuestArrow.Measure(trip.north - here.north, trip.west - here.west)
        state.yards, state.bearing = yards, bearing
        local facing = QuestArrow.Facing()
        state.turn = QuestArrow.Turn(bearing, facing)
        state.facing = facing ~= nil
        state.mode = "point"
        local point = ns.Travel.MapPos(trip.continent, trip.north, trip.west)
        if point then point.mx, point.my = point.x, point.y end
        trip.point = point
        if not trip.atStop then
            local far = QuestArrow.Yards(yards)
            state.note = state.note ~= "" and (state.note .. ", " .. far) or far
        end
        return state
    end
    state.mode = "trip"
    return state
end

--------------------------------------------------------------------------------
-- Checking what the client allows
--------------------------------------------------------------------------------

local function YesNo(ok)
    local colors = ns.COLORS
    return ("|c%s%s|r"):format(ok and colors.upgrade or colors.warn, ok and "yes" or "no")
end

--- /beq arrow check: what the arrow can read here, line by line.
function QuestArrow:Check()
    ns.Print("quest arrow check:")
    local here = self:Here()
    ns.PrintRaw(("  map position: %s%s"):format(YesNo(here),
        here and (" (map %d, %.1f, %.1f)"):format(here.map, here.x * 100, here.y * 100) or ""))

    local facing = QuestArrow.Facing()
    ns.PrintRaw(("  facing: %s%s"):format(YesNo(facing),
        facing and (" (%.2f, %s)"):format(facing, QuestArrow.Compass(facing)) or ""))

    ns.PrintRaw(("  world position: %s%s"):format(YesNo(here and here.continent),
        here and here.continent and (" (continent %d, %.0f, %.0f)"):format(here.continent, here.north, here.west)
        or ", so it only points within the map you are on"))

    local width, height
    if here then width, height = QuestArrow.MapSize(here.map) end
    ns.PrintRaw(("  map size: %s%s"):format(YesNo(width),
        width and (" (%.0f by %.0f yards)"):format(width, height) or ""))

    local continent = here and QuestArrow.ContinentOf(here.map)
    ns.PrintRaw(("  continent map: %s%s"):format(YesNo(continent),
        continent and (" (map %d)"):format(continent) or ""))

    ns.PrintRaw(("  in an instance: %s"):format(QuestArrow.Inside() and "yes, so the arrow hides" or "no"))
    if ns.TomTom then ns.PrintRaw(ns.TomTom.CheckLine()) end
    if ns.Travel then
        local count = 0
        for _ in pairs(ns.Travel:AllFlights()) do count = count + 1 end
        ns.PrintRaw(("  way there: %s, %d flight paths known%s"):format(ns.Travel.IsOn() and "on" or "off", count,
            count == 0 and " (open a flight master's map to read them)" or ""))
        local map = _G.C_Map
        ns.PrintRaw(("  world to map: %s"):format(YesNo(map and type(map.GetMapPosFromWorldPos) == "function")))
    end

    local state = self:State(Number(Read(_G.GetTime)) or 0)
    if state.quest then
        local target = state.target
        ns.PrintRaw(("  following: %s%s"):format(state.name or "the upgrade quest",
            target and (", %s, %s"):format(QuestArrow.Place(target, here), state.distance or "")
            or ", no place in the steps left"))
    else
        ns.PrintRaw("  following: no upgrade quest on the tab shown. /beq quest turns it on.")
    end
end

--------------------------------------------------------------------------------
-- /beq arrow
--------------------------------------------------------------------------------

local function Status()
    if QuestArrow.IsOn() then
        if QuestArrow:Quest() then
            ns.Print(L["quest arrow on. Click it for the next tab's quest, right-click for the next place."])
        else
            ns.Print(L["quest arrow on. It shows whenever the upgrade quest has a quest (/beq quest)."])
        end
    else
        ns.Print(L["quest arrow off. /beq arrow on brings it back."])
    end
end

ns.RegisterCommand("arrow", L["an arrow to the upgrade quest's next place (on, off, next, check, tomtom, route, reset)"], function(rest)
    local word = (rest or ""):lower():match("^%s*(%a*)") or ""
    if word == "" then
        QuestArrow:SetOn(not QuestArrow.IsOn())
        Status()
    elseif word == "on" or word == "off" then
        QuestArrow:SetOn(word == "on")
        Status()
    elseif word == "next" then
        local target = QuestArrow:NextPlace()
        if target then
            ns.Print(L.Format("pointing at %s.", QuestArrow.Place(target)))
        else
            ns.Print(L["no other place in this quest's steps."])
        end
    elseif word == "check" then
        ns.KeepCheck("arrow check", QuestArrow.Check, QuestArrow)
    elseif word == "tomtom" then
        ns.TomTom:Command((rest or ""):lower():match("^%s*%a+%s+(%a+)"))
    elseif word == "route" then
        local Travel = ns.Travel
        local switch = (rest or ""):lower():match("^%s*%a+%s+(%a+)")
        if switch == "on" or switch == "off" then Travel:SetOn(switch == "on") else Travel:SetOn(not Travel.IsOn()) end
        if Travel.IsOn() then
            ns.Print(L["The arrow leads you step by step to places far away."])
        else
            ns.Print(L["The arrow points straight at places far away."])
        end
        if ns.SettingsUI and ns.SettingsUI.Refresh then pcall(ns.SettingsUI.Refresh, ns.SettingsUI) end
    elseif word == "reset" then
        if ns.QuestArrowUI and ns.QuestArrowUI.ResetPosition then ns.QuestArrowUI:ResetPosition() end
        ns.Print(L["quest arrow put back where it started."])
    else
        ns.Print(L["/beq arrow on, off, next, check, tomtom, route or reset."])
    end
end)

--------------------------------------------------------------------------------
-- What Logic/Travel.lua (the same file in every addon) asks of Equipment
--------------------------------------------------------------------------------

ns.TravelHost = {
    DB = function() return ns.db end,
    Owner = function() return ns.Alts and ns.Alts.PlayerGUID and ns.Alts.PlayerGUID() or nil end,
    ZoneOf = function(zone)
        local name = zone
        if type(zone) == "string" and ns.Waypoints and ns.Waypoints.DataZone then
            local ok, english = pcall(ns.Waypoints.DataZone, ns.Waypoints, zone)
            if ok and type(english) == "string" then name = english end
        end
        return ns.Travel.Defaults.ZoneOf(name)
    end,
    Here = function() return QuestArrow:Here() end,
    InInstance = function() return QuestArrow.Inside() end,
    Key = function(target)
        return ("%s|%s|%s|%s"):format(tostring(target.zone), tostring(target.name), tostring(target.x), tostring(target.y))
    end,
    Changed = function() QuestArrow:Changed() end,
    Refresh = function() if ns.QuestArrowUI and ns.QuestArrowUI.Refresh then ns.QuestArrowUI:Refresh() end end,
    State = function() return ns.QuestArrowUI and ns.QuestArrowUI.state end,
    Print = function(text) ns.Print(text) end,
}
