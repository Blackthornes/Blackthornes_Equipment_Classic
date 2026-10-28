-- Blackthornes Equipment -- Core/Init.lua
-- Namespace, module registry, event dispatch and slash-command routing.
--
-- Same shape as Blackthornes Tradeskills and Blackthornes Farmer, and for the
-- same reason: Ace3 and LibStub are not known to be ported to WoW: Forever, so
-- the framework is ours and is small enough to read in one sitting.

local ADDON_NAME, ns = ...
local L = ns.L

_G.BlackthornesEquipment = ns

ns.ADDON_NAME = ADDON_NAME

local function GetMeta(field)
    if C_AddOns and C_AddOns.GetAddOnMetadata then
        local ok, value = pcall(C_AddOns.GetAddOnMetadata, ADDON_NAME, field)
        if ok then return value end
    end
    if type(_G.GetAddOnMetadata) == "function" then
        local ok, value = pcall(_G.GetAddOnMetadata, ADDON_NAME, field)
        if ok then return value end
    end
    return nil
end

-- The newest version in CHANGELOG.md. The release PR that writes that
-- section changes this line too, and tools/check_release.py refuses a tag it
-- does not match. Played straight from the repository there is no packager
-- to fill in the TOC's version, so this is the one shown.
ns.RELEASED_VERSION = "0.3.0"

-- The TOC carries @project-version@, which the release packager rewrites to
-- the tag it is building, "v0.2.0" say. Running straight from the repository
-- the keyword arrives unsubstituted, so the version is the changelog's newest.
local function ReadVersion()
    local value = GetMeta("Version")
    if type(value) ~= "string" or value == "" or value:find("@", 1, true) then
        return ns.RELEASED_VERSION
    end
    -- Tags start with a "v"; the version itself does not.
    return (value:gsub("^[vV]", ""))
end

ns.VERSION = ReadVersion()

--- The version as players see it: "v0.2.0".
function ns.VersionLabel()
    return "v" .. ns.VERSION
end

--------------------------------------------------------------------------------
-- Output
--------------------------------------------------------------------------------

-- The house palette, shared with Tradeskills and Farmer so the three look
-- like one set. Upgrades borrow Tradeskills' profit green, downgrades its loss
-- red.
ns.COLORS = {
    accent    = "ffc8a44d",
    upgrade   = "ff4fd18b",
    downgrade = "ffe5604f",
    muted     = "ff7a8089",
    warn      = "ffe8c15a",
    text      = "ffe6e8ec",
}

local PREFIX = "|c" .. ns.COLORS.accent .. "Equipment|r "

local function Join(...)
    local n = select("#", ...)
    if n == 0 then return "" end

    local parts = {}
    for i = 1, n do
        parts[i] = tostring((select(i, ...)))
    end
    return table.concat(parts, " ")
end

-- Checks kept for Claude (the owner asked 2026-10-10): while a check such as
-- the probe runs, every line it prints is kept as well, and ns.KeepCheck
-- saves them as lastProbe in the account save, replacing the last one. The
-- game writes the save on /reload or logout, so the results can be read from
-- there instead of from screenshots.
local kept

--- A printed line as plain text: colours, links and icons taken out. A
--- secret value never reaches the save.
local function Plain(line)
    local ok, text = pcall(function()
        local isSecret = _G.issecretvalue
        if type(isSecret) == "function" and isSecret(line) then return "(secret)" end
        local plain = table.concat({ tostring(line) })
        plain = plain:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        plain = plain:gsub("|H.-|h", ""):gsub("|h", ""):gsub("|T.-|t", "")
        return plain
    end)
    return ok and text or "(unreadable)"
end

local function Keep(line)
    if kept then kept[#kept + 1] = Plain(line) end
end

function ns.Print(...)
    local frame = DEFAULT_CHAT_FRAME
    if frame then
        local line = PREFIX .. Join(...)
        frame:AddMessage(line)
        Keep(line)
    end
end

-- Raw line with no prefix, for multi-line reports where the prefix is noise.
function ns.PrintRaw(...)
    local frame = DEFAULT_CHAT_FRAME
    if frame then
        local line = Join(...)
        frame:AddMessage(line)
        Keep(line)
    end
end

function ns.Debug(...)
    if ns.db and ns.db.debug then
        ns.PrintRaw("|c" .. ns.COLORS.muted .. "Equipment debug|r " .. Join(...))
    end
end

function ns.Warn(...)
    ns.Print("|c" .. ns.COLORS.warn .. Join(...) .. "|r")
end

--- Runs fn, a check that prints to chat, and saves what it printed as
--- lastProbe: which check, when, the addon version and the lines. Chat shows
--- the same as before, plus one line saying it was kept.
function ns.KeepCheck(name, fn, ...)
    kept = {}
    local ok, err = pcall(fn, ...)
    local lines = kept
    kept = nil
    if not ok then lines[#lines + 1] = "error: " .. Plain(err) end

    local db = ns.db
    if type(db) == "table" then
        db.lastProbe = {
            check = name,
            at = type(date) == "function" and date("%Y-%m-%d %H:%M:%S") or nil,
            version = ns.VERSION,
            lines = lines,
        }
        ns.Print(L["Saved for Claude, /reload to write it."])
    end
    if not ok then error(err, 0) end
end

--------------------------------------------------------------------------------
-- Module registry
--------------------------------------------------------------------------------

ns.modules = {}
ns.moduleOrder = {}

local moduleProto = {}
moduleProto.__index = moduleProto

function moduleProto:RegisterEvent(event, fn)
    return ns.RegisterEvent(self, event, fn or self[event])
end

function moduleProto:UnregisterEvent(event)
    return ns.UnregisterEvent(self, event)
end

function ns.NewModule(name)
    assert(type(name) == "string", "module name must be a string")
    assert(not ns.modules[name], "duplicate module: " .. name)

    local module = setmetatable({ moduleName = name }, moduleProto)
    ns.modules[name] = module
    ns.moduleOrder[#ns.moduleOrder + 1] = module
    ns[name] = module
    return module
end

--------------------------------------------------------------------------------
-- Event dispatch
--------------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame", "BlackthornesEquipmentEventFrame")
ns.eventFrame = eventFrame

local handlers = {}
local unknownEvents = {}

--- Register an event handler.
-- On Forever, registering an event the client does not know raises a Lua error
-- rather than failing quietly, so every registration goes through pcall.
function ns.RegisterEvent(owner, event, fn)
    if type(fn) ~= "function" then
        ns.Debug("RegisterEvent: no handler for", event)
        return false
    end

    local list = handlers[event]
    if not list then
        if unknownEvents[event] then return false end

        local ok, err = pcall(eventFrame.RegisterEvent, eventFrame, event)
        if not ok then
            unknownEvents[event] = err or true
            ns.Debug("event not supported by this client:", event)
            return false
        end
        list = {}
        handlers[event] = list
    end

    list[#list + 1] = { owner = owner, fn = fn }
    return true
end

function ns.UnregisterEvent(owner, event)
    local list = handlers[event]
    if not list then return false end

    -- A new list rather than the old one shortened: a handler that takes
    -- itself off while the event is being dispatched (BagIcons' and
    -- QuestLogUI's combat-end catch-ups) must not shift the next handler
    -- into the slot the dispatcher has just passed.
    local kept = {}
    for i = 1, #list do
        if list[i].owner ~= owner then kept[#kept + 1] = list[i] end
    end

    if #kept == 0 then
        handlers[event] = nil
        pcall(eventFrame.UnregisterEvent, eventFrame, event)
    else
        handlers[event] = kept
    end
    return true
end

function ns.GetUnknownEvents()
    return unknownEvents
end

-- Events a hunter's every shot fires, with what each says changed. Each is
-- passed on only when that has really changed (Data/Items.lua): looking
-- again at every upgrade per arrow made the game hang after each shot.
-- A skill point (crafting, gathering or a weapon swing) fires
-- SKILL_LINES_CHANGED; only a skill learned or dropped is passed on, since
-- a point threw every upgrade verdict away and started a new upgrade scan
-- (a hitch on some finished crafts, 2026-10-11).
local QUIET = { BAG_UPDATE_DELAYED = "BagSignature", PLAYER_EQUIPMENT_CHANGED = "WornSignature",
    SKILL_LINES_CHANGED = "SkillSignature" }
local lastSeen = {}

--- True when the event changed nothing worth looking at again.
function ns.NothingChanged(event)
    local method = QUIET[event]
    local items = ns.Items
    if not (method and items and type(items[method]) == "function") then return false end
    local ok, now = pcall(items[method], items)
    if not ok or type(now) ~= "string" then return false end
    if lastSeen[event] == now then return true end
    lastSeen[event] = now
    return false
end

--------------------------------------------------------------------------------
-- Speed check (/beq perf): how long each piece of work took, this session
-- only. Nothing is saved. A hitch in game can then be traced to its cause.
--------------------------------------------------------------------------------

local Perf = { rows = {} }
ns.Perf = Perf

--- Milliseconds from the client's high resolution clock, or nil.
function Perf.Clock()
    local clock = rawget(_G, "debugprofilestop")
    if type(clock) == "function" then
        local ok, now = pcall(clock)
        if ok and type(now) == "number" then return now end
    end
    return nil
end

--- Note that `label` took `ms` milliseconds.
function Perf:Add(label, ms)
    if type(ms) ~= "number" then return end
    local row = self.rows[label]
    if not row then
        row = { label = label, runs = 0, total = 0, worst = 0 }
        self.rows[label] = row
    end
    row.runs = row.runs + 1
    row.total = row.total + ms
    if ms > row.worst then row.worst = ms end
end

--- Run fn, timing it under `label`. Errors are passed on unchanged.
function Perf:Run(label, fn, ...)
    local started = self.Clock()
    if not started then return fn(...) end
    local result = { pcall(fn, ...) }
    local finished = self.Clock()
    if finished then Perf:Add(label, finished - started) end
    if not result[1] then error(result[2], 0) end
    return unpack(result, 2)
end

--- Time `module[method]` from now on, under "Module:Method".
function Perf:Wrap(module, method)
    local fn = type(module) == "table" and rawget(module, method)
    if type(fn) ~= "function" then return false end
    local label = ("%s:%s"):format(rawget(module, "moduleName") or "?", method)
    module[method] = function(...) return Perf:Run(label, fn, ...) end
    return true
end

-- The pieces of work big enough to hitch, wrapped once every module is
-- enabled. Event handlers are timed where they are dispatched.
Perf.WATCH = {
    { "Finder", "Scan" }, { "UpgradeQuest", "Update" }, { "UpgradeQuest", "LookForBetter" },
    { "Tracking", "Check" }, { "BagIcons", "Refresh" }, { "BagIcons", "RefreshFrame" },
    { "UpgradeChat", "Scan" }, { "Tooltip", "OnTooltip" }, { "Compare", "BestInBags" },
    { "UI", "Refresh" }, { "FinderUI", "Refresh" }, { "QuestPanel", "Refresh" },
    { "TrackerPanel", "Refresh" }, { "MapPins", "Draw" }, { "SlotUpgrades", "Fill" },
    { "QuestRewards", "Refresh" }, { "LootRolls", "Refresh" },
    { "MoreMarks", "RefreshMerchant" }, { "MoreMarks", "RefreshLoot" },
    { "Crafting", "Known" }, { "Butler", "Advise" }, { "Compare", "IsUpgrade" },
}

function Perf:WrapAll()
    if self.wrapped then return end
    self.wrapped = true
    for _, pair in ipairs(Perf.WATCH) do Perf:Wrap(ns.modules[pair[1]], pair[2]) end
end

--- The rows, slowest first.
function Perf:Slowest()
    local list = {}
    for _, row in pairs(self.rows) do list[#list + 1] = row end
    table.sort(list, function(a, b)
        if a.worst ~= b.worst then return a.worst > b.worst end
        return a.label < b.label
    end)
    return list
end

function Perf:Reset()
    self.rows = {}
end

--- Print the slowest pieces of work to chat.
function Perf:Report(count)
    if not self.Clock() then
        ns.Print("speed check: this client has no timer to measure with.")
        return
    end
    local list = Perf:Slowest()
    if #list == 0 then
        ns.Print("speed check: nothing measured yet. Play for a bit and try again.")
        return
    end
    ns.Print("speed check, slowest first (since login or the last clear):")
    for i = 1, math.min(count or 10, #list) do
        local row = list[i]
        ns.PrintRaw(("  %s  worst %.0f ms, %d runs, %.0f ms in all"):format(
            row.label, row.worst, row.runs, row.total))
    end
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if not list then return end
    if ns.NothingChanged(event) then return end

    -- One handler erroring must not swallow the rest.
    for i = 1, #list do
        local entry = list[i]
        if entry then
            local started = Perf.Clock()
            local ok, err = pcall(entry.fn, entry.owner, event, ...)
            if started then
                local finished = Perf.Clock()
                if finished then
                    -- The label made once per handler, not on every event.
                    local label = entry.label
                    if not label then
                        local owner = type(entry.owner) == "table" and rawget(entry.owner, "moduleName") or "?"
                        label = ("%s on %s"):format(owner, event)
                        entry.label = label
                    end
                    Perf:Add(label, finished - started)
                end
            end
            if not ok then
                geterrorhandler()(err)
            end
        end
    end
end)

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

local initialized = false
local enabled = false

local function RunLifecycle(method)
    for i = 1, #ns.moduleOrder do
        local module = ns.moduleOrder[i]
        local fn = module[method]
        if type(fn) == "function" then
            local ok, err = pcall(fn, module)
            if not ok then
                ns.Warn(L.Format("module %s:%s failed", module.moduleName, method))
                geterrorhandler()(err)
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Saved variables
--------------------------------------------------------------------------------

local DEFAULTS = {
    point = "CENTER",
    relativePoint = "CENTER",
    x = 0,
    y = 40,
    debug = false,

    -- Minimap button: where it sits on the ring, how far off the edge, and
    -- whether it is there at all. A little further round than Farmer's and
    -- Tradeskills' buttons, so the three do not start stacked.
    minimapAngle = math.rad(230),
    minimapGap = 16, -- kept for old saves; the button now sits on the ring
    minimapHidden = false,

    -- The verdict on gear: a line on its tooltip, and an arrow on it in the
    -- bags and on the best quest reward when it is an upgrade. Both on unless
    -- switched off.
    tooltipLine = true,
    -- The button under the quest window that takes the best reward
    -- (UI/QuestRewards.lua, asked 2026-10-11).
    rewardButton = true,
    bagArrows = true,
    -- A gold coin on bag gear better sold than kept (BagIcons:Sells). On
    -- unless unticked.
    bagSellCoins = true,
    -- Hide Forever's controller bag button, which covers the combined
    -- backpack's sort button (BagIcons:ApplyGamepadBag). On unless unticked.
    hideGamepadBag = true,

    -- A line in chat when an upgrade you can wear now lands in the bags.
    upgradeChat = true,
    -- Put an upgrade on by itself when it lands in the bags
    -- (Logic/Wear.lua, asked 2026-10-15). Off unless ticked.
    autoEquip = false,

    -- Class spells to train (Logic/ClassTraining.lua): the gear window's
    -- Training button and drawer, and a line in chat at a level up. On
    -- unless unticked; never rename it. trainingDrawer: the drawer was
    -- left open.
    classTraining = true,
    trainingDrawer = false,

    -- The "Where to get upgrades" window: where it sits, and whether it
    -- shows gear ("all") or enchants ("enchant"); an older "vendor",
    -- "quest", "dungeon" or "craft" reads as gear. Never rename it.
    finderPoint = "CENTER",
    finderRelativePoint = "CENTER",
    finderX = 40,
    finderY = 20,
    finderShow = "all",
    -- "Only what I can get now": leave out gear waiting on a reputation or
    -- on a craft nobody of yours can make yet. Off unless ticked. The
    -- sources unticked are kept in finderSourcesOff ({ [kind] = true },
    -- nil until one is), the slot last clicked in finderSlot. Never rename
    -- them.
    finderGetNow = false,
    -- How many levels ahead the finder looks (0 for now).
    finderAhead = 0,
    -- Only quests a player can do alone, in the finder and the upgrade
    -- quest (Finder:SoloOnly). Off unless ticked.
    soloQuestsOnly = false,
    -- How many levels above the character a quest the finder offers may
    -- be, 0 to 10, or 11 for any (Finder:QuestLevelsAbove).
    questLevelsAbove = 4,
    -- The upgrade quest panel's "This zone only": each tab picks only from
    -- the zone the character is in (UpgradeQuest:ZoneOnly). Off: anywhere.
    upgradeQuestZoneOnly = false,
    -- The upgrade quest panel's "Current step only": the panel shows the
    -- step to do now and hides the rest, so it takes less room
    -- (UpgradeQuest:StepOnly). Off: every step.
    upgradeQuestStepOnly = false,
    -- Where to get upgrades' own "This zone only": list only upgrades from
    -- the zone the character is in (FinderUI:ZoneOnly). Off: anywhere.
    finderZoneOnly = false,
    -- How big the upgrade quest panel is drawn, 1 being its normal size
    -- (0.5 to 1.5): its gold corner grip, Settings or /beq quest size. Its
    -- saved spot keeps the size it was taken at in questScaleAt.
    questScale = 1,
    -- The quest arrow: a dial that points at the upgrade quest's next
    -- place (Logic/QuestArrow.lua). Off unless turned on; where it was
    -- dragged to is questArrowX and questArrowY.
    questArrow = false,
    -- With TomTom installed, its arrow shows the quest arrow's place
    -- (Logic/TomTom.lua).
    useTomTom = true,

    -- Upgrade hunts: the banner when an upgrade or a tracked one lands in
    -- the bags, the tracker panel and where it sits, pins on the world map,
    -- upgrades on the character sheet's slots, and naming random rolls on
    -- tooltips. All on unless switched off. What is tracked is kept per
    -- character (`tracked`, `trackedDone`; Logic/Tracking.lua).
    upgradeToast = true,
    showTracker = true,
    mapPins = true,
    slotUpgrades = true,
    suffixLine = true,
    -- "Upgrade for Ana Smith: +9%" on gear that helps another of your
    -- characters (UI/Tooltip.lua, asked 2026-10-11).
    altTooltipLine = true,

    -- The upgrade quest: the best next upgrade handed out as a quest, with
    -- the steps to get it (Logic/UpgradeQuest.lua). Off unless the player
    -- turns it on. The quests are kept per character, one per tab
    -- (`upgradeQuestTabs`, the tab shown in `upgradeQuestTab`, and a copy
    -- of its quest in `upgradeQuest`, where versions before the tabs kept
    -- it), with `upgradeQuestSkipped` and `upgradeQuestsDone`, as are
    -- the quests seen handed in (`questsTurnedIn`, Logic/Finder.lua), for a
    -- client that cannot say which quests are done.
    upgradeQuest = false,

    -- The upgrade quest panel's Quest log tab (UI/QuestLogTab.lua): list
    -- only tracked quests, and hide the game's own quest tracker while the
    -- panel is up. Both off unless ticked. Per character, the tab being
    -- shown is `questLogTab` and the zones folded on it `questLogFolded`.
    questLogTrackedOnly = false,
    hideQuestTracker = false,

    -- The settings window (UI/SettingsPages.lua): its words under every row
    -- rather than in tooltips, and Tradeskills' Text size. The page it was
    -- left on is settingsPage, which has no default.
    settingsDescriptions = false,
    textSize = "normal",

    -- Window style: "titanforged" (the house look) or "blizzard" (the
    -- game's own frames, buttons and tick boxes, asked 2026-10-10). Read
    -- at login, so a change waits for /reload. See UI/BlizzardLook.lua.
    windowStyle = "titanforged",

    -- The player's own stat weights, by class and spec, are kept under
    -- `customWeights` (Logic/Weights.lua). Not given a default here: the
    -- table is made the first time a weight is changed, and once made it is
    -- never cleared or renamed by an update.
}

-- Per character, because class and spec are. `spec` is the spec the player
-- picked to be judged as; nil means work it out from the character.
local CHAR_DEFAULTS = {
    spec = nil,
}

local function ApplyDefaults(db, defaults)
    for key, value in pairs(defaults) do
        if db[key] == nil then
            db[key] = value
        end
    end
end

local function LoadSavedVariables()
    if type(BlackthornesEquipmentDB) ~= "table" then
        BlackthornesEquipmentDB = {}
    end
    if type(BlackthornesEquipmentCharDB) ~= "table" then
        BlackthornesEquipmentCharDB = {}
    end

    ApplyDefaults(BlackthornesEquipmentDB, DEFAULTS)
    ApplyDefaults(BlackthornesEquipmentCharDB, CHAR_DEFAULTS)

    ns.db = BlackthornesEquipmentDB
    ns.charDB = BlackthornesEquipmentCharDB
end

ns.LoadSavedVariables = LoadSavedVariables

-- Read-only: a settings page can put window positions back from here.
ns.DEFAULTS = DEFAULTS

local bootstrap = ns.NewModule("Bootstrap")

function bootstrap:ADDON_LOADED(_, loadedAddon)
    if loadedAddon ~= ADDON_NAME or initialized then return end
    initialized = true

    LoadSavedVariables()
    -- The window style is read before any module draws, so every colour
    -- drawn is the style's (UI/BlizzardLook.lua).
    if ns.BlizzardLook then ns.BlizzardLook.Style() end
    RunLifecycle("OnInitialize")
end

function bootstrap:PLAYER_LOGIN()
    if enabled then return end
    enabled = true
    RunLifecycle("OnEnable")
    Perf:WrapAll()
end

ns.RegisterEvent(bootstrap, "ADDON_LOADED", bootstrap.ADDON_LOADED)
ns.RegisterEvent(bootstrap, "PLAYER_LOGIN", bootstrap.PLAYER_LOGIN)

--------------------------------------------------------------------------------
-- Slash commands
--------------------------------------------------------------------------------

ns.commands = {}
ns.commandOrder = {}

--- Register a `/beq <name>` subcommand.
function ns.RegisterCommand(name, usage, fn)
    ns.commands[name] = { usage = usage, fn = fn }
    ns.commandOrder[#ns.commandOrder + 1] = name
end

local function ShowHelp()
    ns.Print(("|c%sBlackthornes Equipment|r %s"):format(ns.COLORS.accent, ns.VersionLabel()))

    for i = 1, #ns.commandOrder do
        local name = ns.commandOrder[i]
        local command = ns.commands[name]
        ns.PrintRaw(("  |c%s/beq %s|r  |c%s%s|r"):format(
            ns.COLORS.accent, name, ns.COLORS.muted, command.usage or ""))
    end
end

ns.RegisterCommand("help", L["show this list"], ShowHelp)

--- Typed only and left out of help (the owner, 2026-10-23): checks and debug
--- are for tracking down a problem, not for players. Set straight in
--- ns.commands, so help and Settings never list it.
function ns.RegisterHiddenCommand(name, fn)
    ns.commands[name] = { fn = fn, hidden = true }
end

ns.RegisterHiddenCommand("debug", function(rest)
    if not ns.db then return end
    local word = (rest or ""):lower():match("^%s*(%S*)")
    if word == "on" then
        ns.db.debug = true
    elseif word == "off" then
        ns.db.debug = false
    else
        ns.db.debug = not ns.db.debug
    end
    ns.Print(ns.db.debug and "debug on" or "debug off")
end)
ns.RegisterHiddenCommand("perf", function(rest)
    if (rest or ""):lower():match("^%s*clear") then
        Perf:Reset()
        ns.Print("speed check cleared.")
        return
    end
    -- Kept for Claude too, as the probe is (2026-10-11).
    ns.KeepCheck("perf", Perf.Report, Perf, 15)
end)

SLASH_BLACKTHORNESEQUIPMENT1 = "/beq"
SLASH_BLACKTHORNESEQUIPMENT2 = "/equipment"

-- Named rather than anonymous so the test suite can drive it directly; the
-- slash routing is where a command goes wrong, so it is worth testing.
function ns.HandleSlash(input)
    input = (input or ""):gsub("^%s+", ""):gsub("%s+$", "")

    local keyword, rest = input:match("^(%S+)%s*(.*)$")
    if not keyword then
        if ns.UI and ns.UI.Toggle then
            ns.UI:Toggle()
        else
            ShowHelp()
        end
        return
    end

    local command = ns.commands[keyword:lower()]
    if not command then
        ns.Warn(L.Format("unknown command: %s", keyword))
        ShowHelp()
        return
    end

    -- Wrapped because a command that errors is otherwise completely silent:
    -- this client does not show Lua errors unless scriptErrors is on, so a
    -- broken command and one that did nothing look identical from the chat
    -- frame.
    local ok, err = pcall(command.fn, rest or "")

    -- Most commands flip something the settings page shows; keep it honest
    -- if it happens to be open. Before the error handler, which may raise.
    if ns.SettingsUI then
        pcall(ns.SettingsUI.Refresh, ns.SettingsUI)
    end
    -- /beq spec changes what counts as an upgrade.
    if ns.BagIcons then
        pcall(ns.BagIcons.Refresh, ns.BagIcons)
    end
    if ns.UI then
        pcall(ns.UI.Refresh, ns.UI)
    end
    if ns.WeightsUI then
        pcall(ns.WeightsUI.Refresh, ns.WeightsUI)
    end

    if not ok then
        ns.Warn(L.Format("/beq %s failed: %s", keyword, tostring(err)))
        geterrorhandler()(err)
    end
end

SlashCmdList["BLACKTHORNESEQUIPMENT"] = ns.HandleSlash
