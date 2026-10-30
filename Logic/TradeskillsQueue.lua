-- Blackthornes Equipment -- Logic/TradeskillsQueue.lua
-- Queue it: a crafted upgrade sent to Blackthornes Tradeskills' queue.
--
-- A player asked (2026-10-10, the owner agreeing) to queue a crafted upgrade
-- from Where to get upgrades and the Upgrade quest's Crafted tab. Gear this
-- character or an alt can make is queued as a craft, so its materials land
-- on Tradeskills' shopping list. Gear it still has to learn (or needs more
-- skill for) has its materials put on the list instead, ready for when it
-- can. Gear nobody on the account makes goes on the list itself, to buy
-- from a vendor or the auction house.
--
-- Only when Tradeskills is loaded and has the calls. Everything is asked
-- inside a pcall; nothing of Tradeskills' is read or written directly.

local _, ns = ...
local L = ns.L

local TSQueue = ns.NewModule("TradeskillsQueue")

--- Tradeskills' queue, when it is loaded and has the calls this needs.
local function TSQueueModule()
    local ts = _G.BlackthornesTS
    if type(ts) ~= "table" then return nil end
    local ok, queue = pcall(function() return ts.Queue end)
    if not ok or type(queue) ~= "table" then return nil end
    if type(queue.Ensure) ~= "function" or type(queue.EnsureBuy) ~= "function" then return nil end
    return queue
end

--- Can the button do anything?
function TSQueue:Available()
    return TSQueueModule() ~= nil
end

--- The crafted source among a pick's sources, or nil.
function TSQueue.CraftSource(sources)
    for _, source in ipairs(sources or {}) do
        if source.kind == "craft" then return source end
    end
    return nil
end

--- The crafted source as it stands now: a source kept by the upgrade quest
--- can be from before the recipe was learned or the skill went up.
function TSQueue.Fresh(source)
    if not (source and source.itemID and ns.Finder) then return source end
    local ok, sources = pcall(function()
        return ns.Finder:SourcesFor(source.itemID, ns.Finder:Player())
    end)
    return ok and TSQueue.CraftSource(sources) or source
end

--- What Queue it does for this source: "craft" (queue the craft),
--- "materials" (buy its materials, to make it once learned) or "buy" (buy
--- the gear itself).
function TSQueue.Plan(source)
    local state = source and source.state
    if state == "known" or state == "alt" then return "craft" end
    if state == "learn" or state == "skill" then return "materials" end
    return "buy"
end

--- What Tradeskills already holds for this gear: "craft", "buy" or nil.
function TSQueue:Holds(itemID)
    local queue = TSQueueModule()
    if not (queue and type(queue.ForUpgrade) == "function") then return nil end
    local ok, held = pcall(queue.ForUpgrade, queue, itemID)
    if ok and (held == "craft" or held == "buy") then return held end
    return nil
end

--- The button's words: "Queued" once Tradeskills holds it.
function TSQueue:Label(itemID)
    return self:Holds(itemID) and L["Queued"] or L["Queue It"]
end

local function Name(itemID)
    local ok, name = pcall(function()
        local info = C_Item and C_Item.GetItemInfo and C_Item.GetItemInfo(itemID)
            or (GetItemInfo and GetItemInfo(itemID))
        return info
    end)
    -- Chat names it in its rarity colour.
    if ok and type(name) == "string" then return ns.Items.ColorName(itemID, name) end
    return L["that upgrade"]
end

--- The button's tooltip: a title and what a click does.
function TSQueue:Explain(source)
    source = TSQueue.Fresh(source)
    if not source then return L["Queue It"], nil end
    if self:Holds(source.itemID) then
        return L["In Tradeskills' queue"], L["Click to open Tradeskills on the Queue tab."]
    end
    local plan = TSQueue.Plan(source)
    if plan == "craft" then
        local who = source.state == "alt" and source.who and source.who[1]
        return L["Queue the craft"],
            who and L.Format("Adds it to Tradeskills' queue and its materials to the shopping list. %s makes it.", who)
                or L["Adds it to Tradeskills' queue and its materials to the shopping list."]
    elseif plan == "materials" then
        return L["Queue the materials"],
            L["Puts its materials on Tradeskills' shopping list for when you can make it."]
    end
    return L["Put it on the shopping list"],
        L["Nobody on your account makes it, so it goes on Tradeskills' shopping list to buy."]
end

--- Every material of a crafted item onto the list to buy, for that item.
local function BuyMaterials(queue, itemID)
    local craft = ns.Crafts and ns.Crafts.ITEMS[itemID]
    local list = craft and craft.m
    if not list or #list == 0 then return nil, L["its materials aren't known"] end
    for i = 1, #list, 2 do
        local ok, done, why = pcall(queue.EnsureBuy, queue, list[i], list[i + 1], itemID)
        if not ok then return nil, L["Tradeskills ran into an error"] end
        if not done then return nil, why end
    end
    return true
end

--- Queue a crafted upgrade. Says in chat what happened.
-- @param source the finder's crafted source for it (kind "craft")
-- @return true when Tradeskills took it
function TSQueue:Queue(source)
    local queue = TSQueueModule()
    source = TSQueue.Fresh(source)
    if not (queue and source and source.itemID) then
        ns.Print(L["Queue it needs Blackthornes Tradeskills."])
        return false
    end
    local itemID = source.itemID
    local name = Name(itemID)

    -- Already there: the click opens it instead.
    if self:Holds(itemID) then return self:ShowQueue() end

    local plan = TSQueue.Plan(source)
    local done, why

    if plan == "craft" then
        local craft = ns.Crafts.ITEMS[itemID]
        local ok
        ok, done, why = pcall(queue.Ensure, queue, craft and craft[3], 1)
        if not ok then done, why = nil, L["Tradeskills ran into an error"] end
        if done then
            ns.Print(L.Format("Queued %s in Tradeskills. Its materials are on the shopping list.", name))
            return true
        end
        -- Tradeskills has not read the recipe yet: its materials still help.
        local bought, buyWhy = BuyMaterials(queue, itemID)
        if bought then
            ns.Print(L.Format("Put the materials for %s on Tradeskills' shopping list (%s).", name, why or L["it couldn't queue the craft"]))
            return true
        end
        why = buyWhy or why
    elseif plan == "materials" then
        done, why = BuyMaterials(queue, itemID)
        if done then
            ns.Print(L.Format("Put the materials for %s on Tradeskills' shopping list.", name))
            return true
        end
    else
        local ok
        ok, done, why = pcall(queue.EnsureBuy, queue, itemID, 1, itemID)
        if not ok then done, why = nil, L["Tradeskills ran into an error"] end
        if done then
            ns.Print(L.Format("Put %s on Tradeskills' shopping list.", name))
            return true
        end
    end

    ns.Print(L.Format("Couldn't queue %s: %s.", name, why or L["Tradeskills said no"]))
    return false
end

--- Open Tradeskills on its Queue tab.
function TSQueue:ShowQueue()
    local queue = TSQueueModule()
    if not (queue and type(queue.ShowQueue) == "function") then return false end
    local ok = pcall(queue.ShowQueue, queue)
    return ok
end
