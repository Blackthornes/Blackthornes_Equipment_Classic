-- The quest arrow: Farmer's arrow brought to the upgrade quest.
--
-- What matters: it is off until turned on, and /beq arrow, the quest
-- panel's Arrow button and Settings share the switch; it follows the quest
-- on the tab shown and points at the next place in its steps, a vendor's
-- spot beating "Travel to" its zone; it measures across zones in yards and
-- turns the right way for where you face; close enough is "You're there"; a
-- zone with no spot points at its middle and says so, the zone you are in
-- says so, and the other continent gets no arrow; a click on a step aims it
-- there; a click on the dial moves to the next tab's quest; a client
-- without world coordinates still points within the map you are on; an
-- unreadable position breaks nothing; and inside a dungeon it hides.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("questarrow")

local function Agi(n) return { ITEM_MOD_AGILITY_SHORT = n } end
local function Chest(n) return { loc = "INVTYPE_CHEST", class = 4, subclass = 2, stats = Agi(n) } end

local ITEMS = {
    ["item:900"] = Chest(10),    -- worn
    ["item:1002"] = Chest(40),   -- a vendor's in Westfall
    ["item:1003"] = Chest(30),   -- a quest from Elwynn Forest
}

local ns = env.Load()
_G.UnitClass = function() return "Hunter", "HUNTER", 3 end
_G.UnitFactionGroup = function() return "Alliance", "Alliance" end
_G.UnitRace = function() return "Human", "Human", 1 end
local zone = "Elwynn Forest"
_G.GetRealZoneText = function() return zone end
env.InstallItems(ITEMS, { [5] = "item:900" }, { [0] = {} }, 20)
_G.C_QuestLog = { IsQuestFlaggedCompleted = function() return false end }

local S = ns.Sources
ns.Crafts.ITEMS = {}
ns.RollData.ITEMS = {}
S.ZONES = { [12] = "Elwynn Forest", [40] = "Westfall" }
S.NPCS = {
    [2] = { "Kirsta Deepshadow", 40, 56.3, 31.0, "A" },
}
S.QUESTS = {
    [10] = { "Wolves of the Forest", 15, 18, 0, 0, "Marshal Dughan", 12, 42.1, 65.9, "" },
}
S.DUNGEONS = {}
S.BOSSES = {}
S.FOREVER = {}
S.ITEMS = {
    [1002] = { 15, 18, 0, 0, 500, v = { 2, 0 } },
    [1003] = { 15, 18, 0, 0, 0, q = { 10 } },
}

local Arrow, ArrowUI, Quest, Panel = ns.QuestArrow, ns.QuestArrowUI, ns.UpgradeQuest, ns.QuestPanel

--------------------------------------------------------------------------------
-- The maps: two zones side by side, Durotar across the sea
--------------------------------------------------------------------------------

local clock = 100
_G.GetTime = function() return clock end
local inside = false
_G.IsInInstance = function() return inside, inside and "party" or "none" end
local facing = 0
_G.GetPlayerFacing = function() return facing end

-- World coordinates: north runs up the map, west runs left.
local MAPS = {
    [37] = { name = "Elwynn Forest", mapType = 3, parentMapID = 13, continent = 0,
        top = 0, left = 0, width = 3000, height = 2000 },
    [52] = { name = "Westfall", mapType = 3, parentMapID = 13, continent = 0,
        top = -1500, left = 2600, width = 2500, height = 1700 },
    [10] = { name = "Duskwood", mapType = 3, parentMapID = 13, continent = 0,
        top = -1800, left = -1000, width = 2000, height = 2000 },
    [13] = { name = "Eastern Kingdoms", mapType = 2, parentMapID = 947 },
    [1] = { name = "Durotar", mapType = 3, parentMapID = 12, continent = 1,
        top = 0, left = 0, width = 2000, height = 2000 },
    [12] = { name = "Kalimdor", mapType = 2, parentMapID = 947 },
    [947] = { name = "Azeroth", mapType = 1 },
}

_G.CreateVector2D = function(x, y) return { x = x, y = y, GetXY = function(self) return self.x, self.y end } end

local where = { map = 37, x = 0.45, y = 0.50 }
local worldCoords = true

_G.C_Map = {
    GetBestMapForUnit = function() return where.map end,
    GetPlayerMapPosition = function() return _G.CreateVector2D(where.x, where.y) end,
    GetMapInfo = function(mapID)
        local map = MAPS[mapID]
        if not map then return nil end
        return { name = map.name, mapType = map.mapType, parentMapID = map.parentMapID, mapID = mapID }
    end,
    -- Every map under one, as the game's all-descendants form gives them.
    GetMapChildrenInfo = function(mapID)
        local children = {}
        local function Under(parent)
            for id, map in pairs(MAPS) do
                if map.parentMapID == parent then
                    children[#children + 1] = { name = map.name, mapType = map.mapType, mapID = id }
                    Under(id)
                end
            end
        end
        Under(mapID)
        return children
    end,
    GetWorldPosFromMapPos = function(mapID, vector)
        if not worldCoords then error("no world coordinates here") end
        local map = MAPS[mapID]
        if not (map and map.width) then return nil end
        local north = map.top - vector.y * map.height
        local west = map.left - vector.x * map.width
        return map.continent, { GetXY = function() return north, west end }
    end,
    GetMapWorldSize = function(mapID)
        local map = MAPS[mapID]
        if map and map.width then return map.width, map.height end
        return nil
    end,
}

local function near(a, b, within) return a and b and math.abs(a - b) < (within or 0.01) end

-- Yards and bearing the test expects between two map points.
local function Expect(fromMap, fx, fy, toMap, tx, ty)
    local a, b = MAPS[fromMap], MAPS[toMap]
    local north = (b.top - ty * b.height) - (a.top - fy * a.height)
    local west = (b.left - tx * b.width) - (a.left - fx * a.width)
    return math.sqrt(north * north + west * west), math.atan2(west, north)
end

--------------------------------------------------------------------------------
-- Off until asked for
--------------------------------------------------------------------------------

suite.check("off by default", ns.db.questArrow == false and Arrow:State(clock).mode == "off")

ns.HandleSlash("arrow")
suite.check("/beq arrow turns it on", Arrow.IsOn())
suite.check("with the upgrade quest off there is nothing to follow", Arrow:State(clock).mode == "none")
ArrowUI:Refresh()
suite.check("and the dial stays hidden", not (ArrowUI.frame and ArrowUI.frame:IsShown()))

Quest:SetEnabled(true)
Quest:SelectTab("vendor")
suite.check("the vendor tab has its quest", Quest:Current() and Quest:Current().itemID == 1002)

--------------------------------------------------------------------------------
-- Pointing at the vendor
--------------------------------------------------------------------------------

local places = Arrow:Places()
suite.check("one place: the vendor's spot, not Travel to Westfall", #places == 1
    and places[1].name == "Kirsta Deepshadow" and places[1].x == 56.3, #places)

Arrow:Changed()
local state = Arrow:State(clock)
suite.check("points", state.mode == "point", state.mode)
local yards, bearing = Expect(37, 0.45, 0.50, 52, 0.563, 0.31)
suite.check("across two zones, in yards", near(state.yards, yards, 0.5), state.yards)
suite.check("the right way", near(state.bearing, bearing), state.bearing)
suite.check("named with its zone", state.place == "Kirsta Deepshadow, Westfall", state.place)
suite.check("and the step it is", state.note == "Step 2", state.note)
suite.check("distance reads in yards", state.distance == Arrow.Yards(yards), state.distance)
suite.check("yards read plainly", Arrow.Yards(8.4) == "8 yd" and Arrow.Yards(143) == "140 yd"
    and Arrow.Yards(1250) == "1,250 yd")

facing = 0
suite.check("facing north it turns by the bearing", near(Arrow:State(clock).turn, Arrow.Turn(bearing, 0)))
facing = bearing
suite.check("facing it, straight ahead", near(Arrow:State(clock).turn, 0))
facing = 0

-- The dial draws it.
ArrowUI:Refresh()
suite.check("the dial shows", ArrowUI.frame and ArrowUI.frame:IsShown())
suite.check("the plate names the upgrade", ArrowUI.title:GetText() == "Item", ArrowUI.title:GetText())
suite.check("the distance under it", ArrowUI.distance:GetText() == Arrow.Yards(yards), ArrowUI.distance:GetText())
suite.check("the arrow is up", ArrowUI.arrow:IsShown() and not ArrowUI.check:IsShown())
suite.check("no tooltip on the dial", ArrowUI.frame:GetScript("OnEnter") == nil and ArrowUI.ShowTooltip == nil)
suite.check("no click on the dial", ArrowUI.frame:GetScript("OnMouseUp") == nil and ArrowUI.OnClick == nil)

-- Standing at the vendor.
zone = "Westfall"
where = { map = 52, x = 0.5632, y = 0.3101 }
clock = clock + 5
state = Arrow:State(clock)
suite.check("close enough is You're there", state.mode == "arrived" and state.distance == "You're there",
    state.mode)
ArrowUI:Draw(true)
suite.check("with the green check", ArrowUI.check:IsShown() and not ArrowUI.arrow:IsShown())

--------------------------------------------------------------------------------
-- Inside, and unreadable
--------------------------------------------------------------------------------

inside = true
suite.check("inside a dungeon it hides", Arrow:State(clock).mode == "inside")
ArrowUI:Draw(true)
suite.check("the dial too", not ArrowUI.frame:IsShown())
inside = false

local saved = _G.C_Map.GetPlayerMapPosition
_G.C_Map.GetPlayerMapPosition = function() error("secret value") end
Arrow.listedAt = nil
suite.check("an unreadable position says so", Arrow:State(clock).mode == "blind")
_G.C_Map.GetPlayerMapPosition = saved
suite.check("a list made blind is made again once the position is back",
    Arrow:State(clock + 0.1).mode ~= "far", Arrow:State(clock + 0.1).mode)

-- Without world coordinates, only the map you are on can be measured.
worldCoords = false
where = { map = 52, x = 0.50, y = 0.31 }
clock = clock + 5
state = Arrow:State(clock)
suite.check("no world coordinates, same map: still points", state.mode == "point", state.mode)
suite.check("measured with the map's size", near(state.yards, (0.563 - 0.50) * 2500, 0.5), state.yards)
zone = "Elwynn Forest"
where = { map = 37, x = 0.45, y = 0.50 }
clock = clock + 5
suite.check("another map: no arrow", Arrow:State(clock).mode == "far", Arrow:State(clock).mode)
worldCoords = true

-- With "Guide Me:" unticked the arrow only names a zone across the sea
-- (test_travel.lua has it ticked).
ns.db.arrowRoute = false
-- The other continent.
zone = "Durotar"
where = { map = 1, x = 0.5, y = 0.5 }
clock = clock + 5
state = Arrow:State(clock)
suite.check("from another continent: no arrow, just the zone", state.mode == "far"
    and state.distance == "Westfall", state.distance)
ArrowUI:Draw(true)
suite.check("a question mark instead", ArrowUI.mark:IsShown() and not ArrowUI.arrow:IsShown())
zone = "Elwynn Forest"
where = { map = 37, x = 0.45, y = 0.50 }

--------------------------------------------------------------------------------
-- A zone with no spot
--------------------------------------------------------------------------------

-- A quest giver nobody has a spot for: the zone only.
Quest:Quests().vendor.source.x, Quest:Quests().vendor.source.y = nil, nil
Arrow:Changed()
clock = clock + 5
state = Arrow:State(clock)
suite.check("a zone with no spot: its middle", state.mode == "point" and state.target.area, state.mode)
suite.check("and says so", state.note:find("no exact spot", 1, true) ~= nil, state.note)
suite.check("naming the zone with the distance", state.distance:find("^Westfall, ") ~= nil, state.distance)
suite.check("never You're there", (function()
    zone = "Westfall"
    where = { map = 52, x = 0.5, y = 0.5 }
    clock = clock + 5
    return Arrow:State(clock).mode == "here"
end)())
suite.check("in that zone it says so", Arrow:State(clock).distance == "In Westfall")
Quest:Quests().vendor.source.x, Quest:Quests().vendor.source.y = 56.3, 31.0
zone = "Elwynn Forest"
where = { map = 37, x = 0.45, y = 0.50 }
Arrow:Changed()

--------------------------------------------------------------------------------
-- The panel: the Arrow button, and steps that aim it
--------------------------------------------------------------------------------

Panel:Refresh()
suite.check("the panel has an Arrow button", Panel.arrowButton and Panel.arrowButton:IsShown())
Panel.arrowButton:GetScript("OnClick")(Panel.arrowButton)
suite.check("which turns it off", not Arrow.IsOn())
Panel.arrowButton:GetScript("OnClick")(Panel.arrowButton)
suite.check("and on", Arrow.IsOn())
Panel.arrowButton:GetScript("OnEnter")(Panel.arrowButton)
tip = table.concat(GameTooltip._lines, "\n")
suite.check("and says what it does", tip:find("Points the way", 1, true) ~= nil, tip)
Panel.arrowButton:GetScript("OnLeave")(Panel.arrowButton)

-- The footer still fits: Show on map and Arrow on the left, Change and
-- Ignore on the right.
local left = 10 + Panel.mapButton:GetWidth() + 6 + Panel.arrowButton:GetWidth()
local right = 340 - 10 - Panel.skipButton:GetWidth() - 6 - Panel.otherButton:GetWidth()
suite.check("the buttons along the bottom do not touch", left + 6 <= right, left .. " " .. right)

-- Off, a click on a step turns it on and aims it.
ns.HandleSlash("arrow off")
local row
for _, candidate in ipairs(Panel.steps) do
    if candidate:IsShown() and candidate.place and candidate.place.x then row = candidate break end
end
suite.check("a step with a spot can be clicked", row ~= nil)
row:GetScript("OnEnter")(row)
tip = table.concat(GameTooltip._lines, "\n")
suite.check("hovering it says so", tip:find("Point the quest arrow here", 1, true) ~= nil, tip)
row:GetScript("OnLeave")(row)
row:GetScript("OnMouseUp")(row, "LeftButton")
suite.check("clicking it turns the arrow on", Arrow.IsOn())
suite.check("aimed at that step", Arrow.pinned and Arrow.pinned.place.step == row.index)
clock = clock + 5
suite.check("and pointing there", Arrow:State(clock).target.name == "Kirsta Deepshadow")

-- A step with a zone only: the Travel step.
suite.check("a Travel step aims at the zone", Arrow:Aim(1) and (function()
    clock = clock + 5
    local s = Arrow:State(clock)
    return s.target.area and s.target.zone == "Westfall"
end)())
suite.check("a step with no place cannot be aimed at", not Arrow:Aim(4))

--------------------------------------------------------------------------------
-- The next tab's quest
--------------------------------------------------------------------------------

suite.check("the quest tab has its own quest", Quest:QuestOn("quest") and Quest:QuestOn("quest").itemID == 1003)
Arrow:NextTab()
suite.check("the next tab with a quest shows", Quest:Tab() == "quest", Quest:Tab())
suite.check("and forgets the vendor's step", Arrow.pinned == nil)
clock = clock + 5
state = Arrow:State(clock)
suite.check("pointing at the quest giver", state.target and state.target.name == "Marshal Dughan",
    state.target and state.target.name)
yards = Expect(37, 0.45, 0.50, 37, 0.421, 0.659)
suite.check("in the zone you are in, by name alone", state.place == "Marshal Dughan" and near(state.yards, yards, 0.5),
    state.place)

--------------------------------------------------------------------------------
-- TomTom: its arrow instead of the dial, when it is installed
--------------------------------------------------------------------------------

do
    local TomTom = ns.TomTom
    local dial = ArrowUI.frame
    ArrowUI:Draw(true)
    suite.check("without TomTom the dial shows", dial:IsShown() and TomTom.uid == nil)
    suite.check("the TomTom switch is on unless unticked", TomTom.IsOn())

    -- A TomTom keeping its waypoints, as the real one's calls take them.
    local points = {}
    _G.TomTom = {
        AddWaypoint = function(self, map, x, y, opts)
            local uid = { map, x, y, title = opts and opts.title }
            points[uid] = opts
            return uid
        end,
        RemoveWaypoint = function(self, uid) points[uid] = nil end,
    }
    local function Count()
        local count = 0
        for _ in pairs(points) do count = count + 1 end
        return count
    end

    local shownState = ArrowUI.state
    ArrowUI:Draw(true)
    local uid = TomTom.uid
    suite.check("with TomTom the dial hides", not dial:IsShown(), ArrowUI.state.mode)
    suite.check("and TomTom gets one waypoint", Count() == 1, Count())
    suite.check("at the dial's place", uid and uid[1] == ArrowUI.state.target.map
        and uid[2] == ArrowUI.state.target.mx and uid[3] == ArrowUI.state.target.my)
    suite.check("named for what it follows", uid and uid.title:find("Marshal Dughan", 1, true) ~= nil,
        uid and uid.title)
    suite.check("on TomTom's arrow, not saved in its list",
        uid and points[uid].crazy == true and points[uid].persistent == false)
    suite.check("this arrow still holds the screen over the others", _G.BlackthornesArrows.wants["Equipment"])

    ArrowUI:Draw(true)
    suite.check("drawn again, the same waypoint stays", TomTom.uid == uid and Count() == 1)

    -- TomTom clears a waypoint on arrival (or the player removes it): the
    -- dial comes back rather than leaving nothing pointing the way.
    _G.TomTom.IsValidWaypoint = function(self, id) return points[id] ~= nil end
    points[uid] = nil
    ArrowUI:Draw(true)
    suite.check("a waypoint TomTom dropped brings the dial back", dial:IsShown() and Count() == 0)
    ArrowUI:Draw(true)
    suite.check("and it is not put back on TomTom for the same place", dial:IsShown() and Count() == 0)
    _G.TomTom.IsValidWaypoint = nil
    -- Turning the arrow off and on offers the place to TomTom again.
    ns.HandleSlash("arrow off")
    ns.HandleSlash("arrow on")
    ArrowUI:Draw(true)
    uid = TomTom.uid
    suite.check("a fresh waypoint once the arrow is turned off and on", not dial:IsShown() and Count() == 1,
        tostring(dial:IsShown()) .. " " .. Count())

    -- Another Blackthornes arrow aimed later: TomTom's goes too.
    local shared = _G.BlackthornesArrows
    shared.wants.Other, shared.claims.Other = true, 1e12
    ArrowUI:Draw(true)
    suite.check("another addon's arrow aimed later takes it away", Count() == 0)
    shared.wants.Other, shared.claims.Other = nil, nil
    ArrowUI:Draw(true)
    suite.check("and it comes back once that one is put away", Count() == 1)

    ns.HandleSlash("arrow tomtom off")
    ArrowUI:Draw(true)
    suite.check("arrow tomtom off: the dial again", ns.db.useTomTom == false and dial:IsShown() and Count() == 0)
    ns.HandleSlash("arrow tomtom on")
    ArrowUI:Draw(true)
    suite.check("and on: TomTom again", not dial:IsShown() and Count() == 1)

    ns.SettingsUI:Show()
    local box = ns.SettingsUI.controls.useTomTom
    suite.check("Settings has the TomTom switch, ticked", box and box:GetChecked() == true)
    box:GetScript("OnClick")(box)
    suite.check("which unticks it", ns.db.useTomTom == false and Count() == 0)
    box:GetScript("OnClick")(box)
    suite.check("and ticks it again", ns.db.useTomTom == true)
    ns.SettingsUI:Hide()
    ArrowUI:Draw(true)

    ns.HandleSlash("arrow off")
    suite.check("the arrow off takes the waypoint away", Count() == 0)
    ns.HandleSlash("arrow on")

    -- A TomTom that raises, or lacks the calls: the dial, and no error.
    _G.TomTom.AddWaypoint = function() error("different version") end
    TomTom:Clear()
    TomTom.refused = nil
    local okDraw = pcall(ArrowUI.Draw, ArrowUI, true)
    suite.check("a TomTom that raises falls back to the dial", okDraw and dial:IsShown())
    _G.TomTom = { AddWaypoint = "no" }
    TomTom.refused = nil
    ArrowUI:Draw(true)
    suite.check("so does one without the calls", dial:IsShown() and not TomTom.Installed())
    local okCheck, errCheck = pcall(ns.HandleSlash, "arrow check")
    suite.check("arrow check says what TomTom does", okCheck and env.ChatText():find("TomTom", 1, true) ~= nil, errCheck)
    _G.TomTom = nil
    TomTom.refused = nil
    ArrowUI.state = shownState
end
Arrow:NextTab()
suite.check("and round again", Quest:Tab() == "vendor", Quest:Tab())

suite.check("one place: there is no other to step to", Arrow:NextPlace() == nil)

--------------------------------------------------------------------------------
-- Got: nothing left to point at
--------------------------------------------------------------------------------

env.bags[0] = { [1] = "item:1002" }
Arrow:Changed()
clock = clock + 5
state = Arrow:State(clock)
suite.check("bought: nowhere to go", state.mode == "nowhere", state.mode)
suite.check("naming the step left", state.step and state.step:find("Put on", 1, true) ~= nil, state.step)
env.bags[0] = {}

--------------------------------------------------------------------------------
-- Settings and /beq arrow check
--------------------------------------------------------------------------------

ns.SettingsUI:Show()
suite.check("Settings has the switch", ns.SettingsUI.controls.questArrow:GetChecked() == true)
ns.SettingsUI.controls.questArrow:GetScript("OnClick")(ns.SettingsUI.controls.questArrow)
suite.check("which turns it off", not Arrow.IsOn() and ns.db.questArrow == false)
ns.SettingsUI.controls.questArrow:GetScript("OnClick")(ns.SettingsUI.controls.questArrow)
suite.check("and on", Arrow.IsOn())

env.chat = {}
suite.check("the check is typed only", ns.SettingsUI.controls.questArrowCheck == nil)
ns.HandleSlash("arrow check")
local text = env.ChatText()
suite.check("/beq arrow check runs", text:find("quest arrow check", 1, true) ~= nil, text)
suite.check("which names what it reads", text:find("world position", 1, true) ~= nil
    and text:find("facing", 1, true) ~= nil, text)
ns.SettingsUI:Hide()

-- Put them back moves the dial too.
ns.db.questArrowX, ns.db.questArrowY = 10, 10
ns.SettingsUI:ResetPositions()
suite.check("Window positions puts it back", ns.db.questArrowX == nil and ns.db.questArrowY == nil)

ArrowUI:Close()
suite.check("the red gem turns it off", not Arrow.IsOn())

--------------------------------------------------------------------------------
-- One Blackthornes arrow at a time (the same lines are in all three addons)
--------------------------------------------------------------------------------

do
    _G.BlackthornesArrows = nil
    local ui = ArrowUI
    suite.check("alone, it always shows", ui.Wins(true))
    local shared = _G.BlackthornesArrows
    shared.wants.Pets = true
    shared.claims.Pets = 1e9
    suite.check("another addon's arrow aimed later wins", not ui.Wins(true))
    shared.claims.Pets = -1
    ui:Claim()
    suite.check("aiming this one again wins it back", ui.Wins(true))
    shared.claims.Pets = 1e9
    shared.wants.Pets = nil
    suite.check("the other put away, this one shows", ui.Wins(true))
    ui.Wins(false)
    suite.check("off, it stops wanting", next(shared.wants) == nil)
    _G.BlackthornesArrows = nil
end

--------------------------------------------------------------------------------
-- The dial only moves: a drag changes nothing it points at
--------------------------------------------------------------------------------

do
    local dial = ArrowUI.frame
    local tab = Quest:Tab()
    dial:GetScript("OnDragStart")(dial)
    dial:GetScript("OnDragStop")(dial)
    suite.check("a drag keeps the same tab", Quest:Tab() == tab, Quest:Tab())
    suite.check("and is done dragging", ArrowUI.dragging == nil)
end

--------------------------------------------------------------------------------
-- The steps are read again when the upgrade quest says something changed,
-- not every two seconds while the dial is up; once a listing, not twice
--------------------------------------------------------------------------------

do
    local reads = 0
    local realSteps = Quest.Steps
    Quest.Steps = function(...) reads = reads + 1; return realSteps(...) end
    local wasOn = ns.db.questArrow
    ns.db.questArrow, inside = true, false
    Arrow:Changed(false)
    clock = 5000
    reads, Arrow.listedAt = 0, nil
    Arrow:State(clock)
    local after = reads
    suite.check("a fresh listing reads the steps once", after == 1, after)
    for _ = 1, 9 do
        clock = clock + 1
        Arrow:State(clock)
    end
    suite.check("nine quiet seconds read nothing more", reads == after, reads)
    clock = clock + 0.5
    Arrow:OnUpgradeQuestChanged()
    Arrow:State(clock)
    suite.check("the upgrade quest changing reads them at once, once", reads == after + 1, reads)
    clock = clock + Arrow.REFRESH
    Arrow:State(clock)
    suite.check("and with nothing said, again after a while", reads == after + 2, reads)
    Quest.Steps = realSteps
    ns.db.questArrow = wasOn

    -- The dial's lines on drag and drop are the same as Farmer's and Pets'.
    local function Lines(path)
        local file = io.open(path, "r")
        if not file then return nil end
        local text = file:read("*a")
        file:close()
        return text:match('frame:SetScript%("OnDragStart".-ArrowUI%.dragging = nil')
    end
    local mine = Lines(lfs_cwd .. "/UI/QuestArrow.lua")
    suite.check("the drag lines are found", mine ~= nil)
    for _, sister in ipairs({ "/../Blackthornes_Farmer/UI/Arrow.lua", "/../Blackthornes_Pets/UI/BeastArrow.lua" }) do
        local theirs = Lines(lfs_cwd .. sister)
        if theirs then suite.check("the drag lines match " .. sister, theirs == mine) end
    end
end

-- Drawn smaller, and a spot saved before stays where it was: kept in
-- UIParent's units, the arrow's own (smaller) units are turned back.
do
    local frame = ArrowUI.frame or ArrowUI:Build()
    local scale = ArrowUI.SCALE
    suite.check("the arrow is drawn smaller", scale < 1)
    local keptX, keptY = ns.db.questArrowX, ns.db.questArrowY
    ns.db.questArrowX, ns.db.questArrowY = 650, 400
    ArrowUI:RestorePosition()
    local p = frame._point
    suite.check("a saved spot is placed in the arrow's own units",
        p and math.abs(p[4] - 650 / scale) < 0.01 and math.abs(p[5] - 400 / scale) < 0.01)
    frame._cx, frame._cy = 650 / scale, 400 / scale
    ArrowUI:SavePosition()
    suite.check("and saved back in UIParent's units, unmoved",
        math.abs(ns.db.questArrowX - 650) < 0.01 and math.abs(ns.db.questArrowY - 400) < 0.01)
    ns.db.questArrowX, ns.db.questArrowY = keptX, keptY
    ArrowUI:RestorePosition()
end

suite.done()
