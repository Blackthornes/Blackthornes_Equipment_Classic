-- The Classic Era copy.
--
-- This repo is Equipment for WoW Classic Era. What only Forever has (its
-- changed items, its dungeon drops and dungeons, the quests and vendors met
-- there, the quests its client lacks, the spots its NPCs stand on, and the
-- sharing with Forever's characters) is left out of the TOC. The files stay
-- in the repo so Forever changes merge cleanly. Then the finder, Dungeon
-- Loot and Dungeon Quests have to work on Classic's data alone, and what is
-- learned in game still has to be laid over it.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("era")

local handle = assert(io.open(lfs_cwd .. "/Blackthornes_Equipment.toc", "r"))
local toc = handle:read("*a")
handle:close()

suite.check("the TOC is not Forever's", not toc:find("## Interface: 16001", 1, true))
suite.check("the TOC names a Classic Era interface", toc:find("## Interface: 115", 1, true) ~= nil)
suite.check("the TOC never names Forever's CurseForge project",
    not toc:find("^## X%-Curse%-Project%-ID:%s*1720051") and not toc:find("\n## X%-Curse%-Project%-ID:%s*1720051"))
suite.check("the TOC names the Equipment Classic CurseForge project",
    toc:find("\n## X%-Curse%-Project%-ID: 1763347%s") ~= nil)
for _, file in ipairs({ "Data\\ForeverItems.lua", "Data\\ForeverDrops.lua", "Data\\ForeverNPCs.lua",
        "Data\\ForeverQuests.lua", "Data\\ForeverGoneQuests.lua", "Data\\ForeverVendors.lua",
        "Data\\ForeverDungeonQuests.lua", "Logic\\Contribute.lua" }) do
    suite.check("the TOC leaves out " .. file, not toc:find("\n" .. file, 1, true))
end
for _, file in ipairs({ "Data\\Sources.lua", "Data\\Crafts.lua", "Data\\DungeonQuests.lua",
        "Logic\\Finder.lua", "Logic\\DungeonLoot.lua", "Logic\\DungeonQuests.lua",
        "Logic\\QuestLearn.lua", "Logic\\NPCSpots.lua" }) do
    suite.check("the TOC keeps " .. file, toc:find("\n" .. file, 1, true) ~= nil)
end

-- Loading as Era does, with no sister addons.
_G.BlackthornesTS, _G.BlackthornesFarmer, _G.BlackthornesButler, _G.BlackthornesPets = nil, nil, nil, nil
local ns = env.Load()
_G.UnitClass = function() return "Hunter", "HUNTER", 3 end
_G.UnitFactionGroup = function() return "Alliance", "Alliance" end
_G.UnitRace = function() return "Human", "Human", 1 end
env.InstallItems({ ["item:900"] = { loc = "INVTYPE_CHEST", class = 4, subclass = 2,
    stats = { ITEM_MOD_AGILITY_SHORT = 10 } } }, { [5] = "item:900" }, {}, 20)
local ok, err = pcall(function()
    for _, module in ipairs(ns.moduleOrder) do
        if module.OnEnable then module:OnEnable() end
    end
end)
suite.check("it loads and starts", ok, err)

suite.check("no Forever item table", ns.ForeverItems == nil)
suite.check("no Forever drops", ns.Sources.FOREVER == nil)
suite.check("no Forever dungeon rows", ns.Sources.DUNGEONS["3065"] == nil and ns.Sources.DUNGEONS["2999"] == nil)
suite.check("no Forever quests, vendors or spots",
    ns.ForeverQuests == nil and ns.ForeverVendors == nil and ns.ForeverNPCs == nil)
suite.check("no Forever dungeon quests", ns.FOREVER_DUNGEON_QUESTS == nil)
suite.check("no quests dropped as gone", ns.ForeverGoneQuests == nil and ns.Sources.QUESTS[9034] ~= nil)
suite.check("no sharing with Forever's characters", ns.Contribute == nil)

-- The finder.
local scanned, found = pcall(function() return ns.Finder:Scan() end)
suite.check("the finder scans", scanned and type(found) == "table", found)
local player = ns.Finder:Player()
local got, sources = pcall(function() return ns.Finder:SourcesFor(193, player) end)
suite.check("the finder reads a Classic item's sources", got and type(sources) == "table", sources)

-- Dungeon Loot, from Classic's boss drops alone.
local DL = ns.DungeonLoot
DL.index = nil
local indexed, index = pcall(function() return DL:Index() end)
local dungeons = 0
for _ in pairs(indexed and index or {}) do dungeons = dungeons + 1 end
suite.check("Dungeon Loot lays out Classic's dungeons", indexed and dungeons > 10, dungeons)
local listed, list = pcall(function() return DL:Dungeons(player) end)
suite.check("Dungeon Loot lists them", listed and type(list) == "table", list)

-- Dungeon Quests, from Classic's alone.
local DQ = ns.DungeonQuests
local all = DQ:All()
local count = 0
for _ in pairs(all) do count = count + 1 end
suite.check("Dungeon Quests has Classic's quests", count > 100, count)
local built, data = pcall(function() return DQ:Build() end)
suite.check("Dungeon Quests builds", built and type(data) == "table", data)
suite.check("Ragefire Chasm is still a dungeon", DQ.Dungeon("389") ~= nil)

-- What the player meets in game is still laid over Classic's data.
local before = ns.Sources.QUESTS[990001]
ns.db.learnedQuests = ns.db.learnedQuests or {}
ns.db.learnedQuests[990001] = { title = "A Quest Met in Era", level = 20, min = 15,
    giver = "Someone", zone = "Elwynn Forest", x = 40, y = 60, rewards = {}, side = "A" }
ns.QuestLearn:LayAll()
suite.check("a quest learned in game is laid over the data",
    before == nil and ns.Sources.QUESTS[990001] ~= nil)
ns.db.learnedVendors = ns.db.learnedVendors or {}
ns.db.learnedVendors[990002] = { name = "A Vendor Met in Era", zone = "Elwynn Forest", x = 40, y = 60,
    side = "A", items = { [990003] = { price = 500, req = 10, ilvl = 15 } } }
ns.NPCSpots:LayAllVendors()
suite.check("a vendor learned in game is laid over the data",
    ns.Sources.NPCS[990002] ~= nil and ns.Sources.ITEMS[990003] ~= nil)
suite.check("an NPC spot falls back to Classic's", ns.NPCSpots:Get(2999) == nil)

suite.done()
