-- Gear Forever changed from Classic: Data/ForeverItems.lua carries the
-- Forever client's required level, item level, classes, races and vendor
-- price, and the finder reads them over the Classic rows. The Classic Era
-- copy leaves the file out of the TOC, so only the laying is tested here.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("foreveritems")

local ns = env.Load()
local Finder = ns.Finder

--------------------------------------------------------------------------------
-- Classic Era leaves it out
--------------------------------------------------------------------------------

-- The file stays in the repo so Forever changes merge cleanly, but the TOC
-- leaves it out: on Era the Classic rows stand as they are.
suite.check("no Forever item table on Era", ns.ForeverItems == nil)
local classic = ns.Sources.ITEMS[193]
suite.check("a Classic row keeps Classic's numbers", classic and classic[1] == 1 and classic[2] == 5 and classic[5] == 49)

--------------------------------------------------------------------------------
-- Laying one over
--------------------------------------------------------------------------------

local sources = {
    [100] = { 20, 25, 3, 0, 500, v = { 1, 0 } },
    [101] = { 10, 15, 0, 0, 700, q = { 5 } },
}
local crafts = {
    [200] = { 164, 150, 9999, 37, 42, 0, 0, 0, m = { 2840, 4 } },
}
Finder.LayForeverItems({
    [100] = { 18, 24, 0, 0, 480 },
    [101] = { 12, 16, 0, 0, 1 },
    [200] = { 40, 45, 1, 0, 0 },
    [300] = { 1, 1, 0, 0, 0 },
}, sources, crafts)

suite.check("a vendor item takes Forever's level", sources[100][1] == 18 and sources[100][2] == 24)
suite.check("a vendor item takes Forever's classes", sources[100][3] == 0)
suite.check("a vendor item takes Forever's price", sources[100][5] == 480)
suite.check("a quest reward keeps its price field", sources[101][5] == 700 and sources[101][1] == 12)
suite.check("what follows a row is kept", sources[100].v[1] == 1 and sources[101].q[1] == 5)
suite.check("a craft takes Forever's level and classes",
    crafts[200][4] == 40 and crafts[200][5] == 45 and crafts[200][6] == 1)
suite.check("a craft keeps its profession, skill and spell",
    crafts[200][1] == 164 and crafts[200][2] == 150 and crafts[200][3] == 9999 and crafts[200][8] == 0)
suite.check("an item in neither table adds nothing", sources[300] == nil and crafts[300] == nil)
suite.check("nothing to lay over is fine", pcall(Finder.LayForeverItems, nil, sources, crafts))

--------------------------------------------------------------------------------
-- The finder reads it
--------------------------------------------------------------------------------

local ITEMS = {
    ["item:1001"] = { loc = "INVTYPE_CHEST", class = 4, subclass = 2, stats = { ITEM_MOD_AGILITY_SHORT = 20 } },
}
_G.UnitClass = function() return "Hunter", "HUNTER", 3 end
_G.UnitFactionGroup = function() return "Horde", "Horde" end
_G.UnitRace = function() return "Tauren", "Tauren", 6 end
env.InstallItems(ITEMS, {}, { [0] = {} }, 20)

local S = ns.Sources
S.ZONES = { [215] = "Mulgore" }
S.NPCS = { [3079] = { "Varg Windwhisper", 215, 45.8, 58.7, "H" } }
S.QUESTS, S.DUNGEONS, S.BOSSES, S.FOREVER = {}, {}, {}, {}
-- Classic: level 22 and warriors only; Forever: level 20, anyone.
S.ITEMS = { [1001] = { 22, 27, 1, 0, 900, v = { 3079, 0 } } }
ns.Crafts.ITEMS = {}
local player = Finder:Player()

suite.check("before, Classic's level and class keep it out", #Finder:SourcesFor(1001, player) == 0)
Finder.LayForeverItems({ [1001] = { 20, 25, 0, 0, 850 } }, S.ITEMS, ns.Crafts.ITEMS)
local found = Finder:SourcesFor(1001, player)
suite.check("after, the vendor is offered", #found == 1 and found[1].kind == "vendor")
suite.check("at Forever's price", found[1] and found[1].price == 850)

suite.done()
