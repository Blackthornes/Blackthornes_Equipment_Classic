-- The quest arrow's way there (Logic/Travel.lua, the same file in every
-- addon, with Equipment's host at the end of Logic/QuestArrow.lua).
--
-- What matters: it is off until ticked; across the sea the dial reads
-- "Step 1 of 3" and points at the flight master, not straight over the
-- water; TomTom gets that stop; the setting and the arrow command turn it
-- on and off.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("travel")

local clock = 100
local ns = env.Load()
local Travel, QuestArrow = ns.Travel, ns.QuestArrow

_G.GetTime = function() return clock end
_G.UnitFactionGroup = function() return "Alliance" end
_G.UnitOnTaxi = function() return false end
_G.InCombatLockdown = function() return false end

-- The shipped docks: every boat and zeppelin leaves from a dock that is
-- there, and Orgrimmar's two zeppelins from their own platforms on the
-- one tower (the Undercity one was a road sign out by Razor Hill).
local shipped = Travel.DATA
for _, ride in ipairs(shipped.rides) do
    suite.check("the " .. ride[1] .. " to " .. ride[2] .. " ride has both docks",
        shipped.docks[ride[1]] ~= nil and shipped.docks[ride[2]] ~= nil)
end
local toUndercity, toGromgol = shipped.docks.orgrimmar, shipped.docks.orgrimmargromgol
local apart = math.sqrt((toUndercity[3] - toGromgol[3]) ^ 2 + (toUndercity[4] - toGromgol[4]) ^ 2)
suite.check("Orgrimmar's zeppelins leave from one tower", apart > 5 and apart < 50, apart)
suite.check("not from the road sign", math.abs(toUndercity[4] - -4397.8) > 200, toUndercity[4])
suite.check("Undercity's zeppelin leaves from its tower, not the sign below",
    math.abs(shipped.docks.undercity[3] - 1981.6) > 50, shipped.docks.undercity[3])

-- Every shipped flight carries how far it really goes, from its points in
-- the tables, never shorter than the straight line between its ends.
local shippedPaths, shippedLengths = shipped.paths, shipped.lengths or {}
suite.check("a length for every flight", #shippedLengths * 2 == #shippedPaths, #shippedLengths)
local short
for index = 1, #shippedPaths - 1, 2 do
    local a, b = shipped.flights[shippedPaths[index]], shipped.flights[shippedPaths[index + 1]]
    local line = math.sqrt((a[4] - b[4]) ^ 2 + (a[5] - b[5]) ^ 2)
    if (shippedLengths[(index + 1) / 2] or 0) < line then short = shippedPaths[index] .. "-" .. shippedPaths[index + 1] end
end
suite.check("none shorter than a straight line", short == nil, short)

local DATA = Travel.DATA
DATA.flights = {
    [1] = { "Stormwind, Elwynn", "A", 0, 0, -200, "Elwynn" },
    [2] = { "Menethil Harbor, Wetlands", "A", 0, 3000, 1000, "Wetlands" },
}
DATA.paths = { 1, 2 }
DATA.docks = {
    menethil = { "Menethil Harbor", 0, 3050, 1000, "Wetlands" },
    theramore = { "Theramore", 1, -3000, -3000, "Dustwallow Marsh" },
}
DATA.rides = { { "menethil", "theramore", "boat", "A" } }
DATA.lengths = nil

local here = { map = 1429, x = 0.5, y = 0.5, continent = 0, north = 0, west = 0, zone = "Elwynn Forest" }
local place = { continent = 1, north = -3200, west = -3000, zone = "Dustwallow Marsh", name = "Mirefin camp" }
Travel.WorldOf = function() return place end
local target = { name = "Mirefin camp", zone = "Dustwallow Marsh", map = 1445, mx = 0.4, my = 0.6 }
ns.db.travelFlights = { [UnitGUID("player")] = { [1] = true, [2] = true } }

suite.check("Equipment's host is used", Travel.Host.Here ~= nil and ns.TravelHost ~= nil)
ns.db.arrowRoute = nil
suite.check("on when never set", Travel.IsOn())
ns.db.arrowRoute = false
suite.check("off once unticked", Travel:Use(target, here, clock) == nil and not Travel.IsOn())

ns.db.arrowRoute = true
local trip = Travel:Use(target, here, clock)
suite.check("on: a trip of three steps", trip and trip.count == 3, trip and trip.count)

Travel.MapPos = function() return { map = 1429, x = 0.5, y = 0.45 } end
local state = QuestArrow:TripState({}, trip, here)
suite.check("the dial says the step", state.distance == "Step 1 of 3" and state.place == "Fly to Menethil Harbor",
    tostring(state.place))
suite.check("and points at the flight master", state.mode == "point" and state.yards ~= nil)
suite.check("the next stop carries map spots for TomTom", trip.point and trip.point.mx == 0.5 and trip.point.my == 0.45)

local point = ns.TomTom.Point({ trip = trip, target = target })
suite.check("TomTom gets the stop, not the far place", point == trip.point)

suite.check("the host's key names the place", ns.TravelHost.Key(target):find("Mirefin camp") ~= nil)

ns.commands.arrow.fn("route off")
suite.check("/beq arrow route off", not Travel.IsOn())
ns.commands.arrow.fn("route on")
suite.check("/beq arrow route on", Travel.IsOn())

suite.done()
