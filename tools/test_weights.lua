-- Hunter stat weights, and working out which spec a character is judged as
-- from WoW: Forever's classic-style talent trees.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("weights")

--- Load the addon as a character of `class` with `points` in each tree.
-- `shape` is "classic" (name, icon, points) or "modern" (id, name, desc,
-- icon, points), the two ways GetTalentTabInfo answers.
local function LoadAs(class, points, shape)
    local ns = env.Load()
    _G.UnitClass = function() return class, class end
    if points then
        _G.GetNumTalentTabs = function() return #points end
        _G.GetTalentTabInfo = function(tab)
            if shape == "modern" then
                return 100 + tab, "Tree " .. tab, "", "icon", points[tab]
            end
            return "Tree " .. tab, "icon", points[tab]
        end
    else
        _G.GetNumTalentTabs = nil
        _G.GetTalentTabInfo = nil
    end
    return ns
end

local ns = LoadAs("HUNTER", nil)
local spec, why = ns.Weights:CurrentSpec()
suite.check("a hunter with no trees to read is Beast Mastery", spec == "beast", spec)
suite.check("and says it is the default", why == "default", why)

ns = LoadAs("HUNTER", { 0, 0, 0 })
spec, why = ns.Weights:CurrentSpec()
suite.check("no points spent is still the default", spec == "beast" and why == "default", why)

ns = LoadAs("HUNTER", { 2, 11, 0 })
spec, why = ns.Weights:CurrentSpec()
suite.check("most points in the second tree is Marksmanship", spec == "marks", spec)
suite.check("read from talents", why == "talents", why)

ns = LoadAs("HUNTER", { 0, 1, 14 }, "modern")
spec = ns.Weights:CurrentSpec()
suite.check("the modern tab shape is read too", spec == "survival", spec)

ns = LoadAs("HUNTER", { 5, 5, 0 })
spec, why = ns.Weights:CurrentSpec()
suite.check("a tie falls back to the default", spec == "beast" and why == "default", why)

_G.GetTalentTabInfo = function() error("secret value") end
spec, why = ns.Weights:CurrentSpec()
suite.check("a client that raises does not break it", spec == "beast" and why == "default", why)

-- Picking a spec wins over talents, and auto hands it back.
ns = LoadAs("HUNTER", { 0, 0, 20 })
ns.HandleSlash("spec mm")
spec, why = ns.Weights:CurrentSpec()
suite.check("/beq spec mm picks Marksmanship", spec == "marks" and why == "picked", why)
suite.check("and remembers it per character", ns.charDB.spec == "marks", ns.charDB.spec)
suite.check("and says so", env.ChatText():find("Marksmanship", 1, true), env.ChatText())

ns.HandleSlash("spec auto")
spec, why = ns.Weights:CurrentSpec()
suite.check("/beq spec auto goes back to talents", spec == "survival" and why == "talents", why)

env.chat = {}
ns.HandleSlash("spec tank")
suite.check("a spec that is not one is refused",
    env.ChatText():find("tank isn't a spec", 1, true), env.ChatText())
suite.check("and nothing is saved", ns.charDB.spec == nil)

ns = LoadAs("DEATHKNIGHT", nil)
suite.check("a class without weights has none", ns.Weights:ForPlayer() == nil)
env.chat = {}
ns.HandleSlash("spec")
suite.check("and /beq spec says so",
    env.ChatText():find("no stat weights for DEATHKNIGHT", 1, true), env.ChatText())

-- Forever: no talent tabs, one trait tree with the three specs side by side.
-- `bought` maps a node's horizontal position to the ranks bought in it.
local function LoadTraits(bought, opts)
    opts = opts or {}
    local ns = LoadAs("HUNTER", nil)
    local nodeList, layout = {}, {}
    for x, ranks in pairs(bought) do
        nodeList[#nodeList + 1] = x
        layout[x] = { posX = x, posY = 0, ranksPurchased = ranks }
    end
    _G.C_ClassTalents = { GetActiveConfigID = function()
        if opts.config == false then return nil end
        return 9601568
    end }
    _G.C_Traits = {
        GetConfigInfo = function() return { type = 4, name = "Hunter", treeIDs = { 1091 } } end,
        GetTreeNodes = function() return nodeList end,
        GetNodeInfo = function(_, nodeID)
            if opts.raise == nodeID then error("secret value") end
            return layout[nodeID]
        end,
    }
    return ns
end

-- Positions from the real tree: Focused Fire 1020 (BM), Hawk Eye 5020 (MM),
-- Entrapment 9080 (SV), Lightning Reflexes 102800 (SV, far out).
ns = LoadTraits({ [1020] = 0, [5020] = 0, [9080] = 0 })
spec, why = ns.Weights:CurrentSpec()
suite.check("a trait tree with nothing spent is the default",
    spec == "beast" and why == "default", why)

ns = LoadTraits({ [1020] = 1, [5020] = 3, [6820] = 1, [9080] = 2 })
local points = ns.Weights:TreePoints("HUNTER")
suite.check("points are counted per spec by column",
    points[1] == 1 and points[2] == 4 and points[3] == 2,
    table.concat(points, "/"))
spec, why = ns.Weights:CurrentSpec()
suite.check("most points in the Marksmanship columns is Marksmanship",
    spec == "marks" and why == "talents", spec)

ns = LoadTraits({ [1020] = 2, [102800] = 3 })
spec = ns.Weights:CurrentSpec()
suite.check("Lightning Reflexes far out at 102800 counts as Survival", spec == "survival", spec)

ns = LoadTraits({ [1020] = 2, [5020] = 3 }, { raise = 5020 })
spec = ns.Weights:CurrentSpec()
suite.check("a node that raises is skipped", spec == "beast", spec)

ns = LoadTraits({ [5020] = 3 }, { config = false })
spec, why = ns.Weights:CurrentSpec()
suite.check("no active config falls back to the default", why == "default", why)

ns = LoadTraits({ [5020] = 3 })
ns.HandleSlash("spec sv")
spec, why = ns.Weights:CurrentSpec()
suite.check("a pick still beats the talents", spec == "survival" and why == "picked", why)
-- The trait tree is walked once and kept a few seconds, so judging a bag of
-- gear (or a tooltip redrawn while hovering) does not walk it per item.
ns = LoadTraits({ [1020] = 1, [5020] = 3 })
ns.Weights:OnEnable()
local walks, clock = 0, 50
local realNodes = _G.C_Traits.GetTreeNodes
_G.C_Traits.GetTreeNodes = function(...) walks = walks + 1 return realNodes(...) end
_G.GetTime = function() return clock end
for _ = 1, 20 do ns.Weights:CurrentSpec() end
suite.check("twenty asks walk the talents once", walks == 1, walks)
ns.eventFrame:GetScript("OnEvent")(ns.eventFrame, "TRAIT_CONFIG_UPDATED")
-- The event itself walks the tree once, to see whether the talents moved.
local before = walks
ns.Weights:CurrentSpec()
suite.check("a talent change reads them again", walks == before + 1, walks)
clock = clock + 6
ns.Weights:CurrentSpec()
suite.check("and so does the time running out", walks == before + 2, walks)
_G.GetTime = nil

-- The client says TRAIT_CONFIG_UPDATED for any trait tree. Only a change to
-- the talents bought is passed on: the rest used to throw every upgrade
-- verdict away and start a new scan.
local bought = { [1020] = 1, [5020] = 3 }
ns = LoadTraits(bought)
ns.Weights:OnEnable()
ns.Finder:OnEnable()
local function Talents()
    ns.eventFrame:GetScript("OnEvent")(ns.eventFrame, "TRAIT_CONFIG_UPDATED")
end
local first = ns.Weights:TalentSignature()
suite.check("the talents bought read as one string", type(first) == "string" and first ~= "", first)
suite.check("the same talents read the same", ns.Weights:TalentSignature() == first)
Talents()
local generation, changes = ns.Finder.judgeGeneration, ns.Finder.changes
ns.Finder.stale = false
Talents()
Talents()
suite.check("an event with the same talents throws no verdict away",
    ns.Finder.judgeGeneration == generation, ns.Finder.judgeGeneration)
suite.check("and starts no new scan", ns.Finder.stale == false and ns.Finder.changes == changes)
suite.check("it is dropped for every listener", ns.NothingChanged("TRAIT_CONFIG_UPDATED") == true)
-- A point spent is a real change.
local realInfo = _G.C_Traits.GetNodeInfo
_G.C_Traits.GetNodeInfo = function(config, nodeID)
    local node = realInfo(config, nodeID)
    if nodeID == 1020 and type(node) == "table" then
        local copy = {}
        for key, value in pairs(node) do copy[key] = value end
        copy.ranksPurchased = 2
        return copy
    end
    return node
end
suite.check("a point spent reads as another string", ns.Weights:TalentSignature() ~= first)
Talents()
suite.check("and its event is passed on", ns.Finder.judgeGeneration ~= generation and ns.Finder.stale == true)
-- Talents that can't be read hold nothing back.
ns = LoadTraits(bought, { config = false })
ns.Weights:OnEnable()
ns.Finder:OnEnable()
Talents()
generation = ns.Finder.judgeGeneration
ns.Finder.stale = false
Talents()
suite.check("talents that can't be read hold no event back",
    ns.Finder.judgeGeneration ~= generation and ns.Finder.stale == true)

_G.C_ClassTalents, _G.C_Traits = nil, nil

-- Scoring.
ns = LoadAs("HUNTER", nil)
local stats, unknown = ns.Weights:Normalize({
    ITEM_MOD_AGILITY_SHORT = 5,
    ITEM_MOD_STAMINA_SHORT = 4,
    ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 10,
    ITEM_MOD_SOMETHING_NEW = 3,
})
suite.check("known stats are renamed", stats.agility == 5 and stats.stamina == 4 and stats.dps == 10)
suite.check("unknown ones are listed, not scored",
    #unknown == 1 and unknown[1] == "ITEM_MOD_SOMETHING_NEW", unknown[1])

local weights = ns.Weights:ForPlayer()
local bow = ns.Weights:Score({ agility = 5, dps = 10 }, weights, true)
local sword = ns.Weights:Score({ agility = 5, dps = 10 }, weights, false)
suite.check("to Beast Mastery a bow's dps is worth more than a sword's", bow > sword,
    bow .. " vs " .. sword)

local sv = ns.Weights.SPECS.HUNTER.survival.weights
suite.check("to Survival the sword is worth more",
    ns.Weights:Score({ dps = 10 }, sv, false) > ns.Weights:Score({ dps = 10 }, sv, true))

suite.check("agility beats the same points of stamina for every hunter spec", (function()
    for _, key in ipairs(ns.Weights.SPECS.HUNTER.order) do
        local w = ns.Weights.SPECS.HUNTER[key].weights
        if not (w.agility > w.stamina) then return false end
    end
    return true
end)())

suite.done()
