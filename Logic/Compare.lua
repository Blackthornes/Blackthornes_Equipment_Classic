-- Blackthornes Equipment -- Logic/Compare.lua
-- Is this item better than what is worn in its slot, for the spec the
-- character is judged as?
--
-- Each item gets one number from Weights:Score (each stat times its weight),
-- and the verdict is that number against the worn item's. Rings and trinkets
-- have two slots, so a new one is measured against the weaker of the pair. A
-- two-handed weapon is measured against main hand and off hand together.
--
-- The tooltip line and the bag arrow both ask Judge, so they cannot disagree.

local _, ns = ...
local L = ns.L

local Compare = ns.NewModule("Compare")

local Items = ns.Items
local Weights = ns.Weights

-- Where each kind of item goes. Shirts, tabards, bags and ammunition are
-- left out: they carry no stats worth weighing.
local SLOTS = {
    INVTYPE_HEAD = { 1 },
    INVTYPE_NECK = { 2 },
    INVTYPE_SHOULDER = { 3 },
    INVTYPE_CHEST = { 5 },
    INVTYPE_ROBE = { 5 },
    INVTYPE_WAIST = { 6 },
    INVTYPE_LEGS = { 7 },
    INVTYPE_FEET = { 8 },
    INVTYPE_WRIST = { 9 },
    INVTYPE_HAND = { 10 },
    INVTYPE_FINGER = { 11, 12 },
    INVTYPE_TRINKET = { 13, 14 },
    INVTYPE_CLOAK = { 15 },
    INVTYPE_WEAPON = { 16 },
    INVTYPE_2HWEAPON = { 16 },
    INVTYPE_WEAPONMAINHAND = { 16 },
    INVTYPE_WEAPONOFFHAND = { 17 },
    INVTYPE_SHIELD = { 17 },
    INVTYPE_HOLDABLE = { 17 },
    INVTYPE_RANGED = { 18 },
    INVTYPE_RANGEDRIGHT = { 18 },
    INVTYPE_THROWN = { 18 },
    INVTYPE_RELIC = { 18 },
}

-- Weapon damage on these counts as ranged damage; on anything else, melee.
local RANGED = {
    INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true, INVTYPE_THROWN = true,
}

-- Closer than this, in percent, and the two are called the same: stat
-- weights are a guess, and a 0.3% "upgrade" would be noise.
local SAME_WITHIN = 1

Compare.SLOTS = SLOTS

-- The backpack and the four bags beside it.
local FIRST_BAG, LAST_BAG = 0, 4

-- Scores already worked out, by weights table and then by link. Every
-- verdict scores what is worn in that slot again, so the same few links are
-- scored over and over. A change of weights makes new weights tables
-- (Weights:Changed), so old scores are never read again, and the weak keys
-- let them go.
local scores = setmetatable({}, { __mode = "k" })

--- One item's score for these weights, or nil if its stats cannot be read.
-- The second and third returns are its hit (percent, the kind the spec
-- cares about) and what that hit adds to the score, for the hit cap.
function Compare:ScoreOf(link, weights)
    local kept = type(weights) == "table" and type(link) == "string" and scores[weights]
    local held = kept and kept[link]
    if held then return held[1], held[2], held[3] end

    local raw = Items:Stats(link)
    if not raw then return nil end

    local info = Items:Info(link)
    local stats = Weights:Normalize(raw)
    local schools = Items:SchoolDamage(link)
    Weights:AddSchools(stats, schools)
    local score, hit = Weights:Score(stats, weights, info and RANGED[info.equipLoc] or false)
    local _, hitWeight = Weights.HitKind(weights)
    hit = hit or 0
    -- A kind of weapon the player counts for more or less (Weights:FactorFor).
    if info then
        local factor = Weights:FactorFor(weights, info.classID, info.subclassID)
        score, hitWeight = score * factor, hitWeight * factor
    end
    local hitValue = hit * hitWeight

    -- Kept only once everything it read had loaded: the stats, what kind of
    -- item it is, and the tooltip's school damage (nil until it can be read).
    if type(weights) == "table" and type(link) == "string" and info and schools
        and Items:SchoolDamageKnown(link) then
        kept = scores[weights]
        if not kept then
            kept = {}
            scores[weights] = kept
        end
        kept[link] = { score, hit, hitValue }
    end
    return score, hit, hitValue
end

--- Forget every kept score: what rating gives moves with the level.
function Compare:ForgetScores()
    scores = setmetatable({}, { __mode = "k" })
    if Weights.ForgetRatings then Weights:ForgetRatings() end
end

function Compare:OnEnable()
    ns.RegisterEvent(self, "PLAYER_LEVEL_UP", self.ForgetScores)
end

--------------------------------------------------------------------------------
-- The hit cap
--
-- Past a point, more hit does nothing: against a mob of your own level,
-- 5% hit stops weapon attacks missing and 3% stops spells missing (Classic's
-- numbers). Someone swinging two weapons still misses with plain swings
-- until 24%, so for them hit past 5% counts for half, up to 24%. The hit the
-- character has now comes from the client (talents, racials and gear all
-- in it); when it cannot be read, hit counts in full as before.
--------------------------------------------------------------------------------

Compare.HIT_CAP = { melee = 5, spell = 3 }
Compare.DUAL_WIELD_CAP = 24
Compare.DUAL_WIELD_PAST_CAP = 0.5

local HIT_CALLS = {
    melee = { modifier = "GetHitModifier", cr = "CR_HIT_MELEE", index = 6 },
    spell = { modifier = "GetSpellHitModifier", cr = "CR_HIT_SPELL", index = 8 },
}

local hitRead, hitReadAt = {}, {}

-- A number the client gave, or nil, read inside a pcall.
local function Number(value)
    local ok, answer = pcall(function()
        if type(value) == "number" and value == value and value > -100 and value < 100 then return value end
        return nil
    end)
    return ok and answer or nil
end

--- The hit the character has now, in percent, for "melee" or "spell", or
--- nil when the client will not say. Read at most once a second.
function Compare:CurrentHit(kind)
    local calls = HIT_CALLS[kind]
    if not calls then return nil end
    local now = (type(GetTime) == "function" and GetTime()) or 0
    if hitReadAt[kind] and now - hitReadAt[kind] < 1 then return hitRead[kind] or nil end

    local index = _G[calls.cr]
    if type(index) ~= "number" then index = calls.index end
    local modifier = Number((Items.Call({ calls.modifier })))
    local rating = Number((Items.Call({ "GetCombatRatingBonus" }, index)))
    local hit = nil
    if modifier or rating then hit = math.max(0, (modifier or 0) + (rating or 0)) end
    hitRead[kind], hitReadAt[kind] = hit or false, now
    return hit
end

--- Is the character swinging a weapon in each hand?
local function DualWielding()
    for _, slot in ipairs({ 16, 17 }) do
        local link = Items:Equipped(slot)
        local info = link and Items:Info(link)
        local loc = info and info.equipLoc
        if not (loc == "INVTYPE_WEAPON" or loc == "INVTYPE_WEAPONMAINHAND" or loc == "INVTYPE_WEAPONOFFHAND") then
            return false
        end
    end
    return true
end

--- How much of `hit` (percent) counts, added on top of `base`.
function Compare.HitThatCounts(hit, base, cap, dualCap, past)
    local function Worth(total)
        local worth = math.min(total, cap)
        if dualCap and total > cap then worth = worth + (math.min(total, dualCap) - cap) * past end
        return worth
    end
    base = math.max(0, base)
    return Worth(base + hit) - Worth(base)
end

--- The hit cap, worked out for these weights: a function that takes an
--- item's hit (percent) and what that hit added to its score, and the worn
--- hit it would replace, and gives back how much to take off its score.
--- Nil when the spec weighs no hit or the client says nothing.
function Compare:HitCapFor(weights, wornHit)
    local kind = Weights.HitKind(weights)
    if not kind then return nil end
    local current = self:CurrentHit(kind)
    if not current then return nil end
    local cap = self.HIT_CAP[kind]
    local dualCap = kind == "melee" and DualWielding() and self.DUAL_WIELD_CAP or nil
    local base = current - (wornHit or 0)
    return function(hit, hitValue)
        if not hit or hit <= 0 or not hitValue or hitValue <= 0 then return 0 end
        local counts = Compare.HitThatCounts(hit, base, cap, dualCap, self.DUAL_WIELD_PAST_CAP)
        return hitValue * (1 - counts / hit)
    end
end

--- Score and the score to beat with hit past the cap taken off both.
local function Capped(self, weights, score, hit, hitValue, against, wornHit, wornValue)
    local lose = self:HitCapFor(weights, wornHit)
    if not lose then return score, against, false end
    local off, wornOff = lose(hit, hitValue), lose(wornHit, wornValue)
    return score - off, math.max(0, (against or 0) - wornOff), off > 0 or wornOff > 0
end
Compare.Capped = Capped

--- What is worn where this item would go, and the score to beat.
-- @return against (number), empty (true when every slot it could go in is
--         empty), equipped (true when this very item is already worn), and
--         the slot it would go in (the weaker of a pair)
function Compare:Against(link, equipLoc, weights)
    local slots = SLOTS[equipLoc]

    -- A one-handed weapon also fits the off hand, for a character who can
    -- dual wield and is not holding a shield or book there or swinging a
    -- two-hander. Otherwise an empty off hand would make every dagger look
    -- like an upgrade.
    if equipLoc == "INVTYPE_WEAPON"
        and Weights:CanDualWield(Weights:PlayerClass(), Items:PlayerLevel()) then
        local offHand = Items:Equipped(17)
        local offInfo = offHand and Items:Info(offHand)
        local mainHand = Items:Equipped(16)
        local mainInfo = mainHand and Items:Info(mainHand)
        local offIsWeapon = offInfo and (offInfo.equipLoc == "INVTYPE_WEAPON"
            or offInfo.equipLoc == "INVTYPE_WEAPONOFFHAND")
        local mainIsTwoHand = mainInfo and mainInfo.equipLoc == "INVTYPE_2HWEAPON"
        if offIsWeapon or (not offHand and mainHand and not mainIsTwoHand) then
            slots = { 16, 17 }
        end
    end

    local weakest, weakestSlot, empty = nil, slots[1], true
    local wornHit, wornValue = 0, 0
    for _, slot in ipairs(slots) do
        local worn = Items:Equipped(slot)
        if worn == link then return 0, false, true, slot, 0, 0 end

        local score, hit, value = 0, 0, 0
        if worn then
            empty = false
            score, hit, value = self:ScoreOf(worn, weights)
            score = score or 0
        end
        if not weakest or score < weakest then
            weakest, weakestSlot, wornHit, wornValue = score, slot, hit or 0, value or 0
        end
    end

    -- A two-hander replaces the off hand too.
    if equipLoc == "INVTYPE_2HWEAPON" then
        local offHand = Items:Equipped(17)
        if offHand then
            empty = false
            local score, hit, value = self:ScoreOf(offHand, weights)
            weakest = weakest + (score or 0)
            wornHit, wornValue = wornHit + (hit or 0), wornValue + (value or 0)
        end
    end

    -- An off-hand item cannot go on beside a two-hander; it is up against
    -- the two-hander itself.
    if slots[1] == 17 then
        local mainHand = Items:Equipped(16)
        local mainInfo = mainHand and Items:Info(mainHand)
        if mainInfo and mainInfo.equipLoc == "INVTYPE_2HWEAPON" then
            empty = false
            local score, hit, value = self:ScoreOf(mainHand, weights)
            weakest, wornHit, wornValue = score or 0, hit or 0, value or 0
        end
    end

    -- The fifth and sixth returns: the worn hit it would replace, and what
    -- that hit adds to the score to beat (for the hit cap).
    return weakest or 0, empty, false, weakestSlot, wornHit, wornValue
end

--- The character playing is skipped for upgrades (Alts:SetSkipped, a
--- crafting alt): what would be an upgrade is "skipped" instead, so no
--- arrow, banner, finder row or Tradeskills arrow calls it one, and the
--- tooltip names the other character it helps. The scores stay.
local function Skip(result)
    if result and result.verdict == "upgrade" and ns.Alts and ns.Alts:PlayerSkipped() then
        result.verdict = "skipped"
        result.skipped = true
    end
    return result
end

--- Is Best Armor Only ticked on this character? Kept per character in
--- BlackthornesEquipmentCharDB.bestArmorOnly (off unless ticked).
function Compare.BestArmorOnly()
    return type(ns.charDB) == "table" and ns.charDB.bestArmorOnly == true
end

--- Tick or untick it, and judge everything again.
function Compare:SetBestArmorOnly(on)
    if type(ns.charDB) ~= "table" then return end
    ns.charDB.bestArmorOnly = on and true or nil
    Weights:Changed()
    -- An upgrade quest already picked for lighter armor is let go.
    if ns.UpgradeQuest then pcall(ns.UpgradeQuest.Check, ns.UpgradeQuest) end
end

-- Each class's bit in an item's class mask (Classic's numbers, which the
-- Forever client's tables keep).
local CLASS_BITS = {
    WARRIOR = 1, PALADIN = 2, HUNTER = 4, ROGUE = 8, PRIEST = 16,
    SHAMAN = 64, MAGE = 128, WARLOCK = 256, DRUID = 1024,
}
Compare.CLASS_BITS = CLASS_BITS

local function HasBit(mask, bit)
    return math.floor(mask / bit) % 2 == 1
end

--- The class mask the data gives an item: the Forever client's own first,
--- then Classic's sources, then crafted gear. 0 for all classes, nil when
--- no data knows the item.
function Compare.ClassMask(itemID)
    local forever = ns.ForeverItems and ns.ForeverItems[itemID]
    if forever and tonumber(forever[3]) then return forever[3] end
    local item = ns.Sources and ns.Sources.ITEMS and ns.Sources.ITEMS[itemID]
    if item and tonumber(item[3]) then return item[3] end
    local craft = ns.Crafts and ns.Crafts.ITEMS and ns.Crafts.ITEMS[itemID]
    if craft and tonumber(craft[6]) then return craft[6] end
    return nil
end

--- The names the client gives a class, lower case, for matching an item's
--- "Classes:" line.
local function ClassNames(class)
    local names = {}
    for _, list in ipairs({ _G.LOCALIZED_CLASS_NAMES_MALE, _G.LOCALIZED_CLASS_NAMES_FEMALE }) do
        local name = type(list) == "table" and list[class]
        if type(name) == "string" then names[#names + 1] = name:lower() end
    end
    if class == Weights:PlayerClass() then
        local ok, name = pcall(function() return (_G.UnitClass("player")) .. "" end)
        if ok and name then names[#names + 1] = name:lower() end
    end
    names[#names + 1] = class:lower()
    return names
end

--- May this class wear the item, by the classes it is limited to? Gear
--- marked for other classes only ("Classes: Hunter") is never an upgrade
--- for anyone else. False only when the data or the item's own tooltip
--- says so; anything not known is allowed.
function Compare:ClassAllows(class, link)
    local bit = CLASS_BITS[class]
    local itemID = type(link) == "string" and tonumber(link:match("item:(%d+)")) or tonumber(link)
    if not bit or not itemID then return true end
    local mask = Compare.ClassMask(itemID)
    if mask and mask > 0 then
        -- A mask holding every class (some rows say so outright) limits no one.
        return HasBit(mask, bit)
    end
    if mask == 0 then return true end
    local ok, listed = pcall(Items.ClassesOnTooltip, Items, itemID)
    if not ok or type(listed) ~= "table" then return true end
    for _, name in ipairs(ClassNames(class)) do
        if listed[name] then return true end
    end
    return false
end

--- The verdict on one item for this character.
--
-- @return nil when the item is not gear this addon judges, or its details are
--         not known yet. Otherwise a table:
--   verdict   "upgrade", "downgrade", "same", "equipped" or "cantuse"
--   specName  the spec it was judged for, "Beast Mastery"
--   className the class it was judged for, "HUNTER"
--   percent   how much better or worse, when there is something to measure
--             against
--   empty     true when it would go in an empty slot
--   level     the level it can be worn from, when that is above the player's
--             (an upgrade that has to wait)
function Compare:Judge(link)
    link = Items.PlainLink(link)
    if not link then return nil end

    local info = Items:Info(link)
    if not info or not SLOTS[info.equipLoc] then return nil end

    local weights, spec = Weights:ForPlayer()
    if not weights then return nil end

    local class = Weights:PlayerClass()
    local result = {
        className = class,
        specName = Weights:SpecName(class, spec),
    }

    local usable, fromLevel = Weights:CanUse(class, info.classID, info.subclassID, info.equipLoc)
    -- Gear limited to other classes ("Classes: Hunter") is not for it.
    if usable and not self:ClassAllows(class, link) then usable = false end
    -- An off-hand-only weapon needs dual wield, which most classes never
    -- get and the rest learn from a trainer. The client has the last word
    -- when it says this character can.
    if usable and info.equipLoc == "INVTYPE_WEAPONOFFHAND"
        and not Weights:CanDualWield(class, Items:PlayerLevel()) then
        local learns = Weights:DualWieldLevel(class)
        if learns then
            fromLevel = math.max(fromLevel or 0, learns)
            -- Old enough and still the client says no: it has to be
            -- trained first, so it is not an upgrade that can be worn now.
            if (Items:PlayerLevel() or 0) >= learns then result.train = L["Dual Wield"] end
        else
            usable = false
        end
    end
    if not usable then
        result.verdict = "cantuse"
        return result
    end

    -- Armor of a kind the class learns later (mail or plate at 40), far off
    -- yet: not for it until Weights.KIND_SOON levels before, so no tooltip
    -- line, arrow or keep for many levels (the owner, 2026-10-24).
    if Weights:KindTooFar(class, Items:PlayerLevel(),
        info.classID, info.subclassID, info.equipLoc) then
        result.verdict = "cantuse"
        result.laterArmor = fromLevel
        return result
    end

    -- Best Armor Only, ticked on this character: lighter armor than the
    -- heaviest kind it wears is not for it (no tooltip line of its own). A
    -- kind learned later counts in a slot once that slot holds a piece of it.
    if self.BestArmorOnly() and Weights:IsLighterArmor(class, Items:PlayerLevel(),
        info.classID, info.subclassID, info.equipLoc,
        Weights.WornArmorRank(SLOTS[info.equipLoc])) then
        result.verdict = "cantuse"
        result.lighterArmor = true
        return result
    end

    -- A weapon whose skill is not trained yet is still an upgrade, but one
    -- that can't be put on until it is (`skill`, its name). One of a type
    -- this character ignores until trained, or any while Settings hides
    -- untrained weapons (Logic/WeaponSkills.lua), is not for it at all.
    local skills = ns.WeaponSkills
    if info.classID == 2 and skills then
        local skill, subclassID = skills:Untrained(link)
        if skill then
            if skills:IsHidden(subclassID) then
                result.verdict = "cantuse"
                result.ignoredSkill = skill
                return result
            end
            result.skill = skill
        end
    end

    local playerLevel = Items:PlayerLevel()
    local needs = math.max(info.minLevel or 0, fromLevel or 0)
    if playerLevel and needs > playerLevel then
        result.level = needs
    end

    local score, hit, hitValue = self:ScoreOf(link, weights)
    if not score then return nil end

    local against, empty, equipped, slot, wornHit, wornValue = self:Against(link, info.equipLoc, weights)
    result.slot = slot
    if equipped then
        result.verdict = "equipped"
        return result
    end

    -- Hit past the cap counts for less, on this item and on what it replaces.
    score, against, result.hitCapped = Capped(self, weights, score, hit, hitValue, against, wornHit, wornValue)
    result.score, result.against, result.empty = score, against, empty

    if empty then
        result.verdict = "upgrade"
    elseif against > 0 then
        result.percent = (score - against) / against * 100
        if math.abs(result.percent) < SAME_WITHIN then
            result.verdict = "same"
        elseif result.percent > 0 then
            result.verdict = "upgrade"
        else
            result.verdict = "downgrade"
        end
    elseif score > against then
        -- The worn item scores nothing (a plain shirt-like piece), so any
        -- stats at all are better; there is no percentage to give.
        result.verdict = "upgrade"
    else
        result.verdict = "same"
    end

    return Skip(result)
end

-- Rings and trinkets come in pairs: the slot that is not the weaker one.
local PAIRED = { [11] = 12, [12] = 11, [13] = 14, [14] = 13 }

local function IDOf(link)
    return type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
end

--- Can only one of this item be worn at a time? Asked of the client where
--- it can say; otherwise trinkets are taken to be (most are), rings not.
function Compare:IsUnique(link)
    local id = IDOf(link)
    if not id then return false end
    -- Retail: isUnique, limitCategoryName, limitCategoryCount. The older
    -- call: uniqueFamily (-1 for plain Unique), maxEquipped.
    local first, second, third = Items.Call({ "C_Item.GetItemUniquenessByID", "GetItemUniqueness" }, id)
    local ok, answer = pcall(function()
        if first == true or first == -1 then return true end
        if type(second) == "number" and second == 1 then return true end
        if type(third) == "number" and third == 1 then return true end
        if first == false or type(first) == "number" then return false end
        return nil
    end)
    if ok and answer ~= nil then return answer end
    local info = Items:Info(link)
    return info ~= nil and info.equipLoc == "INVTYPE_TRINKET"
end

--- Judge an item known to be carried in the bags, not worn.
--
-- A link alone cannot tell a worn ring from a second copy of it, so Judge
-- calls both "equipped". A copy in the bags is free to go in the other ring
-- or trinket slot, so it is measured against that one instead.
function Compare:JudgeCarried(link)
    local result = self:Judge(link)
    if not (result and result.verdict == "equipped" and PAIRED[result.slot]) then return result end

    local weights = Weights:ForPlayer()
    if not weights then return result end
    local score, hit, hitValue = self:ScoreOf(link, weights)
    if not score then return result end

    local other = PAIRED[result.slot]
    local worn = Items:Equipped(other)
    if worn == link or self:IsUnique(link) then return result end
    local against, wornHit, wornValue = 0, 0, 0
    if worn then
        against, wornHit, wornValue = self:ScoreOf(worn, weights)
        against = against or 0
    end
    score, against = Capped(self, weights, score, hit, hitValue, against, wornHit, wornValue)

    local judged = {
        className = result.className, specName = result.specName, slot = other,
        score = score, against = against, empty = not worn,
    }
    if not worn then
        judged.verdict = "upgrade"
    elseif against > 0 then
        judged.percent = (score - against) / against * 100
        if math.abs(judged.percent) < SAME_WITHIN then
            judged.verdict = "same"
        else
            judged.verdict = judged.percent > 0 and "upgrade" or "downgrade"
        end
    else
        judged.verdict = score > against and "upgrade" or "same"
    end
    return Skip(judged)
end

--- The biggest upgrade in the bags for each slot, that can be worn now.
--
-- A new ring is judged against the weaker ring, so two good rings in the
-- bags would both land on that one slot. The runner-up is then measured
-- against the other ring, so the second slot shows it too.
-- @return { [inventory slot] = { link, result } }
function Compare:BestInBags()
    local best, paired = {}, {}
    for bag = FIRST_BAG, LAST_BAG do
        for bagSlot = 1, Items:BagSize(bag) do
            local link = Items:InBag(bag, bagSlot)
            local ok, result = pcall(self.JudgeCarried, self, link)
            if ok and Compare.WearableUpgrade(result) and result.slot then
                local gain = (result.score or 0) - (result.against or 0)
                local entry = { link = link, result = result, gain = gain, where = bag * 100 + bagSlot }
                -- A weapon the character can wear now beats one that waits
                -- on training, whatever the gain: the gear window offers it
                -- to put on.
                local held = best[result.slot]
                local trained, heldTrained = not result.skill, held and not held.result.skill
                if not held or (trained and not heldTrained)
                    or (trained == heldTrained and gain > held.gain) then
                    best[result.slot] = entry
                end
                if PAIRED[result.slot] then paired[#paired + 1] = entry end
            end
        end
    end

    local weights = #paired > 1 and Weights:ForPlayer()
    for _, pair in ipairs({ { 11, 12 }, { 13, 14 } }) do
        local taken = best[pair[1]] or best[pair[2]]
        local other = best[pair[1]] and pair[2] or pair[1]
        if weights and taken and not best[other] then
            local worn = Items:Equipped(other)
            local wornScore, wornHit, wornValue = 0, 0, 0
            if worn then
                wornScore, wornHit, wornValue = self:ScoreOf(worn, weights)
                wornScore = wornScore or 0
            end
            for _, entry in ipairs(paired) do
                local result = entry.result
                local twin = IDOf(entry.link) == IDOf(taken.link) and self:IsUnique(entry.link)
                if entry.where ~= taken.where and not twin
                    and (result.slot == pair[1] or result.slot == pair[2]) then
                    -- Scored again against this ring, since the hit cap
                    -- depends on which one it replaces.
                    local raw, hit, hitValue = self:ScoreOf(entry.link, weights)
                    local score, against = Capped(self, weights, raw or result.score or 0, hit, hitValue,
                        wornScore, wornHit, wornValue)
                    local percent = against > 0 and (score - against) / against * 100 or nil
                    local beats = not worn or (percent and percent >= SAME_WITHIN)
                        or (against <= 0 and score > 0)
                    local gain = score - against
                    if beats and (not best[other] or gain > best[other].gain) then
                        best[other] = {
                            link = entry.link, gain = gain, where = entry.where,
                            result = {
                                verdict = "upgrade", className = result.className,
                                specName = result.specName, slot = other, score = score,
                                against = against, empty = not worn, percent = worn and percent or nil,
                            },
                        }
                    end
                end
            end
        end
    end
    return best
end

--- Is a verdict an upgrade that can be put on right now: not waiting on a
--- level or on training?
function Compare.WearableUpgrade(result)
    return type(result) == "table" and result.verdict == "upgrade"
        and not result.level and not result.train
end

--- How much better, in words: "+14%", "fills an empty slot" or "better stats".
function Compare:HowMuch(result)
    if result.empty then return L["fills an empty slot"] end
    if result.percent then return ("%+d%%"):format(math.floor(result.percent + 0.5)) end
    return L["better stats"]
end

--- Should this item get the upgrade arrow in the bags? Only a real upgrade
--- that can be worn now. `carried` says the link is a copy in the bags.
function Compare:IsUpgradeNow(link, carried)
    local ok, result = pcall(carried and self.JudgeCarried or self.Judge, self, link)
    return ok and Compare.WearableUpgrade(result)
end

--- Is an item with this ID worn anywhere? Rings and trinkets have two
--- slots, so a ring asked about by ID could otherwise be measured against the
--- other ring and called an upgrade over itself.
--- The item IDs worn now, as a set: read once for a long list, where asking
--- IsWornID per item would read all nineteen slots each time.
function Compare:WornIDs()
    local ids = {}
    for slot = 1, 19 do
        local worn = Items:Equipped(slot)
        local id = worn and tonumber(worn:match("item:(%d+)"))
        if id then ids[id] = true end
    end
    return ids
end

function Compare:IsWornID(itemID)
    for slot = 1, 19 do
        local worn = Items:Equipped(slot)
        if worn and tonumber(worn:match("item:(%d+)")) == itemID then return true end
    end
    return false
end

--- The call other addons make (Tradeskills' item lists): true when an item is
--- an upgrade that can be worn now, false otherwise, and it never raises.
--- `item` is an item ID or a link. Keep the name and meaning stable; see
--- CLAUDE.md.
function Compare:IsUpgrade(item)
    if type(item) == "number" then
        local ok, worn = pcall(self.IsWornID, self, item)
        if not ok or worn then return false end
        item = ("item:%d"):format(item)
    end
    return self:IsUpgradeNow(item)
end

--------------------------------------------------------------------------------
-- Words
--------------------------------------------------------------------------------

local CLASS_NAMES = {
    WARRIOR = L["Warriors"], PALADIN = L["Paladins"], HUNTER = L["Hunters"], ROGUE = L["Rogues"],
    PRIEST = L["Priests"], SHAMAN = L["Shamans"], MAGE = L["Mages"], WARLOCK = L["Warlocks"],
    DRUID = L["Druids"],
}

--- The line a tooltip shows for a verdict, and the colour to show it in, or
--- nil when there is nothing worth saying (the item is the one worn).
function Compare:Describe(result)
    if not result then return nil end

    local verdict, spec = result.verdict, result.specName
    local percent = result.percent and ("%+d%%"):format(math.floor(result.percent + 0.5)) or nil

    if verdict == "cantuse" and (result.lighterArmor or result.laterArmor) then
        return nil
    elseif verdict == "cantuse" and result.ignoredSkill then
        return L.Format("Ignored until you train %s", result.ignoredSkill), "muted"
    elseif verdict == "cantuse" then
        return L.Format("%s can't use this", CLASS_NAMES[result.className] or L["Your class"]), "muted"
    elseif verdict == "equipped" or verdict == "skipped" then
        return nil
    elseif verdict == "upgrade" then
        local how = result.empty and L["fills an empty slot"] or percent or L["better stats"]
        if result.level then
            return L.Format("Upgrade for %s at level %d: %s", spec, result.level, how), "warn"
        end
        if result.train or result.skill then
            return L.Format("Upgrade for %s once you train %s: %s", spec, result.train or result.skill, how), "warn"
        end
        return L.Format("Upgrade for %s: %s", spec, how), "upgrade"
    elseif verdict == "downgrade" then
        return L.Format("Worse for %s: %s", spec, percent), "downgrade"
    end
    return L.Format("About the same for %s", spec), "muted"
end

--------------------------------------------------------------------------------
-- /beq bags
--------------------------------------------------------------------------------

function Compare:ReportBags()
    local weights, spec = Weights:ForPlayer()
    if not weights then
        ns.Print(L.Format("no stat weights for %s yet", Weights:PlayerClass() or L["this class"]))
        return
    end

    ns.Print(L.Format("gear in your bags, judged as |c%s%s|r", ns.COLORS.accent,
        Weights:SpecName(Weights:PlayerClass(), spec)))

    local shown = 0
    for bag = FIRST_BAG, LAST_BAG do
        for slot = 1, Items:BagSize(bag) do
            local link = Items:InBag(bag, slot)
            local ok, result = pcall(self.Judge, self, link)
            local text, color = nil, nil
            if ok then text, color = self:Describe(result) end
            if text then
                shown = shown + 1
                ns.PrintRaw(("  %s  |c%s%s|r"):format(link, ns.COLORS[color], text))
            end
        end
    end

    if shown == 0 then
        ns.PrintRaw(L.Format("  |c%snothing in your bags to wear|r", ns.COLORS.muted))
    end
end

ns.RegisterCommand("bags", L["judge every piece of gear in your bags"], function()
    Compare:ReportBags()
end)
