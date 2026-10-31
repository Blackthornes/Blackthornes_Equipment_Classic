-- Shared test environment: enough of the WoW client to load the addon.
--
-- Not a test itself -- runtests.py only runs tools/test_*.lua -- this is what
-- each suite calls to get a loaded addon and a chat frame that remembers what
-- was printed to it.
--
--   local env = dofile(lfs_cwd .. "/tools/testenv.lua")
--   local ns = env.Load()

local env = {}

local ROOT = lfs_cwd or "."
local ADDON = "Blackthornes_Equipment"

--------------------------------------------------------------------------------
-- Widgets
--------------------------------------------------------------------------------

-- Any method a test does not care about answers as a no-op, so a window can
-- build its panels, labels and anchors undisturbed.
local function Stub(fields)
    local frame = fields or {}

    frame._shown = frame._shown or false
    frame._height = frame._height or 300
    frame._text = frame._text or ""

    function frame:Show() self._shown = true end
    function frame:Hide() self._shown = false end
    function frame:IsShown() return self._shown end
    function frame:SetShown(value) self._shown = value and true or false end

    function frame:SetHeight(value) self._height = value end
    function frame:GetHeight() return self._height end
    function frame:SetWidth(value) self._width = value end
    function frame:GetWidth() return self._width or 500 end

    function frame:SetText(value) self._text = tostring(value or "") end
    function frame:SetTextColor(r, g, b) self._color = { r, g, b } end
    function frame:GetText() return self._text end
    -- About as wide as the game's small font: 6 pixels a character.
    function frame:GetStringWidth() return #(self._text or "") * 6 end

    function frame:SetScript(script, fn) self._scripts[script] = fn end
    function frame:GetScript(script) return self._scripts[script] end
    -- Runs after whatever script was there, as the game's HookScript does.
    function frame:HookScript(script, fn)
        local before = self._scripts[script]
        self._scripts[script] = function(...)
            if before then before(...) end
            return fn(...)
        end
    end

    function frame:GetPoint()
        local p = rawget(self, "_point")
        if p and #p == 5 then return p[1], p[2], p[3], p[4], p[5] end
        return "CENTER", nil, "CENTER", 0, 40
    end
    -- Nil until a test places the frame on screen, as before layout.
    function frame:GetLeft() return self._left end
    function frame:GetTop() return self._top end
    function frame:GetFrameLevel() return rawget(self, "_frameLevel") or 1 end
    function frame:SetFrameLevel(value) self._frameLevel = value end

    -- Recorded so a test can check where something was anchored.
    function frame:SetPoint(...) self._point = { ... } end
    function frame:SetParent(parent) self._parent = parent end
    function frame:GetParent() return rawget(self, "_parent") end
    function frame:GetCenter() return self._cx or 0, self._cy or 0 end
    function frame:GetEffectiveScale() return 1 end

    function frame:RegisterEvent(event) self._events[event] = true end
    function frame:UnregisterEvent(event) self._events[event] = nil end

    function frame:CreateTexture() return Stub() end
    function frame:CreateFontString() return Stub() end

    function frame:SetMinMaxValues(low, high) self._min, self._max = low, high end
    function frame:SetValue(value) self._value = value end
    function frame:GetValue() return self._value or 0 end

    frame._scripts = frame._scripts or {}
    frame._events = frame._events or {}

    return setmetatable(frame, { __index = function(self, key)
        local noop = function() end
        rawset(self, key, noop)
        return noop
    end })
end

env.Stub = Stub

--------------------------------------------------------------------------------
-- Client
--------------------------------------------------------------------------------

function env.InstallClient()
    env.chat = {}

    _G.UIParent = Stub()
    -- The arrows' shared table (one Blackthornes arrow at a time) would
    -- carry one suite's arrow into the next.
    _G.BlackthornesArrows = nil

    -- A default-sized minimap, and a cursor parked somewhere unambiguous so a
    -- simulated drag lands at a known angle.
    _G.Minimap = Stub({ _width = 140, _cx = 500, _cy = 500 })
    _G.GetCursorPosition = function() return 600, 500 end

    local function Tooltip()
        return Stub({
            _lines = {},
            SetOwner = function(self) self._lines = {} end,
            AddLine = function(self, text) self._lines[#self._lines + 1] = text end,
            NumLines = function(self) return #self._lines end,
            ClearLines = function(self) self._lines = {} end,
        })
    end
    _G.GameTooltip = Tooltip()
    _G.ItemRefTooltip = Tooltip()

    -- Timers run straight away: a test has nothing to wait for.
    _G.C_Timer = {
        After = function(_, fn) fn() end,
        NewTicker = function(_, fn) return Stub({ _fn = fn }) end,
    }

    -- Theme asks for the default font through pcall and falls back on its
    -- own, so leaving GameFontNormal absent exercises that path.
    _G.GameFontNormal = nil
    _G.Settings = nil
    _G.InterfaceOptions_AddCategory = nil

    _G.CreateFrame = function(_, name, parent)
        local frame = Stub({ _parent = parent })
        if name then _G[name] = frame end
        return frame
    end

    _G.DEFAULT_CHAT_FRAME = {
        AddMessage = function(_, message) env.chat[#env.chat + 1] = message end,
    }

    _G.SlashCmdList = {}
    _G.UISpecialFrames = {}
    _G.geterrorhandler = function() return function(err) error(err, 0) end end

    -- Suites share one Lua state; what one suite saved must not leak into the
    -- next.
    _G.BlackthornesEquipmentDB = nil
    _G.BlackthornesSisterNote = nil
    _G.BlackthornesEquipmentCharDB = nil
    _G.UnitClass = nil
    _G.UnitFactionGroup = nil
    _G.UnitRace = nil
    _G.C_Reputation = nil
    _G.GetFactionInfoByID = nil
    _G.GetRealZoneText = nil
    _G.GetLocale = nil
    _G.GetInstanceInfo = nil
    _G.C_QuestLog = nil
    _G.QuestFrame = nil
    _G.IsQuestFlaggedCompleted = nil
    _G.C_SpellBook = nil
    _G.IsPlayerSpell = nil
    _G.IsSpellKnown = nil
    _G.GetNumSkillLines = nil
    _G.GetSkillLineInfo = nil
    _G.GetNumTalentTabs = nil
    _G.GetTalentTabInfo = nil
    _G.GetInventoryItemLink = nil
    _G.GetItemStats = nil
    _G.C_Item = nil
    _G.UnitLevel = nil
    _G.C_ClassTalents = nil
    _G.C_Traits = nil
    _G.C_Spell = nil
    _G.GetSpellInfo = nil
    _G.C_SpecializationInfo = nil
    _G.C_CreatureInfo = nil
    _G.C_Container = nil
    _G.GetContainerItemLink = nil
    _G.GetItemInfo = nil
    _G.GetItemInfoInstant = nil
    _G.TooltipDataProcessor = nil
    _G.TooltipUtil = nil
    _G.C_TooltipInfo = nil
    _G.Enum = nil
    _G.C_Texture = nil
    _G.hooksecurefunc = nil
    _G.ContainerFrame_Update = nil
    _G.ContainerFrameCombinedBags = nil
    _G.NUM_CONTAINER_FRAMES = nil
    for i = 1, 13 do _G["ContainerFrame" .. i] = nil end
    _G.C_TradeSkillUI = nil
    _G.BlackthornesTS = nil
    _G.C_Map = nil
    _G.UiMapPoint = nil
    _G.C_SuperTrack = nil
    _G.OpenWorldMap = nil
    _G.WorldMapFrame = nil
    _G.GetMerchantItemLink = nil
    _G.GetMerchantNumItems = nil
    _G.GetMerchantItemInfo = nil
    _G.GetMerchantItemID = nil
    _G.GetMoney = nil
    _G.C_MerchantFrame = nil
    _G.MerchantFrame = nil
    _G.MerchantFrame_UpdateMerchantInfo = nil
    _G.MerchantFrame_Update = nil
    _G.GetLootSlotLink = nil
    _G.LootFrame_Update = nil
    for i = 1, 12 do _G["MerchantItem" .. i .. "ItemButton"] = nil end
    for i = 1, 4 do _G["LootButton" .. i] = nil end
    for _, slot in ipairs({ "Head", "Neck", "Shoulder", "Back", "Chest", "Shirt", "Tabard", "Wrist", "Hands",
        "Waist", "Legs", "Feet", "Finger0", "Finger1", "Trinket0", "Trinket1", "MainHand", "SecondaryHand",
        "Ranged" }) do
        _G["Character" .. slot .. "Slot"] = nil
    end
end

--------------------------------------------------------------------------------
-- Items
--------------------------------------------------------------------------------

--- A pretend item cache, worn gear and bags, answered through the C_Item and
--- C_Container calls Forever has.
--
--   items    [link] = { loc, class, subclass, minLevel, stats }
--   worn     [inventory slot] = link
--   bags     [bag] = { [slot] = link }
--   level    the player's level
function env.InstallItems(items, worn, bags, level)
    env.items, env.worn, env.bags = items, worn or {}, bags or {}

    _G.UnitLevel = function() return level or 20 end
    _G.GetInventoryItemLink = function(_, slot) return env.worn[slot] end

    local function Known(link)
        return env.items[link]
    end

    _G.C_Item = {
        GetItemInfoInstant = function(link)
            local item = Known(link)
            if not item then return nil end
            return 1, "Armor", "Leather", item.loc, "icon", item.class, item.subclass
        end,
        GetItemInfo = function(link)
            local item = Known(link)
            if not item then return nil end
            return "Item", link, 2, 10, item.minLevel or 1, "Armor", "Leather", 1,
                item.loc, "icon", 100, item.class, item.subclass
        end,
        GetItemStats = function(link)
            local item = Known(link)
            return item and item.stats or nil
        end,
    }

    _G.C_Container = {
        GetContainerItemLink = function(bag, slot)
            return env.bags[bag] and env.bags[bag][slot] or nil
        end,
        GetContainerNumSlots = function(bag)
            if not env.bags[bag] then return 0 end
            local most = 0
            for slot in pairs(env.bags[bag]) do most = math.max(most, slot) end
            return most
        end,
    }
end

--- A hooksecurefunc that runs the hook after the original, as the game's does.
function env.InstallHooks()
    _G.hooksecurefunc = function(a, b, c)
        local owner, name, hook = _G, a, b
        if type(a) == "table" then owner, name, hook = a, b, c end
        local original = owner[name]
        owner[name] = function(...)
            local result = { original(...) }
            hook(...)
            return unpack(result)
        end
    end
end

--------------------------------------------------------------------------------
-- Loading
--------------------------------------------------------------------------------

--- The Lua files the TOC loads, in order. Read from the TOC itself, so a new
-- file is tested the moment it is listed and there is no second list here to
-- forget.
function env.TocFiles()
    local files = {}
    local handle = assert(io.open(ROOT .. "/" .. ADDON .. ".toc", "r"))
    for line in handle:lines() do
        line = line:gsub("\r$", "")
        if line ~= "" and not line:find("^#") and line:find("%.lua$") then
            files[#files + 1] = (line:gsub("\\", "/"))
        end
    end
    handle:close()
    return files
end

--- Load the addon exactly as the TOC does, and return its namespace.
--- `locale` ("deDE") loads it as a client in that language would.
function env.Load(locale)
    env.InstallClient()
    if locale then _G.GetLocale = function() return locale end end

    local ns = {}
    for _, file in ipairs(env.TocFiles()) do
        local chunk = assert(loadfile(ROOT .. "/" .. file))
        chunk(ADDON, ns)
    end

    -- ADDON_LOADED installs saved variables; tests that skip the event loop
    -- still need ns.db to exist.
    ns.LoadSavedVariables()
    -- "One Window:" is on unless unticked; suites test Equipment's own windows
    -- unless they tick it (test_onewindow.lua checks the default).
    if ns.db then ns.db.oneWindow = false end

    env.ns = ns
    return ns
end

--- Everything printed to chat since the addon loaded, as one string.
function env.ChatText()
    return table.concat(env.chat, "\n")
end

--------------------------------------------------------------------------------
-- Assertions
--------------------------------------------------------------------------------

function env.NewSuite(name)
    local suite = { name = name, checks = 0 }

    function suite.check(label, ok, detail)
        suite.checks = suite.checks + 1
        if not ok then
            error(("%s: %s%s"):format(name, label,
                detail and ("  -> " .. tostring(detail)) or ""), 0)
        end
    end

    function suite.done()
        print(("  %s: %d checks passed"):format(name, suite.checks))
    end

    return suite
end

return env
