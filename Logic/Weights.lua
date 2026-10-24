-- Blackthornes Equipment -- Logic/Weights.lua
-- How much each stat is worth to a class and spec, and which spec the player
-- is judged as.
--
-- WoW: Forever hunters have classic-style talent trees (Beast Mastery,
-- Marksmanship, Survival) rather than a specialization picked from a menu, so
-- "spec" here means the tree with the most points in it. Below level 10 there
-- are no points, and the class default applies until the player picks one
-- with /beq spec. Forever has no classic talent-tab calls; its talents are one
-- trait tree per class (C_ClassTalents, C_Traits), so the points are counted
-- per spec from where each talent sits in that tree.
--
-- Every classic class has weights: warrior, paladin, hunter, rogue, priest,
-- shaman, mage, warlock and druid. The numbers are a starting guess for
-- levelling, per point of the stat with each spec's main stat as 1. Crit and
-- hit are per 1%, the way classic-era items print them. /beq probe shows what
-- the client really reports so they can be tuned, and players can change any
-- of them for themselves in the weights window (UI/WeightsWindow.lua). Every class's talent layout
-- has been checked on Forever; see CLASSIC_COLUMNS.

local _, ns = ...
local L = ns.L

local Weights = ns.NewModule("Weights")

--------------------------------------------------------------------------------
-- The weights
--------------------------------------------------------------------------------

-- Stats a weight can name. Anything else the client reports is ignored.
--   dps is weapon damage per second; Score applies it as rangedDps or
--   meleeDps depending on the weapon, because a hunter's bow matters far more
--   than a sword to Beast Mastery and far less to Survival.
-- Where a class's three specs split in its talent tree, by a talent's posX.
-- Measured on the hunter and confirmed on all nine classes.
local CLASSIC_COLUMNS = { 4000, 8000 }

local SPECS = {
    HUNTER = {
        order = { "beast", "marks", "survival" },
        default = "beast",
        -- Forever puts all three hunter specs in one talent tree, side by
        -- side. A talent left of 4000 is Beast Mastery (Focused Fire,
        -- Endurance Training), left of 8000 Marksmanship (Hawk Eye, Lone
        -- Wolf), and anything further right Survival (Entrapment, Deflection,
        -- Lightning Reflexes, which sits far out at 102800). Read with
        -- /beq probe on 2026-09-29; see docs/FOREVER_API_FINDINGS.md.
        columns = CLASSIC_COLUMNS,
        -- The level a second weapon opens at (classic's trainer). A class
        -- with none never holds a weapon in the off hand.
        dualWield = 20,
        -- What a hunter can equip, by the client's item subclass, and the
        -- level each opens at (0 for any level). Classic rules: mail from 40,
        -- no plate, shields, maces or wands. Not yet checked on Forever; if it
        -- differs, the tooltip will say "can't use" on something a hunter can
        -- wear.
        armor = {
            [0] = 0,    -- miscellaneous: rings, necks, trinkets
            [1] = 0,    -- cloth (cloaks are cloth)
            [2] = 0,    -- leather
            [3] = 40,   -- mail
        },
        weapons = {
            [0] = 0, [1] = 0,       -- one- and two-handed axes
            [2] = 0, [3] = 0,       -- bows, guns
            [6] = 0,                -- polearms
            [7] = 0, [8] = 0,       -- one- and two-handed swords
            [10] = 0,               -- staves
            [13] = 0,               -- fist weapons
            [15] = 0,               -- daggers
            [18] = 0,               -- crossbows
            -- No thrown: in classic only warriors and rogues learn it, so a
            -- hunter is never offered a throwing dagger.
        },
        beast = {
            name = "Beast Mastery",
            weights = {
                agility = 1.0, strength = 0.1, stamina = 0.5, intellect = 0.25,
                spirit = 0.1, attackPower = 0.35, rangedAttackPower = 0.45,
                crit = 12, hit = 10, armor = 0.02,
                rangedDps = 6, meleeDps = 0.5,
            },
        },
        marks = {
            name = "Marksmanship",
            weights = {
                agility = 1.0, strength = 0.05, stamina = 0.35, intellect = 0.3,
                spirit = 0.05, attackPower = 0.3, rangedAttackPower = 0.5,
                crit = 15, hit = 14, armor = 0.01,
                rangedDps = 8, meleeDps = 0.3,
            },
        },
        survival = {
            -- Survival fights in melee on Forever (Mongoose Bite, bleeds, traps),
            -- so strength, melee attack power and the melee weapon count.
            name = "Survival",
            weights = {
                agility = 1.0, strength = 0.35, stamina = 0.5, intellect = 0.2,
                spirit = 0.1, attackPower = 0.55, rangedAttackPower = 0.3,
                crit = 14, hit = 12, armor = 0.03,
                rangedDps = 3, meleeDps = 5,
            },
        },
    },

    ----------------------------------------------------------------------------
    -- The other eight classic classes. Every one of their talent trees
    -- has been probed on Forever: split at 4000 and 8000, in classic's
    -- order, like the hunter's. If Forever ever reshapes one, /beq probe
    -- shows the new layout and that class gets its own columns. Equip rules are classic's.
    ----------------------------------------------------------------------------

    WARRIOR = {
        order = { "arms", "fury", "prot" },
        default = "arms",
        columns = CLASSIC_COLUMNS,
        dualWield = 20,
        armor = { [0] = 0, [1] = 0, [2] = 0, [3] = 0, [4] = 40, [6] = 0 },
        weapons = {
            [0] = 0, [1] = 0, [2] = 0, [3] = 0, [4] = 0, [5] = 0, [6] = 0,
            [7] = 0, [8] = 0, [10] = 0, [13] = 0, [15] = 0, [16] = 0, [18] = 0,
        },
        arms = {
            name = "Arms",
            weights = {
                strength = 1.0, agility = 0.6, stamina = 0.5, attackPower = 0.5,
                crit = 14, hit = 12, armor = 0.02, meleeDps = 7, rangedDps = 0.3,
            },
        },
        fury = {
            name = "Fury",
            weights = {
                strength = 1.0, agility = 0.7, stamina = 0.4, attackPower = 0.5,
                crit = 16, hit = 16, armor = 0.01, meleeDps = 5, rangedDps = 0.3,
            },
        },
        prot = {
            name = "Protection",
            weights = {
                stamina = 1.0, strength = 0.6, agility = 0.6, armor = 0.1,
                defense = 1.2, dodge = 12, parry = 10, block = 6, blockValue = 0.4,
                hit = 6, attackPower = 0.2, meleeDps = 2, rangedDps = 0.2,
            },
        },
    },

    PALADIN = {
        order = { "holy", "prot", "ret" },
        default = "ret",
        columns = CLASSIC_COLUMNS,
        -- 7 is a libram.
        armor = { [0] = 0, [1] = 0, [2] = 0, [3] = 0, [4] = 40, [6] = 0, [7] = 0 },
        weapons = { [0] = 0, [1] = 0, [4] = 0, [5] = 0, [6] = 0, [7] = 0, [8] = 0 },
        holy = {
            name = "Holy",
            weights = {
                intellect = 1.0, healing = 0.8, spellPower = 0.9, spirit = 0.5,
                stamina = 0.3, mp5 = 2, spellCrit = 10, armor = 0.005,
                holyDamage = 0.3,
            },
        },
        prot = {
            name = "Protection",
            weights = {
                stamina = 1.0, strength = 0.5, agility = 0.4, intellect = 0.3,
                armor = 0.08, defense = 1.0, dodge = 10, parry = 8, block = 6,
                blockValue = 0.3, spellPower = 0.5, meleeDps = 2,
                holyDamage = 0.5,
            },
        },
        ret = {
            name = "Retribution",
            weights = {
                strength = 1.0, agility = 0.5, stamina = 0.5, intellect = 0.3,
                attackPower = 0.45, crit = 12, hit = 12, spellPower = 0.3,
                armor = 0.02, meleeDps = 7, holyDamage = 0.3,
            },
        },
    },

    ROGUE = {
        order = { "assassination", "combat", "sub" },
        default = "combat",
        columns = CLASSIC_COLUMNS,
        dualWield = 10,
        armor = { [0] = 0, [1] = 0, [2] = 0 },
        weapons = {
            [2] = 0, [3] = 0, [4] = 0, [7] = 0, [13] = 0, [15] = 0, [16] = 0, [18] = 0,
        },
        assassination = {
            name = "Assassination",
            weights = {
                agility = 1.0, strength = 0.5, stamina = 0.4, attackPower = 0.5,
                crit = 15, hit = 14, armor = 0.01, meleeDps = 5, rangedDps = 0.3,
            },
        },
        combat = {
            name = "Combat",
            weights = {
                agility = 1.0, strength = 0.5, stamina = 0.4, attackPower = 0.5,
                crit = 13, hit = 16, armor = 0.01, meleeDps = 6, rangedDps = 0.3,
            },
        },
        sub = {
            name = "Subtlety",
            weights = {
                agility = 1.0, strength = 0.5, stamina = 0.5, attackPower = 0.5,
                crit = 14, hit = 13, armor = 0.02, meleeDps = 5, rangedDps = 0.3,
            },
        },
    },

    PRIEST = {
        order = { "disc", "holy", "shadow" },
        default = "shadow",
        columns = CLASSIC_COLUMNS,
        armor = { [0] = 0, [1] = 0 },
        weapons = { [4] = 0, [10] = 0, [15] = 0, [19] = 0 },
        disc = {
            name = "Discipline",
            weights = {
                intellect = 1.0, spirit = 0.7, stamina = 0.4, healing = 0.8,
                spellPower = 0.8, mp5 = 2, spellCrit = 8, rangedDps = 2,
                holyDamage = 0.3, shadowDamage = 0.3,
            },
        },
        holy = {
            name = "Holy",
            weights = {
                intellect = 1.0, spirit = 0.9, stamina = 0.3, healing = 1.0,
                spellPower = 0.8, mp5 = 2.5, spellCrit = 10, rangedDps = 2,
                holyDamage = 0.3, shadowDamage = 0.2,
            },
        },
        shadow = {
            name = "Shadow",
            weights = {
                intellect = 0.8, spirit = 0.8, stamina = 0.6, spellPower = 1.1,
                spellHit = 12, spellCrit = 4, mp5 = 1.5, rangedDps = 3,
                shadowDamage = 1.1, holyDamage = 0.2,
            },
        },
    },

    SHAMAN = {
        order = { "elemental", "enhancement", "resto" },
        default = "enhancement",
        columns = CLASSIC_COLUMNS,
        -- 9 is a totem.
        armor = { [0] = 0, [1] = 0, [2] = 0, [3] = 40, [6] = 0, [9] = 0 },
        weapons = { [0] = 0, [1] = 0, [4] = 0, [5] = 0, [10] = 0, [13] = 0, [15] = 0 },
        elemental = {
            name = "Elemental",
            weights = {
                intellect = 1.0, stamina = 0.5, spirit = 0.3, spellPower = 1.1,
                spellCrit = 12, spellHit = 12, mp5 = 2, armor = 0.01, meleeDps = 1,
                natureDamage = 1.0, fireDamage = 0.3, frostDamage = 0.2,
            },
        },
        enhancement = {
            name = "Enhancement",
            weights = {
                strength = 1.0, agility = 0.7, stamina = 0.5, intellect = 0.3,
                attackPower = 0.5, crit = 14, hit = 12, armor = 0.02, meleeDps = 7,
            },
        },
        resto = {
            name = "Restoration",
            weights = {
                intellect = 1.0, spirit = 0.3, stamina = 0.4, healing = 1.0,
                spellPower = 0.8, mp5 = 3, spellCrit = 10,
            },
        },
    },

    MAGE = {
        order = { "arcane", "fire", "frost" },
        default = "frost",
        columns = CLASSIC_COLUMNS,
        armor = { [0] = 0, [1] = 0 },
        weapons = { [7] = 0, [10] = 0, [15] = 0, [19] = 0 },
        arcane = {
            name = "Arcane",
            weights = {
                intellect = 1.0, spirit = 0.4, stamina = 0.5, spellPower = 1.2,
                spellCrit = 10, spellHit = 12, mp5 = 1.5, rangedDps = 3,
                arcaneDamage = 0.6, frostDamage = 0.6, fireDamage = 0.4,
            },
        },
        fire = {
            name = "Fire",
            weights = {
                intellect = 0.9, spirit = 0.4, stamina = 0.5, spellPower = 1.2,
                spellCrit = 14, spellHit = 12, mp5 = 1.5, rangedDps = 3,
                fireDamage = 1.2, frostDamage = 0.2, arcaneDamage = 0.2,
            },
        },
        frost = {
            name = "Frost",
            weights = {
                intellect = 0.9, spirit = 0.5, stamina = 0.6, spellPower = 1.2,
                spellCrit = 10, spellHit = 12, mp5 = 1.5, rangedDps = 3,
                frostDamage = 1.2, fireDamage = 0.2, arcaneDamage = 0.2,
            },
        },
    },

    WARLOCK = {
        order = { "affliction", "demo", "destro" },
        default = "affliction",
        columns = CLASSIC_COLUMNS,
        armor = { [0] = 0, [1] = 0 },
        weapons = { [7] = 0, [10] = 0, [15] = 0, [19] = 0 },
        affliction = {
            name = "Affliction",
            weights = {
                stamina = 0.8, intellect = 0.8, spirit = 0.4, spellPower = 1.2,
                spellHit = 12, spellCrit = 5, mp5 = 1, rangedDps = 3,
                shadowDamage = 1.2, fireDamage = 0.3,
            },
        },
        demo = {
            name = "Demonology",
            weights = {
                stamina = 1.0, intellect = 0.8, spirit = 0.4, spellPower = 1.1,
                spellHit = 12, spellCrit = 5, mp5 = 1, rangedDps = 3,
                shadowDamage = 1.1, fireDamage = 0.4,
            },
        },
        destro = {
            name = "Destruction",
            weights = {
                stamina = 0.7, intellect = 0.8, spirit = 0.3, spellPower = 1.2,
                spellHit = 12, spellCrit = 12, mp5 = 1, rangedDps = 3,
                shadowDamage = 1.2, fireDamage = 0.6,
            },
        },
    },

    DRUID = {
        order = { "balance", "feral", "resto" },
        default = "feral",
        columns = CLASSIC_COLUMNS,
        -- 8 is an idol.
        armor = { [0] = 0, [1] = 0, [2] = 0, [8] = 0 },
        -- Forever lets druids train polearms, from 20 (classic never did).
        weapons = { [4] = 0, [5] = 0, [6] = 20, [10] = 0, [13] = 0, [15] = 0 },
        balance = {
            name = "Balance",
            weights = {
                intellect = 1.0, spirit = 0.5, stamina = 0.4, spellPower = 1.1,
                spellCrit = 10, spellHit = 10, mp5 = 2,
                natureDamage = 0.7, arcaneDamage = 0.6,
            },
        },
        feral = {
            -- On Forever, unlike classic, cat and bear attacks scale with the
            -- weapon's damage, and Cat Form gives far less attack power of
            -- its own, so weapon dps counts about as it does for a rogue
            -- (checked 2026-10-05 against several Forever druid guides).
            name = "Feral Combat",
            weights = {
                agility = 1.0, strength = 1.0, stamina = 0.8, attackPower = 0.5,
                crit = 14, hit = 12, armor = 0.05, dodge = 6, defense = 0.4,
                meleeDps = 5,
            },
        },
        resto = {
            name = "Restoration",
            weights = {
                intellect = 1.0, spirit = 0.8, stamina = 0.4, healing = 1.0,
                spellPower = 0.8, mp5 = 2.5, spellCrit = 8,
            },
        },
    },
}

-- Names a player can type after /beq spec. One list for every class: a name
-- only counts when the player's own class has that spec.
local ALIASES = {
    beast = "beast", bm = "beast", ["beast mastery"] = "beast", beastmastery = "beast",
    marks = "marks", mm = "marks", marksmanship = "marks",
    survival = "survival", sv = "survival", surv = "survival",
    arms = "arms", fury = "fury",
    prot = "prot", protection = "prot", tank = "prot",
    holy = "holy", ret = "ret", retribution = "ret",
    assassination = "assassination", assa = "assassination", mut = "assassination",
    combat = "combat", sub = "sub", subtlety = "sub",
    disc = "disc", discipline = "disc", shadow = "shadow", spriest = "shadow",
    elemental = "elemental", ele = "elemental",
    enhancement = "enhancement", enh = "enhancement", enhance = "enhancement",
    resto = "resto", restoration = "resto",
    arcane = "arcane", fire = "fire", frost = "frost",
    affliction = "affliction", affli = "affliction", aff = "affliction",
    demo = "demo", demonology = "demo", destro = "destro", destruction = "destro",
    balance = "balance", boomkin = "balance", moonkin = "balance",
    feral = "feral", ["feral combat"] = "feral", cat = "feral", bear = "feral",
}

-- What the client calls each stat, as returned by GetItemStats, mapped to the
-- names above. Both the modern ITEM_MOD keys and their ranged variants are
-- listed; /beq probe prints any key that is missing from here.
local STAT_KEYS = {
    ["ITEM_MOD_AGILITY_SHORT"] = "agility",
    ["ITEM_MOD_STRENGTH_SHORT"] = "strength",
    ["ITEM_MOD_STAMINA_SHORT"] = "stamina",
    ["ITEM_MOD_INTELLECT_SHORT"] = "intellect",
    ["ITEM_MOD_SPIRIT_SHORT"] = "spirit",
    ["ITEM_MOD_ATTACK_POWER_SHORT"] = "attackPower",
    ["ITEM_MOD_RANGED_ATTACK_POWER_SHORT"] = "rangedAttackPower",
    ["ITEM_MOD_CRIT_RATING_SHORT"] = "crit",
    ["ITEM_MOD_CRIT_RANGED_RATING_SHORT"] = "crit",
    ["ITEM_MOD_CRIT_MELEE_RATING_SHORT"] = "crit",
    ["ITEM_MOD_HIT_RATING_SHORT"] = "hit",
    ["ITEM_MOD_HIT_RANGED_RATING_SHORT"] = "hit",
    ["ITEM_MOD_HIT_MELEE_RATING_SHORT"] = "hit",
    ["RESISTANCE0_NAME"] = "armor",
    ["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = "dps",
    -- Casters and healers.
    ["ITEM_MOD_SPELL_POWER_SHORT"] = "spellPower",
    ["ITEM_MOD_SPELL_DAMAGE_DONE_SHORT"] = "spellPower",
    ["ITEM_MOD_SPELL_HEALING_DONE_SHORT"] = "healing",
    ["ITEM_MOD_MANA_REGENERATION_SHORT"] = "mp5",
    ["ITEM_MOD_POWER_REGEN0_SHORT"] = "mp5",
    ["ITEM_MOD_CRIT_SPELL_RATING_SHORT"] = "spellCrit",
    ["ITEM_MOD_SPELL_CRIT_RATING_SHORT"] = "spellCrit",
    ["ITEM_MOD_HIT_SPELL_RATING_SHORT"] = "spellHit",
    ["ITEM_MOD_SPELL_HIT_RATING_SHORT"] = "spellHit",
    -- Tanks.
    ["ITEM_MOD_DEFENSE_SKILL_RATING_SHORT"] = "defense",
    ["ITEM_MOD_DODGE_RATING_SHORT"] = "dodge",
    ["ITEM_MOD_PARRY_RATING_SHORT"] = "parry",
    ["ITEM_MOD_BLOCK_RATING_SHORT"] = "block",
    ["ITEM_MOD_BLOCK_VALUE_SHORT"] = "blockValue",
}

-- Forever's gear carries hit, crit, dodge, parry, block and defense as
-- rating (Devilsaur Gauntlets: 14 crit rating where Classic had 1% crit),
-- while the weights are per 1% (per point of defense). So a rating is turned
-- into what it gives before it is weighed, the way the game does: asked of
-- the client first (Weights:RatingPer), else by the usual rating table at
-- the player's level. `cr` is the client's combat rating index (CR_HIT_MELEE
-- and the like, its number beside it in case the global is missing), and
-- `at60` the rating for 1% at level 60.
--
-- Forever made hit and crit one stat for weapons and spells alike, so the
-- plain hit and crit rating keys become anyHit and anyCrit, which Score
-- weighs by whichever of the two weights (hit or spellHit, crit or
-- spellCrit) the spec cares about more. The keys that name melee, ranged or
-- spells stay with that one.
local RATINGS = {
    ITEM_MOD_HIT_RATING_SHORT = { stat = "anyHit", cr = "CR_HIT_MELEE", index = 6, at60 = 10 },
    ITEM_MOD_HIT_MELEE_RATING_SHORT = { stat = "hit", cr = "CR_HIT_MELEE", index = 6, at60 = 10 },
    ITEM_MOD_HIT_RANGED_RATING_SHORT = { stat = "hit", cr = "CR_HIT_RANGED", index = 7, at60 = 10 },
    ITEM_MOD_HIT_SPELL_RATING_SHORT = { stat = "spellHit", cr = "CR_HIT_SPELL", index = 8, at60 = 8 },
    ITEM_MOD_SPELL_HIT_RATING_SHORT = { stat = "spellHit", cr = "CR_HIT_SPELL", index = 8, at60 = 8 },
    ITEM_MOD_CRIT_RATING_SHORT = { stat = "anyCrit", cr = "CR_CRIT_MELEE", index = 9, at60 = 14 },
    ITEM_MOD_CRIT_MELEE_RATING_SHORT = { stat = "crit", cr = "CR_CRIT_MELEE", index = 9, at60 = 14 },
    ITEM_MOD_CRIT_RANGED_RATING_SHORT = { stat = "crit", cr = "CR_CRIT_RANGED", index = 10, at60 = 14 },
    ITEM_MOD_CRIT_SPELL_RATING_SHORT = { stat = "spellCrit", cr = "CR_CRIT_SPELL", index = 11, at60 = 14 },
    ITEM_MOD_SPELL_CRIT_RATING_SHORT = { stat = "spellCrit", cr = "CR_CRIT_SPELL", index = 11, at60 = 14 },
    ITEM_MOD_DEFENSE_SKILL_RATING_SHORT = { stat = "defense", cr = "CR_DEFENSE_SKILL", index = 2, at60 = 1.5 },
    ITEM_MOD_DODGE_RATING_SHORT = { stat = "dodge", cr = "CR_DODGE", index = 3, at60 = 12 },
    ITEM_MOD_PARRY_RATING_SHORT = { stat = "parry", cr = "CR_PARRY", index = 4, at60 = 20 },
    ITEM_MOD_BLOCK_RATING_SHORT = { stat = "block", cr = "CR_BLOCK", index = 5, at60 = 5 },
}

-- The plain rating stats, weighed by the larger of the two weights.
local EITHER = {
    anyHit = { "hit", "spellHit" },
    anyCrit = { "crit", "spellCrit" },
}

-- Every stat a weight can name, in the order the weights window lists them,
-- with the name a player reads there. `per` marks the ones counted per 1%.
-- Weapon damage per second is two weights, because Score applies dps as one
-- or the other depending on the weapon.
local STAT_ORDER = {
    { key = "strength", name = "Strength" },
    { key = "agility", name = "Agility" },
    { key = "stamina", name = "Stamina" },
    { key = "intellect", name = "Intellect" },
    { key = "spirit", name = "Spirit" },
    { key = "armor", name = "Armor" },
    { key = "attackPower", name = "Attack power" },
    { key = "rangedAttackPower", name = "Ranged attack power" },
    { key = "crit", name = "Crit", per = true },
    { key = "hit", name = "Hit", per = true },
    { key = "meleeDps", name = "Melee weapon dps" },
    { key = "rangedDps", name = "Ranged weapon dps" },
    { key = "spellPower", name = "Spell power" },
    { key = "arcaneDamage", name = "Arcane spell damage" },
    { key = "fireDamage", name = "Fire spell damage" },
    { key = "frostDamage", name = "Frost spell damage" },
    { key = "natureDamage", name = "Nature spell damage" },
    { key = "shadowDamage", name = "Shadow spell damage" },
    { key = "holyDamage", name = "Holy spell damage" },
    { key = "healing", name = "Healing" },
    { key = "spellCrit", name = "Spell crit", per = true },
    { key = "spellHit", name = "Spell hit", per = true },
    { key = "mp5", name = "Mana every 5 sec" },
    { key = "defense", name = "Defense" },
    { key = "dodge", name = "Dodge", per = true },
    { key = "parry", name = "Parry", per = true },
    { key = "block", name = "Block", per = true },
    { key = "blockValue", name = "Block value" },
}

-- The largest weight a player can set. Far above any built-in one (16), and
-- low enough that a typo cannot make one stat drown out the rest by a
-- thousand times.
local MAX_WEIGHT = 100

-- Kinds of weapon, by the client's item subclass, in the order the weights
-- window lists them. A player can make one kind count for more or less than
-- another (a rogue preferring daggers to swords): the weapon's whole score
-- is multiplied by its kind's number, 1 unless the player changed it.
local WEAPON_TYPES = {
    { key = 15, name = "Daggers" },
    { key = 13, name = "Fist weapons" },
    { key = 0, name = "One-handed axes" },
    { key = 4, name = "One-handed maces" },
    { key = 7, name = "One-handed swords" },
    { key = 1, name = "Two-handed axes" },
    { key = 5, name = "Two-handed maces" },
    { key = 8, name = "Two-handed swords" },
    { key = 6, name = "Polearms" },
    { key = 10, name = "Staves" },
    { key = 2, name = "Bows" },
    { key = 18, name = "Crossbows" },
    { key = 3, name = "Guns" },
    { key = 16, name = "Thrown" },
    { key = 19, name = "Wands" },
}

-- The most a kind of weapon can be multiplied by. 0 leaves it out.
local MAX_TYPE = 3

-- The words a player reads for the English names above. The English stays
-- the name everywhere else (saved weights, typed spec names, tests), so only
-- what is shown goes through here: Weights.Label(name), or SpecName.
local LABELS = {
    -- Specs
    ["Beast Mastery"] = L["Beast Mastery"], ["Marksmanship"] = L["Marksmanship"],
    ["Survival"] = L["Survival"], ["Arms"] = L["Arms"], ["Fury"] = L["Fury"],
    ["Protection"] = L["Protection"], ["Holy"] = L["Holy"], ["Retribution"] = L["Retribution"],
    ["Assassination"] = L["Assassination"], ["Combat"] = L["Combat"], ["Subtlety"] = L["Subtlety"],
    ["Discipline"] = L["Discipline"], ["Shadow"] = L["Shadow"], ["Elemental"] = L["Elemental"],
    ["Enhancement"] = L["Enhancement"], ["Restoration"] = L["Restoration"], ["Arcane"] = L["Arcane"],
    ["Fire"] = L["Fire"], ["Frost"] = L["Frost"], ["Affliction"] = L["Affliction"],
    ["Demonology"] = L["Demonology"], ["Destruction"] = L["Destruction"], ["Balance"] = L["Balance"],
    ["Feral Combat"] = L["Feral Combat"],
    -- Stats
    ["Strength"] = L["Strength"], ["Agility"] = L["Agility"], ["Stamina"] = L["Stamina"],
    ["Intellect"] = L["Intellect"], ["Spirit"] = L["Spirit"], ["Armor"] = L["Armor"],
    ["Attack power"] = L["Attack power"], ["Ranged attack power"] = L["Ranged attack power"],
    ["Crit"] = L["Crit"], ["Hit"] = L["Hit"], ["Melee weapon dps"] = L["Melee weapon damage"],
    ["Ranged weapon dps"] = L["Ranged weapon damage"], ["Spell power"] = L["Spell power"],
    ["Arcane spell damage"] = L["Arcane spell damage"], ["Fire spell damage"] = L["Fire spell damage"],
    ["Frost spell damage"] = L["Frost spell damage"], ["Nature spell damage"] = L["Nature spell damage"],
    ["Shadow spell damage"] = L["Shadow spell damage"], ["Holy spell damage"] = L["Holy spell damage"],
    ["Healing"] = L["Healing"], ["Spell crit"] = L["Spell crit"], ["Spell hit"] = L["Spell hit"],
    ["Mana every 5 sec"] = L["Mana every 5 sec"], ["Defense"] = L["Defense"], ["Dodge"] = L["Dodge"],
    ["Parry"] = L["Parry"], ["Block"] = L["Block"], ["Block value"] = L["Block value"],
    -- Kinds of weapon
    ["Daggers"] = L["Daggers"], ["Fist weapons"] = L["Fist weapons"],
    ["One-handed axes"] = L["One-handed axes"], ["One-handed maces"] = L["One-handed maces"],
    ["One-handed swords"] = L["One-handed swords"], ["Two-handed axes"] = L["Two-handed axes"],
    ["Two-handed maces"] = L["Two-handed maces"], ["Two-handed swords"] = L["Two-handed swords"],
    ["Polearms"] = L["Polearms"], ["Staves"] = L["Staves"], ["Bows"] = L["Bows"],
    ["Crossbows"] = L["Crossbows"], ["Guns"] = L["Guns"], ["Thrown"] = L["Thrown"], ["Wands"] = L["Wands"],
}

--- What a player reads for a spec, stat or weapon kind's English name.
function Weights.Label(name)
    return name and LABELS[name] or name
end

--- The shown name of a class's spec ("Beast Mastery", or the client's
--- language's), or nil when there is no such spec.
function Weights:SpecName(class, spec)
    local entry = class and SPECS[class] and spec and SPECS[class][spec]
    return entry and Weights.Label(entry.name) or nil
end

Weights.SPECS = SPECS
Weights.STAT_KEYS = STAT_KEYS
Weights.RATINGS = RATINGS
Weights.STAT_ORDER = STAT_ORDER
Weights.MAX_WEIGHT = MAX_WEIGHT
Weights.WEAPON_TYPES = WEAPON_TYPES
Weights.MAX_TYPE = MAX_TYPE

--------------------------------------------------------------------------------
-- Reading the player
--------------------------------------------------------------------------------

--- The player's class token, "HUNTER" say, or nil if the client will not say.
function Weights:PlayerClass()
    if type(UnitClass) ~= "function" then return nil end
    local ok, _, token = pcall(UnitClass, "player")
    if ok and type(token) == "string" then return token end
    return nil
end

--- Points spent in each talent tree, in the client's tab order, or nil when
-- the client has no talent trees to read.
--
-- GetTalentTabInfo has two shapes in the wild: the classic one starts with the
-- tree's name and has the points third; the later one starts with a numeric
-- id and has them fifth. Forever is a modern engine running classic trees, so
-- both are handled rather than guessed.
function Weights:TreePoints(class)
    if type(GetNumTalentTabs) ~= "function" or type(GetTalentTabInfo) ~= "function" then
        return self:TraitPoints(class)
    end

    -- Old talent calls that are only stubs (no tabs, or raising) fall back
    -- to the trait tree, which is what Forever really has.
    local okCount, count = pcall(GetNumTalentTabs)
    if not okCount or type(count) ~= "number" or count < 1 then return self:TraitPoints(class) end

    local points = {}
    for tab = 1, count do
        local info = { pcall(GetTalentTabInfo, tab) }
        if not info[1] then return self:TraitPoints(class) end

        local spent
        if type(info[2]) == "number" then
            spent = info[6]     -- id, name, description, icon, pointsSpent
        else
            spent = info[4]     -- name, icon, pointsSpent
        end
        points[tab] = type(spent) == "number" and spent or 0
    end
    return points
end

--- Points per spec from Forever's trait tree: every talent with ranks bought
--- counts toward the spec whose columns it sits in. Nil when there is no
--- config to read or no split known for the class. Each call is in a pcall,
--- and a node that will not answer is skipped rather than guessed.
function Weights:TraitPoints(class)
    local specs = class and SPECS[class]
    local columns = specs and specs.columns
    if not columns then return nil end

    local talents = type(C_ClassTalents) == "table" and C_ClassTalents
    local traits = type(C_Traits) == "table" and C_Traits
    if not (talents and traits and type(talents.GetActiveConfigID) == "function"
        and type(traits.GetConfigInfo) == "function"
        and type(traits.GetTreeNodes) == "function"
        and type(traits.GetNodeInfo) == "function") then
        return nil
    end

    local ok, configID = pcall(talents.GetActiveConfigID)
    if not ok or not configID then return nil end

    local okInfo, info = pcall(traits.GetConfigInfo, configID)
    if not okInfo or type(info) ~= "table" or type(info.treeIDs) ~= "table" then return nil end

    local points = {}
    for index = 1, #specs.order do points[index] = 0 end

    for _, treeID in ipairs(info.treeIDs) do
        local okNodes, nodes = pcall(traits.GetTreeNodes, treeID)
        if okNodes and type(nodes) == "table" then
            for _, nodeID in ipairs(nodes) do
                local okNode, node = pcall(traits.GetNodeInfo, configID, nodeID)
                if okNode and type(node) == "table" and type(node.posX) == "number" then
                    local ranks = tonumber(node.ranksPurchased) or 0
                    if ranks > 0 then
                        local index = #columns + 1
                        for column, edge in ipairs(columns) do
                            if node.posX < edge then
                                index = column
                                break
                            end
                        end
                        points[index] = points[index] + ranks
                    end
                end
            end
        end
    end
    return points
end

-- The talent read walks every node of the trait tree through the client,
-- and every item judged asks for the spec: a tooltip on each redraw while
-- hovering, the bag arrows once per item. So one read is kept until the
-- talents or the level change, and never for longer than POINTS_KEPT
-- seconds in case the client says nothing.
local POINTS_KEPT = 5
local pointsRead = nil

local function Now()
    local clock = rawget(_G, "GetTime")
    if type(clock) ~= "function" then return nil end
    local ok, now = pcall(clock)
    if ok and type(now) == "number" then return now end
    return nil
end

--- TreePoints, kept a few seconds.
function Weights:SpentPoints(class)
    local now = Now()
    local kept = pointsRead
    if now and kept and kept.class == class and now >= kept.at and now - kept.at < POINTS_KEPT then
        return kept.points
    end
    local points = self:TreePoints(class)
    pointsRead = now and { class = class, at = now, points = points } or nil
    return points
end

--- Read the talents afresh on the next ask.
function Weights:ForgetPoints()
    pointsRead = nil
end

function Weights:OnEnable()
    for _, event in ipairs({ "TRAIT_CONFIG_UPDATED", "PLAYER_TALENT_UPDATE", "CHARACTER_POINTS_CHANGED",
        "PLAYER_LEVEL_UP", "PLAYER_ENTERING_WORLD" }) do
        ns.RegisterEvent(self, event, self.ForgetPoints)
    end
    ns.RegisterEvent(self, "PLAYER_LEVEL_UP", self.ForgetRatings)
end

--- The spec this character is judged as, and why: "picked", "talents" or
--- "default". Nil when there are no weights for the class yet.
function Weights:CurrentSpec()
    local class = self:PlayerClass()
    local specs = class and SPECS[class]
    if not specs then return nil, nil, class end

    local picked = ns.charDB and ns.charDB.spec
    if picked and specs[picked] then
        return picked, "picked", class
    end

    local points = self:SpentPoints(class)
    if points then
        local best, bestPoints, tied = nil, 0, false
        for tab, spent in ipairs(points) do
            if spent > bestPoints then
                best, bestPoints, tied = tab, spent, false
            elseif spent == bestPoints and spent > 0 then
                tied = true
            end
        end
        if best and not tied and specs.order[best] then
            return specs.order[best], "talents", class
        end
    end

    return specs.default, "default", class
end

-- Each merged table's weapon kind numbers, kept beside it rather than in it,
-- so everything that reads a weights table still finds only stats there.
local typesOf = setmetatable({}, { __mode = "k" })

--- The weights to judge this character's gear by, or nil for a class that
--- has none yet. The player's own weights where they changed any.
function Weights:ForPlayer()
    local spec, _, class = self:CurrentSpec()
    if not spec then return nil end
    return self:WithRacials(self:Get(class, spec)), spec
end

--------------------------------------------------------------------------------
-- Racial stat bonuses
--
-- A few races get more from one stat: Tauren more health, Humans more
-- Spirit, Gnomes more mana. That stat is worth that much more on gear for
-- them. Flat crit, hit, haste and dodge racials need nothing here: the
-- client already counts them in the character's numbers, and the hit cap
-- reads those (Compare:CurrentHit). Since the 10-15 patch no racial is tied
-- to a weapon kind any more, so none changes which weapon is better.
--
-- Known by the racial's spell, else by race; the percent is read off the
-- spell's own text when the client gives it, else the usual 5%.
--------------------------------------------------------------------------------

Weights.RACIALS = {
    { spell = 20550, race = "Tauren", stat = "stamina", percent = 5 },   -- Endurance
    { spell = 20598, race = "Human", stat = "spirit", percent = 5 },     -- The Human Spirit
    { spell = 20591, race = "Gnome", stat = "intellect", percent = 5 },  -- Expansive Mind
}

local SPELL_KNOWN = { "C_SpellBook.IsSpellKnown", "IsPlayerSpell", "IsSpellKnown" }
local SPELL_TEXT = { "C_Spell.GetSpellDescription", "GetSpellDescription" }

-- The racials found, read once a session: { [stat] = factor }.
local racialRead

local function Known(spellID)
    local Call = ns.Items and ns.Items.Call
    if not Call then return false end
    for _, path in ipairs(SPELL_KNOWN) do
        if Call({ path }, spellID) == true then return true end
    end
    return false
end

local function PercentIn(spellID)
    local Call = ns.Items and ns.Items.Call
    local text = Call and Call(SPELL_TEXT, spellID)
    local ok, percent = pcall(function()
        if type(text) ~= "string" then return nil end
        return tonumber(text:match("(%d+)%%"))
    end)
    if ok and percent and percent >= 1 and percent <= 25 then return percent end
    return nil
end

--- The player's racial stat bonuses, { [stat] = factor }, empty for none.
function Weights:Racials()
    if racialRead then return racialRead end
    local Call = ns.Items and ns.Items.Call
    local race
    if Call then
        local _, file = Call({ "UnitRace" }, "player")
        local ok, copy = pcall(function()
            if type(file) == "string" then return file .. "" end
        end)
        race = ok and copy or nil
    end
    local found = {}
    for _, racial in ipairs(self.RACIALS) do
        if Known(racial.spell) or (race and race == racial.race) then
            local percent = PercentIn(racial.spell) or racial.percent
            found[racial.stat] = (found[racial.stat] or 1) * (1 + percent / 100)
        end
    end
    -- Not kept until the race can be read, or a login read too early
    -- would miss it for the session.
    if race then racialRead = found end
    return found
end

-- The player's tables with racials laid on, by the merged table they came from.
local withRacials = setmetatable({}, { __mode = "k" })

--- A weights table with the player's racial bonuses laid over it. The same
--- table back when there are none, so nothing is copied for most races.
function Weights:WithRacials(weights)
    if type(weights) ~= "table" then return weights end
    local racials = self:Racials()
    if not next(racials) then return weights end
    if withRacials[weights] then return withRacials[weights] end

    local copy = {}
    for stat, value in pairs(weights) do copy[stat] = value end
    for stat, factor in pairs(racials) do
        if copy[stat] then copy[stat] = copy[stat] * factor end
    end
    typesOf[copy] = typesOf[weights]
    withRacials[weights] = copy
    return copy
end

--------------------------------------------------------------------------------
-- The player's own weights
--
-- Kept account wide in BlackthornesEquipmentDB.customWeights, by class and
-- spec: customWeights.HUNTER.marks.crit = 10. Only the stats a player changed
-- are kept, so a built-in weight tuned in a later version still reaches every
-- stat they left alone. Nothing here ever deletes a saved weight except the
-- player setting it back to the built-in value or pressing reset, and a value
-- that is not a number is skipped rather than removed.
--------------------------------------------------------------------------------

-- Merged tables, so judging a bag full of gear does not rebuild one per item.
-- Forgotten whenever a weight changes.
local merged = {}


--- The built-in weights for a class and spec, or nil. Never changed.
function Weights:Defaults(class, spec)
    local specs = class and SPECS[class]
    local entry = specs and spec and specs[spec]
    return type(entry) == "table" and entry.weights or nil
end

--- The saved changes for a class and spec, or nil. `create` makes the
--- tables when they are missing.
function Weights:Custom(class, spec, create)
    local db = ns.db
    if type(db) ~= "table" or not class or not spec then return nil end

    if type(db.customWeights) ~= "table" then
        if not create then return nil end
        db.customWeights = {}
    end
    local byClass = db.customWeights[class]
    if type(byClass) ~= "table" then
        if not create then return nil end
        byClass = {}
        db.customWeights[class] = byClass
    end
    local bySpec = byClass[spec]
    if type(bySpec) ~= "table" then
        if not create then return nil end
        bySpec = {}
        byClass[spec] = bySpec
    end
    return bySpec
end

local function Usable(value)
    return type(value) == "number" and value == value and value >= 0 and value <= MAX_WEIGHT
end

--- The weights a class and spec are judged by: the built-in ones with the
--- player's changes laid over them. Nil for a spec that does not exist.
function Weights:Get(class, spec)
    local defaults = self:Defaults(class, spec)
    if not defaults then return nil end

    local key = class .. ":" .. spec
    if merged[key] then return merged[key] end

    local weights = {}
    for stat, value in pairs(defaults) do weights[stat] = value end
    for stat, value in pairs(self:Custom(class, spec) or {}) do
        if Usable(value) then
            -- 0 is kept as 0 rather than left out, so the player's "ignore
            -- this stat" wins over the built-in weight.
            weights[stat] = value
        end
    end

    local types = {}
    for _, entry in ipairs(WEAPON_TYPES) do
        local factor = self:TypeFactor(class, spec, entry.key)
        if factor ~= 1 then types[entry.key] = factor end
    end
    typesOf[weights] = types

    -- Not kept before the saved weights have loaded, or the player's would
    -- be missed until the next change.
    if type(ns.db) == "table" then merged[key] = weights end
    return weights
end

--- One stat's weight for a class and spec: what it is now, and the built-in
--- value. Either is 0 when the stat has no weight.
function Weights:Value(class, spec, stat)
    local weights = self:Get(class, spec) or {}
    local defaults = self:Defaults(class, spec) or {}
    return weights[stat] or 0, defaults[stat] or 0
end

--- True when the player has changed this stat (or, with no stat, any stat)
--- for a class and spec.
function Weights:IsCustom(class, spec, stat)
    local custom = self:Custom(class, spec)
    if not custom then return false end
    if stat then return Usable(custom[stat]) end
    for _, value in pairs(custom) do
        if Usable(value) then return true end
    end
    return false
end

--- Round a typed or stepped weight to what is kept: never below 0 or above
--- MAX_WEIGHT, and to three decimals, so 0.1 + 0.2 is kept as 0.3.
function Weights:Clean(value)
    value = tonumber(value)
    if not value or value ~= value then return nil end
    value = math.max(0, math.min(MAX_WEIGHT, value))
    return math.floor(value * 1000 + 0.5) / 1000
end

--- Set one stat's weight for a class and spec. Setting it to the built-in
--- value forgets the change, so the stat follows the built-in one again.
-- @return the weight kept, or nil and why
function Weights:SetWeight(class, spec, stat, value)
    if not self:Defaults(class, spec) then return nil, "no such spec" end

    local known = false
    for _, entry in ipairs(STAT_ORDER) do
        if entry.key == stat then known = true break end
    end
    if not known then return nil, "no such stat" end

    value = self:Clean(value)
    if not value then return nil, "not a number" end

    local default = self:Defaults(class, spec)[stat] or 0
    if math.abs(value - default) < 0.0005 then
        local custom = self:Custom(class, spec)
        if custom then custom[stat] = nil end
    else
        self:Custom(class, spec, true)[stat] = value
    end

    self:Changed()
    return value
end

--- Put every stat and kind of weapon for a class and spec back to the
--- built-in weights.
function Weights:Reset(class, spec)
    for _, custom in ipairs({ self:Custom(class, spec) or {}, self:TypeCustom(class, spec) or {} }) do
        for stat, value in pairs(custom) do
            -- Junk that is not a weight was never ours to read; leave it be.
            if Usable(value) then custom[stat] = nil end
        end
    end
    self:Changed()
end

--------------------------------------------------------------------------------
-- Kinds of weapon
--
-- Kept account wide in BlackthornesEquipmentDB.weaponTypeWeights, by class,
-- spec and the client's weapon subclass: weaponTypeWeights.ROGUE.combat[15]
-- = 1.2 counts a dagger's score 20% higher. Apart from customWeights, so a
-- version of the addon from before this never meets a table among its
-- weights. Only kinds a player changed are kept; 1 is no change.
--------------------------------------------------------------------------------

--- The saved weapon kind numbers for a class and spec, or nil. `create`
--- makes the tables when they are missing.
function Weights:TypeCustom(class, spec, create)
    local db = ns.db
    if type(db) ~= "table" or not class or not spec then return nil end

    if type(db.weaponTypeWeights) ~= "table" then
        if not create then return nil end
        db.weaponTypeWeights = {}
    end
    local byClass = db.weaponTypeWeights[class]
    if type(byClass) ~= "table" then
        if not create then return nil end
        byClass = {}
        db.weaponTypeWeights[class] = byClass
    end
    local bySpec = byClass[spec]
    if type(bySpec) ~= "table" then
        if not create then return nil end
        bySpec = {}
        byClass[spec] = bySpec
    end
    return bySpec
end

local function UsableType(value)
    return type(value) == "number" and value == value and value >= 0 and value <= MAX_TYPE
end

--- The kinds of weapon a class can ever hold, in the window's order.
function Weights:WeaponTypesFor(class)
    local list = {}
    local weapons = class and SPECS[class] and SPECS[class].weapons
    if not weapons then return list end
    for _, entry in ipairs(WEAPON_TYPES) do
        if weapons[entry.key] then list[#list + 1] = entry end
    end
    return list
end

--- What a kind of weapon's score is multiplied by for a class and spec: the
--- player's number, or 1.
function Weights:TypeFactor(class, spec, subclassID)
    local custom = self:TypeCustom(class, spec)
    local value = custom and custom[subclassID]
    if UsableType(value) then return value end
    return 1
end

--- True when the player has changed this kind of weapon (or, with none
--- given, any kind) for a class and spec.
function Weights:IsTypeCustom(class, spec, subclassID)
    local custom = self:TypeCustom(class, spec)
    if not custom then return false end
    if subclassID ~= nil then return UsableType(custom[subclassID]) and custom[subclassID] ~= 1 end
    for _, value in pairs(custom) do
        if UsableType(value) and value ~= 1 then return true end
    end
    return false
end

--- Round a typed or stepped number for a kind of weapon: 0 to MAX_TYPE, to
--- two decimals.
function Weights:CleanType(value)
    value = tonumber(value)
    if not value or value ~= value then return nil end
    value = math.max(0, math.min(MAX_TYPE, value))
    return math.floor(value * 100 + 0.5) / 100
end

--- Set what a kind of weapon counts for, for a class and spec. 1 forgets the
--- change.
-- @return the number kept, or nil and why
function Weights:SetTypeFactor(class, spec, subclassID, value)
    if not self:Defaults(class, spec) then return nil, "no such spec" end

    local known = false
    for _, entry in ipairs(self:WeaponTypesFor(class)) do
        if entry.key == subclassID then known = true break end
    end
    if not known then return nil, "no such weapon" end

    value = self:CleanType(value)
    if not value then return nil, "not a number" end

    if math.abs(value - 1) < 0.005 then
        local custom = self:TypeCustom(class, spec)
        if custom then custom[subclassID] = nil end
        value = 1
    else
        self:TypeCustom(class, spec, true)[subclassID] = value
    end

    self:Changed()
    return value
end

-- The client's item class for weapons; see CanUse below.
local WEAPON_CLASS = 2

--- What an item's score is multiplied by under these weights (a table from
--- Get or ForPlayer), from the item's class and subclass: 1 for anything
--- that is not a weapon or whose kind the player left alone.
function Weights:FactorFor(weights, classID, subclassID)
    if classID ~= WEAPON_CLASS or subclassID == nil then return 1 end
    local types = weights and typesOf[weights]
    return types and types[subclassID] or 1
end

--- Something changed what an item is worth: forget the merged tables and
--- redraw everything that shows a verdict.
function Weights:Changed()
    merged = {}
    -- Verdicts kept by the finder were judged with the old weights.
    self.generation = (self.generation or 0) + 1

    if ns.BagIcons then pcall(ns.BagIcons.Refresh, ns.BagIcons) end
    if ns.QuestRewards then pcall(ns.QuestRewards.Refresh, ns.QuestRewards) end
    if ns.LootRolls then pcall(ns.LootRolls.Refresh, ns.LootRolls) end
    if ns.UI then pcall(ns.UI.Refresh, ns.UI) end
    -- The finder's kept picks and the character sheet's slots too.
    if ns.Finder then pcall(ns.Finder.MarkStale, ns.Finder) end
    if ns.FinderUI then pcall(ns.FinderUI.RefreshSoon, ns.FinderUI) end

    -- Tradeskills keeps its upgrade arrows per item until gear or talents
    -- change; tell it to ask again. Read only, inside a pcall, and nothing
    -- happens without Tradeskills. See CLAUDE.md.
    pcall(function()
        local tradeskills = rawget(_G, "BlackthornesTS")
        local upgrades = type(tradeskills) == "table" and tradeskills.Upgrades
        if type(upgrades) == "table" and type(upgrades.RedrawSoon) == "function" then
            upgrades:RedrawSoon()
        end
    end)
end

-- The client's item classes that `armor` and `weapons` above describe.
local CLASS_WEAPON, CLASS_ARMOR = 2, 4

-- Only a weapon goes in these slots, whatever the client says the item is.
local WEAPON_SLOTS = {
    INVTYPE_WEAPON = true, INVTYPE_2HWEAPON = true, INVTYPE_WEAPONMAINHAND = true,
    INVTYPE_WEAPONOFFHAND = true, INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true,
    INVTYPE_THROWN = true,
}

-- The ranged slot's weapons: bows, guns, thrown, crossbows and wands.
local RANGED_SLOTS = { INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true, INVTYPE_THROWN = true }
local RANGED_WEAPONS = { [2] = true, [3] = true, [16] = true, [18] = true, [19] = true }

--- Can this class equip an item of this kind? `equipLoc` is where it goes,
--- when known: a weapon slot makes it a weapon even when the client's class
--- for it is missing, and the ranged slot takes only ranged weapons, so a
--- druid, paladin or shaman is never offered a wand, bow or gun.
-- @return false if never; else true and the level it opens at, or nil when
--         it is open from the start
function Weights:CanUse(class, classID, subclassID, equipLoc)
    local specs = class and SPECS[class]
    if WEAPON_SLOTS[equipLoc] then classID = CLASS_WEAPON end
    local list
    if classID == CLASS_ARMOR then
        list = specs and specs.armor
    elseif classID == CLASS_WEAPON then
        list = specs and specs.weapons
    end
    -- Anything else that goes in a slot (a shirt, a quiver) is not judged by
    -- class, and a class with no list yet is not second-guessed.
    if not list then return true end

    -- A weapon of a kind the client did not say, or something in the ranged
    -- slot that is not a ranged weapon, is never called wearable.
    if subclassID == nil then return false, nil end
    if RANGED_SLOTS[equipLoc] and not RANGED_WEAPONS[subclassID] then return false, nil end

    local level = list[subclassID]
    if not level then return false, nil end
    return true, level > 0 and level or nil
end

-- Body armor kinds, lightest to heaviest: cloth, leather, mail, plate.
local BODY_ARMOR = { [1] = 1, [2] = 2, [3] = 3, [4] = 4 }

--- Is this armor of the heaviest kind the class wears at this level? Only
--- cloth, leather, mail and plate are asked; a cloak (cloth for everyone),
--- rings, necks, trinkets, shields and weapons always pass, and so does a
--- class with no armor list. A heavier kind the class learns later (a
--- warrior's plate before 40) passes too, to be worn then.
function Weights:IsBestArmor(class, level, classID, subclassID, equipLoc)
    if classID ~= CLASS_ARMOR or equipLoc == "INVTYPE_CLOAK" then return true end
    local rank = BODY_ARMOR[subclassID]
    if not rank then return true end
    local list = class and SPECS[class] and SPECS[class].armor
    if not list then return true end
    level = tonumber(level) or 0
    local best = 0
    for kind, opens in pairs(list) do
        if BODY_ARMOR[kind] and opens <= level and BODY_ARMOR[kind] > best then
            best = BODY_ARMOR[kind]
        end
    end
    return rank >= best
end

--- Armor of a kind the class learns later (mail for a hunter or shaman,
--- plate for a warrior or paladin, at 40) is worth holding for Butler only
--- once the character is within KIND_SOON levels of it (the owner,
--- 2026-10-24: a level 5 hunter kept chain leggings for level 40).
Weights.KIND_SOON = 2
function Weights:KindTooFar(class, level, classID, subclassID, equipLoc)
    if classID ~= CLASS_ARMOR or type(level) ~= "number" then return false end
    local ok, opens = self:CanUse(class, classID, subclassID, equipLoc)
    return ok == true and type(opens) == "number" and level < opens - self.KIND_SOON
end

--- The heaviest body armor kind worn now, 0 for none (1 cloth to 4 plate),
--- in the slots given, else in every armor slot.
function Weights.WornArmorRank(slots)
    local Items = ns.Items
    local heaviest = 0
    for _, slot in ipairs(slots or { 1, 3, 5, 6, 7, 8, 9, 10 }) do
        local link = Items and Items:Equipped(slot)
        local info = link and Items:Info(link)
        local rank = info and info.classID == CLASS_ARMOR and BODY_ARMOR[info.subclassID]
        if rank and rank > heaviest then heaviest = rank end
    end
    return heaviest
end

--- Best Armor Only (the owner, 2026-10-18): is this armor lighter than the
--- heaviest kind the character wears? A kind the class learns later (plate
--- or mail at 40) only counts once a piece of it is worn in that slot
--- (`wornRank`), so a warrior who just turned 40 still sees mail for each
--- slot until plate goes in it.
function Weights:IsLighterArmor(class, level, classID, subclassID, equipLoc, wornRank)
    if self:IsBestArmor(class, level, classID, subclassID, equipLoc) then return false end
    local rank = BODY_ARMOR[subclassID]
    local list = SPECS[class].armor
    level = tonumber(level) or 0
    local best = 0
    for kind, opens in pairs(list) do
        local kindRank = BODY_ARMOR[kind]
        if kindRank and opens <= level and kindRank > best
            and (opens <= 1 or (wornRank or 0) >= kindRank) then
            best = kindRank
        end
    end
    return rank < best
end

--- Can this character hold a weapon in the off hand now? The client's
--- CanDualWield answers when it has one; otherwise classic's rule.
function Weights:CanDualWield(class, level)
    if type(CanDualWield) == "function" then
        local ok, can = pcall(CanDualWield)
        if ok and type(can) == "boolean" then return can end
    end
    local from = self:DualWieldLevel(class)
    return from ~= nil and (tonumber(level) or 0) >= from
end

--- The level this class learns to dual wield at, or nil if it never does:
--- warriors and hunters 20, rogues 10, as in classic.
function Weights:DualWieldLevel(class)
    return class and SPECS[class] and SPECS[class].dualWield or nil
end

--- Turn a spec a player typed into its key, or nil.
function Weights:ResolveSpec(text)
    text = (text or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    return ALIASES[text]
end

--------------------------------------------------------------------------------
-- Scoring
--------------------------------------------------------------------------------

-- In case the client does hand school damage over as a stat: a key that
-- names a school (and is not a resistance) is that school's spell damage.
-- /beq probe prints every key it finds, so the real name can be added above.
local SCHOOL_WORDS = {
    ARCANE = "arcaneDamage", FIRE = "fireDamage", FROST = "frostDamage",
    NATURE = "natureDamage", SHADOW = "shadowDamage", HOLY = "holyDamage",
}

local function SchoolKey(key)
    if type(key) ~= "string" then return nil end
    local upper = key:upper()
    if upper:find("RESIST", 1, true) or not upper:find("DAMAGE", 1, true) then return nil end
    for word, name in pairs(SCHOOL_WORDS) do
        if upper:find(word, 1, true) then return name end
    end
    return nil
end

--------------------------------------------------------------------------------
-- Rating to percent
--------------------------------------------------------------------------------

-- A number the client gave, or nil. Inside a pcall: instances hand out
-- secret values that raise when compared.
local function Number(value)
    local ok, answer = pcall(function()
        if type(value) == "number" and value == value and value > 0 and value < 1e7 then return value end
        return nil
    end)
    return ok and answer or nil
end

-- Rating for 1% by combat rating index, kept for the level it was read at.
local ratingPer, ratingLevel = {}, nil

--- How much rating gives 1% (one point, for defense) at the player's
--- level. The client says when it can: by the number it gives for a rating
--- (GetCombatRatingBonusForCombatRatingValue), else by what the player's
--- own rating gives now. Otherwise the usual table: `at60` at level 60,
--- less below it, as (level - 8) / 52 of it from level 10.
function Weights:RatingPer(rating)
    local level = ns.Items and ns.Items:PlayerLevel() or 60
    if level ~= ratingLevel then ratingPer, ratingLevel = {}, level end
    local index = _G[rating.cr]
    if type(index) ~= "number" then index = rating.index end
    if ratingPer[index] then return ratingPer[index] end

    local Call = ns.Items and ns.Items.Call
    local per
    if Call then
        local gives = Number((Call({ "GetCombatRatingBonusForCombatRatingValue" }, index, 100)))
        if gives then per = 100 / gives end
        if not per then
            local have = Number((Call({ "GetCombatRating" }, index)))
            local bonus = have and Number((Call({ "GetCombatRatingBonus" }, index)))
            if bonus then per = have / bonus end
        end
    end
    if not per or per <= 0 then
        local scale = level >= 10 and (level - 8) / 52 or 2 / 52
        per = rating.at60 * math.min(scale, 1)
    end
    ratingPer[index] = per
    return per
end

--- Forget the rates, so the next item reads them again (a level up).
function Weights:ForgetRatings()
    ratingPer, ratingLevel = {}, nil
end

--- Convert what GetItemStats returned into the names above. Keys this addon
--- does not know are returned separately so the probe can show them.
--- Ratings come back as the percent they give.
function Weights:Normalize(clientStats)
    local stats, unknown = {}, {}
    for key, value in pairs(clientStats or {}) do
        local rating = RATINGS[key]
        local name = rating and rating.stat or STAT_KEYS[key] or SchoolKey(key)
        if name and type(value) == "number" then
            if rating then value = value / self:RatingPer(rating) end
            stats[name] = (stats[name] or 0) + value
        else
            unknown[#unknown + 1] = key
        end
    end
    table.sort(unknown)
    return stats, unknown
end

--- Lay school damage read off the tooltip (Items:SchoolDamage) over the
--- normalized stats. A school the client's stats already gave is left as it
--- is, so the same line is never counted twice.
function Weights:AddSchools(stats, schools)
    if type(stats) ~= "table" or type(schools) ~= "table" then return stats end
    for name, value in pairs(schools) do
        if stats[name] == nil and type(value) == "number" then stats[name] = value end
    end
    return stats
end

--- Which hit the spec cares about: "melee" (weapons) or "spell", and its
--- weight. Nil when it weighs neither.
function Weights.HitKind(weights)
    local melee, spell = weights and weights.hit or 0, weights and weights.spellHit or 0
    if melee <= 0 and spell <= 0 then return nil, 0 end
    if spell > melee then return "spell", spell end
    return "melee", melee
end

--- One number for how good a set of stats is: each stat times its weight.
-- `ranged` says whether weapon dps counts as a ranged or a melee weapon.
-- The second return is how much hit, in percent, counts toward the hit the
-- spec cares about (HitKind), so Compare can stop counting it at the cap.
function Weights:Score(stats, weights, ranged)
    local score = 0
    for name, value in pairs(stats or {}) do
        local weight
        if name == "dps" then
            -- Not `ranged and rangedDps or meleeDps`: a spec with no ranged
            -- weight would then count a bow's damage as melee damage.
            if ranged then weight = weights.rangedDps else weight = weights.meleeDps end
        elseif EITHER[name] then
            local pair = EITHER[name]
            weight = math.max(weights[pair[1]] or 0, weights[pair[2]] or 0)
        else
            weight = weights[name]
        end
        if weight then
            score = score + value * weight
        end
    end

    local kind = Weights.HitKind(weights)
    local hit = 0
    if kind and stats then
        hit = (stats.anyHit or 0) + (kind == "spell" and (stats.spellHit or 0) or (stats.hit or 0))
    end
    return score, hit
end

--------------------------------------------------------------------------------
-- /beq spec
--------------------------------------------------------------------------------

local WHY = {
    picked = L["you picked it"],
    talents = L["from your talent points"],
    default = L["the default until you spend talent points"],
}

local function ShowSpec()
    local spec, why, class = Weights:CurrentSpec()
    if not spec then
        ns.Print(L.Format("no stat weights for %s yet", class or L["this class"]))
        return
    end
    ns.Print(L.Format("judging gear as |c%s%s|r (%s)",
        ns.COLORS.accent, Weights:SpecName(class, spec), WHY[why]))
end

ns.RegisterCommand("spec", L["show the spec gear is judged for, or pick one by name (or auto)"],
    function(rest)
        rest = (rest or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
        if rest == "" then
            ShowSpec()
            return
        end

        if rest == "auto" then
            ns.charDB.spec = nil
            Weights:Changed()
            ShowSpec()
            return
        end

        local spec = Weights:ResolveSpec(rest)
        local class = Weights:PlayerClass()
        if not spec or not (class and SPECS[class] and SPECS[class][spec]) then
            local names = {}
            for _, key in ipairs(class and SPECS[class] and SPECS[class].order or {}) do
                names[#names + 1] = key
            end
            names[#names + 1] = "auto"
            ns.Warn(L.Format("%s isn't a spec (try %s)", rest, table.concat(names, ", ")))
            return
        end

        ns.charDB.spec = spec
        -- Every verdict can change with the spec, Tradeskills' arrows too.
        Weights:Changed()
        ShowSpec()
    end)
