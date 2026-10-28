-- Blackthornes Equipment -- Logic/UpgradeQuest.lua
-- The upgrade quest: the character's best next upgrade, handed out like a
-- quest, with the steps to go and get it.
--
-- Off until the player turns it on (the "Upgrade quest" setting,
-- `upgradeQuest`, or /beq quest). Then it asks the upgrade finder for every
-- upgrade that can be worn now, picks the one most worth the trip (how much
-- better it is, and how easy it is to get), and keeps that one until it is
-- worn: no quest that changes under the player every time the bags do. Each
-- step (travel, find the vendor, pick up the quest, kill the boss, craft it,
-- put it on) ticks itself off as the game shows it done. Once the item is
-- worn the quest is complete, a banner says so, and the next one is picked.
--
-- One quest per kind of source, each on a tab of the panel: Vendor, Quest,
-- Dungeons and Raids, Crafted. The player flips between them freely; each
-- tab keeps its own upgrade until it is worn, and the panel shows the one
-- picked. The first time, the tab with the upgrade most worth the trip is
-- picked.
--
-- Kept per character, in BlackthornesEquipmentCharDB:
--   upgradeQuestTabs     { [tab] = quest } the quest on each tab, a quest
--                        being { itemID, link, slot, at, howMuch, source,
--                        here, followed }; `source` is the finder's source
--                        it was picked for, `here` set when it was picked
--                        while "This zone only" was ticked, `followed` when
--                        the player chose it in Where to get upgrades
--   upgradeQuestTab      the tab picked ("vendor", "quest", "dungeon",
--                        "craft")
--   upgradeQuest         a copy of the picked tab's quest, as versions
--                        before the tabs kept it; read once into the tabs
--   upgradeQuestSkipped  { [itemID] = true } upgrades the player ignored
--                        (the panel's Ignore, once called Skip), never
--                        offered again until restored in Settings or picked
--                        by hand in Where to get upgrades
--   upgradeQuestsDone    how many upgrade quests this character finished
-- And account wide, in BlackthornesEquipmentDB: `upgradeQuestZoneOnly`, the
-- quest panel's "This zone only" box (off: upgrades from anywhere), and
-- `upgradeQuestZoneSwap`, its "Change on a new zone" box (on unless
-- unticked: with This zone only, a new zone lets go of quests elsewhere).
-- Made the first time they are needed, and never renamed or cleared by an
-- update.

local _, ns = ...
local L = ns.L

local UpgradeQuest = ns.NewModule("UpgradeQuest")

-- Upgrades a level up offered that the player chose not to switch to, this
-- session: { [itemID] = true }.
UpgradeQuest.declined = {}

-- The tabs, in the panel's order: the finder's source kind each holds (a
-- raid is a dungeon), its name and its colour, as in the upgrade finder.
UpgradeQuest.TABS = {
    { key = "vendor", name = L["Vendor"], color = "accent" },
    { key = "quest", name = L["Quest"], color = "quest" },
    { key = "dungeon", name = L["Dungeons and Raids"], color = "dungeon" },
    { key = "craft", name = L["Crafted"], color = "craft" },
}
local TABS = UpgradeQuest.TABS
local IS_TAB = {}
for _, tab in ipairs(TABS) do IS_TAB[tab.key] = tab end

-- How each tab says it has nothing to chase.
local NONE = {
    vendor = L["No vendor sells an upgrade right now."],
    quest = L["No quest reward is an upgrade right now."],
    dungeon = L["No dungeon or raid drop is an upgrade right now."],
    craft = L["No crafted upgrade right now."],
}
UpgradeQuest.NONE = NONE

-- Where each tab stands: "active", "waiting" or "none". Not saved.
UpgradeQuest.states = {}

-- A tab with nothing to pick is only looked at again when something that can
-- open new gear happens (gear, level, talents, recipes, quests handed in, item
-- answers) or the player asks, so looting and quest log ticks stay cheap.
-- A bag change looks again at most once a minute (gear sold or thrown away
-- can be picked again). Not saved.
UpgradeQuest.rescan = true
local BAG_RESCAN = 60
local RESCAN_ON = {
    PLAYER_EQUIPMENT_CHANGED = true, PLAYER_LEVEL_UP = true, QUEST_TURNED_IN = true,
    GET_ITEM_INFO_RECEIVED = true, SKILL_LINES_CHANGED = true, NEW_RECIPE_LEARNED = true,
    TRAIT_CONFIG_UPDATED = true, CHARACTER_POINTS_CHANGED = true, PLAYER_TALENT_UPDATE = true,
}

local Items = ns.Items

-- How often, in seconds, to look whether a flight across a zone has landed.
local LANDING_CHECK = 3

-- How long to wait for the server to answer about gear before picking
-- from what is known. Most answers arrive within a few seconds.
local WAIT_FOR_ITEMS = 12

-- How much each kind of source is worth the trip: buying beats a quest,
-- which beats a dungeon run that might not drop it.
local EASE = {
    vendor = 1.0,
    quest = 0.85,
    dungeon = 0.6,
    raid = 0.3,
    known = 1.0,
    alt = 0.9,
    learn = 0.75,
    skill = 0.45,
    other = 0.2,
}

-- Somewhere in the zone the character is standing in is worth this much more.
local HERE = 1.25

-- Each quest still to do before a quest reward opens makes it this much
-- more work: a reward at the end of four quests counts at half.
local PER_CHAIN_QUEST = 0.25

-- How many quests before the one with the reward are listed as steps of
-- their own; the rest are one step.
local CHAIN_SHOWN = 2

-- After a level up, how long to keep looking for gear the new level opened,
-- while the server answers about gear the client has not seen.
local LEVEL_LOOK = 20

-- How much more an upgrade the new level opened has to be worth than the
-- quest being followed before it is offered in its place.
local CLEARLY_BETTER = 1.5

-- The note on a quest step that needs more than the player.
local NEED_NOTES = {
    group = L["Needs a group."],
    dungeon = L["Done in a dungeon, so bring a group."],
    raid = L["Needs a raid."],
    battleground = L["Done in a battleground."],
}

local function Read(fn, ...)
    if type(fn) ~= "function" then return nil end
    local result = { pcall(fn, ...) }
    if not result[1] then return nil end
    return unpack(result, 2)
end

local function Now()
    local ok, value = pcall(function() return time() end)
    return ok and value or 0
end

--- A plain copy of a finder source, safe to save.
local function Copy(value, depth)
    if type(value) ~= "table" then return value end
    if (depth or 0) > 3 then return nil end
    local copy = {}
    for key, inner in pairs(value) do
        local kind = type(inner)
        if kind == "string" or kind == "number" or kind == "boolean" or kind == "table" then
            copy[key] = Copy(inner, (depth or 0) + 1)
        end
    end
    return copy
end

function UpgradeQuest:IsEnabled()
    return ns.db ~= nil and ns.db.upgradeQuest == true
end

local function Valid(quest)
    if type(quest) == "table" and tonumber(quest.itemID) then return quest end
    return nil
end

--- The tab a source belongs on, or nil.
function UpgradeQuest.TabOf(source)
    local kind = type(source) == "table" and source.kind
    return IS_TAB[kind] and kind or nil
end

--- Each tab's quest: { [tab] = quest }. A quest saved before there were
--- tabs goes on its own tab, picked.
function UpgradeQuest:Quests()
    local char = ns.charDB
    if not char then return {} end
    if type(char.upgradeQuestTabs) ~= "table" then
        char.upgradeQuestTabs = {}
        local old = Valid(char.upgradeQuest)
        local tab = old and self.TabOf(old.source)
        if tab then
            char.upgradeQuestTabs[tab] = old
            if not IS_TAB[char.upgradeQuestTab] then char.upgradeQuestTab = tab end
        end
    end
    return char.upgradeQuestTabs
end

--- The tab picked: "vendor" until one is.
function UpgradeQuest:Tab()
    local tab = ns.charDB and ns.charDB.upgradeQuestTab
    return IS_TAB[tab] and tab or "vendor"
end

--- The quest on the picked tab, or nil.
function UpgradeQuest:Current()
    return Valid(self:Quests()[self:Tab()])
end

--- The quest on a tab, or nil.
function UpgradeQuest:QuestOn(tab)
    return Valid(self:Quests()[tab])
end

--- Keep the copy older versions read in step with the picked tab.
function UpgradeQuest:Mirror()
    if ns.charDB then ns.charDB.upgradeQuest = self:Current() end
end

--- Show another tab; it gets its quest at once if it has none yet.
function UpgradeQuest:SelectTab(tab)
    if not (IS_TAB[tab] and ns.charDB) then return false end
    -- A source's tab is shown in place of the Quest log tab
    -- (UI/QuestLogTab.lua).
    local fromLog = ns.charDB.questLogTab == true
    ns.charDB.questLogTab = nil
    if tab == self:Tab() and ns.charDB.upgradeQuestTab then
        if fromLog then self:Changed() end
        return true
    end
    ns.charDB.upgradeQuestTab = tab
    self.rescan = true
    self.offer = nil
    self.lastStep = nil
    self:Mirror()
    if self:IsEnabled() then self:Update() else self:Changed() end
    return true
end

function UpgradeQuest:Skipped()
    local char = ns.charDB
    if not char then return {} end
    if type(char.upgradeQuestSkipped) ~= "table" then char.upgradeQuestSkipped = {} end
    return char.upgradeQuestSkipped
end

--- The upgrades this character ignored, for Settings' list: each
--- { itemID, name, link }, by name. `link` is nil and `name` "Item 123"
--- while the client has not sent the item yet; it is asked for, and
--- GET_ITEM_INFO_RECEIVED says when it arrives.
function UpgradeQuest:IgnoredList()
    local list = {}
    local Items = ns.Items
    for itemID in pairs(self:Skipped()) do
        local id = tonumber(itemID)
        if id then
            local name, link
            if Items then
                local rawName, rawLink = Items.Call({ "C_Item.GetItemInfo", "GetItemInfo" }, id)
                link = Items.PlainLink(rawLink)
                local ok, copy = pcall(function()
                    if type(rawName) == "string" and rawName ~= "" then return rawName .. "" end
                end)
                name = ok and copy or nil
            end
            if not name then
                local C = _G.C_Item
                if C and type(C.RequestLoadItemDataByID) == "function" then
                    pcall(C.RequestLoadItemDataByID, id)
                end
            end
            list[#list + 1] = { itemID = id, name = name or L.Format("Item %d", id), link = link }
        end
    end
    table.sort(list, function(a, b)
        if a.name ~= b.name then return a.name < b.name end
        return a.itemID < b.itemID
    end)
    return list
end

--- Let an ignored upgrade be offered again.
-- @return true when it was ignored
function UpgradeQuest:Restore(itemID)
    itemID = tonumber(itemID)
    local skipped = self:Skipped()
    if not (itemID and skipped[itemID]) then return false end
    skipped[itemID] = nil
    self:Restored()
    return true
end

--- Let every ignored upgrade be offered again.
-- @return how many there were
function UpgradeQuest:RestoreAll()
    local count = 0
    for _ in pairs(self:Skipped()) do count = count + 1 end
    if ns.charDB then ns.charDB.upgradeQuestSkipped = {} end
    self:Restored()
    return count
end

--- After a restore: look again, so a restored upgrade can be picked for a
--- tab with nothing to chase, and tell the windows.
function UpgradeQuest:Restored()
    self.rescan = true
    if self:IsEnabled() then pcall(self.Update, self) end
    self:Changed()
end

function UpgradeQuest:DoneCount()
    return tonumber(ns.charDB and ns.charDB.upgradeQuestsDone) or 0
end

--------------------------------------------------------------------------------
-- Picking the next upgrade
--------------------------------------------------------------------------------

--- How easy a source is, 0 to 1 and a little over for one close by.
function UpgradeQuest.Ease(source, zone)
    local key = source.kind
    if source.kind == "dungeon" and source.raid then key = "raid" end
    if source.kind == "craft" then key = source.state or "other" end
    local ease = EASE[key] or 0.5
    -- A rare drop means many runs.
    if source.kind == "dungeon" and source.chance and source.chance < 10 then
        ease = ease * (0.5 + source.chance / 20)
    end
    -- A reward at the end of a chain is more work.
    if source.kind == "quest" and source.questID and ns.Finder then
        local chain, unknown = ns.Finder:Chain(source.questID)
        local count = #chain + (unknown and 1 or 0)
        ease = ease / (1 + PER_CHAIN_QUEST * count)
    end
    if zone and UpgradeQuest.SourceZone(source) == zone then ease = ease * HERE end
    return ease
end

--- Is "This zone only" ticked on the quest panel? Saved account wide as
--- `upgradeQuestZoneOnly`, off unless ticked (the quest looks anywhere).
function UpgradeQuest:ZoneOnly()
    return ns.db ~= nil and ns.db.upgradeQuestZoneOnly == true
end

--- Does a new zone let go of the tabs' quests elsewhere while "This zone
--- only" is ticked? Saved account wide as `upgradeQuestZoneSwap`, on
--- unless unticked (the owner asked 2026-10-08 for a way to stop it).
--- Off, the quests stay as the character travels; a tab with nothing to
--- chase still picks from the zone it is in.
function UpgradeQuest:ZoneSwap()
    return ns.db == nil or ns.db.upgradeQuestZoneSwap ~= false
end

--- Tick or untick "Change on a new zone". Nothing is let go straight away:
--- the next new zone does that.
function UpgradeQuest:SetZoneSwap(on)
    if not ns.db then return end
    ns.db.upgradeQuestZoneSwap = on and true or false
    self:Changed()
end

--- "Current step only" on the quest panel: show only the step to do now.
function UpgradeQuest:StepOnly()
    return ns.db ~= nil and ns.db.upgradeQuestStepOnly == true
end

--- Tick or untick it. Only the panel and Settings draw again; nothing is
--- looked for again.
function UpgradeQuest:SetStepOnly(on)
    if not ns.db then return end
    ns.db.upgradeQuestStepOnly = on and true or false
    for _, name in ipairs({ "QuestPanel", "SettingsUI" }) do
        local module = ns[name]
        if module and module.OnUpgradeQuestChanged then pcall(module.OnUpgradeQuestChanged, module) end
    end
end

--- Is a source in the zone `here`? A dungeon counts from its entrance's
--- zone and from inside. Gear made from what you know has no place, so it
--- is in every zone, and so is anything when the zone is not known.
function UpgradeQuest.InZone(source, here)
    if not here or type(source) ~= "table" then return true end
    local zone = UpgradeQuest.SourceZone(source)
    if not zone then
        -- A quest is always somewhere: one whose start is not known is not
        -- in this zone.
        return source.kind ~= "quest"
    end
    return zone == here or source.dungeon == here
end

--- The zone a source is got in. A quest that starts from an item has no
--- giver, so it is where the item is got (Data/QuestStarts.lua). Before,
--- such a quest counted as in every zone, so "This zone only" could send
--- a player to another zone for it. Nil when not known.
function UpgradeQuest.SourceZone(source)
    if type(source) ~= "table" then return nil end
    if source.zone then return source.zone end
    if source.kind == "quest" and source.questID then
        local starter = UpgradeQuest.Starter(source.questID)
        local first = starter and starter.places[1]
        if first then return first.kind == "boss" and first.door or first.zone end
    end
    return nil
end

--- The easiest of a pick's sources (only those for one tab, when `tab` is
--- given, and only those in the zone `here`, when it is), and how easy it is.
function UpgradeQuest.BestSource(sources, zone, tab, here)
    local best, bestEase
    for _, source in ipairs(sources or {}) do
        if (not tab or source.kind == tab) and UpgradeQuest.InZone(source, here) then
            local ease = UpgradeQuest.Ease(source, zone)
            if not best or ease > bestEase then best, bestEase = source, ease end
        end
    end
    return best, bestEase or 0
end

--- How much a pick is worth going after: how much better it is, times how
--- easy its source is.
local function Worth(result, gain, ease)
    -- Filling an empty slot counts as a big step up.
    if result and result.empty then gain = math.max(gain, 1) * 1.5 end
    return gain * ease
end

--- From a finder scan, the pick most worth going after: { pick, source },
--- or nil. Gear that waits on a reputation, that nobody on the account can
--- make, or that the player skipped is left out, and so is anything in
--- `except` ({ [itemID] = true }). With `tab`, only that tab's sources count;
--- with "This zone only" ticked, only those in the zone the character is in.
--- Gear tied to a reputation, even one already reached, comes last: it is
--- picked only when nothing else will do (the player can still follow one
--- from the finder by hand).
function UpgradeQuest:Choose(found, except, tab)
    if type(found) ~= "table" or type(found.slots) ~= "table" then return nil end
    local skipped = self:Skipped()
    local zone = found.player and found.player.zone
    -- Read now: the scan may be from before the last zone change.
    local here = self:ZoneOnly() and (self.Zone() or zone) or nil
    local everything = type(found.all) == "table" and found.all or nil
    -- Only a few of the best per slot are kept for the finder's window; the
    -- best in this zone is seldom among them, so look at them all.
    local slots = here and everything or found.slots
    local best, bestRep
    -- The slots whose short list holds reputation gear.
    local crowded = {}
    local function Look(slot, list, repToo)
        for _, pick in ipairs(list) do
            if pick.rep then crowded[slot] = true end
            if not pick.needs and not pick.remote and not pick.at and not skipped[pick.itemID]
                and not (except and except[pick.itemID]) and (repToo or not pick.rep) then
                local source, ease = self.BestSource(pick.sources, zone, tab, here)
                if source then
                    local worth = Worth(pick.result, pick.gain or 0, ease)
                    local held = best
                    if pick.rep then held = bestRep end
                    if not held or worth > held.worth
                        or (worth == held.worth and pick.itemID < held.pick.itemID) then
                        held = { pick = pick, source = source, worth = worth }
                        if pick.rep then bestRep = held else best = held end
                    end
                end
            end
        end
    end
    for slot, list in pairs(slots) do Look(slot, list, true) end
    -- Reputation gear among a slot's few best may have pushed the rest of
    -- that slot out of the short list, so those slots are looked at whole.
    if slots ~= everything and everything then
        for slot in pairs(crowded) do
            if type(everything[slot]) == "table" then Look(slot, everything[slot], false) end
        end
    end
    return best or bestRep
end

--- Make a pick the quest on its source's tab.
function UpgradeQuest:Start(pick, source)
    local char = ns.charDB
    local tab = self.TabOf(source)
    if not (char and pick and tab) then return nil end
    local quest = {
        itemID = pick.itemID,
        link = Items.PlainLink(pick.link) or ("item:%d"):format(pick.itemID),
        slot = pick.result and pick.result.slot,
        at = Now(),
        howMuch = pick.result and ns.Compare:HowMuch(pick.result) or nil,
        source = Copy(source),
        -- Picked while "This zone only" was ticked: let go when it is
        -- unticked, so the tab picks again from anywhere.
        here = self:ZoneOnly() or nil,
    }
    self:Quests()[tab] = quest
    self:Mirror()
    return quest
end

--- Can a pick from the upgrade finder be followed as an upgrade quest?
--- Gear that waits on a reputation, a level or another player's craft
--- cannot be yet.
-- @return the source to follow, or nil and why not
function UpgradeQuest.CanFollow(pick)
    if type(pick) ~= "table" or not tonumber(pick.itemID) then return nil, L["nothing to follow"] end
    if pick.needs then
        return nil, L.Format("it needs %s with %s first", tostring(pick.needs.standing),
            tostring(pick.needs.faction))
    end
    if pick.at then return nil, L.Format("you can wear it from level %d", pick.at) end
    local usable = {}
    for _, source in ipairs(pick.sources or {}) do
        if not (source.kind == "craft" and source.state == "other") then usable[#usable + 1] = source end
    end
    local source = UpgradeQuest.BestSource(usable, UpgradeQuest.Zone())
    if not (source and UpgradeQuest.TabOf(source)) then
        return nil, L["only another player can make it"]
    end
    return source
end

--- Follow a pick the player chose in the upgrade finder: it becomes the
--- quest on its source's tab, that tab is shown, and the upgrade quest is
--- turned on. The quest it replaces is not skipped, so it can come back.
-- @return the quest, or nil and why not
function UpgradeQuest:Follow(pick)
    if not (ns.db and ns.charDB) then return nil, L["not loaded yet"] end
    local source, why = self.CanFollow(pick)
    if not source then return nil, why end
    self:Skipped()[pick.itemID] = nil
    self.declined[pick.itemID] = nil
    local quest = self:Start(pick, source)
    if not quest then return nil, L["nothing to follow"] end
    -- Picked by hand: "This zone only" never lets it go.
    quest.followed = true
    ns.charDB.upgradeQuestTab = self.TabOf(source)
    -- Shown on its tab, not left behind the Quest log tab.
    ns.charDB.questLogTab = nil
    -- Chosen by hand: no level-up offer to swap it straight away.
    self.offer = nil
    self.levelledAt = nil
    self.lastStep = nil
    self:Mirror()
    ns.db.upgradeQuest = true
    self:Update()
    -- The gear window's Upgrade quest button shows it is up.
    if ns.UI and ns.UI.OnUpgradeQuestToggled then pcall(ns.UI.OnUpgradeQuestToggled, ns.UI) end
    if ns.QuestPanel and ns.QuestPanel.Unfold then pcall(ns.QuestPanel.Unfold, ns.QuestPanel) end
    return quest
end

--- Is an item the quest on one of the tabs?
function UpgradeQuest:IsFollowing(itemID)
    if not self:IsEnabled() then return false end
    for _, quest in pairs(self:Quests()) do
        if type(quest) == "table" and quest.itemID == itemID then return true end
    end
    return false
end

--- The finder's latest full scan, when nothing has changed since. If there
--- is none, one is started in the background (a slice per frame, so the
--- game never stops for it) and the quest looks again when it is done.
-- @return the scan, or nil and "waiting" (scanning) or "none"
function UpgradeQuest:FreshScan()
    local finder = ns.Finder
    if not finder then return nil, "none" end
    local found = finder:Fresh()
    if found then return found end
    if not finder:Scanning() then
        finder:ScanInBackground(function(result)
            UpgradeQuest.scanFailed = not result
            -- Something changed while it ran. After a few in a row (item
            -- answers still pouring in), the last one is good enough.
            UpgradeQuest.staleScans = finder:Fresh() and 0 or (UpgradeQuest.staleScans or 0) + 1
            -- Finished at once (no timers): the caller picks it up below.
            if not UpgradeQuest.updating then UpgradeQuest:UpdateSoon(0) end
        end)
    end
    found = finder:Fresh()
    if found then return found end
    if not finder:Scanning() and (self.staleScans or 0) >= 3 and finder.latest then
        self.staleScans = 0
        return finder.latest
    end
    if not finder:Scanning() and self.scanFailed then return nil, "none" end
    return nil, "waiting"
end

--- A finder scan to pick from. Waits a little for the server to answer
--- about gear the client has not seen, so the pick is made from all of it.
-- @return the scan, or nil and "waiting" or "none"
function UpgradeQuest:Look()
    local found, why = self:FreshScan()
    if why == "waiting" then return nil, "waiting" end
    if not found then
        self.lookingSince = nil
        return nil, "none"
    end
    self.lookingSince = self.lookingSince or ns.Finder.Now()
    if found.waiting > 0 and ns.Finder.Now() - self.lookingSince < WAIT_FOR_ITEMS then
        return nil, "waiting"
    end
    self.lookingSince = nil
    return found
end

--- Whether the empty tabs need a fresh scan: not when each already found
--- nothing and nothing since could have opened new gear.
function UpgradeQuest:WorthLooking(empty)
    if self.rescan or not IS_TAB[ns.charDB.upgradeQuestTab] then return true end
    for _, tab in ipairs(empty) do
        if self.states[tab] ~= "none" then return true end
    end
    return self.bagsChanged and Now() - (self.lookedAt or 0) >= BAG_RESCAN or false
end

--- Give every tab without a quest its best upgrade, and pick the tab the
--- first time: the one whose upgrade is most worth the trip.
function UpgradeQuest:PickEmpty()
    local quests = self:Quests()
    local empty = {}
    for _, tab in ipairs(TABS) do
        if not Valid(quests[tab.key]) then empty[#empty + 1] = tab.key end
    end
    if #empty == 0 and IS_TAB[ns.charDB.upgradeQuestTab] then return end
    -- "This zone only" on a flight: the zone below is not where the player
    -- is going, so the tabs wait for the landing.
    if self:ZoneOnly() and self.OnTaxi() then return end
    if not self:WorthLooking(empty) then return end

    local found, why = self:Look()
    if not found then
        for _, tab in ipairs(empty) do self.states[tab] = why end
        return
    end
    self.rescan = false
    self.bagsChanged = false
    self.lookedAt = Now()
    for _, tab in ipairs(empty) do
        local best = self:Choose(found, nil, tab)
        if best then self:Start(best.pick, best.source) end
        self.states[tab] = best and "active" or "none"
    end
    if not IS_TAB[ns.charDB.upgradeQuestTab] then
        local best = self:Choose(found)
        ns.charDB.upgradeQuestTab = best and self.TabOf(best.source) or "vendor"
    end
end

--- The picked tab's next upgrade, when it has none.
-- @return the quest, or nil and "waiting" or "none"
function UpgradeQuest:PickNext()
    self:PickEmpty()
    local quest = self:Current()
    if quest then return quest end
    return nil, self.states[self:Tab()] or "none"
end

--------------------------------------------------------------------------------
-- What the game says is done
--------------------------------------------------------------------------------

local function Plain(value)
    local ok, copy = pcall(function()
        if type(value) == "string" and value ~= "" then return value .. "" end
    end)
    return ok and copy or nil
end

--- The zone the character is in: the instance's name inside a dungeon. By
--- the data's name for it, on a client in another language too.
function UpgradeQuest.Zone()
    local zone = Plain(Read(_G.GetRealZoneText))
    if ns.Waypoints then zone = ns.Waypoints:DataZone(zone) end
    return zone
end

--- How many of an item the bags hold.
function UpgradeQuest.Count(itemID)
    local count = tonumber((Items.Call({ "C_Item.GetItemCount", "GetItemCount" }, itemID)))
    if count then return count end
    count = 0
    for bag = 0, 4 do
        for slot = 1, Items:BagSize(bag) do
            local link = Items:InBag(bag, slot)
            if link and tonumber(link:match("item:(%d+)")) == itemID then count = count + 1 end
        end
    end
    return count
end

--- Is the item worn?
function UpgradeQuest.Worn(itemID)
    for slot = 1, 19 do
        local link = Items:Equipped(slot)
        if link and tonumber(link:match("item:(%d+)")) == itemID then return true end
    end
    return false
end

--- Is a quest in the quest log? Nil when the client cannot say.
local function OnQuest(questID)
    local log = _G.C_QuestLog
    local on = Read(log and log.IsOnQuest, questID)
    if on ~= nil then return on == true end
    local index = Read(log and log.GetLogIndexForQuestID, questID)
    if index ~= nil then return (tonumber(index) or 0) > 0 end
    -- Era has neither call: read the quest log itself.
    local QL = ns.QuestLog
    if QL and QL.Size and QL.Find then
        local okSize, _, how = pcall(QL.Size)
        if okSize and how then
            local ok, found = pcall(QL.Find, QL, questID)
            if ok then return found ~= nil end
        end
    end
    return nil
end

--- Are a quest's objectives done, ready to hand in?
local function QuestReady(questID)
    local log = _G.C_QuestLog
    if Read(log and log.ReadyForTurnIn, questID) == true then return true end
    if Read(log and log.IsComplete, questID) == true then return true end
    -- Era has neither call: the quest log's own line says when it is done.
    local QL = ns.QuestLog
    if QL and QL.Find then
        local ok, found = pcall(QL.Find, QL, questID)
        if ok and type(found) == "table" then return found.complete == true end
    end
    return false
end
UpgradeQuest.QuestReady = QuestReady


--------------------------------------------------------------------------------
-- The steps
--------------------------------------------------------------------------------

local function At(place)
    if place.x and place.y then return (" (%s, %s)"):format(place.x, place.y) end
    return ""
end

--- Where to get the item that starts a quest (Data/QuestStarts.lua), for a
--- quest that starts from an item rather than a person: { itemID, item,
--- total, places }, each place { kind, name, zone, x, y, low, high, chance,
--- rank, forever, door }, `door` the zone a boss's dungeon opens from.
--- Nil when the data has nothing for the quest.
function UpgradeQuest.Starter(questID)
    local starts = ns.Sources and ns.Sources.STARTS
    local row = type(starts) == "table" and starts[questID]
    if type(row) ~= "table" then return nil end
    local places = {}
    for index = 4, #row do
        local p = row[index]
        if type(p) == "table" then
            local place = { kind = p[1], name = p[2], zone = p[3], low = p[6], high = p[7],
                chance = p[8], rank = p[9] ~= "" and p[9] or nil, forever = p.f and true or nil }
            if (tonumber(p[4]) or 0) > 0 then place.x, place.y = p[4], p[5] end
            if place.kind == "boss" then
                for _, dungeon in pairs(ns.Sources.DUNGEONS or {}) do
                    if dungeon[1] == place.zone then place.door = dungeon[4] end
                end
            end
            places[#places + 1] = place
        end
    end
    return { itemID = row[1], item = row[2], total = tonumber(row[3]) or #places, places = places }
end

--- A place from Data/QuestEnds.lua as the steps use it: a boss's place is
--- its dungeon, found from the zone its door opens in.
local function EndPlace(p)
    if type(p) ~= "table" then return nil end
    local place = { kind = p[1], name = p[2], zone = p[3] }
    if (tonumber(p[4]) or 0) > 0 then place.x, place.y = p[4], p[5] end
    if place.kind == "boss" then
        place.dungeon = place.zone
        place.zone = nil
        for _, dungeon in pairs(ns.Sources.DUNGEONS or {}) do
            if dungeon[1] == place.dungeon then place.zone = dungeon[4] end
        end
        if not place.zone then return nil end
        -- A boss's own spot is inside; the arrow aims at the learned door.
        if ns.DungeonDoors then
            local door = { zone = place.zone }
            ns.DungeonDoors:Fill(door, place.dungeon)
            if door.x then place.zone, place.x, place.y = door.zone, door.x, door.y end
        end
    end
    place.item = p[6]
    return place
end

--- Where a quest is worked on and handed in (Data/QuestEnds.lua): { hand,
--- goal, goals }, each a place { kind, name, zone, x, y }, `goal` with the
--- `item` to collect when that is the objective and `dungeon` for a boss.
--- `goals` is every objective's place, `goal` the first. Either can be
--- nil; nil when the data has nothing for the quest.
function UpgradeQuest.Ender(questID)
    local ends = ns.Sources and ns.Sources.ENDS
    local row = type(ends) == "table" and questID and ends[questID]
    if type(row) ~= "table" then return nil end
    local hand = row[1] and EndPlace(row) or nil
    if hand then hand.item = nil end
    local goals = {}
    goals[#goals + 1] = EndPlace(row.o)
    if type(row.m) == "table" then
        for _, more in ipairs(row.m) do goals[#goals + 1] = EndPlace(more) end
    end
    return { hand = hand, goal = goals[1], goals = goals }
end

--- Does a quest log objective line name this place's objective? The item
--- to collect, else the mob or object, found in the line's text ("1/1
--- Logging Rope", "Foulweald Den Watcher slain: 0/8"). The data's names
--- are English, so another language matches nothing.
local function Names(text, goal)
    local key = goal.item or goal.name
    if type(key) ~= "string" or key == "" then return false end
    local ok, found = pcall(function()
        return text:lower():find(key:lower(), 1, true) ~= nil
    end)
    return ok and found or false
end

--- The objective to work on now: the first of the quest's places whose
--- objective the log does not show done. `objectives` is the log's list
--- ({ text, done } each); without it, the first place. A place the log
--- has no line for counts as not done. Nil when every place's objective
--- is done.
function UpgradeQuest.OpenGoal(ender, objectives)
    if not ender then return nil end
    local goals = ender.goals or { ender.goal }
    if type(objectives) ~= "table" or #objectives == 0 then return goals[1] end
    for _, goal in ipairs(goals) do
        local done = false
        for _, objective in ipairs(objectives) do
            if type(objective) == "table" and objective.done and type(objective.text) == "string"
                and Names(objective.text, goal) then
                done = true
                break
            end
        end
        if not done then return goal end
    end
    return nil
end

--- The log's objectives for a quest in it, read for that one quest; nil
--- when it can't be read.
local function LogObjectives(questID)
    if not (questID and ns.QuestLog and ns.QuestLog.Find) then return nil end
    local ok, found = pcall(ns.QuestLog.Find, ns.QuestLog, questID)
    return ok and type(found) == "table" and found.objectives or nil
end
UpgradeQuest.LogObjectives = LogObjectives

--- "to Morin Cloudstalker in Mulgore (51.9, 59.6)", "at" for an object.
local function HandText(hand, withZone)
    if hand.kind == "object" then
        if withZone then return L.Format("at %s in %s%s", hand.name, hand.zone, At(hand)) end
        return L.Format("at %s%s", hand.name, At(hand))
    end
    if withZone then return L.Format("to %s in %s%s", hand.name, hand.zone, At(hand)) end
    return L.Format("to %s%s", hand.name, At(hand))
end

--- What to do for a quest's objective: "collect Fizsprocket's Clipboard
--- from Supervisor Fizsprocket in Mulgore (64.9, 43.3)".
local function GoalText(goal)
    local where = goal.dungeon and L.Format(" in %s", goal.dungeon)
        or L.Format(" in %s", goal.zone) .. At(goal)
    if goal.item then
        -- The data names the item without its ID: coloured once the
        -- client knows the name, else as it is.
        local item = Items.ColorName(nil, goal.item)
        if goal.kind == "vendor" then return L.Format("buy %s from %s%s", item, goal.name, where) end
        return L.Format("collect %s from %s%s", item, goal.name, where)
    end
    return L.Format("find %s%s", goal.name, where)
end

--- A place for the map and the arrow, as the other steps carry it.
local function Spot(place)
    if not place then return nil end
    return { zone = place.zone, x = place.x, y = place.y, name = place.dungeon or place.name }
end

--- "level 12" or "levels 10 to 12", and ", rare" for a rare.
local function LevelText(place)
    local parts = {}
    if (place.low or 0) > 0 then
        parts[#parts + 1] = place.high and place.high > place.low
            and L.Format("levels %d to %d", place.low, place.high) or L.Format("level %d", place.low)
    end
    -- The rank is the data's word; only how it is shown is translated.
    if place.rank == "rare" then
        parts[#parts + 1] = L["rare"]
    elseif place.rank == "rare elite" then
        parts[#parts + 1] = L["rare elite"]
    elseif place.rank then
        parts[#parts + 1] = place.rank
    end
    return #parts > 0 and (" (%s)"):format(table.concat(parts, ", ")) or ""
end

local function Who(names)
    if type(names) ~= "table" or #names == 0 then return L["An alt"] end
    if #names == 1 then return names[1] end
    return L.Format("%s or %s", names[1], names[2])
end

--- The steps to get the quest's upgrade, worked out from where it comes
--- from and what the game shows. A list of { text, done, place, note },
--- every step before the furthest one done counted as done too.
-- @return steps, and the index of the step to do now
function UpgradeQuest:Steps(quest)
    quest = quest or self:Current()
    if not quest then return {}, 0 end
    local source = quest.source or {}
    local itemID = quest.itemID
    -- Shown in its rarity colour: the item's own link once the client has
    -- it, even when the quest was saved before it did.
    local link = Items.ShowLink(quest.link)
    local zone = self.Zone()
    local have = self.Count(itemID) > 0
    local worn = self.Worn(itemID)
    local money = ns.Finder and ns.Finder.Money or function() return nil end
    local steps = {}

    local function Add(text, done, place, note)
        steps[#steps + 1] = { text = text, done = done and true or false, place = place, note = note }
    end

    local function Travel(where)
        if where and where.zone then
            Add(L.Format("Travel to %s", where.zone), zone == where.zone, { zone = where.zone, name = where.zone })
            -- Standing in the zone says nothing about the steps before it.
            steps[#steps].soft = true
        end
    end

    -- A quest that starts from an item: where to get the item (the first
    -- place the data gives, Forever's before Classic's), then using it.
    -- With the item in the bags, only the using is left.
    local function StartFromItem(questID, title, itemName, started, travel, lead)
        title = title or L["the quest"]
        local starter = questID and UpgradeQuest.Starter(questID)
        itemName = (starter and starter.item) or itemName or L["an item"]
        -- The item that starts it, in its rarity colour.
        itemName = Items.ColorName(starter and starter.itemID, itemName)
        local held = starter and UpgradeQuest.Count(starter.itemID) > 0
        local first = starter and starter.places[1]
        if not first and not held then
            Add(L.Format("Find %s, the item that starts %s", itemName, title), started, nil,
                (lead and lead .. " " or "") .. L["Where it drops isn't known yet. Once you have it, right-click it in your bags to start the quest."])
            return
        end
        if first and not held and not started then
            local place
            if first.kind == "boss" then
                place = first.door and { zone = first.door, name = first.zone } or nil
                if place and ns.DungeonDoors then ns.DungeonDoors:Fill(place, first.zone) end
            else
                place = { zone = first.zone, x = first.x, y = first.y, name = first.name }
            end
            if travel then Travel(place) end
            local where = first.kind == "boss" and L.Format(" in %s", first.zone)
                or L.Format(" in %s", first.zone) .. At(first)
            local notes = { lead }
            if first.kind == "boss" then
                notes[#notes + 1] = first.zone == first.door and L["Bring a group."] or L["A dungeon boss, so bring a group."]
            elseif first.rank == "rare" or first.rank == "rare elite" then
                notes[#notes + 1] = L["A rare, so it may not be up when you get there."]
            end
            local chance = tonumber(first.chance)
            if chance and chance < 100 and first.kind ~= "vendor" then
                notes[#notes + 1] = L.Format("A %s%% drop.", tostring(chance))
            end
            local others = {}
            for index = 2, #starter.places do others[#others + 1] = starter.places[index].name end
            if #others > 0 then
                local more = starter.total - #starter.places
                local names = table.concat(others, L[" and "])
                notes[#notes + 1] = more > 0 and L.Format("Also from %s and %d more.", names, more)
                    or L.Format("Also from %s.", names)
            end
            local text = first.kind == "vendor"
                and L.Format("Buy %s from %s%s%s", itemName, first.name or "?", LevelText(first), where)
                or L.Format("Get %s from %s%s%s", itemName, first.name or "?", LevelText(first), where)
            Add(text, false, place, table.concat(notes, " "))
            lead = nil
        end
        Add(L.Format("Right-click %s in your bags to start %s", itemName, title), started, nil, lead)
    end

    if source.kind == "vendor" then
        local place = { zone = source.zone, x = source.x, y = source.y, name = source.name }
        Travel(place)
        local text = L.Format("Find %s%s", source.name or L["the vendor"], At(place))
        Add(text, false, place)
        -- What a merchant window showed on Forever beats the Classic price
        -- saved with the quest.
        local cost = (ns.NPCSpots and ns.NPCSpots:Price(itemID)) or source.price
        local price = money(cost)
        local notes = {}
        local short = not have and ns.Finder and money(ns.Finder.Short(cost))
        if short then
            local held = money(ns.Finder.MoneyHeld()) or L["no money"]
            notes[#notes + 1] = L.Format("|c%sNot enough money:|r you have %s and need %s more.",
                ns.COLORS.downgrade, held, short)
        end
        if source.limited then
            notes[#notes + 1] = L["Limited stock. If it's sold out, wait for the vendor to restock."]
        end
        Add(price and L.Format("Buy %s for %s", link, price) or L.Format("Buy %s", link), have, place,
            #notes > 0 and table.concat(notes, " ") or nil)
        steps[#steps].short = short and true or nil
    elseif source.kind == "quest" then
        local questID = source.questID
        local turnedIn = questID and ns.Finder and ns.Finder:QuestDone(questID)
        local onQuest = questID and OnQuest(questID)
        -- The quests before it in its chain, first one first. The first
        -- two are spelled out; the rest wait as one step, so a long chain
        -- does not bury the quest it leads to.
        local chain, unknown = {}, nil
        if questID and ns.Finder then chain, unknown = ns.Finder:Chain(questID) end
        local count = #chain + (unknown and 1 or 0)
        local lead = count > 1 and L.Format("%d quests to do before %s.", count, source.title or L["it"]) or nil
        if unknown then
            local after = chain[1] and chain[1].questID or questID
            Add(L.Format("Do %s", unknown), OnQuest(after), nil,
                (lead and lead .. " " or "") .. L["Skip this one if you have done it."])
            lead = nil
        end
        for index, before in ipairs(chain) do
            if index > CHAIN_SHOWN then
                local rest = #chain - CHAIN_SHOWN
                local upTo = chain[#chain].title or L["it"]
                Add(rest == 1 and L.Format("Then %d more quest in the chain, up to %s", rest, upTo)
                    or L.Format("Then %d more quests in the chain, up to %s", rest, upTo), false, nil,
                    L.Format("The quests come one after another, and %s opens once they're done.", source.title or L["the quest"]))
                break
            end
            local spot = before.x and { zone = before.zone, x = before.x, y = before.y, name = before.name } or nil
            local text, turnIn
            local note = lead
            lead = nil
            if OnQuest(before.questID) then
                -- In the log: the giver is behind the player. Send them to
                -- the objective, or to whoever takes it back once it is done
                -- (or when it has nothing else to do).
                local ender = UpgradeQuest.Ender(before.questID) or {}
                local hand = ender.hand
                local goal = ender.goal and UpgradeQuest.OpenGoal(ender, LogObjectives(before.questID))
                local title = L.Format("%s (level %d)", before.title, before.questLevel or 0)
                if hand and QuestReady(before.questID) then
                    text = L.Format("Hand in %s %s", before.title, HandText(hand, true))
                    spot = Spot(hand)
                    turnIn = true
                elseif goal then
                    text = L.Format("Complete %s: %s", title, GoalText(goal))
                    spot = Spot(goal)
                    if hand then
                        note = (note and note .. " " or "") .. L.Format("Then hand it in %s.", HandText(hand))
                    end
                elseif hand then
                    text = L.Format("Complete %s and hand it in %s", title, HandText(hand, true))
                    spot = Spot(hand)
                else
                    text = L.Format("Complete %s", title)
                    spot = nil
                end
            elseif spot then
                -- Two quests in a row can share a title (The Ravaged
                -- Caravan): say this one is the next part.
                local again = index > 1 and chain[index - 1].title == before.title
                text = again
                    and L.Format("Then do the next part of %s: pick it up from %s in %s%s",
                        before.title, before.name or "?", before.zone or "?", At(spot))
                    or L.Format("Do %s: pick it up from %s in %s%s",
                        before.title, before.name or "?", before.zone or "?", At(spot))
            end
            local need = NEED_NOTES[before.group]
            if need then note = (note and note .. " " or "") .. need end
            if text then
                Add(text, false, spot, note)
                -- Ready to hand in: the panel shows the game's ? for it.
                steps[#steps].turnIn = turnIn
                -- In the log: the panel shows its objectives and counts.
                if OnQuest(before.questID) then steps[#steps].questID = before.questID end
            else
                StartFromItem(before.questID, before.title, before.name, false, false, note)
            end
        end
        local place = source.x and { zone = source.zone, x = source.x, y = source.y, name = source.name } or nil
        if place then Travel(place) end
        if place then
            Add(L.Format("Pick up %s from %s%s", source.title or L["the quest"], source.name or "?", At(place)),
                onQuest, place)
        else
            StartFromItem(questID, source.title, source.name, onQuest, true)
        end
        local note = NEED_NOTES[source.group]
        -- Where to work on it and who takes it back (Data/QuestEnds.lua),
        -- so the arrow leaves the giver once the quest is in the log.
        local ender = questID and UpgradeQuest.Ender(questID) or {}
        -- In the log, the first objective not done yet: Warsong Supplies
        -- moves on from Logging Rope once the log shows it collected.
        local goal = ender.goal
        if goal and onQuest then goal = UpgradeQuest.OpenGoal(ender, LogObjectives(questID)) end
        local complete = goal
            and L.Format("Complete %s (level %d): %s", source.title or L["the quest"], source.questLevel or 0,
                GoalText(goal))
            or L.Format("Complete %s (level %d)", source.title or L["the quest"], source.questLevel or 0)
        Add(complete, questID and QuestReady(questID), Spot(goal), note)
        if onQuest then steps[#steps].questID = questID end
        -- A reward given outright comes with the quest; only one of a
        -- choice is picked. Read from the data, so a quest kept from before
        -- this was known reads right too.
        local given = source.given or (ns.Finder and ns.Finder.Given(itemID, questID))
        if ender.hand then
            local hand = HandText(ender.hand, ender.hand.zone ~= source.zone)
            Add(given and L.Format("Hand it in %s to get %s", hand, link)
                or L.Format("Hand it in %s and choose %s", hand, link),
                have or turnedIn, Spot(ender.hand))
        else
            Add(given and L.Format("Hand it in to get %s", link) or L.Format("Hand it in and choose %s", link),
                have or turnedIn, nil)
        end
        steps[#steps].turnIn = not (have or turnedIn) and questID ~= nil and QuestReady(questID) or nil
        if onQuest and not (have or turnedIn) then steps[#steps].questID = questID end
    elseif source.kind == "dungeon" then
        local door = source.zone and { zone = source.zone, name = source.dungeon } or nil
        if door and ns.DungeonDoors then ns.DungeonDoors:Fill(door, source.dungeon) end
        if door and door.zone ~= source.dungeon then Travel(door) end
        local range = (not source.raid and source.minLevel)
            and L.Format(" (levels %d to %d)", source.minLevel, source.maxLevel or source.minLevel) or ""
        local dungeon = source.dungeon or L["the dungeon"]
        Add(source.raid and L.Format("Gather a raid and enter %s%s", dungeon, range)
            or L.Format("Gather a group and enter %s%s", dungeon, range),
            zone == source.dungeon, door)
        local note = source.chance
            and L.Format("It's a %s%% drop, so it can take a few runs.", tostring(source.chance)) or nil
        Add(L.Format("Defeat %s and loot %s", source.name or L["the boss"], link), have, nil, note)
    elseif source.kind == "craft" then
        local crafting = ns.Crafting
        local profession = source.profession or L["the profession"]
        local learn = source.learn
        local place = source.zone and { zone = source.zone, x = source.x, y = source.y, name = source.name } or nil
        local craft = ns.Crafts and ns.Crafts.ITEMS[itemID]
        local skill = craft and crafting and crafting:Professions()[craft[1]]
        local knows = craft and crafting and crafting:Knows(craft[3])

        if source.state == "alt" then
            Add(L.Format("Ask %s to make %s (%s) and mail it to you", Who(source.who), link, profession),
                have, nil)
            Add(L["Collect it from a mailbox"], have, nil)
        elseif source.state == "other" then
            Add(L.Format("Buy %s at the auction house, or ask a %s crafter", link, profession), have, nil)
        else
            if source.state == "skill" then
                Add(L.Format("Raise %s to %d", profession, source.skill or 0),
                    (skill or 0) >= (source.skill or 0), nil,
                    L.Format("You have %d.", skill or source.have or 0))
            end
            if source.state == "skill" or source.state == "learn" then
                if place then Travel(place) end
                local how = crafting and learn and crafting:LearnText(learn, money)
                Add(how and L.Format("Learn the recipe: %s", how) or L["Learn the recipe"], knows == true, place)
            end
            local materials = crafting and crafting:MaterialsText(itemID) or ""
            if materials ~= "" then
                local all = true
                local list = craft and craft.m or {}
                for i = 1, #list, 2 do
                    if self.Count(list[i]) < list[i + 1] then all = false end
                end
                local cost = money(source.cost)
                Add(L.Format("Gather the materials: %s", materials), all, nil,
                    cost and (source.partial and L.Format("About over %s to buy.", cost)
                        or L.Format("About %s to buy.", cost)) or nil)
            end
            Add(L.Format("Make %s (%s)", link, profession), have, nil)
        end
    else
        Add(L.Format("Get %s", link), have, nil)
    end

    Add(L.Format("Put on %s", link), worn, nil, quest.howMuch and L.Format("%s over what you wear now.", quest.howMuch) or nil)

    -- A later step done means the ones before it are too: the vendor was
    -- found once the item is bought, wherever the character is now.
    local furthest = 0
    for index, step in ipairs(steps) do
        if step.done and not step.soft then furthest = index end
    end
    local current = #steps
    for index, step in ipairs(steps) do
        if index < furthest then step.done = true end
    end
    for index, step in ipairs(steps) do
        if not step.done then
            current = index
            break
        end
    end
    -- The step to do now on a quest in the log carries the quest as the log
    -- shows it (objectives with their counts, tracked or not), read for
    -- that one quest only.
    local now = steps[current]
    if now and not now.done and now.questID and ns.QuestLog then
        local ok, found = pcall(ns.QuestLog.Find, ns.QuestLog, now.questID)
        now.progress = ok and found or nil
    end
    return steps, current
end

--- The next step with a spot to put on the map, from the current one on.
function UpgradeQuest:NextPlace()
    local steps, current = self:Steps()
    local first
    for index = math.max(current, 1), #steps do
        local step = steps[index]
        local place = not step.done and step.place
        if place and place.zone then
            -- A spot beats a zone-only step for the same zone ("Travel to
            -- Westfall", then the vendor there), as the arrow has it.
            if place.x and place.y then
                if not first or first.zone == place.zone then return place end
                return first
            end
            first = first or place
        end
    end
    return first
end

--------------------------------------------------------------------------------
-- Keeping it up to date
--------------------------------------------------------------------------------

--- Tell whatever shows the quest to draw it again.
function UpgradeQuest:Changed()
    for _, name in ipairs({ "QuestPanel", "MapPins", "SettingsUI", "FinderUI", "QuestArrow", "IgnoredUI" }) do
        local module = ns[name]
        if module and module.OnUpgradeQuestChanged then pcall(module.OnUpgradeQuestChanged, module) end
    end
end

--- Is the quest's item still an upgrade worth the trip? False when
--- something as good or better is worn now (found elsewhere, say).
function UpgradeQuest:StillWanted(quest)
    local ok, result = pcall(ns.Compare.Judge, ns.Compare, quest.link)
    if not ok or not result then return true end
    if result.verdict == "downgrade" or result.verdict == "same" then return false end
    return true
end

--- Is the quest's item armor Best Armor Only now leaves out?
function UpgradeQuest:LighterArmor(quest)
    local ok, result = pcall(ns.Compare.Judge, ns.Compare, quest.link)
    return ok and type(result) == "table" and result.lighterArmor == true
end

--- Is the quest's item a weapon this character hides until trained
--- (Settings' Untrained Weapons on Hide, or its type ignored from a banner)?
function UpgradeQuest:HiddenWeapon(quest)
    local ok, result = pcall(ns.Compare.Judge, ns.Compare, quest.link)
    return ok and type(result) == "table" and result.ignoredSkill ~= nil
end

--- Was the quest that gives this upgrade handed in, with the upgrade
--- neither carried nor worn? Only after a few seconds of it missing, since
--- the reward can reach the bags a moment after the hand-in.
function UpgradeQuest:HandedInWithout(quest)
    local source = quest.source
    if not (source and source.kind == "quest" and source.questID and ns.Finder) then return false end
    -- Kept per quest: each tab's quest is checked in turn, so one shared
    -- clock was reset by the others, or carried from one to the next.
    self.missingSince = self.missingSince or {}
    local key = source.questID
    if not ns.Finder:QuestDone(source.questID) or self.Count(quest.itemID) > 0 then
        self.missingSince[key] = nil
        return false
    end
    local now = ns.Finder.Now()
    local since = self.missingSince[key]
    if not since then
        self.missingSince[key] = now
        self.recheck = true
        return false
    end
    return now - since >= 5
end

--------------------------------------------------------------------------------
-- A level up that opens something better
--------------------------------------------------------------------------------

--- How much the quest being followed is worth now, judged like a pick.
function UpgradeQuest:QuestWorth(quest, zone)
    local ok, result = pcall(ns.Compare.Judge, ns.Compare, quest.link)
    if not (ok and result) then return nil end
    local gain = (result.score or 0) - (result.against or 0)
    return Worth(result, gain, self.Ease(quest.source or {}, zone))
end

--- After a level up: is there now an upgrade clearly more worth the trip
--- than the quest being followed? The quest is kept either way; a better
--- one is only offered, for the player to switch to or not.
function UpgradeQuest:LookForBetter(quest)
    local found, why = self:FreshScan()
    if why == "waiting" then return end
    if not found then
        self.levelledAt = nil
        return
    end
    local now = ns.Finder.Now()
    local looking = now - self.levelledAt < LEVEL_LOOK
    -- The scan was made before the client caught up with the new level.
    if looking and self.newLevel and found.player and (found.player.level or 0) < self.newLevel then
        ns.Finder:MarkStale()
        self.recheck = true
        return
    end
    if looking and found.waiting > 0 then
        self.recheck = true
    else
        self.levelledAt = nil
    end

    local except = { [quest.itemID] = true }
    for itemID in pairs(self.declined) do except[itemID] = true end
    local tab = self.TabOf(quest.source) or self:Tab()
    local best = self:Choose(found, except, tab)
    local worth = self:QuestWorth(quest, found.player and found.player.zone)
    if not (best and worth) or best.worth < worth * CLEARLY_BETTER then return end
    if self.offer and self.offer.pick.itemID == best.pick.itemID then return end

    self.offer = {
        pick = best.pick,
        source = best.source,
        questItemID = quest.itemID,
        level = (found.player and found.player.level) or self.newLevel,
        howMuch = best.pick.result and ns.Compare:HowMuch(best.pick.result) or nil,
    }
    if ns.Toast then
        ns.Toast:Show({ title = L["New upgrade on offer"], link = best.pick.link,
            text = L["Your new level opened a better upgrade. Switch to it on the quest panel."] })
    end
end

--- The upgrade the last level up opened, while it is on offer, or nil:
--- { pick, source, level, howMuch }.
function UpgradeQuest:Offer()
    return self.offer
end

--- Follow the upgrade on offer instead of the quest being followed.
function UpgradeQuest:SwitchToOffer()
    local offer = self.offer
    if not offer then return false end
    self.offer = nil
    self:Start(offer.pick, offer.source)
    self.lastStep = nil
    self:Update()
    return true
end

--- Keep the quest being followed: the upgrade on offer is not offered
--- again this session.
function UpgradeQuest:KeepCurrent()
    local offer = self.offer
    if not offer then return false end
    self.declined[offer.pick.itemID] = true
    self.offer = nil
    self:Changed()
    return true
end

--- Look at the quest: finish it when the item is worn, drop it when it is
--- no longer an upgrade, and pick the next one when there is none.
function UpgradeQuest:Update()
    self.updating = true
    local ok, err = pcall(self.Check, self)
    self.updating = false
    if not ok then error(err, 0) end
    -- Still waiting on the server: look again shortly, in case no more
    -- answers come in to prompt it.
    if self.state == "waiting" or self.recheck then
        self.recheck = nil
        self:RetrySoon()
    end
end

function UpgradeQuest:RetrySoon()
    local after = _G.C_Timer and _G.C_Timer.After
    if self.retryPending or type(after) ~= "function" then return end
    self.retryPending = true
    local scheduling = true
    after(6, function()
        UpgradeQuest.retryPending = false
        -- Run at once, by a client without real timers: looking again now
        -- would only go round in circles.
        if scheduling then return end
        local ok, err = pcall(UpgradeQuest.Update, UpgradeQuest)
        if not ok then ns.Debug("upgrade quest:", tostring(err)) end
    end)
    scheduling = false
end

function UpgradeQuest:Check()
    if not self:IsEnabled() then
        self:Changed()
        return
    end

    local quests = self:Quests()
    local shownBefore = self:Current()
    local before = shownBefore and shownBefore.itemID
    local beforeTab = self:Tab()
    local firstPick = not IS_TAB[ns.charDB.upgradeQuestTab]
    local lastStep = self.lastStep
    local completed = {}

    for _, tab in ipairs(TABS) do
        local quest = Valid(quests[tab.key])
        local shown = tab.key == beforeTab
        if quest and self.Worn(quest.itemID) then
            quests[tab.key] = nil
            -- The same upgrade on two tabs is one quest done.
            if not completed[quest.itemID] then
                completed[quest.itemID] = true
                ns.charDB.upgradeQuestsDone = self:DoneCount() + 1
                if ns.Toast then
                    ns.Toast:Show({ title = L["Upgrade quest complete"], link = quest.link,
                        text = L.Format("That's %d upgrade quests done. Picking your next one.", self:DoneCount()) })
                end
            end
            if ns.Finder then ns.Finder:MarkStale() end
        elseif quest and (self:LighterArmor(quest) or self:HiddenWeapon(quest)) then
            -- Best Armor Only was ticked, or an untrained weapon hidden,
            -- after this was picked (followed by hand too): let it go
            -- quietly (not skipped), and the tab picks again.
            quests[tab.key] = nil
            if ns.Finder then ns.Finder:MarkStale() end
        elseif quest and not self:StillWanted(quest) then
            -- Something as good or better was put on first (looted, bought,
            -- made): this one is beaten, carried or not. Only the tab on
            -- show says so; the others quietly pick again.
            quests[tab.key] = nil
            if shown then
                ns.Print(L.Format("dropped the upgrade quest for %s, since you're already wearing something as good.", Items.ShowLink(quest.link)))
                if ns.Toast then
                    ns.Toast:Show({ title = L["You already beat this one"], link = quest.link,
                        text = L["You're already wearing something as good. Picking your next upgrade."] })
                end
            end
            if ns.Finder then ns.Finder:MarkStale() end
        elseif quest and self:HandedInWithout(quest) then
            -- The quest was handed in and another reward taken: it cannot be
            -- done again, so this upgrade is out of reach.
            quests[tab.key] = nil
            self:Skipped()[quest.itemID] = true
            ns.Print(L.Format("dropped the upgrade quest for %s, since that quest is already done.", Items.ShowLink(quest.link)))
        end
        if Valid(quests[tab.key]) then self.states[tab.key] = "active" end
    end

    self:PickEmpty()
    local quest = self:Current()
    self.state = quest and "active" or self.states[self:Tab()] or "none"
    if quest and quest.itemID ~= before and (firstPick or beforeTab == self:Tab()) then
        self.lastStep = nil
        if ns.Toast then
            ns.Toast:Show({ title = L["New upgrade quest"], link = quest.link,
                text = quest.howMuch and L.Format("%s over what you wear now.", quest.howMuch)
                    or L["Follow the steps on the quest panel."] })
        end
    end

    -- An offer is only for the quest it was made against.
    if self.offer and not (quest and self.offer.questItemID == quest.itemID) then self.offer = nil end
    if quest and quest.itemID == before and self.levelledAt then
        self:LookForBetter(quest)
    elseif not (quest and quest.itemID == before) then
        -- A quest picked after the level up already counts the new level.
        self.levelledAt = nil
    end

    -- A step ticked off since last time: a little cheer.
    local steps
    if quest and quest.itemID == before then
        local current
        steps, current = self:Steps(quest)
        if lastStep and current > lastStep then self.stepDone = current - 1 end
        self.lastStep = current
    elseif quest then
        local current
        steps, current = self:Steps(quest)
        self.lastStep = current
    end

    self:Mirror()
    -- After an event (a bag change, a quest log tick, a new zone), the
    -- panel, the map pins and the arrow are drawn again only when what they
    -- show moved. A click or a command always draws them.
    local shows = self:Shows(steps)
    if self.fromEvent and shows == self.shown then return end
    self.shown = shows
    self:Changed()
end

--- Everything the panel, the map pins, the arrow and the finder's Quest
--- marks are drawn from, as one string: two that match draw the same.
function UpgradeQuest:Shows(steps)
    local parts = { tostring(self:Tab()), tostring(self.state), tostring(self.scanFailed),
        tostring(self.stepDone), tostring(self.offer and self.offer.questItemID),
        tostring(self.offer and self.offer.pick and self.offer.pick.itemID) }
    local quests = self:Quests()
    for _, tab in ipairs(TABS) do
        local quest = quests[tab.key]
        parts[#parts + 1] = ("%s=%s/%s/%s"):format(tab.key, tostring(type(quest) == "table" and quest.itemID),
            tostring(self.states[tab.key]), tostring(type(quest) == "table" and quest.here))
    end
    local skipped = 0
    for _ in pairs(self:Skipped()) do skipped = skipped + 1 end
    parts[#parts + 1] = "skipped=" .. skipped
    for index, step in ipairs(type(steps) == "table" and steps or {}) do
        local place = type(step.place) == "table" and step.place or {}
        parts[#parts + 1] = table.concat({ tostring(index), tostring(step.text), tostring(step.done),
            tostring(step.note), tostring(step.turnIn), tostring(step.soft), tostring(step.short),
            tostring(place.zone), tostring(place.x), tostring(place.y), tostring(place.name) }, "~")
        local progress = type(step.progress) == "table" and step.progress
        if progress then
            local lines = { tostring(progress.title), tostring(progress.level), tostring(progress.tracked),
                tostring(progress.complete), tostring(progress.failed) }
            for _, objective in ipairs(progress.objectives or {}) do
                lines[#lines + 1] = tostring(objective.text) .. "=" .. tostring(objective.done)
            end
            parts[#parts + 1] = table.concat(lines, "~")
        end
    end
    return table.concat(parts, "|")
end

--- Update after a short pause, so a burst of bag events is one update.
function UpgradeQuest:UpdateSoon(delay)
    -- Never from inside an update: a client whose timers run at once would
    -- go round for ever while it waits on the server.
    if self.waiting or self.updating or not self:IsEnabled() then return end
    self.waiting = true
    local after = _G.C_Timer and _G.C_Timer.After
    if type(after) ~= "function" then
        self.waiting = false
        pcall(self.Update, self)
        return
    end
    after(delay or 0.5, function()
        UpgradeQuest.waiting = false
        UpgradeQuest.fromEvent = true
        local ok, err = pcall(UpgradeQuest.Update, UpgradeQuest)
        UpgradeQuest.fromEvent = nil
        if not ok then ns.Debug("upgrade quest:", tostring(err)) end
    end)
end

--- Ignore this upgrade for good (until restored) and pick another for the
--- tab.
function UpgradeQuest:Skip()
    local quest = self:Current()
    if not quest then return false end
    self:Skipped()[quest.itemID] = true
    self:Quests()[self:Tab()] = nil
    self.lastStep = nil
    self.rescan = true
    self:Update()
    return true
end

--- Turn the upgrade quest on or off.
function UpgradeQuest:SetEnabled(on)
    if not ns.db then return end
    ns.db.upgradeQuest = on and true or false
    if on then
        self.rescan = true
        self:Update()
    else
        self.state = nil
        self:Changed()
    end
    if ns.UI and ns.UI.OnUpgradeQuestToggled then pcall(ns.UI.OnUpgradeQuestToggled, ns.UI) end
end

--- Bring the upgrade quest back: on, and its panel shown unfolded. Its
--- quests were kept while it was closed, so it picks up where it was.
--- For every way back (the gear window's Upgrade quest button, the minimap
--- button's Shift-click, Settings, /beq quest, What's New).
function UpgradeQuest:TurnOn()
    if not self:IsEnabled() then
        self:SetEnabled(true)
        ns.Print(L["upgrade quest on. Follow the steps on the quest panel."])
    else
        self.rescan = true
        self:Update()
    end
    if ns.QuestPanel then ns.QuestPanel:Unfold() end
end

--- Close the upgrade quest: its panel goes, its quests are kept, and chat
--- says how to bring it back.
function UpgradeQuest:TurnOff()
    if self:IsEnabled() then self:SetEnabled(false) end
    ns.Print(L["upgrade quest closed. Your quests are saved. Bring it back with the Upgrade quest button in the gear window, Shift-click on the minimap button, or /beq quest."])
end

--- Close it when it is up, bring it back when it is not.
function UpgradeQuest:Toggle()
    if self:IsEnabled() then self:TurnOff() else self:TurnOn() end
end

--- A quest filter changed ("Solo quests only", or how far above the
--- character a quest may be). A tab following a quest the filters now
--- leave out lets it go (not skipped, so it can come back) and picks
--- again; either way the empty tabs look again.
function UpgradeQuest:OnQuestFilterChanged()
    local finder = ns.Finder
    if not finder then return end
    local player = finder:Player()
    local quests = self:Quests()
    for _, tab in ipairs(TABS) do
        local quest = Valid(quests[tab.key])
        local source = quest and quest.source
        if source and source.kind == "quest" then
            local allowed = finder:QuestAllowed(source, player and player.level)
            if allowed and finder:SoloOnly() and source.questID then
                for _, before in ipairs((finder:Chain(source.questID))) do
                    if finder.Need(before.group) then allowed = false end
                end
            end
            if not allowed then quests[tab.key] = nil end
        end
    end
    self:Mirror()
    self.rescan = true
    self.offer = nil
    self.lastStep = nil
    if self:IsEnabled() then self:Update() else self:Changed() end
end

--- Is the character only passing through: on a flight, or inside a
--- dungeon or raid? Then the zone it is in says nothing about where it
--- will look for gear, so "This zone only" lets go of nothing. Unreadable
--- counts as passing: keeping a quest a little longer does no harm.
function UpgradeQuest.Passing()
    local ok, passing = pcall(function()
        if type(_G.UnitOnTaxi) == "function" and _G.UnitOnTaxi("player") then return true end
        if type(_G.IsInInstance) == "function" and _G.IsInInstance() then return true end
        return false
    end)
    return not ok or passing == true
end

--- Is the character on a flight?
function UpgradeQuest.OnTaxi()
    local ok, flying = pcall(function()
        return type(_G.UnitOnTaxi) == "function" and _G.UnitOnTaxi("player") and true or false
    end)
    return ok and flying == true
end

--- Let go of the tabs' quests that are not in the zone the character is
--- in (not skipped: they come back in their own zone), while "This zone
--- only" is ticked. A quest followed from Where to get upgrades stays, and
--- nothing is let go on a flight or inside a dungeon (UpgradeQuest.Passing).
-- @return true when one was let go
function UpgradeQuest:LetGoOutOfZone()
    if not self:ZoneOnly() or self.Passing() then return false end
    local here = self.Zone()
    if not here then return false end
    local quests = self:Quests()
    local any = false
    for _, tab in ipairs(TABS) do
        local quest = Valid(quests[tab.key])
        if quest and not quest.followed and not self.InZone(quest.source, here) then
            quests[tab.key] = nil
            any = true
        end
    end
    return any
end

--- Tick or untick "This zone only". Ticked, the tabs' quests elsewhere are
--- let go and each tab picks again from the zone the character is in;
--- unticked, the quests it picked are let go and every tab picks again
--- from anywhere. A quest followed from Where to get upgrades stays.
function UpgradeQuest:SetZoneOnly(on)
    if not ns.db then return end
    ns.db.upgradeQuestZoneOnly = on and true or false
    if on then
        self:LetGoOutOfZone()
    else
        local quests = self:Quests()
        for _, tab in ipairs(TABS) do
            local quest = Valid(quests[tab.key])
            if quest and quest.here and not quest.followed then quests[tab.key] = nil end
        end
    end
    self:Mirror()
    self.rescan = true
    self.offer = nil
    self.lastStep = nil
    if self:IsEnabled() then self:Update() else self:Changed() end
end

--- Is an item answer from the server about gear the quest cares about: an
--- item a finder scan asked for, or one of the tabs' upgrades?
function UpgradeQuest:WantsItem(itemID)
    if ns.Finder and ns.Finder:Asked(itemID) then return true end
    local ok, id = pcall(function() return tonumber(itemID) end)
    if not (ok and id) then return false end
    for _, quest in pairs(self:Quests()) do
        if type(quest) == "table" and quest.itemID == id then return true end
    end
    return false
end

function UpgradeQuest:OnEvent(event, level)
    -- Control comes back after every stun and fear; it only matters at the
    -- end of a flight that crossed a zone.
    local newZone = event == "ZONE_CHANGED_NEW_AREA"
    if event == "PLAYER_CONTROL_GAINED" then
        if not self.landing then return end
        newZone = true
    end
    -- A flight that crossed a zone is over once the character is off it,
    -- whichever event says so first: if the client never sends
    -- PLAYER_CONTROL_GAINED at the landing, the quests from the zone flown
    -- out of would otherwise stay until the next zone change. The event
    -- that said so is still handled as itself below.
    if self.landing and not self.OnTaxi() then
        self.landing = nil
        self:StopWatchingLanding()
        newZone = true
    end
    -- A loading screen, a login or a /reload: the character may be in
    -- another zone from the one the quests were picked in.
    if event == "PLAYER_ENTERING_WORLD" then newZone = true end
    -- The client loads items for chat links, vendors and other addons all
    -- the time; only answers this addon asked for are worth looking again.
    if event == "GET_ITEM_INFO_RECEIVED" and not self:WantsItem(level) then return end
    if event == "PLAYER_LEVEL_UP" then
        -- Look for gear the new level opened, for a little while.
        self.levelledAt = ns.Finder and ns.Finder.Now() or Now()
        local ok, value = pcall(function()
            local number = tonumber(level)
            if number and number > 0 and number < 1000 then return number end
        end)
        self.newLevel = ok and value or nil
    end
    if RESCAN_ON[event] then self.rescan = true end
    -- A new zone has its own upgrades while "This zone only" is ticked.
    -- On a flight, every zone flown over would pick (and announce) its own,
    -- so that waits for the landing.
    -- Unless "Change on a new zone" is unticked: then the quests stay, but
    -- a tab that found nothing in the last zone still looks in this one.
    if newZone and self:ZoneOnly() then
        if self.OnTaxi() then
            if self:ZoneSwap() then
                self.landing = true
                self:WatchLanding()
            end
            return
        end
        if self:ZoneSwap() then
            self:LetGoOutOfZone()
            self:Mirror()
        end
        self.rescan = true
    end
    if event == "BAG_UPDATE_DELAYED" then self.bagsChanged = true end
    self:UpdateSoon()
end

--- Look every few seconds whether a flight that crossed a zone has
--- landed, in case no event says so. Stops once it has.
function UpgradeQuest:WatchLanding()
    local timer = _G.C_Timer
    if self.watcher or not (timer and type(timer.NewTicker) == "function") then return end
    local ok, ticker = pcall(timer.NewTicker, LANDING_CHECK, function()
        if not self.landing then
            self:StopWatchingLanding()
        elseif not self.OnTaxi() then
            self:OnEvent("ZONE_CHANGED_NEW_AREA")
        end
    end)
    if ok then self.watcher = ticker end
end

function UpgradeQuest:StopWatchingLanding()
    local ticker = self.watcher
    self.watcher = nil
    if ticker and type(ticker.Cancel) == "function" then pcall(ticker.Cancel, ticker) end
end

function UpgradeQuest:OnEnable()
    for _, event in ipairs({ "BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED", "PLAYER_LEVEL_UP",
        "ZONE_CHANGED_NEW_AREA", "QUEST_ACCEPTED", "QUEST_LOG_UPDATE", "QUEST_TURNED_IN", "QUEST_WATCH_LIST_CHANGED",
        "GET_ITEM_INFO_RECEIVED", "SKILL_LINES_CHANGED", "NEW_RECIPE_LEARNED", "TRAIT_CONFIG_UPDATED",
        "CHARACTER_POINTS_CHANGED", "PLAYER_TALENT_UPDATE", "PLAYER_CONTROL_GAINED", "PLAYER_ENTERING_WORLD" }) do
        ns.RegisterEvent(self, event, self.OnEvent)
    end
    if self:IsEnabled() then self:UpdateSoon(3) end
end

--------------------------------------------------------------------------------
-- /beq quest
--------------------------------------------------------------------------------

-- The words that pick a tab.
local TAB_WORDS = {
    vendor = "vendor", vendors = "vendor",
    quest = "quest", quests = "quest", reward = "quest", rewards = "quest",
    dungeon = "dungeon", dungeons = "dungeon", raid = "dungeon", raids = "dungeon",
    craft = "craft", crafted = "craft", crafting = "craft",
}

ns.RegisterCommand("quest", L["a quest for your next upgrade (/beq quest off, ignore, ignored, restore, switch, size, or a tab: vendor, quest, dungeon, crafted, log)"], function(rest)
    local word = (rest or ""):lower():match("^%s*(%a*)") or ""
    -- How big the panel is drawn: small, normal, large or a percent, as its
    -- gold corner grip and the Settings row do (UI/QuestPanel.lua).
    if word == "size" then
        local panel = ns.QuestPanel
        if not panel then return end
        local scale = panel.ParseSize((rest or ""):lower():match("^%s*size%s*(.-)%s*$"))
        if not scale then
            ns.Print(L.Format("the quest panel is at %s. To change it, type /beq quest size small, normal, large or a percent from 50%% to 150%%, or drag the gold corner below its bottom right.",
                panel.ScaleText(panel:GetScale())))
            return
        end
        panel:Build()
        ns.Print(L.Format("quest panel size: %s.", panel.ScaleText(panel:SetPanelScale(scale))))
        return
    end
    -- The Quest log tab: the character's quests, as the game's tracker
    -- shows them (UI/QuestLogTab.lua).
    if word == "log" then
        if not UpgradeQuest:IsEnabled() then UpgradeQuest:SetEnabled(true) end
        if ns.QuestPanel then
            ns.QuestPanel.folded = false
            ns.QuestPanel:ShowLog(true)
        end
        ns.Print(L["upgrade quest: showing the Quest log tab."])
        return
    end
    local tab = TAB_WORDS[word]
    if tab then
        if not UpgradeQuest:IsEnabled() then UpgradeQuest:SetEnabled(true) end
        UpgradeQuest:SelectTab(tab)
        ns.Print(L.Format("upgrade quest: showing the %s tab.", IS_TAB[tab].name))
        if ns.QuestPanel then ns.QuestPanel:Unfold() end
        return
    end
    if word == "off" then
        UpgradeQuest:TurnOff()
        return
    end
    -- "skip" was the word before Ignore and still works.
    if word == "ignore" or word == "skip" then
        local quest = UpgradeQuest:Current()
        if UpgradeQuest:Skip() then
            ns.Print(L.Format("ignored %s. It won't be offered again. To bring it back, go to Settings > Upgrade quest > Ignored.",
                quest and Items.ShowLink(quest.link) or L["that upgrade"]))
        else
            ns.Print(L["there is no upgrade quest to ignore."])
        end
        return
    end
    if word == "ignored" then
        if ns.IgnoredUI then ns.IgnoredUI:Show() end
        return
    end
    if word == "switch" then
        if UpgradeQuest:SwitchToOffer() then
            ns.Print(L["switched to the upgrade your new level opened."])
        else
            ns.Print(L["no new upgrade is on offer."])
        end
        return
    end
    -- "reset" was the word before Restore all and still works.
    if word == "restore" or word == "reset" then
        UpgradeQuest:RestoreAll()
        ns.Print(L["ignored upgrades can come up again."])
        return
    end
    UpgradeQuest:TurnOn()
end)

-- A one-time card in the What's New window (the owner asked 2026-10-13, as
-- many players miss the quest): shown once per account, and only while the
-- quest is off. Its button turns the quest on and opens the panel.
ns.WHATS_NEW_TIPS = ns.WHATS_NEW_TIPS or {}
table.insert(ns.WHATS_NEW_TIPS, {
    key = "upgradeQuest",
    title = L["Upgrade quest"],
    icon = [[Interface\GossipFrame\AvailableQuestIcon]],
    paragraphs = {
        L["Equipment can pick your next gear upgrade and walk you to it step by step, like a quest, with an arrow showing the way. It's off until you turn it on."],
    },
    hint = L["You can also find it in Equipment's Settings or type /beq quest."],
    button = L["Turn it on"],
    due = function() return not UpgradeQuest:IsEnabled() end,
    run = function() UpgradeQuest:TurnOn() end,
})
