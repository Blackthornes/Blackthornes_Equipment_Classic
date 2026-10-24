-- Quests the Forever client does not have: Data/ForeverGoneQuests.lua names
-- them, and the finder leaves them out, while a quest learned in game still
-- shows. The Classic Era copy leaves the file out of the TOC, so only the
-- leaving out is tested here.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("gonequests")

local ns = env.Load()
local Finder = ns.Finder

--------------------------------------------------------------------------------
-- Classic Era leaves it out
--------------------------------------------------------------------------------

-- Era has every Classic quest, so the TOC leaves the Forever list out and
-- nothing is dropped. The file stays in the repo so Forever changes merge.
suite.check("no Forever gone list on Era", ns.ForeverGoneQuests == nil)
suite.check("a quest Forever lacks stays on Era", ns.Sources.QUESTS[9034] ~= nil)
suite.check("quests the client has stay", ns.Sources.QUESTS[962] ~= nil)

--------------------------------------------------------------------------------
-- Leaving them out
--------------------------------------------------------------------------------

local sources = {
    QUESTS = {
        [1] = { "Kept", 10, 12, 0, 0, "", 0, 0, 0, "" },
        [2] = { "Gone", 58, 60, 0, 0, "", 0, 0, 0, "" },
        [3] = { "After gone", 60, 60, 0, 0, "", 0, 0, 0, "Gone", p = 2 },
        [4] = { "Learned", 20, 20, 0, 0, "", 0, 0, 0, "", learned = true },
    },
    ITEMS = {
        [100] = { 10, 15, 0, 0, 0, q = { 1, 2 }, g = { 2 } },
        [101] = { 60, 70, 0, 0, 0, q = { 2 } },
        [102] = { 20, 25, 0, 0, 0, q = { 4 } },
    },
}
local dropped = Finder.DropGoneQuests({ [2] = true, [4] = true, [9] = true }, sources)
suite.check("one quest is dropped", dropped == 1 and sources.QUESTS[2] == nil)
suite.check("a quest the client has stays", sources.QUESTS[1] ~= nil)
suite.check("a learned quest stays", sources.QUESTS[4] ~= nil and sources.ITEMS[102].q[1] == 4)
suite.check("a quest after it no longer waits on it", sources.QUESTS[3].p == nil)
suite.check("its rewards forget it",
    #sources.ITEMS[100].q == 1 and sources.ITEMS[100].q[1] == 1 and #sources.ITEMS[100].g == 0
        and #sources.ITEMS[101].q == 0)
suite.check("nothing to leave out does nothing", Finder.DropGoneQuests(nil, sources) == 0)

-- Learned in game later, it is laid back over the data.
ns.Sources.ITEMS[101] = { 60, 70, 0, 0, 0, q = {} }
ns.QuestLearn:Lay(2, { title = "Gone", level = 60, rewards = { { 101, 60, 70, false } } })
suite.check("learned in game, it shows again", ns.Sources.QUESTS[2] ~= nil and ns.Sources.ITEMS[101].q[1] == 2)

suite.done()
