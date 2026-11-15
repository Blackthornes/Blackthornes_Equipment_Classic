-- Caster power is two totals (2026-11-12, a player's report): damage and
-- healing gear counts toward both, damage-only toward spell power, healing
-- toward healing, and an item that sends power and healing together is
-- never counted twice.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("spellhealing")

local ns = env.Load()
local Weights = ns.Weights

local function near(a, b) return math.abs((a or 0) - (b or 0)) < 1e-6 end

-- "Damage and healing" alone counts in both totals.
local s = Weights:Normalize({ ITEM_MOD_SPELL_POWER_SHORT = 32 })
suite.check("combined power counts as damage", near(s.spellPower, 32), s.spellPower)
suite.check("combined power counts as healing", near(s.healing, 32), s.healing)

-- Damage only and healing only stay apart.
s = Weights:Normalize({ ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = 10 })
suite.check("damage only is spell power", near(s.spellPower, 10) and s.healing == nil)
s = Weights:Normalize({ ITEM_MOD_SPELL_HEALING_DONE_SHORT = 22 })
suite.check("healing only is healing", near(s.healing, 22) and s.spellPower == nil)

-- Sent as two separate totals.
s = Weights:Normalize({ ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = 16, ITEM_MOD_SPELL_HEALING_DONE_SHORT = 48 })
suite.check("separate totals: damage 16", near(s.spellPower, 16), s.spellPower)
suite.check("separate totals: healing 48", near(s.healing, 48), s.healing)

-- Sent as combined power plus a healing total: the healing line is the
-- whole healing figure, never added on top.
s = Weights:Normalize({ ITEM_MOD_SPELL_POWER_SHORT = 16, ITEM_MOD_SPELL_HEALING_DONE_SHORT = 48 })
suite.check("power plus healing: damage 16", near(s.spellPower, 16), s.spellPower)
suite.check("power plus healing: healing 48, not 64", near(s.healing, 48), s.healing)

-- Other stats still come through beside it.
s = Weights:Normalize({ ITEM_MOD_SPELL_POWER_SHORT = 5, ITEM_MOD_INTELLECT_SHORT = 7 })
suite.check("intellect still read", near(s.intellect, 7) and near(s.spellPower, 5) and near(s.healing, 5))

-- The report: a hybrid priest weighing both. 32 damage and healing beats
-- 16 damage and 48 healing.
local w = { spellPower = 0.9, healing = 0.5, intellect = 0.85, spirit = 0.85 }
local rod = Weights:Score(Weights:Normalize({ ITEM_MOD_SPELL_POWER_SHORT = 32 }), w)
local staff = Weights:Score(Weights:Normalize({ ITEM_MOD_SPELL_POWER_SHORT = 16, ITEM_MOD_SPELL_HEALING_DONE_SHORT = 48 }), w)
suite.check("both-ways power is no longer scored low", rod > staff, rod, staff)

-- A caster that weighs no healing scores it exactly as before.
local mage = { spellPower = 1 }
suite.check("damage-only caster unchanged",
    near(Weights:Score(Weights:Normalize({ ITEM_MOD_SPELL_POWER_SHORT = 20 }), mage), 20))

-- Pure healers: healing gear beats the same amount of damage-only gear.
for _, pair in ipairs({ { "PRIEST", "holy" }, { "DRUID", "resto" }, { "SHAMAN", "resto" }, { "PALADIN", "holy" } }) do
    local spec = Weights.SPECS[pair[1]][pair[2]]
    local hw = spec and spec.weights or {}
    suite.check(pair[1] .. " " .. pair[2] .. " weighs healing over damage", (hw.healing or 0) > (hw.spellPower or 0))
end

suite.done()
