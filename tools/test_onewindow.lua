-- Equipment's tabs in the one Blackthornes window (UI/FinderWindow.lua, the
-- owner said build it, 2026-10-30).
--
-- What must hold:
--   1. On unless unticked; unticked, the gear window opens in its own place.
--   2. Ticked, opening Equipment opens the one window on it, with the gear
--      window laid into its area, bare of its own rim and grip.
--   3. Dungeon Quests, Dungeon Loot and Settings open in the same area,
--      also when opened by themselves; one tab at a time.
--   4. Closing the one window gives the tabs back their own place.
--   5. "One Window:" on the General page writes every save.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("onewindow")

_G.BlackthornesWindow = nil
local ns = env.Load()
local Finder, SettingsUI, SW = ns.FinderUI, ns.SettingsUI, ns.SharedWindow

ns.MinimapButton.button = ns.MinimapButton.button or env.Stub()
ns.MinimapButton:JoinShared()
local hub = _G.BlackthornesWindow
suite.check("Equipment joins with its tabs", hub.entries.equipment and hub.entries.equipment.host == Finder.host)
suite.check("the one window is Equipment's own copy", Finder.One() == SW)

-- 1.
ns.db.oneWindow = nil
suite.check("on unless unticked", SW.On())
ns.db.oneWindow = false
Finder:Show()
suite.check("off: the gear window opens by itself", Finder.frame:IsShown() and not Finder:Hosted())
Finder:Hide()

-- 2.
SW.SetOn(true)
Finder:Show()
local area = hub.frame and hub.frame.area
suite.check("on: the one window opens", hub.frame and hub.frame:IsShown())
suite.check("on Equipment", hub.current == hub.entries.equipment and ns.db.oneWindowPick == "equipment")
suite.check("the gear window is in it", Finder:Hosted() and Finder.frame:GetParent() == area
    and Finder.frame:IsShown())
suite.check("without its own rim", Finder.frame.titan == nil or not Finder.frame.titan:IsShown())
suite.check("or its own size grip", Finder.sizeGrip and not Finder.sizeGrip:IsShown())

-- 3.
Finder:ShowTab("dungeons")
local dq = ns.DungeonQuestsUI.frame
suite.check("Dungeon Quests is in the same area", dq:GetParent() == area and dq:IsShown())
suite.check("and the gear window stepped aside", not Finder.frame:IsShown())
suite.check("the one window stays up", hub.frame:IsShown() and Finder:Hosted())
SettingsUI:Build()
local settings = SettingsUI.frame
settings._point = false
function settings:SetAlpha(value) self._alpha = value end
SettingsUI:Show()
suite.check("Settings opened by itself goes in as a tab", SettingsUI.frame:GetParent() == area
    and SettingsUI.frame:IsShown() and not dq:IsShown())

-- Show Descriptions makes the pages taller: the one window grows to hold
-- them. On the client Settings fills the area, so its own size only says
-- how big the area is; the stand-in frame is made to answer the same way.
do
    local frame = SettingsUI.frame
    local getW, getH = frame.GetWidth, frame.GetHeight
    frame.GetWidth = function() return area:GetWidth() end
    frame.GetHeight = function() return area:GetHeight() end
    local before, oneBefore = area:GetHeight(), hub.frame:GetHeight()
    SettingsUI.pages:ShowDescriptions(true)
    local need = SettingsUI.pages.need
    suite.check("descriptions on: the pages say how tall they are", type(need) == "table" and need[2] > before)
    suite.check("Settings says what the pages need", Finder.needs and Finder.needs.settings and Finder.needs.settings[2] == need[2])
    -- The test's frames don't follow their anchors, so the area keeps its
    -- old height; the one window around it is what grows.
    suite.check("and the one window grows to hold them",
        hub.frame:GetHeight() - oneBefore >= need[2] - before)
    SettingsUI.pages:ShowDescriptions(false)
    frame.GetWidth, frame.GetHeight = getW, getH
end
-- A player saw it dimmed there (2026-10-31): its opening fade was left
-- running with a spot of its own on the screen.
suite.check("at full strength, its fade let go", settings._alpha == 1
    and not ns.Motion:Running(settings, "open"))
suite.check("and not placed at its own saved spot", not (rawget(settings, "_point") and settings._point[2] == UIParent))
ns.DungeonLootUI:Show()
suite.check("so does Dungeon Loot", ns.DungeonLootUI.frame:GetParent() == area
    and not SettingsUI.frame:IsShown())

-- A window built for the first time hides itself before it is laid in
-- (a player's report, 2026-10-30: picking another addon on the rail once
-- turned the one window into that addon's own window).
local fresh = { GetParent = function() return UIParent end }
Finder:Closed(fresh)
suite.check("a window not yet laid in hiding keeps the one window", hub.frame:IsShown() and Finder.oneArea)

-- 4.
hub.frame:Hide()
local onHide = hub.frame:GetScript("OnHide")
if onHide then onHide(hub.frame) end
suite.check("closing it lets Equipment go", not Finder:Hosted() and hub.current == nil)
suite.check("the tabs are back on their own", Finder.frame:GetParent() == UIParent
    and dq:GetParent() == UIParent and SettingsUI.frame:GetParent() == UIParent)
suite.check("hidden", not Finder.frame:IsShown() and not ns.DungeonLootUI.frame:IsShown())
suite.check("with their grip", Finder.sizeGrip:IsShown())

-- 5.
local other = {}
SW:Join({ key = "pets", order = 3, name = "Pets", db = function() return other end })
SettingsUI:Show()
suite.check("Settings opens in the one window", Finder:Hosted() and SettingsUI.frame:GetParent() == hub.frame.area)
SettingsUI:SetOneWindow(false)
local onHideAgain = hub.frame:GetScript("OnHide")
if onHideAgain then onHideAgain(hub.frame) end
suite.check("unticked in every save", ns.db.oneWindow == false and other.oneWindow == false)
SettingsUI:Show()
suite.check("Settings opens on its own again", not Finder:Hosted() and SettingsUI.frame:GetParent() == UIParent
    and SettingsUI.frame:IsShown())
SettingsUI:SetOneWindow(true)
suite.check("ticked again in every save", ns.db.oneWindow == true and other.oneWindow == true)
suite.check("and Settings moves into the one window", Finder:Hosted() and SettingsUI.frame:GetParent() == hub.frame.area)

SW.SetOn(false)
_G.BlackthornesWindow = nil
suite.done()
