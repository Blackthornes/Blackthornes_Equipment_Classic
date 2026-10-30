-- Where to get upgrades, slot by slot: the slots down the left with how many
-- upgrades each has, every upgrade for the slot picked, tick boxes for the
-- sources (raids apart from dungeons), and "Only what I can get now".

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("finderslots")

local function Agi(n) return { ITEM_MOD_AGILITY_SHORT = n } end
local function Gear(loc, n) return { loc = loc, class = 4, subclass = 2, stats = Agi(n) } end
local function Ring(n) return { loc = "INVTYPE_FINGER", class = 4, subclass = 0, stats = Agi(n) } end

local ITEMS = {
    ["item:900"] = Gear("INVTYPE_CHEST", 10),   -- worn
    ["item:901"] = Ring(5),                     -- worn, first ring
    ["item:902"] = Ring(6),                     -- worn, second ring
    ["item:1001"] = Gear("INVTYPE_CHEST", 20),  -- a vendor's
    ["item:1002"] = Gear("INVTYPE_CHEST", 40),  -- a dungeon drop
    ["item:1003"] = Gear("INVTYPE_CHEST", 60),  -- a raid drop
    ["item:1004"] = Gear("INVTYPE_CHEST", 30),  -- a reputation not reached
    ["item:1101"] = Ring(20),
    ["item:1102"] = Ring(30),
}
-- The level each can be worn from, as the client says it.
for id, level in pairs({ [1001] = 15, [1002] = 15, [1003] = 20, [1004] = 15 }) do
    ITEMS["item:" .. id].minLevel = level
end

local ns = env.Load()
_G.UnitClass = function() return "Hunter", "HUNTER", 3 end
_G.UnitFactionGroup = function() return "Alliance", "Alliance" end
_G.UnitRace = function() return "Human", "Human", 1 end
_G.GetRealZoneText = function() return "Elwynn Forest" end
env.InstallItems(ITEMS, { [5] = "item:900", [11] = "item:901", [12] = "item:902" }, { [0] = {} }, 25)
_G.C_QuestLog = { IsQuestFlaggedCompleted = function() return false end }
_G.C_Reputation = { GetFactionDataByID = function() return { reaction = 4 } end }

local S = ns.Sources
ns.Crafts.ITEMS = {}
ns.RollData.ITEMS = {}
S.ZONES = { [12] = "Elwynn Forest" }
S.NPCS = { [1] = { "Corina Steele", 12, 41.5, 65.9, "A" } }
S.QUESTS = {}
S.DUNGEONS = {
    ["36"] = { "The Deadmines", 17, 26, "Westfall", "" },
    ["409"] = { "Molten Core", 20, 25, "Blackrock Mountain", "", true },
}
S.BOSSES = {
    [100] = { "Edwin VanCleef", "36", 21 },
    [101] = { "Ragnaros", "409", 25 },
}
S.FOREVER = {}
S.ITEMS = {
    [1001] = { 15, 18, 0, 0, 500, v = { 1, 0 } },
    [1002] = { 15, 20, 0, 0, 0, d = { 100, 20 } },
    [1003] = { 20, 25, 0, 0, 0, d = { 101, 10 } },
    [1004] = { 15, 18, 0, 0, 500, v = { 1, 0 }, r = { 72, 6 } },
    [1101] = { 15, 18, 0, 0, 500, v = { 1, 0 } },
    [1102] = { 15, 18, 0, 0, 500, v = { 1, 0 } },
}

local UI = ns.FinderUI

local function Listed()
    local ids = {}
    for _, line in ipairs(UI.lines or {}) do ids[#ids + 1] = line.pick.itemID end
    return table.concat(ids, ",")
end
local function Button(key)
    for _, button in ipairs(UI.slotButtons) do if button.group == key then return button end end
end
local function Box(kind)
    for _, box in ipairs(UI.sourceBoxes) do if box.kind == kind then return box end end
end

suite.check("a slot line for each of the 15", #UI.SLOT_GROUPS == 15)
suite.check("both rings share a line, and both trinkets", UI.GROUP_OF[12] == 11 and UI.GROUP_OF[14] == 13)

-- An old saved choice of one source reads as gear, every source ticked.
ns.db.finderShow = "vendor"
UI:Show()
suite.check("an old one-source choice shows gear", not UI:ShowingEnchants())
suite.check("the tick boxes in order", Box("vendor") and Box("quest") and Box("dungeon") and Box("raid")
    and Box("craft") and #UI.sourceBoxes == 5)
suite.check("worded for players", Box("dungeon").label:GetText() == "Dungeons" and Box("raid").label:GetText() == "Raids",
    Box("dungeon").label:GetText())
suite.check("Only what I can get now starts unticked", ns.db.finderGetNow == false and not UI.getNow:GetChecked())
suite.check("named as approved", UI.getNow.label:GetText() == "Only What I Can Get Now")

suite.check("the first slot with upgrades shows, chest", UI.slot == 5, UI.slot)
suite.check("every upgrade for it, best first", Listed() == "1003,1002,1001,1004", Listed())
suite.check("the slot counts them", Button(5).count:GetText() == "4")
suite.check("the rings line counts both rings' upgrades once", Button(11).count:GetText() == "2",
    Button(11).count:GetText())
suite.check("a slot with nothing counts 0", Button(1).count:GetText() == "0")
suite.check("nothing hidden, the footer says nothing", UI.footer:GetText() == "",
    UI.footer:GetText())
suite.check("the heading names the slot", UI.listTitle:GetText() == "Chest")
suite.check("and the order", UI.sortLabel:GetText():find("Best first", 1, true) ~= nil)

-- The headings sort: a click sorts, a second flips, a third goes back.
local function Heading(key)
    for _, heading in ipairs(UI.columnHeads) do if heading.key == key then return heading end end
end
suite.check("four headings, as approved", Heading("item").label:GetText() == "ITEM"
    and Heading("level").label:GetText() == "LEVEL" and Heading("where").label:GetText() == "WHERE"
    and Heading("gain").label:GetText() == "GAIN" and #UI.columnHeads == 4)
Heading("level"):GetScript("OnClick")(Heading("level"))
suite.check("Level sorts low to high", Listed() == "1002,1001,1004,1003", Listed())
suite.check("the Sort line says so", UI.sortLabel:GetText():find("Level", 1, true) ~= nil
    and UI.sortArrow:IsShown() and Heading("level").arrow:IsShown(), UI.sortLabel:GetText())
Heading("level"):GetScript("OnClick")(Heading("level"))
suite.check("a second click flips it", Listed() == "1003,1004,1001,1002" and UI.sortFlip == true, Listed())
Heading("level"):GetScript("OnClick")(Heading("level"))
suite.check("a third goes back to best first", Listed() == "1003,1002,1001,1004"
    and UI.sortLabel:GetText():find("Best first", 1, true) ~= nil and not UI.sortArrow:IsShown(), Listed())
Heading("where"):GetScript("OnClick")(Heading("where"))
suite.check("Where sorts A to Z, a dungeon by its name", Listed() == "1001,1004,1003,1002", Listed())
Heading("gain"):GetScript("OnClick")(Heading("gain"))
suite.check("another heading starts again, Gain biggest first", Listed() == "1003,1002,1004,1001"
    and UI.sortKey == "gain" and not UI.sortFlip and not Heading("where").arrow:IsShown(), Listed())
Heading("gain"):GetScript("OnClick")(Heading("gain"))
Heading("gain"):GetScript("OnClick")(Heading("gain"))
suite.check("and back to best first", Listed() == "1003,1002,1001,1004" and UI.sortKey == nil, Listed())
suite.check("each row shows its level and where", UI.rows[1].level:GetText() == "20"
    and UI.rows[1].where:GetText():find("Molten Core", 1, true) ~= nil, UI.rows[1].level:GetText())
Heading("item"):GetScript("OnEnter")(Heading("item"))
suite.check("the heading's hover says how", table.concat(GameTooltip._lines or {}, "\n"):find("Click a heading to sort.", 1, true) ~= nil)
Heading("item"):GetScript("OnLeave")(Heading("item"))

-- Raids apart from dungeons.
Box("raid"):GetScript("OnClick")(Box("raid"))
suite.check("unticking Raids leaves the raid drop out", Listed() == "1002,1001,1004", Listed())
suite.check("and is kept", ns.db.finderSourcesOff.raid == true and not ns.db.finderSourcesOff.dungeon)
suite.check("the count follows", Button(5).count:GetText() == "3")
suite.check("the footer says how many are left out", UI.footer:GetText() == "Your filters hide 1 more.")
Box("dungeon"):GetScript("OnClick")(Box("dungeon"))
suite.check("unticking Dungeons too leaves the vendors'", Listed() == "1001,1004", Listed())
Box("raid"):GetScript("OnClick")(Box("raid"))
Box("dungeon"):GetScript("OnClick")(Box("dungeon"))
suite.check("ticked again, all four", Listed() == "1003,1002,1001,1004" and next(ns.db.finderSourcesOff) == nil)

-- Only what I can get now: no gear waiting on a reputation.
UI.getNow:GetScript("OnClick")(UI.getNow)
suite.check("ticked, it is kept", ns.db.finderGetNow == true)
suite.check("and the reputation gear goes", Listed() == "1003,1002,1001", Listed())
UI.getNow:GetScript("OnClick")(UI.getNow)
suite.check("unticked, it comes back", Listed() == "1003,1002,1001,1004", Listed())
suite.check("a craft nobody of yours makes yet waits", not UI.GetsNow({ kind = "craft", state = "learn" }, {})
    and UI.GetsNow({ kind = "craft", state = "alt" }, {}) and UI.GetsNow({ kind = "vendor" }, {}))

-- A click on a slot shows it and is kept for next time.
Button(11):GetScript("OnClick")(Button(11))
suite.check("Rings shows both rings' upgrades, best first", Listed() == "1102,1101" and ns.db.finderSlot == 11,
    Listed())
suite.check("it lights", UI.slot == 11 and Button(11).edge:IsShown())
suite.check("and the heading says Rings", UI.listTitle:GetText() == "Rings")
UI:Hide()
UI:Show()
suite.check("opened again, the slot last clicked", UI.slot == 11)
Button(1):GetScript("OnClick")(Button(1))
suite.check("a slot with nothing says so", UI.empty:IsShown() and Listed() == "")
UI:Hide()
UI:Show()
suite.check("opened again with nothing there, the first that has something", UI.slot == 5, UI.slot)

suite.done()
