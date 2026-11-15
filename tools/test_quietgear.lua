-- Worn gear the client lets go of is no gear change.
-- The client drops an item from its memory now and then, and its link then
-- reads with no name. PLAYER_EQUIPMENT_CHANGED and BAG_UPDATE_DELAYED are
-- passed on only when what is worn or carried changed (ns.NothingChanged),
-- and a name coming or going must not count: it marked the finder out of
-- date and the Upgrades window scanned again.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("quietgear")

local named = "|cff1eff00|Hitem:2000::::::::20:::::|h[Fine Helm]|h|r"
local blank = "|cff1eff00|Hitem:2000::::::::20:::::|h[]|h|r"
local other = "|cff1eff00|Hitem:2001::::::::20:::::|h[Other Helm]|h|r"
local ore = "|cffffffff|Hitem:2770::::::::20:::::|h[Copper Ore]|h|r"
local oreBlank = "|cffffffff|Hitem:2770::::::::20:::::|h[]|h|r"

local ns = env.Load()
env.InstallItems({}, { [1] = named }, { [0] = { [1] = ore } }, 20)
local Items = ns.Items

suite.check("a link's key is its item string", Items.LinkKey(named) == "item:2000::::::::20:::::",
    tostring(Items.LinkKey(named)))
suite.check("with or without its name", Items.LinkKey(named) == Items.LinkKey(blank))
suite.check("a plain item string is its own key", Items.LinkKey("item:900") == "item:900")
suite.check("nothing has no key", Items.LinkKey(nil) == nil)

local worn = Items:WornSignature()
env.worn[1] = blank
suite.check("worn gear with no name reads the same", Items:WornSignature() == worn)
env.worn[1] = other
suite.check("other gear reads another way", Items:WornSignature() ~= worn)
env.worn[1] = nil
suite.check("and so does an empty slot", Items:WornSignature() ~= worn)
env.worn[1] = named

local bags = Items:BagSignature()
env.bags[0][1] = oreBlank
suite.check("a carried item with no name reads the same", Items:BagSignature() == bags)
env.bags[0][2] = other
suite.check("a new item in the bags reads another way", Items:BagSignature() ~= bags)
env.bags[0][2] = nil
env.bags[0][1] = ore

-- The event is passed on only for a real change.
ns.NothingChanged("PLAYER_EQUIPMENT_CHANGED")
suite.check("the same gear is nothing new", ns.NothingChanged("PLAYER_EQUIPMENT_CHANGED") == true)
env.worn[1] = blank
suite.check("its name going is nothing new", ns.NothingChanged("PLAYER_EQUIPMENT_CHANGED") == true)
env.worn[1] = named
suite.check("nor its name coming back", ns.NothingChanged("PLAYER_EQUIPMENT_CHANGED") == true)
env.worn[1] = other
suite.check("new gear is passed on", ns.NothingChanged("PLAYER_EQUIPMENT_CHANGED") == false)
env.worn[1] = named

ns.NothingChanged("BAG_UPDATE_DELAYED")
env.bags[0][1] = oreBlank
suite.check("a carried name going is nothing new", ns.NothingChanged("BAG_UPDATE_DELAYED") == true)
env.bags[0][1] = ore

suite.done()
