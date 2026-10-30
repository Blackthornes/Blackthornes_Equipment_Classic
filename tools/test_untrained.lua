-- An upgrade whose weapon skill is not trained yet (a player found a staff
-- offered to a warrior who had not learned Staves, 2026-10-11): still an
-- upgrade, but no Put it on; its banner offers the weapon master or to
-- ignore the type until trained, and learning the skill brings the usual
-- banner.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("untrained")

local function Weapon(subclass, strength)
    return { loc = "INVTYPE_2HWEAPON", class = 2, subclass = subclass,
        stats = { ITEM_MOD_STRENGTH_SHORT = strength } }
end

local ITEMS = {
    ["item:1"] = Weapon(1, 10),   -- a two-handed axe, worn
    ["item:2"] = Weapon(10, 20),  -- a staff, better
    ["item:3"] = Weapon(8, 20),   -- a two-handed sword, trained
}

local ns = env.Load()
_G.UnitClass = function() return "Warrior", "WARRIOR" end
_G.UnitFactionGroup = function() return "Horde" end
local known = { [196] = true, [197] = true, [202] = true }   -- axes, two-handed axes and swords
_G.IsPlayerSpell = function(id) return known[id] == true end
env.InstallItems(ITEMS, { [16] = "item:1" }, { [0] = {} })

local Compare = ns.Compare
local result = Compare:JudgeCarried("item:2")
suite.check("an untrained staff is still an upgrade", result and result.verdict == "upgrade",
    result and result.verdict)
suite.check("that needs Staves", result.skill == "Staves", result.skill)
local line = Compare:Describe(result)
suite.check("the tooltip says once you train it",
    line and line:find("Upgrade for Arms once you train Staves", 1, true), line)
suite.check("a trained sword needs nothing", Compare:JudgeCarried("item:3").skill == nil)

-- The gear window's best in bags: a staff at +100% would hide the sword at
-- +100% the character can wear, so the trained one wins whatever the gain.
env.bags[0][1], env.bags[0][2] = "item:2", "item:3"
local best = Compare:BestInBags()[16]
suite.check("the trained sword is the one offered", best and best.link == "item:3",
    best and best.link)
env.bags[0][2] = nil
best = Compare:BestInBags()[16]
suite.check("alone, the staff is still listed", best and best.link == "item:2"
    and best.result.skill == "Staves", best and best.link)
env.bags[0][1] = nil

env.bags[0][1] = "item:2"
_G.C_Item.EquipItemByName = function() end
_G.InCombatLockdown = function() return false end
local can, why = ns.Wear:Can("item:2")
suite.check("it can't be put on", can == false and why == "train Staves first", why)
local advice = ns.Butler:Advise("item:2", 0, 1)
suite.check("Butler hears it is for later", advice and advice.upgrade == "later",
    advice and advice.upgrade)
env.bags[0][1] = nil

-- The weapon master: the first listed, or the one in the city you're in.
local place = ns.WeaponSkills:Master("item:2")
suite.check("Hanashi in Orgrimmar teaches it", place and place.name == "Hanashi"
    and place.zone == "Orgrimmar" and place.x == 81.5, place and place.name)
_G.GetRealZoneText = function() return "Thunder Bluff" end
place = ns.WeaponSkills:Master("item:2")
suite.check("in Thunder Bluff, Ansekhwa", place and place.name == "Ansekhwa", place and place.name)
_G.GetRealZoneText = nil
suite.check("a trained weapon has no master to show", ns.WeaponSkills:Master("item:3") == nil)

-- The banner draws its own buttons in a row along its foot, instead of
-- Put it on, and grows to fit a long weapon name.
ns.Toast:Show({ title = "Upgrade once you train Two-Handed Swords", link = "item:2",
    actions = { { text = "Show the trainer", fn = function() end },
        { text = "Ignore Two-Handed Swords", fn = function() end } } })
local toast = ns.Toast
suite.check("the banner shows both buttons", toast.actions[1]:IsShown() and toast.actions[2]:IsShown())
suite.check("and no Put it on", not toast.wear:IsShown())
suite.check("named as given", toast.actions[2].label:GetText() == "Ignore Two-Handed Swords")
suite.check("a row taller", toast.frame:GetHeight() == 104, toast.frame:GetHeight())
suite.check("wide enough for both", toast.frame:GetWidth() >= toast.actions[1]:GetWidth()
    + toast.actions[2]:GetWidth() + 32, toast.frame:GetWidth())
toast:Dismiss()
ns.Toast:Show({ title = "Upgrade in your bags", link = "item:3" })
suite.check("a plain banner hides them again", not toast.actions[1]:IsShown()
    and toast.frame:GetHeight() == 74)
toast:Dismiss()

-- The banner when it lands in the bags.
local banners = {}
ns.Toast.Show = function(_, banner) banners[#banners + 1] = banner return true end
local UpgradeChat = ns.UpgradeChat
UpgradeChat:OnEnable()
UpgradeChat:Scan()
env.bags[0][1] = "item:2"
UpgradeChat:Scan()
suite.check("chat says it waits on training",
    env.ChatText():find("upgrade in your bags once you train Staves: item:2", 1, true), env.ChatText())
local banner = banners[1]
suite.check("one banner", #banners == 1 and banner.title == "Upgrade once you train Staves",
    banner and banner.title)
suite.check("with no Put it on", banner.wear == nil)
suite.check("but the trainer and Ignore", #banner.actions == 2
    and banner.actions[1].text == "Show the trainer" and banner.actions[2].text == "Ignore Staves")

-- Show the trainer: the quest arrow points at him.
local aimed
ns.QuestArrow.AimAtQuest = function(_, questID, title, where)
    aimed = { questID = questID, title = title, where = where }
    return true
end
banner.actions[1].fn()
suite.check("the arrow points at the weapon master", aimed and aimed.questID == nil
    and aimed.title == "Learn Staves" and aimed.where.zone == "Orgrimmar"
    and aimed.where.name == "Hanashi", aimed and aimed.title)
suite.check("and chat says where", env.ChatText():find("Hanashi teaches Staves, in Orgrimmar (82, 20)", 1, true),
    env.ChatText())

-- Ignore: not an upgrade at all until trained.
local redrawn = 0
local Changed = ns.Weights.Changed
ns.Weights.Changed = function(...) redrawn = redrawn + 1 return Changed(...) end
banner.actions[2].fn()
suite.check("ignoring is kept for this character", ns.charDB.ignoredWeaponTypes[10] == true)
suite.check("and redraws the verdicts", redrawn == 1)
result = Compare:JudgeCarried("item:2")
suite.check("the staff is no longer for this character", result.verdict == "cantuse")
suite.check("the tooltip says why", Compare:Describe(result) == "Ignored until you train Staves",
    Compare:Describe(result))
suite.check("nor an upgrade now", not Compare:IsUpgradeNow("item:2", true))
suite.check("Settings names it", ns.SettingsUI:WeaponsHint():find("Ignored until you train them: Staves", 1, true))

-- Learning Staves brings it back by itself, banner and all.
banners = {}
known[227] = true
ns.WeaponSkills:Learned()
suite.check("trained, it is an upgrade to wear now", Compare.WearableUpgrade(Compare:JudgeCarried("item:2"))
    and Compare:JudgeCarried("item:2").skill == nil)
ns.WeaponSkills:ShowAll()
known[227] = nil
ns.WeaponSkills:Learned()
suite.check("show them clears the list", next(ns.charDB.ignoredWeaponTypes) == nil)

-- An untrained upgrade waiting in the bags, then the skill learned.
UpgradeChat.untrained = { ["item:2"] = true }
banners = {}
known[227] = true
ns.WeaponSkills:Learned()
suite.check("learning it brings the usual banner", #banners == 1 and banners[1].title == "Ready to wear"
    and banners[1].wear == true, banners[1] and banners[1].title)
suite.check("and chat says so", env.ChatText():find("you can wear item:2 now", 1, true), env.ChatText())
suite.check("said once", next(UpgradeChat.untrained) == nil)

-- /beq weapons.
ns.charDB.ignoredWeaponTypes = { [10] = true }
ns.HandleSlash("weapons")
suite.check("/beq weapons lists them", env.chat[#env.chat]:find("ignored until you train them: Staves", 1, true),
    env.chat[#env.chat])
ns.HandleSlash("weapons show")
suite.check("/beq weapons show clears them", next(ns.charDB.ignoredWeaponTypes) == nil)

-- Settings, Untrained Weapons: Hide keeps every untrained weapon out of the
-- upgrades for this character; Show brings them back, banner ignores too.
known[227] = nil
ns.WeaponSkills:Learned()
suite.check("shown, the staff is an upgrade", Compare:JudgeCarried("item:2").verdict == "upgrade")
ns.WeaponSkills:HideAll(true)
suite.check("Hide is kept for this character", ns.charDB.hideUntrainedWeapons == true)
result = Compare:JudgeCarried("item:2")
suite.check("hidden, the staff is not for this character", result.verdict == "cantuse"
    and result.ignoredSkill == "Staves", result.verdict)
suite.check("a trained sword still is", Compare:JudgeCarried("item:3").verdict == "upgrade")
suite.check("Settings says they're hidden", ns.SettingsUI:WeaponsHint()
    == "Weapons you haven't trained don't show as upgrades until you train them.")
ns.charDB.ignoredWeaponTypes = { [10] = true }
suite.check("Show clears both", ns.WeaponSkills:ShowAll(true) and ns.charDB.hideUntrainedWeapons == nil
    and next(ns.charDB.ignoredWeaponTypes) == nil)
suite.check("and the staff is back", Compare:JudgeCarried("item:2").verdict == "upgrade")
ns.HandleSlash("weapons hide")
suite.check("/beq weapons hide hides them", ns.charDB.hideUntrainedWeapons == true)
ns.HandleSlash("weapons show")
suite.check("/beq weapons show shows them", ns.charDB.hideUntrainedWeapons == nil)

-- An upgrade quest already on the staff (followed by hand) is let go as
-- soon as untrained weapons are hidden, and stays with them shown.
ns.db.upgradeQuest = true
local function StaffQuest()
    ns.charDB.upgradeQuestTabs = { vendor = { itemID = 2, link = "item:2", followed = true,
        source = { kind = "vendor" } } }
end
StaffQuest()
ns.UpgradeQuest:Check()
suite.check("shown, the staff quest stays", ns.charDB.upgradeQuestTabs.vendor ~= nil
    and ns.charDB.upgradeQuestTabs.vendor.itemID == 2)
ns.WeaponSkills:HideAll(true)
local staffLeft = ns.charDB.upgradeQuestTabs.vendor
suite.check("Hide lets the staff quest go", staffLeft == nil or staffLeft.itemID ~= 2)
ns.WeaponSkills:ShowAll(true)
StaffQuest()
ns.charDB.ignoredWeaponTypes = { [10] = true }
ns.UpgradeQuest:Check()
staffLeft = ns.charDB.upgradeQuestTabs.vendor
suite.check("a type ignored from a banner lets it go too", staffLeft == nil or staffLeft.itemID ~= 2)
ns.WeaponSkills:ShowAll(true)
ns.charDB.upgradeQuestTabs = {}
ns.db.upgradeQuest = nil

-- The Settings row is a Show or Hide stepper that follows the save.
ns.SettingsUI:Show()
local stepper = ns.SettingsUI.controls.weapons
suite.check("the row reads Show", stepper and stepper.text:GetText() == "Show", stepper and stepper.text:GetText())
stepper:SetValue(0)
suite.check("picking Hide hides them", stepper.text:GetText() == "Hide" and ns.charDB.hideUntrainedWeapons == true)
stepper:SetValue(1)
suite.check("picking Show shows them", stepper.text:GetText() == "Show" and ns.charDB.hideUntrainedWeapons == nil)
ns.charDB.ignoredWeaponTypes = { [10] = true }
ns.SettingsUI:Refresh()
suite.check("a type ignored from a banner reads Hide", stepper.text:GetText() == "Hide")
stepper:SetValue(1)
suite.check("and Show clears it", next(ns.charDB.ignoredWeaponTypes) == nil)

suite.done()
