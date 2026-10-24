-- Blackthornes Equipment -- Logic/Butler.lua
-- What Equipment says about one carried item, for Blackthornes Butler, which
-- tells the player what to do with each thing in the bags.
--
-- The one call Butler makes here, inside a pcall and read only:
--
--   _G.BlackthornesEquipment.Butler:Advise(link [, bag, slot])
--
-- It answers what the bags already show: the green arrow
-- (Compare:JudgeCarried, Compare.WearableUpgrade), the gold sell coin
-- (BagIcons:Sells) and the tools that never get one (BagIcons.IsTool), so
-- Butler and the bags cannot disagree. Keep the name, the fields and their
-- meaning stable; see CLAUDE.md ("What Butler calls here").
--
-- Butler asks once per bag item when it judges the bags, so a burst of a
-- hundred calls. Each one only reads: no bag scan, no list rebuilt, nothing
-- on a timer. Anything that is not gear is turned away after two cheap item
-- calls, and scores, sell prices and tools are kept per link where the bag
-- icons keep them.

local _, ns = ...

local Butler = ns.NewModule("Butler")

local Items = ns.Items
local Compare = ns.Compare

-- What GetItemInfoInstant gives an item that is never worn.
local NOT_WORN = { [""] = true, INVTYPE_NON_EQUIP = true, INVTYPE_NON_EQUIP_IGNORE = true }
-- A fishing pole is kept to use, like the tools (the bag coin skips it too).
local CLASS_WEAPON, FISHING_POLE = 2, 20

--- A link or item string to judge, from a link or an item ID.
local function LinkOf(item)
    if type(item) == "number" then return ("item:%d"):format(item) end
    return Items.PlainLink(item)
end

--- The size of an upgrade as a whole percent, or nil when there is nothing
--- to measure it against (an empty slot, a worn piece that scores nothing).
local function Gain(result)
    if type(result.percent) ~= "number" then return nil end
    return math.floor(result.percent + 0.5)
end

local function Read(item, bag, slot)
    local link = LinkOf(item)
    if not link then return nil end

    local BagIcons = ns.BagIcons
    local id = tonumber(link:match("item:(%d+)"))
    local knownTool = id ~= nil and BagIcons.TOOLS[id] == true

    -- The cheap check first: not gear, and not a tool, says nothing.
    local info = Items:Info(link)
    local worn = info ~= nil and not NOT_WORN[info.equipLoc]
    if not worn then
        if knownTool then return { tool = true, sell = false } end
        return nil
    end

    local result = Compare:JudgeCarried(link)
    local tool = knownTool
        or (info.classID == CLASS_WEAPON and info.subclassID == FISHING_POLE)
        or BagIcons.IsTool(link)
    if type(result) ~= "table" and not tool then return nil end

    local advice = { tool = tool, sell = false }
    if type(result) == "table" and result.verdict == "upgrade"
        and not (result.level and ns.Weights:KindTooFar(result.className, Items:PlayerLevel(),
            info.classID, info.subclassID, info.equipLoc)) then
        advice.upgrade = (Compare.WearableUpgrade(result) and not result.skill) and "now" or "later"
        advice.gain = Gain(result)
    end
    if not tool then
        advice.sell = BagIcons:Sells(bag, slot, link, result) == true
        -- No use to the character playing: is it an upgrade for another?
        if not advice.upgrade and type(result) == "table" and ns.Alts then
            local alt = ns.Alts:BestFor(link)
            if alt then advice.alt = { key = alt.key, gain = alt.gain, level = alt.level } end
        end
    end
    return advice
end

--- What Equipment says about one carried item.
-- `item` is an item link (or an item ID). `bag` and `slot`, when given, say
-- where it is carried, so soulbound green and better gear can be told apart
-- for the sell coin; without them that gear never gets `sell`.
-- @return nil for anything that is not gear (or not loaded yet), else a table:
--   upgrade  "now" (the bag arrow shows), "later" (an upgrade waiting on a
--            level or on training), or nil; armor of a kind the class learns later
--            (mail or plate at 40) is "later" only from 38
--            (Weights:KindTooFar), and goes to an alt only on the same terms
--   gain     the upgrade's size as a whole percent, or nil
--   sell     true when the bag's sell coin would show on it
--   tool     true for gathering and profession tools and fishing poles,
--            kept to use and never sold
--   alt      when it is no upgrade here but is for another of the player's
--            characters on this realm and side (Alts:BestFor): { key (that
--            character's GUID), gain (whole percent, nil for an empty
--            slot), level (when it waits on that character's level) }
-- Never raises.
function Butler:Advise(item, bag, slot)
    local ok, advice = pcall(Read, item, bag, slot)
    if ok then return advice end
    return nil
end
