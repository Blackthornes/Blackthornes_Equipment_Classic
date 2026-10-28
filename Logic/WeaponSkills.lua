-- Blackthornes Equipment -- Logic/WeaponSkills.lua
-- Which weapon skills the character knows, and for a weapon their class can
-- learn but has not, where its weapon master is.
--
-- Two ways to ask, both inside a pcall: the spell each weapon skill gives
-- (C_SpellBook.IsSpellKnown, IsPlayerSpell, IsSpellKnown, whichever the
-- client has), and classic's skill list (GetSkillLineInfo). A skill either
-- way says known counts as known. Every character starts with at least one
-- weapon skill, so when neither way finds any the client is not answering
-- and nothing is said: a wrong "go learn this" is worse than none.
--
-- An untrained weapon is still an upgrade (the owner, 2026-10-02: "it gives
-- you a reason to go learn the skill"), but one that can't be put on yet, so
-- the banner offers two things instead of Put it on (2026-10-11): point the
-- quest arrow at the weapon master who teaches it (ShowMaster), or ignore
-- that weapon type until it is trained (Ignore). Ignored types are kept per
-- character in `ignoredWeaponTypes[subclassID] = true` (never rename it);
-- Compare then calls such a weapon one this character doesn't use, and
-- learning the skill brings it back by itself.

local _, ns = ...
local L = ns.L

local WeaponSkills = ns.NewModule("WeaponSkills")

local Items = ns.Items
local Weights = ns.Weights
local WeaponTrainers = ns.WeaponTrainers

local CLASS_WEAPON = 2

local SPELL_CALLS = { "C_SpellBook.IsSpellKnown", "IsPlayerSpell", "IsSpellKnown" }

--- Does any of the client's spell calls say this spell is known?
local function SpellKnown(spellID)
    for _, path in ipairs(SPELL_CALLS) do
        local known = Items.Call({ path }, spellID)
        if known == true then return true end
    end
    return false
end

--- The names in classic's skill list, as a set, or an empty set.
local function SkillLines()
    local names = {}
    local count = tonumber((Items.Call({ "GetNumSkillLines" }))) or 0
    for index = 1, count do
        local name = Items.Call({ "GetSkillLineInfo" }, index)
        local ok, copy = pcall(function()
            if type(name) == "string" then return name .. "" end
        end)
        if ok and copy then names[copy] = true end
    end
    return names
end

--- The weapon skills this character knows, by weapon subclass ID, or nil
--- when the client gives no answer at all. Kept until a skill or spell
--- event says it may have changed, so lists that ask for every row stay
--- cheap.
function WeaponSkills:Known()
    if self.kept == nil then self.kept = self:ReadKnown() or false end
    return self.kept or nil
end

--- Forget the kept answer: a skill may have been learned.
function WeaponSkills:Forget()
    self.kept = nil
    -- The finder keeps its verdicts, and a weapon's "Train" mark or an
    -- ignored type's "cantuse" is one of them: judge again.
    if ns.Finder and ns.Finder.ForgetVerdicts then pcall(ns.Finder.ForgetVerdicts, ns.Finder) end
end

--- A skill was learned (the skill list or the spellbook changed): forget,
--- and let the banner look again at weapons waiting on one.
function WeaponSkills:Learned()
    self:Forget()
    if ns.UpgradeChat and ns.UpgradeChat.SkillsChanged then
        pcall(ns.UpgradeChat.SkillsChanged, ns.UpgradeChat)
    end
end

--- The skill's spell as the client names it ("Stäbe"), or nil: the skill
--- list's name for it on a client in another language.
local function SpellName(spellID)
    local name = Items.Call({ "C_Spell.GetSpellName", "GetSpellInfo" }, spellID)
    local ok, copy = pcall(function()
        if type(name) == "string" and name ~= "" then return name .. "" end
    end)
    return ok and copy or nil
end

function WeaponSkills:ReadKnown()
    local lines = SkillLines()
    local known, any = {}, false
    for subclassID, skill in pairs(WeaponTrainers.SKILLS) do
        local has = SpellKnown(skill.spell)
        for _, line in ipairs(skill.lines) do
            if lines[line] then has = true end
        end
        if not has and next(lines) ~= nil then
            local own = SpellName(skill.spell)
            if own and lines[own] then has = true end
        end
        if has then
            known[subclassID] = true
            any = true
        end
    end
    if not any then return nil end
    return known
end

--- "Horde" or "Alliance", or nil.
function WeaponSkills:Faction()
    local faction = Items.Call({ "UnitFactionGroup" }, "player")
    local ok, copy = pcall(function()
        if faction == "Horde" or faction == "Alliance" then return faction .. "" end
    end)
    if ok then return copy end
    return nil
end

--- Where to learn the weapon skill an item needs, when this character's
--- class can learn it and has not.
-- @return the skill's name, a list of cities and the level it opens at
-- (when that is above the character's), or nil
function WeaponSkills:TrainerFor(link)
    local info = Items:Info(link)
    if not info or info.classID ~= CLASS_WEAPON then return nil end

    local skill = WeaponTrainers.SKILLS[info.subclassID]
    if not skill then return nil end

    local usable, from = Weights:CanUse(Weights:PlayerClass(), info.classID, info.subclassID, info.equipLoc)
    if not usable then return nil end
    local level = Items:PlayerLevel()
    if not (from and level and level < from) then from = nil end

    local faction = self:Faction()
    if not faction then return nil end

    local known = self:Known()
    if not known or known[info.subclassID] then return nil end

    local cities = WeaponTrainers:Cities(faction, info.subclassID)
    if #cities == 0 then return nil end
    return skill.name, cities, from, info.subclassID
end

--- Does an item need a weapon skill this character can learn but has
--- not? For the red "Train" in the upgrade lists. False when unsure.
function WeaponSkills:NeedsTraining(link)
    if not link then return false end
    local ok, name = pcall(self.TrainerFor, self, link)
    return ok and name ~= nil
end

--- The weapon skill an item still needs, when this character's class can
--- learn it and has not: its name and the weapon's subclass ID, or nil.
function WeaponSkills:Untrained(link)
    if not link then return nil end
    local ok, name, _, _, subclassID = pcall(self.TrainerFor, self, link)
    if ok and name then return name, subclassID end
    return nil
end

--------------------------------------------------------------------------------
-- Ignoring a weapon type until it is trained
--------------------------------------------------------------------------------

local function IgnoredList()
    local char = ns.charDB
    if type(char) ~= "table" then return nil end
    if type(char.ignoredWeaponTypes) ~= "table" then char.ignoredWeaponTypes = {} end
    return char.ignoredWeaponTypes
end

--- Is this weapon type ignored by this character?
function WeaponSkills:IsIgnored(subclassID)
    local char = ns.charDB
    local list = type(char) == "table" and char.ignoredWeaponTypes
    return type(list) == "table" and subclassID ~= nil and list[subclassID] == true
end

--- Does this character hide every weapon it has not trained (Settings,
--- "Untrained Weapons:" on Hide)? Kept per character, as the types are.
function WeaponSkills:HidesAll()
    local char = ns.charDB
    return type(char) == "table" and char.hideUntrainedWeapons == true
end

--- Is an untrained weapon of this type kept out of the upgrades, by the
--- Settings row or by its banner's Ignore?
function WeaponSkills:IsHidden(subclassID)
    return self:HidesAll() or self:IsIgnored(subclassID)
end

--- Does Settings read Hide: every untrained weapon hidden, or some types?
function WeaponSkills:AnyHidden()
    local char = ns.charDB
    local list = type(char) == "table" and char.ignoredWeaponTypes
    return self:HidesAll() or (type(list) == "table" and next(list) ~= nil)
end

--- The names of the weapon types this character ignores, sorted.
function WeaponSkills:IgnoredNames()
    local names = {}
    local char = ns.charDB
    local list = type(char) == "table" and char.ignoredWeaponTypes
    if type(list) ~= "table" then return names end
    for subclassID, on in pairs(list) do
        local skill = WeaponTrainers.SKILLS[subclassID]
        if on == true and skill then names[#names + 1] = skill.name end
    end
    table.sort(names)
    return names
end

--- Every verdict on a weapon may have changed: redraw what shows them.
local function Changed()
    if Weights and Weights.Changed then pcall(Weights.Changed, Weights) end
    -- An upgrade quest already on an untrained weapon now hidden is let go.
    if ns.UpgradeQuest then pcall(ns.UpgradeQuest.Check, ns.UpgradeQuest) end
    if ns.SettingsUI and ns.SettingsUI.Refresh then pcall(ns.SettingsUI.Refresh, ns.SettingsUI) end
end

--- Stop calling weapons of this type upgrades until the skill is trained.
function WeaponSkills:Ignore(subclassID)
    local skill = WeaponTrainers.SKILLS[subclassID]
    local list = IgnoredList()
    if not (skill and list) then return false end
    list[subclassID] = true
    ns.Print(L.Format("ignoring %s until you train them. To bring them back, use Settings or /beq weapons show.", skill.name))
    Changed()
    return true
end

--- Show every untrained weapon again: the Settings row's Hide and every
--- type ignored from a banner. `quiet` (Settings) says nothing in chat.
function WeaponSkills:ShowAll(quiet)
    local list = IgnoredList()
    local char = ns.charDB
    if not self:AnyHidden() then
        if not quiet then ns.Print(L["no weapon types are ignored."]) end
        return false
    end
    if list then
        for key in pairs(list) do list[key] = nil end
    end
    if type(char) == "table" then char.hideUntrainedWeapons = nil end
    if not quiet then ns.Print(L["untrained weapons show as upgrades again."]) end
    Changed()
    return true
end

--- Hide every weapon this character has not trained until it is trained.
--- `quiet` (Settings) says nothing in chat.
function WeaponSkills:HideAll(quiet)
    local char = ns.charDB
    if type(char) ~= "table" then return false end
    if char.hideUntrainedWeapons == true then return false end
    char.hideUntrainedWeapons = true
    if not quiet then ns.Print(L["untrained weapons won't show as upgrades until you train them."]) end
    Changed()
    return true
end

--------------------------------------------------------------------------------
-- The weapon master
--------------------------------------------------------------------------------

--- The zone the character is in, plain, or nil: by the data's name for it,
--- on a client in another language too.
local function ZoneNow()
    local zone = Items.Call({ "GetRealZoneText", "GetZoneText" })
    local ok, copy = pcall(function()
        if type(zone) == "string" and zone ~= "" then return zone .. "" end
    end)
    copy = ok and copy or nil
    if copy and ns.Waypoints then copy = ns.Waypoints:DataZone(copy) end
    return copy
end

--- Where to learn the skill an item needs: { name, zone, x, y, skill },
--- the trainer in the city the character is in when one there teaches it,
--- else the first listed. Forever's spot wins when one was learned. Nil
--- when the item needs no training.
function WeaponSkills:Master(link)
    local skillName, subclassID = self:Untrained(link)
    local faction = skillName and self:Faction()
    if not faction then return nil end
    local teachers = WeaponTrainers:Teachers(faction, subclassID)
    if #teachers == 0 then return nil end
    local here = ZoneNow()
    local pick = teachers[1]
    for _, trainer in ipairs(teachers) do
        if trainer.city == here then pick = trainer break end
    end
    local name, zone, x, y = pick.name, pick.city, pick.x, pick.y
    if ns.NPCSpots and pick.npc then
        local ok, a, b, c, d = pcall(ns.NPCSpots.Place, ns.NPCSpots, pick.npc, name, zone, x, y)
        if ok and a then name, zone, x, y = a, b, c, d end
    end
    return { name = name, zone = zone, x = x, y = y, skill = skillName }
end

--- Point the quest arrow at the weapon master for an item's skill, and say
--- where in chat. True when there was one to point at.
function WeaponSkills:ShowMaster(link)
    local place = self:Master(link)
    if not place then
        ns.Print(L["no weapon master to show for that."])
        return false
    end
    -- The game's own names on a client in another language; the arrow keeps the data's.
    local names = ns.Names
    local zone = names and names:Zone(place.zone) or place.zone
    local who = names and names:NPC(place.name) or place.name
    local where = place.x and ("%s (%.0f, %.0f)"):format(zone, place.x, place.y) or zone
    ns.Print(L.Format("%s teaches %s, in %s.", who, place.skill, where))
    local arrow = ns.QuestArrow
    if arrow and arrow.AimAtQuest then
        pcall(arrow.AimAtQuest, arrow, nil, L.Format("Learn %s", place.skill),
            { zone = place.zone, x = place.x, y = place.y, name = place.name })
    end
    return true
end

function WeaponSkills:OnEnable()
    -- SPELLS_CHANGED comes often and only forgets; the other two are a
    -- skill being learned.
    ns.RegisterEvent(self, "SPELLS_CHANGED", self.Forget)
    for _, event in ipairs({ "SKILL_LINES_CHANGED", "LEARNED_SPELL_IN_TAB" }) do
        ns.RegisterEvent(self, event, self.Learned)
    end
end

ns.RegisterCommand("weapons", L["weapons you haven't trained (show or hide them as upgrades)"], function(rest)
    rest = (rest or ""):lower()
    if rest:match("^show") then
        WeaponSkills:ShowAll()
        return
    end
    if rest:match("^hide") then
        WeaponSkills:HideAll()
        return
    end
    if WeaponSkills:HidesAll() then
        ns.Print(L["untrained weapons won't show as upgrades until you train them."])
        return
    end
    local names = WeaponSkills:IgnoredNames()
    if #names == 0 then
        ns.Print(L["untrained weapons show as upgrades, with where to learn them. To ignore a type, use the upgrade banner."])
    else
        ns.Print(L.Format("ignored until you train them: %s. /beq weapons show brings them back.", table.concat(names, ", ")))
    end
end)

--- "A", "A or B", "A, B or C".
local function List(cities)
    if #cities == 1 then return cities[1] end
    return L.Format("%s or %s", table.concat(cities, ", ", 1, #cities - 1), cities[#cities])
end

--- The tooltip line for an item, and its colour, or nil.
function WeaponSkills:Describe(link)
    local name, cities, from = self:TrainerFor(link)
    if not name then return nil end
    if from then
        return L.Format("Learn %s at level %d from the weapon master in %s", name, from, List(cities)), "warn"
    end
    return L.Format("Learn %s from the weapon master in %s", name, List(cities)), "warn"
end
