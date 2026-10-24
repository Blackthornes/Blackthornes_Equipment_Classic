-- Blackthornes Equipment -- Logic/Alts.lua
-- The player's other characters, so gear carried by one can be judged for
-- the rest (the owner asked 2026-10-11: "if an item you find is an upgrade
-- for another of your characters, butler should offer it as a mail").
--
-- Each character, when it plays, keeps a note of itself account wide in
-- BlackthornesEquipmentDB.characterGear[guid] (never rename it):
--
--   { class, level, spec, realm, faction, worn = { [slot] = link }, at,
--     name, spare = { link, ... }, bank = { { link, bound }, ... }, bankAt }
--
-- Only what judging needs. Added 2026-10-11 (the owner: the addons should
-- do the work): `name` (UnitName, for the tooltip's "Upgrade for Ana
-- Smith"; Tradeskills' record, by the same GUID, is asked first for the
-- whole name), `spare` (gear in its bags that is not soulbound, so it can be
-- mailed to whoever it helps; read as the character settles in and as it
-- logs out) and `bank` (gear in its bank, read while the bank is open). A
-- character counts once it has been played with this version.
--
-- Alts:BestFor(link) judges one item for every other character on the
-- same realm and side, with that character's class, spec, level and worn
-- gear, through the same scoring as the character playing
-- (Compare:ScoreOf), and answers the one it helps most.
--
-- Smooth play: the note is written once, 1 second after a burst of gear,
-- level or talent events, and is a handful of reads. Judging only reads
-- the notes and the per-link scores Compare keeps.

local _, ns = ...

local Alts = ns.NewModule("Alts")
local L = ns.L

local Items = ns.Items
local Weights = ns.Weights
local Compare = ns.Compare

Alts.SETTLE = 1
-- At most this many pieces kept in `spare` and `bank` a character.
Alts.SPARE_MOST = 80
Alts.BAGS = { 0, 1, 2, 3, 4 }

-- Every slot a judged item can go in.
local WORN_SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18 }

-- Closer than this, in percent, is no upgrade (as Compare's SAME_WITHIN).
local SAME_WITHIN = 1

local function Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local results = { pcall(fn, ...) }
    if not results[1] then return nil end
    return select(2, unpack(results))
end

--- A plain string from the client, or nil (a secret value reads as nil).
local function Text(value)
    local ok, copy = pcall(function()
        if type(value) == "string" and value ~= "" then return value .. "" end
    end)
    return ok and copy or nil
end

function Alts.PlayerGUID()
    return Text(Call(_G.UnitGUID, "player"))
end

function Alts.Realm()
    return Text(Call(_G.GetRealmName))
end

function Alts.Faction()
    return Text((Call(_G.UnitFactionGroup, "player")))
end

--- Every character's note, account wide.
function Alts:Notes()
    local db = ns.db
    if type(db) ~= "table" then return {} end
    if type(db.characterGear) ~= "table" then db.characterGear = {} end
    return db.characterGear
end

--------------------------------------------------------------------------------
-- Characters skipped for upgrades
--
-- A player asked, the owner agreed (2026-10-14): crafting alts should never
-- be told gear is an upgrade. A skipped character gets no upgrade verdict
-- of its own (Compare:Judge says "skipped" where it would say "upgrade"),
-- and no other character names it as the one an item helps (BestFor).
-- Kept account wide by GUID in BlackthornesEquipmentDB.skipUpgrades[guid] =
-- true (never rename it), so Settings can tick any character. The character
-- playing also keeps BlackthornesEquipmentCharDB.skipUpgrades, so it still
-- knows inside a dungeon, where the client can keep its GUID back.
--------------------------------------------------------------------------------

function Alts:Skipped()
    local db = ns.db
    if type(db) ~= "table" then return {} end
    if type(db.skipUpgrades) ~= "table" then db.skipUpgrades = {} end
    return db.skipUpgrades
end

function Alts:IsSkipped(key)
    return key ~= nil and self:Skipped()[key] == true
end

--- Is the character playing skipped? Read for every judged item, so it is
--- a GUID read and a lookup.
function Alts:PlayerSkipped()
    local guid = self.PlayerGUID()
    if guid then return self:IsSkipped(guid) end
    return type(ns.charDB) == "table" and ns.charDB.skipUpgrades == true
end

--- Skip a character (by GUID) or bring it back, then judge everything again.
function Alts:SetSkipped(key, on)
    if type(key) ~= "string" then return false end
    self:Skipped()[key] = on and true or nil
    if key == self.PlayerGUID() and type(ns.charDB) == "table" then
        ns.charDB.skipUpgrades = on and true or nil
    end
    self.version = (self.version or 0) + 1
    -- Every kept verdict (bag arrows, the finder, Tradeskills' arrows) was
    -- judged with the old answer; this is what a weights change does too.
    if Weights.Changed then pcall(Weights.Changed, Weights) end
    if ns.SettingsUI and ns.SettingsUI.Refresh then pcall(ns.SettingsUI.Refresh, ns.SettingsUI) end
    return true
end

--- Every character with a note, the one playing first, then by name:
--- { key, name } with the whole name (or nil when none is known).
function Alts:Characters()
    local me = self.PlayerGUID()
    local list = {}
    for key, note in pairs(self:Notes()) do
        if type(key) == "string" and type(note) == "table" then
            list[#list + 1] = { key = key, name = self:NameOf(key), me = key == me }
        end
    end
    table.sort(list, function(a, b)
        if a.me ~= b.me then return a.me end
        local an, bn = (a.name or "~"):lower(), (b.name or "~"):lower()
        if an ~= bn then return an < bn end
        return a.key < b.key
    end)
    return list
end

--- The whole names of the skipped characters, sorted.
function Alts:SkippedNames()
    local names = {}
    for _, entry in ipairs(self:Characters()) do
        if self:IsSkipped(entry.key) then
            names[#names + 1] = entry.name or L["A character not seen yet"]
        end
    end
    return names
end

--- Write the character playing's note now.
function Alts:Record()
    self.settling = false
    local guid = self.PlayerGUID()
    -- The per-character copy follows the account's answer while the GUID
    -- can be read, for the times it can't.
    if guid and type(ns.charDB) == "table" then
        ns.charDB.skipUpgrades = self:IsSkipped(guid) or nil
    end
    local class = Weights:PlayerClass()
    local level = Items:PlayerLevel()
    if not (guid and class and level) then return false end

    local worn = {}
    for _, slot in ipairs(WORN_SLOTS) do
        worn[slot] = Items:Equipped(slot)
    end
    local spec = Weights:CurrentSpec()
    local old = self:Notes()[guid]
    local spare = self.GearIn(self.BAGS, true)
    -- A read that finds nothing worn is the client not saying (on a
    -- /reload or logout it can answer nil for every slot), not a character
    -- that took everything off: keep the gear the last note read, or every
    -- piece would look like an upgrade for an empty slot (2026-10-11).
    if not next(worn) and type(old) == "table" then
        if type(old.worn) == "table" then worn = old.worn end
        if not next(spare) and type(old.spare) == "table" then spare = old.spare end
    end
    local note = {
        class = class,
        level = level,
        spec = spec,
        realm = self.Realm(),
        faction = self.Faction(),
        worn = worn,
        at = Call(_G.time),
        name = Text(Call(_G.UnitName, "player")),
        spare = spare,
        -- The bank is only read while it is open; kept from the last time.
        bank = type(old) == "table" and old.bank or nil,
        bankAt = type(old) == "table" and old.bankAt or nil,
    }
    self:Notes()[guid] = note
    self.version = (self.version or 0) + 1
    return true
end

--- Gear in these bags, as links (one each), at most SPARE_MOST. With
--- `unboundOnly`, soulbound pieces are left out; otherwise each entry is
--- { link, bound }.
function Alts.GearIn(bags, unboundOnly)
    local list, seen = {}, {}
    for _, bag in ipairs(bags) do
        for slot = 1, Items:BagSize(bag) do
            local link = Items:InBag(bag, slot)
            if link and not seen[link] then
                local info = Items:Info(link)
                if info and Compare.SLOTS[info.equipLoc] then
                    seen[link] = true
                    local bound = Items:SlotBound(bag, slot)
                    if unboundOnly then
                        if not bound then list[#list + 1] = link end
                    else
                        list[#list + 1] = { link = link, bound = bound }
                    end
                    if #list >= Alts.SPARE_MOST then return list end
                end
            end
        end
    end
    return list
end

--- The bank's containers: the bank itself and its bag slots.
function Alts.BankBags()
    local index = rawget(_G, "Enum") and _G.Enum.BagIndex
    local bags = { type(index) == "table" and index.Bank or -1 }
    local first = type(index) == "table" and index.BankBag_1 or ((tonumber(rawget(_G, "NUM_BAG_SLOTS")) or 4) + 1)
    local count = tonumber(rawget(_G, "NUM_BANKBAGSLOTS")) or 7
    for bag = first, first + count - 1 do bags[#bags + 1] = bag end
    return bags
end

--- The bank is open: keep the gear in it on the character's note.
function Alts:ReadBank()
    local guid = self.PlayerGUID()
    local note = guid and self:Notes()[guid]
    if type(note) ~= "table" then return false end
    note.bank = self.GearIn(self.BankBags(), false)
    note.bankAt = Call(_G.time)
    self.version = (self.version or 0) + 1
    return true
end

--- A character's whole name: Tradeskills' record (first and last) when it
--- has one, else the name the note kept. Nil when neither knows.
function Alts:NameOf(key)
    local ts = rawget(_G, "BlackthornesTS")
    local recipes = type(ts) == "table" and rawget(ts, "Recipes")
    local db = type(ts) == "table" and rawget(ts, "db")
    if type(recipes) == "table" and type(db) == "table" and type(db.characters) == "table"
        and db.characters[key] and type(recipes.GetCharacterName) == "function" then
        local ok, name = pcall(recipes.GetCharacterName, recipes, key)
        if ok and type(name) == "string" and name ~= "" and name ~= "?" then return name end
    end
    local note = self:Notes()[key]
    return type(note) == "table" and note.name or nil
end

--- Better gear the character playing already owns but does not carry:
--- in its own bank, or not soulbound in another character's bags or bank
--- on this realm and side. { [slot] = { link, result, gain, where } }, the
--- best for each slot; `where` is "bank" or the other character's GUID.
--- For the gear window, worked out only while it draws.
function Alts:BetterElsewhere()
    local best = {}
    local function Consider(link, where)
        local ok, result = pcall(Compare.JudgeCarried, Compare, link)
        if ok and Compare.WearableUpgrade(result) and result.slot then
            local gain = (result.score or 0) - (result.against or 0)
            local held = best[result.slot]
            if not held or gain > held.gain then
                best[result.slot] = { link = link, result = result, gain = gain, where = where }
            end
        end
    end

    -- Without the character playing's GUID (a dungeon can keep it back),
    -- its own note can't be told from another's: nothing is offered.
    local me = self.PlayerGUID()
    if not me then return best end
    local realm, faction = self.Realm(), self.Faction()
    for key, note in pairs(self:Notes()) do
        if type(note) == "table" then
            if key == me then
                for _, entry in ipairs(type(note.bank) == "table" and note.bank or {}) do
                    if type(entry) == "table" and entry.link then Consider(entry.link, "bank") end
                end
            elseif (not realm or not note.realm or note.realm == realm)
                and (not faction or not note.faction or note.faction == faction) then
                for _, link in ipairs(type(note.spare) == "table" and note.spare or {}) do
                    Consider(link, key)
                end
                for _, entry in ipairs(type(note.bank) == "table" and note.bank or {}) do
                    if type(entry) == "table" and entry.link and not entry.bound then Consider(entry.link, key) end
                end
            end
        end
    end
    return best
end

--- Gear, a level or talents changed: write the note once the burst is over.
function Alts:Changed()
    if self.settling then return end
    self.settling = true
    C_Timer.After(self.SETTLE, function() Alts:Record() end)
end

--- The weaker score of what a character wears where this item would go,
--- by the note's worn gear (Compare:Against for the character playing).
-- @return against, empty, equipped
local function Against(note, link, info, weights)
    local slots = Compare.SLOTS[info.equipLoc]
    local worn = note.worn or {}

    local function Score(slot)
        local item = worn[slot]
        if not item then return 0, true end
        return Compare:ScoreOf(item, weights) or 0, false
    end
    local function Kind(slot)
        local item = worn[slot]
        local kind = item and Items:Info(item)
        return kind and kind.equipLoc
    end

    if info.equipLoc == "INVTYPE_WEAPON" then
        local from = Weights:DualWieldLevel(note.class)
        if from and (note.level or 0) >= from then
            local off, main = Kind(17), Kind(16)
            local offIsWeapon = off == "INVTYPE_WEAPON" or off == "INVTYPE_WEAPONOFFHAND"
            if offIsWeapon or (not worn[17] and worn[16] and main ~= "INVTYPE_2HWEAPON") then
                slots = { 16, 17 }
            end
        end
    end

    local weakest, empty = nil, true
    for _, slot in ipairs(slots) do
        if worn[slot] == link then return 0, false, true end
        local score, none = Score(slot)
        if not none then empty = false end
        if not weakest or score < weakest then weakest = score end
    end
    if info.equipLoc == "INVTYPE_2HWEAPON" and worn[17] then
        empty = false
        weakest = weakest + (Score(17))
    end
    if slots[1] == 17 and Kind(16) == "INVTYPE_2HWEAPON" then
        empty = false
        weakest = (Score(16))
    end
    return weakest or 0, empty, false
end

--- How one item does for one character's note: nil when it is no upgrade
--- (or the note has no worn gear to judge it against), else { gain (whole percent, nil for an empty slot), level (when it can
--- only be worn later) }.
function Alts:Judge(note, link, soonOnly)
    if type(note) ~= "table" or not note.class then return nil end
    -- With no gear on record nothing is known to be an upgrade.
    if type(note.worn) ~= "table" or not next(note.worn) then return nil end
    local info = Items:Info(link)
    if not info or not Compare.SLOTS[info.equipLoc] then return nil end

    local specs = Weights.SPECS[note.class]
    local spec = note.spec
    if not (specs and spec and specs[spec]) then spec = specs and specs.default end
    local weights = spec and Weights:Get(note.class, spec)
    if not weights then return nil end

    local usable, fromLevel = Weights:CanUse(note.class, info.classID, info.subclassID, info.equipLoc)
    if not usable or not Compare:ClassAllows(note.class, link) then return nil end
    -- Armor goes only to a character who wears that kind as its heaviest:
    -- no cloth for a leather wearer.
    if not Weights:IsBestArmor(note.class, note.level, info.classID, info.subclassID, info.equipLoc) then
        return nil
    end
    -- For Butler, armor of a kind this character learns far ahead waits.
    if soonOnly and Weights:KindTooFar(note.class, note.level, info.classID, info.subclassID, info.equipLoc) then
        return nil
    end
    if info.equipLoc == "INVTYPE_WEAPONOFFHAND" then
        local learns = Weights:DualWieldLevel(note.class)
        if not learns then return nil end
        fromLevel = math.max(fromLevel or 0, learns)
    end

    local score = Compare:ScoreOf(link, weights)
    if not score or score <= 0 then return nil end
    local against, empty, equipped = Against(note, link, info, weights)
    if equipped then return nil end

    local result = {}
    local needs = math.max(info.minLevel or 0, fromLevel or 0)
    if needs > (note.level or 0) then result.level = needs end
    if empty then return result end
    if against > 0 then
        local percent = (score - against) / against * 100
        if percent < SAME_WITHIN then return nil end
        result.gain = math.floor(percent + 0.5)
        return result
    end
    if score > against then return result end
    return nil
end

--- The other character this item helps most: { key (its GUID), gain,
--- level }, or nil. Only characters on the same realm and side as the one
--- playing, so it can be mailed; an empty slot beats any percent, and an
--- upgrade to wear now beats one that waits on a level. `soonOnly`
--- (Butler) leaves out armor of a kind learned far ahead (Weights:KindTooFar).
function Alts:BestFor(link, soonOnly)
    link = Items.PlainLink(link)
    if not link then return nil end
    -- Without the character playing's GUID its own note can't be told from
    -- an alt's, and an upgrade "for an alt" could be mailed to itself
    -- (2026-10-11): no answer then. A character is its GUID, the one way
    -- every Blackthornes addon names one in saved data.
    local me = self.PlayerGUID()
    if not me then return nil end
    local realm, faction = self.Realm(), self.Faction()
    local best, bestKey
    for key, note in pairs(self:Notes()) do
        if key ~= me and type(note) == "table" and not self:IsSkipped(key)
            and (not realm or not note.realm or note.realm == realm)
            and (not faction or not note.faction or note.faction == faction) then
            local result = self:Judge(note, link, soonOnly)
            if result then
                local rank = (result.level and 0 or 2) + (result.gain == nil and 1 or 0)
                local bestRank = best and ((best.level and 0 or 2) + (best.gain == nil and 1 or 0))
                if not best or rank > bestRank
                    or (rank == bestRank and (result.gain or 0) > (best.gain or 0))
                    or (rank == bestRank and (result.gain or 0) == (best.gain or 0) and key < bestKey) then
                    best, bestKey = result, key
                end
            end
        end
    end
    if not best then return nil end
    best.key = bestKey
    return best
end

function Alts:OnEnable()
    for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_EQUIPMENT_CHANGED", "PLAYER_LEVEL_UP",
        "TRAIT_CONFIG_UPDATED", "PLAYER_TALENT_UPDATE", "CHARACTER_POINTS_CHANGED" }) do
        ns.RegisterEvent(self, event, function() Alts:Changed() end)
    end
    -- What the bags carry is kept as the character logs out, and the bank's
    -- gear a moment after the bank opens (its slots come in after the event).
    ns.RegisterEvent(self, "PLAYER_LOGOUT", function() pcall(Alts.Record, Alts) end)
    ns.RegisterEvent(self, "BANKFRAME_OPENED", function()
        C_Timer.After(0.5, function() pcall(Alts.ReadBank, Alts) end)
    end)
end

-- /beq skip [on|off|list]: the character playing, or who is skipped.
ns.RegisterCommand("skip", L["skip upgrades for this character, such as a crafting alt (on, off, list)"], function(rest)
    local word = (rest or ""):lower():match("^%s*(%S*)")
    if word == "list" then
        local names = Alts:SkippedNames()
        if #names == 0 then
            ns.Print(L["No characters are skipped for upgrades."])
        else
            ns.Print(L.Format("Skipped for upgrades: %s.", table.concat(names, ", ")))
        end
        return
    end
    local guid = Alts.PlayerGUID()
    if not guid then
        ns.Print(L["Can't tell which character this is right now. Try again outside the dungeon."])
        return
    end
    local on
    if word == "on" then on = true elseif word == "off" then on = false else on = not Alts:IsSkipped(guid) end
    Alts:SetSkipped(guid, on)
    if on then
        ns.Print(L["Upgrades are skipped for this character. Your other characters' gear won't be offered to it either."])
    else
        ns.Print(L["Upgrades are back on for this character."])
    end
end)

