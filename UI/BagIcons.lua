-- Blackthornes Equipment -- UI/BagIcons.lua
-- A green arrow on the corner of any item in the bags that is an upgrade
-- over what is worn, for the spec the character is judged as.
--
-- Only the game's own bags get arrows. How the client draws them is not
-- assumed, since Forever is a retail engine with classic content: both
-- shapes are handled. Retail has ContainerFrameCombinedBags and
-- ContainerFrame1..13 whose buttons list themselves through
-- EnumerateValidItems and know their bag through GetBagID; classic names each
-- button ContainerFrame<n>Item<m> and keeps the bag id on the frame.
-- /beq probe says which frames this client has.
--
-- Gear that is not an upgrade and is better sold gets a gold coin instead
-- (BagIcons:Sells): white gear, and soulbound green or better gear when the
-- character cannot disenchant it. Greys and gathering tools get none.
--
-- The arrow and the coin are textures this addon owns, laid over the item button. Nothing
-- of Blizzard's is changed or written to, so using an item from the bags in
-- combat is not affected.

local _, ns = ...

local BagIcons = ns.NewModule("BagIcons")

local Compare = ns.Compare
local Items = ns.Items

-- The most bag windows the game opens at once, when it does not say.
local MAX_FRAMES = 13
-- The most buttons a classic bag window names.
local MAX_BUTTONS = 36

-- Retail's own upgrade arrow; the fallback is a green arrow every client
-- has, turned to point up.
local ATLAS = "bags-greenarrow"
local FALLBACK_TEXTURE = [[Interface\Buttons\UI-MicroStream-Green]]

local arrows = setmetatable({}, { __mode = "k" })
local coins = setmetatable({}, { __mode = "k" })

-- The quest reward coin's look (UI/QuestRewards.lua).
local COIN_TEXTURE = "Interface\\MoneyFrame\\UI-GoldIcon"
-- Disenchant, the spell Enchanting teaches.
local DISENCHANT = 13262
local ENCHANTING_LINE = 333
-- Kept to wear, not to sell: shirts, tabards and fishing poles.
local KEEP_LOC = { INVTYPE_BODY = true, INVTYPE_TABARD = true }
local CLASS_WEAPON, FISHING_POLE = 2, 20
-- Gathering and profession tools, kept to use: the mining pick, skinning
-- knife, blacksmith hammer, engineering tools, enchanting rods and the
-- skinning weapons. Gear that adds to a gathering skill is found by its
-- tooltip (BagIcons.IsTool).
local TOOLS = {
    [2901] = true, [7005] = true, [5956] = true, [6219] = true, [10498] = true,
    [6218] = true, [6339] = true, [11130] = true, [11145] = true, [16207] = true,
    [15138] = true, [19901] = true,
}
BagIcons.TOOLS = TOOLS
local TOOL_SKILLS = { "Mining", "Skinning", "Herbalism", "Fishing" }
-- The same skills as the client names them, for a client in another
-- language: their skill lines, classic's and Forever's modern ones
-- (Tradeskills' findings; 356 is classic's Fishing), and the spells that
-- carry a skill's own name (Farmer's: 2575 Mining, 8613 Skinning).
local TOOL_LINES = { 186, 2946, 393, 2947, 182, 2944, 356 }
local TOOL_SPELLS = { 2575, 8613 }

local function Field(object, key)
    if type(object) ~= "table" then return nil end
    local ok, value = pcall(function() return object[key] end)
    if ok then return value end
    return nil
end

--- Call object:method(...) if it has it; the first return, or nil.
local function Ask(object, method, ...)
    local fn = Field(object, method)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, object, ...)
    if ok then return value end
    return nil
end

function BagIcons:IsEnabled()
    return not (ns.db and ns.db.bagArrows == false)
end

function BagIcons:CoinsEnabled()
    return not (ns.db and ns.db.bagSellCoins == false)
end

--------------------------------------------------------------------------------
-- Finding the bag buttons
--------------------------------------------------------------------------------

--- The bag windows this client has, open or not.
function BagIcons:Frames()
    local frames = {}
    if type(_G.ContainerFrameCombinedBags) == "table" then
        frames[#frames + 1] = _G.ContainerFrameCombinedBags
    end
    local count = tonumber(_G.NUM_CONTAINER_FRAMES) or MAX_FRAMES
    for i = 1, count do
        local frame = _G["ContainerFrame" .. i]
        if type(frame) == "table" then frames[#frames + 1] = frame end
    end
    return frames
end

--- The item buttons in one bag window.
function BagIcons:Buttons(frame)
    local buttons = {}

    local enumerate = Field(frame, "EnumerateValidItems")
    if type(enumerate) == "function" then
        local ok = pcall(function()
            for _, button in enumerate(frame) do
                buttons[#buttons + 1] = button
            end
        end)
        if ok and #buttons > 0 then return buttons end
        buttons = {}
    end

    local name = Ask(frame, "GetName")
    if type(name) == "string" then
        for i = 1, MAX_BUTTONS do
            local button = _G[name .. "Item" .. i]
            if type(button) ~= "table" then break end
            buttons[#buttons + 1] = button
        end
    end
    return buttons
end

--- Which bag and slot a button shows, or nil.
function BagIcons:Location(button, frame)
    local bag = Ask(button, "GetBagID")
    if type(bag) ~= "number" then
        bag = Ask(Ask(button, "GetParent") or frame, "GetID")
    end
    local slot = Ask(button, "GetID")
    if type(bag) ~= "number" or type(slot) ~= "number" then return nil end
    return bag, slot
end

--------------------------------------------------------------------------------
-- The arrow
--------------------------------------------------------------------------------

local function HasAtlas(name)
    local info = Field(_G.C_Texture, "GetAtlasInfo")
    if type(info) ~= "function" then return false end
    local ok, found = pcall(info, name)
    return ok and found ~= nil
end

--- The arrow already made for a button, or nil; never makes one.
function BagIcons:ExistingArrow(button)
    return arrows[button]
end

--- The arrow for a button, made the first time it is asked for. The quest
--- reward buttons use it too.
function BagIcons:Arrow(button)
    local arrow = arrows[button]
    if arrow then return arrow end

    local create = Field(button, "CreateTexture")
    if type(create) ~= "function" then return nil end

    local ok, texture = pcall(create, button, nil, "OVERLAY", nil, 7)
    if not ok or not texture then return nil end

    texture:SetSize(16, 16)
    texture:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)

    local usedAtlas = HasAtlas(ATLAS) and pcall(texture.SetAtlas, texture, ATLAS)
    if not usedAtlas then
        texture:SetTexture(FALLBACK_TEXTURE)
        -- The stream arrow points down; flipped, it points up.
        texture:SetTexCoord(0, 1, 1, 0)
    end
    texture:Hide()

    arrows[button] = texture
    return texture
end

--- The coin already made for a button, or nil; never makes one.
function BagIcons:ExistingCoin(button)
    return coins[button]
end

--- The gold coin for a button, made the first time it is asked for.
function BagIcons:Coin(button)
    local coin = coins[button]
    if coin then return coin end
    local create = Field(button, "CreateTexture")
    if type(create) ~= "function" then return nil end
    local ok, texture = pcall(create, button, nil, "OVERLAY", nil, 7)
    if not ok or not texture then return nil end
    texture:SetSize(14, 14)
    texture:SetPoint("TOPLEFT", button, "TOPLEFT", 2, -2)
    texture:SetTexture(COIN_TEXTURE)
    texture:Hide()
    coins[button] = texture
    return texture
end

--------------------------------------------------------------------------------
-- What is better sold
--------------------------------------------------------------------------------

local SPELL_CALLS = { "C_SpellBook.IsSpellKnown", "IsPlayerSpell", "IsSpellKnown" }

--- value == want, false when the value is one the client will not let us touch.
local function Is(value, want)
    local ok, yes = pcall(function() return value == want end)
    return ok and yes
end

--- A string, copied, or nil (a secret value raises when touched).
local function Text(value)
    local ok, copy = pcall(function()
        if type(value) == "string" and value ~= "" then return value .. "" end
    end)
    return ok and copy or nil
end

--- A profession's name as the client gives it, or nil.
local function ProfessionName(skillLineID)
    local info = Items.Call({ "C_TradeSkillUI.GetProfessionInfoBySkillLineID" }, skillLineID)
    local ok, name = pcall(function() return type(info) == "table" and info.professionName or nil end)
    return ok and Text(name) or nil
end
BagIcons.ProfessionName = ProfessionName

--- A spell's name as the client gives it, or nil.
local function SpellName(spellID)
    return Text(Items.Call({ "C_Spell.GetSpellName", "GetSpellInfo" }, spellID))
end

--- Does this character have Enchanting? Any way the client says yes counts:
--- the Disenchant spell, the profession list, or classic's skill list.
function BagIcons:ReadEnchanter()
    for _, path in ipairs(SPELL_CALLS) do
        if Is(Items.Call({ path }, DISENCHANT), true) then return true end
    end
    local first, second = Items.Call({ "GetProfessions" })
    for _, index in ipairs({ first, second }) do
        local line = select(7, Items.Call({ "GetProfessionInfo" }, index))
        if Is(line, ENCHANTING_LINE) then return true end
    end
    -- Classic's skill list names it, in the client's own language too.
    local own = ProfessionName(ENCHANTING_LINE)
    local count = tonumber((Items.Call({ "GetNumSkillLines" }))) or 0
    for index = 1, count do
        local name = Items.Call({ "GetSkillLineInfo" }, index)
        if Is(name, "Enchanting") or (own and Is(name, own)) then return true end
    end
    return false
end

--- Can this character disenchant? Kept until a skill or spell event.
function BagIcons:CanDisenchant()
    if self.enchanter == nil then
        local ok, yes = pcall(self.ReadEnchanter, self)
        self.enchanter = ok and yes == true
    end
    return self.enchanter
end

-- Sell prices by link; a link's price never changes.
local sellPrices = {}

local function SellPrice(link)
    local price = sellPrices[link]
    if price == nil then
        price = Items:SellPrice(link) or false
        if price then sellPrices[link] = price end
    end
    return price
end

-- Whether each link is a tool, read once.
local tools = {}

--- The tooltip's lines for a link, as plain strings.
local function TooltipLines(link)
    local data = Items.TooltipData(link)
    local ok, lines = pcall(function()
        local found = {}
        for _, line in ipairs(type(data) == "table" and type(data.lines) == "table" and data.lines or {}) do
            if type(line) == "table" and type(line.leftText) == "string" then
                found[#found + 1] = line.leftText .. ""
            end
        end
        return found
    end)
    return ok and lines or {}
end

-- The gathering skills' names to look for: English, then the client's own,
-- read once. Kept as plain-text patterns ("Kürschnerei" has no magic
-- characters, but a name could).
local toolSkillPatterns

local function ToolSkillPatterns()
    if toolSkillPatterns then return toolSkillPatterns end
    local names, seen, read = {}, {}, 0
    local function Add(name, own)
        if name and own then read = read + 1 end
        if name and not seen[name] then
            seen[name] = true
            names[#names + 1] = name:gsub("[%%%^%$%(%)%.%[%]%*%+%-%?]", "%%%0") .. " %+%d"
        end
    end
    for _, skill in ipairs(TOOL_SKILLS) do Add(skill) end
    for _, line in ipairs(TOOL_LINES) do Add(ProfessionName(line), true) end
    for _, spellID in ipairs(TOOL_SPELLS) do Add(SpellName(spellID), true) end
    -- Kept once the client named any; until then (names not loaded yet at
    -- login, or a client without the calls) asked again next time.
    if read > 0 then toolSkillPatterns = names end
    return names
end

--- Is an item a gathering or profession tool? The known tools by ID, and
--- gear whose tooltip adds to a gathering skill ("Skinning +10", or the
--- client's own name for it).
function BagIcons.IsTool(link)
    local known = tools[link]
    if known ~= nil then return known end
    local id = tonumber(link:match("item:(%d+)"))
    local yes = id ~= nil and TOOLS[id] == true
    if not yes then
        local patterns = ToolSkillPatterns()
        for _, text in ipairs(TooltipLines(link)) do
            for _, pattern in ipairs(patterns) do
                if text:find(pattern) then yes = true end
            end
        end
    end
    tools[link] = yes
    return yes
end

--- Should the item in a bag slot get the sell coin? `result` is how it was
--- judged (Compare:JudgeCarried). Only gear judged and found no upgrade,
--- now or later, that a vendor pays for: white, or soulbound green and up
--- when the character cannot disenchant it.
function BagIcons:Sells(bag, slot, link, result)
    if not self:CoinsEnabled() then return false end
    if type(result) ~= "table" or result.verdict == "upgrade" then return false end
    -- On a character skipped for upgrades, gear one of the others would
    -- wear is kept for them, not sold (a crafting alt making gear for a main).
    if result.skipped and ns.Alts then
        local ok, alt = pcall(ns.Alts.BestFor, ns.Alts, link)
        if not ok or alt then return false end
    end

    local info = Items:Info(link)
    if not info or KEEP_LOC[info.equipLoc] then return false end
    if info.classID == CLASS_WEAPON and info.subclassID == FISHING_POLE then return false end
    if BagIcons.IsTool(link) then return false end

    local quality = Items:SlotQuality(bag, slot, link)
    if type(quality) ~= "number" or quality < 1 then return false end
    if quality >= 2 and not (Items:SlotBound(bag, slot) and not self:CanDisenchant()) then
        return false
    end

    local price = SellPrice(link)
    return type(price) == "number" and price > 0
end

--- Show or hide the arrow and the coin on one button.
function BagIcons:UpdateButton(button, frame)
    local show, sell = false, false
    if self:IsEnabled() or self:CoinsEnabled() then
        local bag, slot = self:Location(button, frame)
        local link = bag and Items:InBag(bag, slot)
        if link then
            local ok, result = pcall(Compare.JudgeCarried, Compare, link)
            if not ok then result = nil end
            show = self:IsEnabled() and Compare.WearableUpgrade(result)
            if not show then sell = self:Sells(bag, slot, link, result) end
        end
    end

    if show then
        local arrow = self:Arrow(button)
        if arrow then arrow:Show() end
    elseif arrows[button] then
        arrows[button]:Hide()
    end
    if sell then
        local coin = self:Coin(button)
        if coin then coin:Show() end
    elseif coins[button] then
        coins[button]:Hide()
    end
    return show
end

--- Look again at every open bag window.
function BagIcons:Refresh()
    local shown = 0
    for _, frame in ipairs(self:Frames()) do
        if Ask(frame, "IsShown") then
            shown = shown + self:RefreshFrame(frame)
        end
    end
    self.lastShown = shown
    return shown
end

function BagIcons:RefreshFrame(frame)
    local shown = 0
    for _, button in ipairs(self:Buttons(frame)) do
        local ok, on = pcall(self.UpdateButton, self, button, frame)
        if ok and on then shown = shown + 1 end
    end
    return shown
end

--- Refresh once things settle, so a burst of bag events costs one pass.
function BagIcons:RefreshSoon()
    if self.pending then return end
    self.pending = true

    local after = Field(_G.C_Timer, "After")
    if type(after) ~= "function" then
        self.pending = false
        self:Refresh()
        return
    end

    after(0.2, function()
        BagIcons.pending = false
        BagIcons:Refresh()
    end)
end

--------------------------------------------------------------------------------
-- Being told the bags changed
--------------------------------------------------------------------------------

function BagIcons:InstallHooks()
    local hook = _G.hooksecurefunc
    local hooked = {}
    if type(hook) ~= "function" then return hooked end

    -- Classic redraws every bag window through this one function.
    if type(_G.ContainerFrame_Update) == "function" then
        if pcall(hook, "ContainerFrame_Update", function(frame)
            pcall(BagIcons.RefreshFrame, BagIcons, frame)
        end) then
            hooked[#hooked + 1] = "ContainerFrame_Update"
        end
    end

    -- Retail redraws each window through its own UpdateItems, and opening
    -- one shows it; both are hooked per window.
    local updateItems = false
    for _, frame in ipairs(self:Frames()) do
        if type(Field(frame, "UpdateItems")) == "function" then
            if pcall(hook, frame, "UpdateItems", function(shown)
                pcall(BagIcons.RefreshFrame, BagIcons, shown)
            end) then
                updateItems = true
            end
        end
        local hookScript = Field(frame, "HookScript")
        if type(hookScript) == "function" then
            pcall(hookScript, frame, "OnShow", function(shown)
                pcall(BagIcons.RefreshFrame, BagIcons, shown)
                pcall(BagIcons.ApplyGamepadBag, BagIcons)
            end)
        end
    end
    if updateItems then hooked[#hooked + 1] = "UpdateItems" end
    return hooked
end

--- What the probe prints about the bags: which windows there are, how their
--- buttons are found, and what got hooked.
function BagIcons:Describe()
    local names = {}
    for _, frame in ipairs(self:Frames()) do
        local name = Ask(frame, "GetName") or "?"
        local how = type(Field(frame, "EnumerateValidItems")) == "function" and "list" or "named"
        names[#names + 1] = ("%s (%s)"):format(name, how)
    end
    local frames = #names > 0 and table.concat(names, ", ") or "none found"
    local hooks = self.hooked and #self.hooked > 0 and table.concat(self.hooked, ", ") or "none"
    return frames, hooks
end

--------------------------------------------------------------------------------
-- Forever's controller bag button
--------------------------------------------------------------------------------

-- Forever's client puts a controller bag button (GamepadBackpackButton, on
-- its GamepadBagBar) right over the combined backpack's sort button. While
-- hideGamepadBag is on it is out of sight and lets clicks through to the sort
-- button; unticking the setting puts it back as it was. It is never hidden
-- with Hide, which would run the game's own code for the bag bar as this
-- addon and leave Edit Mode's layout tainted (UI/Veil.lua says more). A
-- protected button that has to wait for combat is done once combat ends.
local GAMEPAD_BUTTON = "GamepadBackpackButton"

function BagIcons:HidesGamepadBag()
    return not (ns.db and ns.db.hideGamepadBag == false)
end

--- Is the controller bag button out of sight through this addon?
function BagIcons:GamepadHidden()
    local button = _G[GAMEPAD_BUTTON]
    return type(button) == "table" and ns.Veil:Covers(button)
end

--- Put the controller bag button out of sight or back, as the setting says.
--- True when it is out of sight.
function BagIcons:ApplyGamepadBag()
    local button = _G[GAMEPAD_BUTTON]
    if type(button) ~= "table" then return false end

    local hide = self:HidesGamepadBag()
    local done
    if hide then done = ns.Veil:Cover(button) else done = ns.Veil:Uncover(button) end
    if not done and not self.gamepadWaiting then
        self.gamepadWaiting = ns.RegisterEvent(self, "PLAYER_REGEN_ENABLED", function()
            ns.UnregisterEvent(BagIcons, "PLAYER_REGEN_ENABLED")
            BagIcons.gamepadWaiting = false
            BagIcons:ApplyGamepadBag()
        end)
    end
    return hide and ns.Veil:Covers(button)
end

-- Anything that can change what is an upgrade: the bags, what is worn, the
-- level, the talents, weapon skills (Dual Wield) and an item's details
-- arriving from the server.
local EVENTS = {
    "BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED", "PLAYER_LEVEL_UP",
    "GET_ITEM_INFO_RECEIVED", "TRAIT_CONFIG_UPDATED", "SKILL_LINES_CHANGED",
}

function BagIcons:OnEnable()
    self.hooked = self:InstallHooks()
    pcall(self.ApplyGamepadBag, self)
    ns.RegisterEvent(self, "PLAYER_ENTERING_WORLD", function()
        pcall(BagIcons.ApplyGamepadBag, BagIcons)
    end)
    for _, event in ipairs(EVENTS) do
        ns.RegisterEvent(self, event, self.RefreshSoon)
    end
    -- Learning or dropping Enchanting changes which greens get a coin.
    for _, event in ipairs({ "SKILL_LINES_CHANGED", "LEARNED_SPELL_IN_TAB", "SPELLS_CHANGED" }) do
        ns.RegisterEvent(self, event, self.ForgetEnchanter)
    end
end

--- Forget whether the character can disenchant, and look again at the bags
--- only when the answer changed.
function BagIcons:ForgetEnchanter()
    local before = self.enchanter
    self.enchanter = nil
    if before ~= nil and self:CanDisenchant() ~= before then self:RefreshSoon() end
end
