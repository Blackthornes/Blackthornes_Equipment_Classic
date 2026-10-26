-- The settings window.
--
-- What matters is that every way in opens it, that each control changes the
-- same saved value its chat command does, and that the page shows what is
-- saved rather than what it last drew.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("settings")

local ns = env.Load()
_G.UnitClass = function() return "Hunter", "HUNTER" end

local SettingsUI = ns.SettingsUI

-- A client with retail's Settings API, recording what is registered.
local registered = {}
_G.Settings = {
    RegisterCanvasLayoutCategory = function(panel, name) return { panel = panel, name = name } end,
    RegisterAddOnCategory = function(category) registered[#registered + 1] = category end,
}

for _, module in ipairs(ns.moduleOrder) do
    if module.OnEnable then module:OnEnable() end
end

suite.check("it is listed under the game's AddOns options",
    registered[1] and registered[1].name == "Blackthornes Equipment")

-- Ways in.
ns.HandleSlash("settings")
suite.check("/beq settings opens it", SettingsUI.frame:IsShown())
ns.HandleSlash("settings")
suite.check("and closes it", not SettingsUI.frame:IsShown())
ns.HandleSlash("options")
suite.check("/beq options works too", SettingsUI.frame:IsShown())
suite.check("options is not listed twice in help",
    not (function()
        for _, name in ipairs(ns.commandOrder) do
            if name == "options" or name == "config" then return true end
        end
    end)())

local controls = SettingsUI.controls

-- The spec stepper.
suite.check("the spec starts on Auto", controls.spec:GetValue() == 1)
suite.check("which reads Auto", controls.spec.text:GetText() == "Auto", controls.spec.text:GetText())

-- Effects: Full until picked, so nobody's windows change.
suite.check("effects start at Full", ns.Motion.Level() == "full" and controls.effects.text:GetText() == "Full",
    controls.effects.text:GetText())
controls.effects:SetValue(2)
suite.check("Subtle is kept", ns.db.effectsLevel == "subtle" and ns.Motion.Level() == "subtle")
controls.effects:SetValue(3)
suite.check("Off is kept", ns.db.effectsLevel == "off" and ns.Motion.Level() == "off")
controls.effects:SetValue(1)
suite.check("Full saves nothing", ns.db.effectsLevel == nil and ns.Motion.Level() == "full")
suite.check("and says what Auto means now",
    SettingsUI.specRow.hint:GetText():find("Beast Mastery until your talents", 1, true),
    SettingsUI.specRow.hint:GetText())

controls.spec:SetValue(3)
suite.check("stepping to Marksmanship picks it", ns.charDB.spec == "marks", ns.charDB.spec)
suite.check("the stepper shows its name",
    controls.spec.text:GetText() == "Marksmanship", controls.spec.text:GetText())
suite.check("and the hint says it was picked",
    SettingsUI.specRow.hint:GetText():find("because you picked it", 1, true))

ns.HandleSlash("spec sv")
suite.check("/beq spec while it is open moves the stepper",
    controls.spec:GetValue() == 4 and controls.spec.text:GetText() == "Survival",
    controls.spec.text:GetText())

controls.spec:SetValue(1)
suite.check("stepping back to Auto clears the pick", ns.charDB.spec == nil)

-- Every verdict can change with the spec: quest rewards and Tradeskills'
-- arrows are drawn again too, not only the bag arrows.
local asked, rewards = 0, 0
_G.BlackthornesTS = { Upgrades = { RedrawSoon = function() asked = asked + 1 end } }
local QuestRefresh = ns.QuestRewards.Refresh
ns.QuestRewards.Refresh = function(...) rewards = rewards + 1; return QuestRefresh(...) end
local function Told() return ("%d/%d"):format(asked, rewards) end

controls.spec:SetValue(2)
suite.check("picking a spec redraws quest rewards and Tradeskills' arrows",
    asked == 1 and rewards == 1, Told())
ns.HandleSlash("spec mm")
suite.check("and so does /beq spec", asked == 2 and rewards == 2, Told())
ns.HandleSlash("spec auto")
suite.check("and /beq spec auto", asked == 3 and rewards == 3 and ns.charDB.spec == nil, Told())

ns.QuestRewards.Refresh = QuestRefresh
_G.BlackthornesTS = nil

-- The minimap button always shows (the owner, 2026-10-15), so it has no
-- row here.
suite.check("there is no minimap box", controls.minimap == nil)

-- Debug, the speed check and the client check are typed only (the owner,
-- 2026-10-23): no row for them, and help leaves them out.
suite.check("there is no debug box", controls.debug == nil and controls.probe == nil)
ns.HandleSlash("debug")
suite.check("/beq debug turns debug on", ns.db.debug == true)
ns.HandleSlash("debug off")
suite.check("/beq debug off turns it off", ns.db.debug == false)
local listed = {}
for _, name in ipairs(ns.commandOrder) do listed[name] = true end
suite.check("help leaves out debug, probe and perf",
    not listed.debug and not listed.probe and not listed.perf
    and ns.commands.debug and ns.commands.probe and ns.commands.perf)

-- The sister note (Core/SisterNote.lua).
suite.check("the sister addons box starts ticked", controls.sisters:GetChecked())
controls.sisters:GetScript("OnClick")(controls.sisters)
suite.check("unticking it turns the note off", ns.db.sisterNote == false)
ns.HandleSlash("sisters")
suite.check("/beq sisters turns it back on", ns.db.sisterNote == true and controls.sisters:GetChecked())

-- The verdict switches.
suite.check("the tooltip line starts on Always", controls.tooltip:GetValue() == 2, controls.tooltip:GetValue())
suite.check("so does the bag arrows box", controls.arrows:GetChecked())
controls.arrows:GetScript("OnClick")(controls.arrows)
suite.check("unticking it switches the arrows off", ns.db.bagArrows == false, ns.db.bagArrows)
controls.tooltip:SetValue(0)
suite.check("and Off turns the tooltip line off", ns.db.tooltipLine == false, ns.db.tooltipLine)
suite.check("the upgrade in chat box starts ticked", controls.upgradeChat:GetChecked())
controls.upgradeChat:GetScript("OnClick")(controls.upgradeChat)
suite.check("unticking it switches the chat line off", ns.db.upgradeChat == false, ns.db.upgradeChat)

-- The pages along the top, as Tradeskills' Settings tab has them.
local pages = SettingsUI.pages
suite.check("it opens on the first page", pages.shown == "gear", pages.shown)
suite.check("with the gear rows showing", pages.pages.gear.content:IsShown()
    and not pages.pages.general.content:IsShown())
local generalPart
for _, part in ipairs(pages.switch) do
    if part.key == "general" then generalPart = part end
end
generalPart.button:GetScript("OnClick")(generalPart.button)
suite.check("a click on the switch shows that page", pages.pages.general.content:IsShown()
    and not pages.pages.gear.content:IsShown())
suite.check("and the page is remembered", ns.db.settingsPage == "general")
suite.check("the page picked is gold", generalPart.label._color[1] == ns.Theme.colors.accent[1])
SettingsUI:Hide()
SettingsUI:Show()
suite.check("it opens again on the page left", pages.shown == "general")

-- Every page has rows, and the window is at least two columns wide.
-- About (UI/About.lua) has its note and its facts instead.
for _, page in pairs(pages.pages) do
    if page.key == "about" then
        suite.check("about has the note and the facts", #page.items[1] == 2 and #page.items[2] == 2)
    else
        suite.check(page.key .. " has rows", #page.rows > 0)
    end
end
suite.check("the window is two columns wide or more",
    SettingsUI.frame:GetWidth() >= 330 * 2 + 18 + 18 * 2, SettingsUI.frame:GetWidth())

-- What a setting does is a tooltip until Show descriptions is ticked.
local tooltipRow
for _, row in ipairs(pages.pages.gear.rows) do
    if row.labelText == "Tooltip Line:" then tooltipRow = row end
end
suite.check("descriptions start hidden", ns.db.settingsDescriptions == false
    and not tooltipRow.hint:IsShown())
GameTooltip._lines = {}
tooltipRow:GetScript("OnEnter")(tooltipRow)
suite.check("a row lights under the mouse", tooltipRow.hover:IsShown())
suite.check("and says what it does in a tooltip", GameTooltip._lines[1] and
    GameTooltip._lines[1]:find("beats what you wear") ~= nil)
local before = SettingsUI.frame:GetHeight()
pages.describe:GetScript("OnClick")(pages.describe)
suite.check("Show descriptions is saved", ns.db.settingsDescriptions == true)
suite.check("and puts the words under the rows", tooltipRow.hint:IsShown())
suite.check("and the window grows to fit them", SettingsUI.frame:GetHeight() > before)
pages.describe:GetScript("OnClick")(pages.describe)
suite.check("unticked, the window goes back", SettingsUI.frame:GetHeight() == before)

-- The spec row's words change with the spec, in its tooltip too.
controls.spec:SetValue(3)
suite.check("the spec row's description follows the pick",
    SettingsUI.specRow.description:find("because you picked it", 1, true) ~= nil)
controls.spec:SetValue(1)

-- Find a setting.
pages.find:SetText("tomtom")
pages:Search("tomtom")
suite.check("the search shows the page that has it", pages.shown == "quest", pages.shown)
local lit = 0
for _, entry in ipairs(pages.searchables) do
    if entry.glow:IsShown() then lit = lit + 1 end
end
suite.check("and lights only what matches", lit == 1, lit)
pages:Search("")
lit = 0
for _, entry in ipairs(pages.searchables) do
    if entry.glow:IsShown() then lit = lit + 1 end
end
suite.check("an empty search lights nothing", lit == 0)

-- Text size, saved as a word, waits for a reload.
controls.textSize:Pick(controls.textSize:GetValue() + 1)
suite.check("Text size saves Large", ns.db.textSize == "large")
suite.check("and offers Reload", controls.textSize.reload:IsShown())
suite.check("under the stepper, at its right edge", controls.textSize.reload._point[1] == "TOPRIGHT"
    and controls.textSize.reload._point[2] == controls.textSize
    and controls.textSize.reload._point[3] == "BOTTOMRIGHT")
suite.check("the Window style's Reload sits the same way", controls.windowStyle.reload._point[1] == "TOPRIGHT"
    and controls.windowStyle.reload._point[2] == controls.windowStyle
    and controls.windowStyle.reload._point[3] == "BOTTOMRIGHT")
controls.textSize:Pick(controls.textSize:GetValue() - 1)
suite.check("back to Normal needs no reload", ns.db.textSize == "normal"
    and not controls.textSize.reload:IsShown())
-- Word choices are drop-downs (the owner, 2026-10-23), the character
-- picker too.
controls.textSize:GetScript("OnMouseDown")(controls.textSize)
suite.check("Text size opens a menu of its words", controls.textSize.menu:IsShown()
    and #controls.textSize.options == 3)
controls.textSize.entries[1]:GetScript("OnClick")()
suite.check("picking the one shown changes nothing", ns.db.textSize == "normal"
    and not controls.textSize.menu:IsShown())
do
    local picked = 0
    local picker = SettingsUI.CharacterPicker(CreateFrame("Frame"), 0, function() picked = picked + 1 end)
    suite.check("an empty picker says so", picker.text:GetText() == "No characters yet" and picker:GetEntry() == nil)
    picker:SetEntries({ { key = "Player-1", name = "Ana Stormwind" }, { key = "Player-2", name = "Bob Wither" } })
    suite.check("then shows the first whole name", picker:GetEntry().key == "Player-1"
        and picker.text:GetText() == "Ana Stormwind")
    picker:GetScript("OnMouseDown")(picker)
    picker.entries[2]:GetScript("OnClick")()
    suite.check("a line of its menu picks that character", picker:GetEntry().key == "Player-2" and picked == 1)
    picker:SetEntries({ { key = "Player-3", name = "Cid Hale" }, { key = "Player-2", name = "Bob Wither" } })
    suite.check("and the pick stays through a new list", picker:GetEntry().key == "Player-2")
end
suite.check("sizes read through the step", ns.Theme.sizes.small == ns.Theme.BASE_SIZES.small)

-- The command buttons run their commands.
local ran = {}
local realSlash = ns.HandleSlash
ns.HandleSlash = function(text) ran[#ran + 1] = text end
for _, key in ipairs({ "openWindow", "find", "questArrowNext", "whatsnew" }) do
    controls[key]:GetScript("OnClick")(controls[key])
end
ns.HandleSlash = realSlash
suite.check("the command buttons run their commands",
    table.concat(ran, ",") == "window,find,arrow next,whatsnew", table.concat(ran, ","))

-- Every command registered has a control here, but for the ones that are
-- typed only (the owner, 2026-10-15): commands that only list things in
-- chat, or only do what a panel already has a button for.
local covered = { sisters = true, whatsnew = true,
    window = true, find = true, quest = true, arrow = true,
    spec = true, weights = true,
    settings = true, weapons = true, training = true, skip = true, autoequip = true,
    dungeons = true, loot = true,
}
local typedOnly = { bags = true, tracked = true, help = true }
for _, name in ipairs(ns.commandOrder) do
    suite.check("/beq " .. name .. " has a button in Settings, or is typed only",
        covered[name] == true or typedOnly[name] == true)
end
suite.check("the chat-only commands still work", ns.commands.bags and ns.commands.tracked
    and ns.commands.help and ns.commands.training)

-- An empty description shows no tooltip and nothing under the row.
local textRow
for _, row in ipairs(pages.pages.general.rows) do
    if row.labelText == "Text Size:" then textRow = row end
end
GameTooltip._lines = {}
GameTooltip:Hide()
textRow:GetScript("OnEnter")(textRow)
suite.check("a row with no description has no tooltip", not (GameTooltip._lines and GameTooltip._lines[1]))
pages.describe:GetScript("OnClick")(pages.describe)
suite.check("and nothing under it with Show descriptions on",
    textRow.description == "" and textRow:GetHeight() == textRow.compactHeight)
pages.describe:GetScript("OnClick")(pages.describe)

-- Window style (2026-10-10): a stepper, saved flat, waiting for /reload.
local style = controls.windowStyle
suite.check("window style starts on Titanforged", style.text:GetText() == "Titanforged", style.text:GetText())
suite.check("with no reload to offer", not style.reload:IsShown())
style:Pick(style:GetValue() + 1)
suite.check("stepping picks Blizzard", ns.db.windowStyle == "blizzard" and style.text:GetText() == "Blizzard")
suite.check("which waits for /reload", style.reload:IsShown() and ns.BlizzardLook.Style() == "titanforged")
style:Pick(style:GetValue() - 1)
suite.check("stepping back saves Titanforged", ns.db.windowStyle == "titanforged" and not style.reload:IsShown())
ns.db.windowStyle = "blizzard"
SettingsUI:Refresh()
suite.check("the page shows what is saved", style.text:GetText() == "Blizzard" and style.reload:IsShown())
ns.db.windowStyle = "titanforged"
SettingsUI:Refresh()

-- Position.
ns.db.settingsX = 400
controls.resetPositions:GetScript("OnClick")(controls.resetPositions)
suite.check("Set Default forgets where it was dragged", ns.db.settingsX == nil)
suite.check("and says so", env.chat[#env.chat]:find("UI windows set to defaults.", 1, true) ~= nil, env.chat[#env.chat])

-- A client with neither options API still loads.
local ns2 = env.Load()
_G.UnitClass = function() return "Hunter", "HUNTER" end
suite.check("no options API is not an error", ns2.SettingsUI:RegisterGameOptions() == false)

-- The share box on About shows only in North America, on the realm the
-- owner's Era characters are on, off until ticked.
suite.check("no share box outside North America", ns.SettingsUI.controls.shareData == nil)
local oldRealm = _G.GetNormalizedRealmName
_G.GetCurrentRegion = function() return 1 end
_G.GetNormalizedRealmName = function() return "Mankrik" end
local ns4 = env.Load()
_G.UnitClass = function() return "Hunter", "HUNTER" end
ns4.SettingsUI:Build()
suite.check("no share box on another realm", ns4.SettingsUI.controls.shareData == nil)
_G.GetNormalizedRealmName = function() return "Ashkandi" end
local ns3 = env.Load()
_G.UnitClass = function() return "Hunter", "HUNTER" end
ns3.SettingsUI:Build()
local share = ns3.SettingsUI.controls.shareData
suite.check("a share box on the owner's realm", share ~= nil)
suite.check("unticked at first", share and not share:GetChecked())
if share then share:GetScript("OnClick")(share) end
suite.check("ticking it turns sharing on", ns3.db.shareData == true)
_G.GetCurrentRegion = nil
_G.GetNormalizedRealmName = oldRealm

suite.done()
