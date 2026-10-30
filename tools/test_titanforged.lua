-- The Titanforged window frame (picked 2026-10-04), outside WoW.
--
-- What must hold:
--   1. A dressed window gets its rim, four corner gems turned to their
--      corners, the name on a plate wide enough for it, the portrait with
--      the emblem, and a close gem that closes.
--   2. Its art comes from this addon's own Media\Frame folder.
--   3. The light round the portrait runs once as the window opens and goes
--      out; with the window effects off it never shows.
--   4. The glint runs along the top edge and comes round again while the
--      window shows, never with effects Subtle or Off, and stops when the
--      window hides.
--   5. Every kind of button keeps its label readable on its own face, at
--      rest and under the mouse: a primary button is gold with dark ink.
--   6. The gear window and the finder wear the whole frame, settings and
--      the stat weights and the upgrade quest panel the plate and close
--      gem, and the other panels that stay on screen while playing keep
--      their own look.

local ns = {}

-- Tests share one Lua state, so the globals replaced here are put back.
local saved = { CreateFrame = CreateFrame, UIParent = UIParent, CreateColor = CreateColor,
    GameTooltip = GameTooltip }

local function Region(parent)
    local region = { shown = true, parent = parent, scripts = {}, points = {}, alpha = 1,
        width = 0, height = 0, events = {}, children = {} }

    region.Show = function(self)
        local was = self.shown
        self.shown = true
        if not was and self.scripts.OnShow then self.scripts.OnShow(self) end
    end
    region.Hide = function(self)
        local was = self.shown
        self.shown = false
        if was and self.scripts.OnHide then self.scripts.OnHide(self) end
    end
    region.SetShown = function(self, on) if on then self:Show() else self:Hide() end end
    region.IsShown = function(self) return self.shown end
    region.SetAlpha = function(self, a) self.alpha = a end
    region.GetAlpha = function(self) return self.alpha end
    region.SetWidth = function(self, w) self.width = w end
    region.SetHeight = function(self, h) self.height = h end
    region.GetWidth = function(self) return self.width end
    region.GetHeight = function(self) return self.height end
    region.SetSize = function(self, w, h) self.width, self.height = w, h end
    region.SetColorTexture = function(self, r, g, b, a) self.color = { r, g, b, a or 1 } end
    region.SetGradient = function(self, orientation, from, to)
        self.gradient = { orientation, from, to }
    end
    region.SetTextColor = function(self, r, g, b, a) self.textColor = { r, g, b, a } end
    region.SetText = function(self, text) self.text = text end
    region.GetText = function(self) return self.text end
    region.GetStringWidth = function(self) return #(self.text or "") * 6 end
    region.SetScript = function(self, name, fn) self.scripts[name] = fn end
    region.GetScript = function(self, name) return self.scripts[name] end
    region.HookScript = function(self, name, fn)
        local old = self.scripts[name]
        self.scripts[name] = function(...)
            if old then old(...) end
            fn(...)
        end
    end

    -- As the game does: the short forms fill in the parent and the same
    -- point, and setting a point the region already has moves that one.
    region.SetPoint = function(self, point, a, b, c, d)
        local relativeTo, relativePoint, x, y
        if a == nil or type(a) == "number" then
            relativeTo, relativePoint, x, y = self.parent, point, a or 0, b or 0
        elseif type(b) == "string" then
            relativeTo, relativePoint, x, y = a, b, c or 0, d or 0
        else
            relativeTo, relativePoint, x, y = a, point, b or 0, c or 0
        end

        local anchor = { point, relativeTo, relativePoint, x, y }
        for index, existing in ipairs(self.points) do
            if existing[1] == point then
                self.points[index] = anchor
                return
            end
        end
        self.points[#self.points + 1] = anchor
    end
    region.ClearAllPoints = function(self) self.points = {} end
    region.GetPoint = function(self, index)
        local p = self.points[index or 1]
        if not p then return nil end
        return p[1], p[2], p[3], p[4], p[5]
    end
    region.CreateTexture = function(self) return Region(self) end
    region.CreateFontString = function(self) return Region(self) end
    region.GetParent = function(self) return self.parent end
    region.SetTexture = function(self, path) self.texture = path end
    region.SetTexCoord = function(self, ...) self.coords = { ... } end
    region.SetRotation = function(self, radians) self.rotation = radians end
    region.SetBlendMode = function(self, mode) self.blend = mode end
    region.SetFrameLevel = function(self, level) self.level = level end
    region.GetFrameLevel = function(self) return self.level or 1 end

    -- Any other method does nothing. Fields read as nil, as on a real frame.
    return setmetatable(region, { __index = function(_, key)
        if type(key) == "string" and key:match("^%u") then return function() end end
    end })
end

CreateFrame = function(_, _, parent)
    local frame = Region(parent)
    if type(parent) == "table" and rawget(parent, "children") then
        parent.children[#parent.children + 1] = frame
    end
    return frame
end
UIParent = Region()
CreateColor = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end
GameTooltip = Region()

local function Load(path)
    local chunk = assert(loadfile(lfs_cwd .. path))
    chunk("Blackthornes_Equipment", ns)
end

Load("/UI/Theme.lua")
Load("/UI/Widgets.lua")
Load("/UI/Titanforged.lua")

local Theme, Widgets, Motion, Titanforged = ns.Theme, ns.Widgets, ns.Motion, ns.Titanforged

local passed, failed = 0, 0

local function check(label, got, want)
    local ok = got == want
    if ok then passed = passed + 1 else failed = failed + 1 end
    print(string.format("  %-58s %-10s %s", label, tostring(got), ok and "ok" or
        ("WRONG, wanted " .. tostring(want))))
end

--- The window effects, for the length of `fn`. Equipment has no setting for
--- them, so Motion.Level is swapped and put back.
local function WithLevel(level, fn)
    local real = Motion.Level
    Motion.Level = function() return level end
    fn()
    Motion.Level = real
end

print("")
print("dressing a window")

local window = Region()
window:SetSize(1060, 548)
local closed = false
local trim = Titanforged:Dress(window, {
    title = "Blackthornes Equipment", portrait = true,
    close = function() closed = true end,
})

check("the trim is kept on the window", window.titan, trim)
check("four corner gems", #trim.corners, 4)
check("from this addon's art", trim.corners[1].texture,
    [[Interface\AddOns\Blackthornes_Equipment\Media\Frame\Corner]])
check("the top left one unturned", trim.corners[1].coords[1] == 0 and trim.corners[1].coords[2] == 1, true)
check("the top right one turned to face it", trim.corners[2].coords[1] == 1 and trim.corners[2].coords[2] == 0, true)
check("the bottom right one upside down too", trim.corners[3].coords[3] == 1 and trim.corners[3].coords[4] == 0, true)
check("the name on the plate", trim.plate.label.text, "Blackthornes Equipment")
check("which is wide enough for it", trim.plate.width >= #"Blackthornes Equipment" * 6 + 30, true)
check("sat on the top edge", trim.plate.points[1][3], "TOP")
check("a portrait", trim.portrait ~= nil, true)
check("its light starts out", trim.portrait.sweep.alpha, 0)
check("drawn added, as light", trim.portrait.sweep.blend, "ADD")
check("the trim sits above the window's contents", trim.level, 21)

trim.closeButton.scripts.OnClick(trim.closeButton)
check("the close gem closes", closed, true)
trim.closeButton.scripts.OnEnter(trim.closeButton)
Motion:Step(1)
check("and glows red under the mouse", trim.closeButton.glow.alpha > 0.7, true)

local left, right, top = Titanforged.Reach(trim)
check("it reaches out past the top left for the portrait", left == 20 and top == 20, true)
check("and a little past the right for the gem", right > 3, true)

local plated = Titanforged:Dress(Region(), { title = "Blackthornes Equipment", close = function() end })
local _, plateRight, plateTop = Titanforged.Reach(plated)
check("a window with a plate and no portrait", plated.portrait, nil)
check("reaches up by half the plate", plateTop, 15)
check("and right for its gem", plateRight > 3, true)

local plain = Titanforged:Dress(Region())
check("a side panel gets no plate", plain.plate, nil)
check("or portrait", plain.portrait, nil)
local pl, _, pt = Titanforged.Reach(plain)
check("so it reaches out only by its corners", pl == 3 and pt == 3, true)

print("")
print("opening")

Titanforged:Opened(window)
Motion:Step(0.1)
check("the light runs round the portrait", trim.portrait.sweep.alpha > 0, true)
check("turning as it goes", trim.portrait.sweep.rotation < 0, true)
Motion:Step(2)
check("and goes out when it has been round", trim.portrait.sweep.alpha, 0)

WithLevel("off", function()
    Titanforged:Opened(window)
    check("with effects off it never shows", trim.portrait.sweep.alpha, 0)
    check("and nothing is left running", Motion:Running(trim.portrait.sweep), false)
end)
Titanforged:Opened(plain)
check("a window with no portrait opens quietly", Motion:Running(plain), false)

print("")
print("the glint")

window.shown = true
Titanforged:StartGlint(window, 0)
Motion:Step(0.8)
check("it runs along the top edge", trim.glint.alpha > 0.5, true)
local _, _, _, x = trim.glint:GetPoint(1)
check("about halfway along at halfway", x > 400 and x < 700, true)
Motion:Step(1)
check("then it is gone", trim.glint.alpha, 0)
check("and another is on its way", Motion:Running(trim.glint, "glint"), true)

Titanforged:StopGlint(window)
check("hidden, the window stops it", Motion:Running(trim.glint, "glint"), false)

WithLevel("subtle", function()
    Titanforged:StartGlint(window, 0)
    check("with effects subtle there is none", Motion:Running(trim.glint, "glint"), false)
end)

Titanforged:StartGlint(window, 0)
window.shown = false
Motion:Step(2)
check("one finishing on a hidden window sends no other", Motion:Running(trim.glint, "glint"), false)

print("")
print("buttons")

local function Same(color, key)
    local want = Theme.colors[key]
    return type(color) == "table" and math.abs(color[1] - want[1]) < 0.001
        and math.abs(color[2] - want[2]) < 0.001 and math.abs(color[3] - want[3]) < 0.001
end

local primary = Widgets.CreateButton(Region(), "Find upgrades", function() end, { primary = true })
check("a primary button is solid gold", Same(primary.background.color, "accent"), true)
check("with dark lettering", Same(primary.label.textColor, "ink"), true)
check("and a faint glow at rest", primary.haloTextures[1].shown, true)
primary.scripts.OnEnter(primary)
Motion:Step(1)
check("it lights under the mouse", Same(primary.background.color, "accentHi"), true)
primary:SetLabelColor("accent")
check("and its lettering stays dark whatever is asked", Same(primary.label.textColor, "ink"), true)
primary.scripts.OnLeave(primary)
Motion:Step(1)
check("then rests", Same(primary.background.color, "accent"), true)

local plainButton = Widgets.CreateButton(Region(), "Settings", function() end)
check("a plain button has a gold label", Same(plainButton.label.textColor, "gilt"), true)
check("in a metal edge", Same(plainButton.borderTextures[1].color, "metal"), true)
check("and no glow at rest", plainButton.haloTextures[1].shown, false)
plainButton.scripts.OnEnter(plainButton)
Motion:Step(1)
check("its edge lights under the mouse", Same(plainButton.borderTextures[1].color, "accentHi"), true)
check("and it glows", plainButton.haloTextures[1].shown, true)
plainButton.scripts.OnLeave(plainButton)
Motion:Step(1)

local danger = Widgets.CreateButton(Region(), "X", function() end, { danger = true })
danger.scripts.OnEnter(danger)
Motion:Step(1)
check("a danger button turns red under the mouse", Same(danger.label.textColor, "loss"), true)
danger.scripts.OnLeave(danger)
Motion:Step(1)

-- Every kind of button keeps its label readable on its own face, at rest and
-- under the mouse. Tradeskills' auction house buttons once drew dark
-- lettering on a dark face and read as empty boxes.
local function Luminance(c)
    local function lin(v) v = v or 0; return v <= 0.03928 and v / 12.92 or ((v + 0.055) / 1.055) ^ 2.4 end
    return 0.2126 * lin(c[1]) + 0.7152 * lin(c[2]) + 0.0722 * lin(c[3])
end
local function Contrast(a, b)
    local la, lb = Luminance(a), Luminance(b)
    if la < lb then la, lb = lb, la end
    return (la + 0.05) / (lb + 0.05)
end

local kinds = {
    { "a plain button", {}, 4.5 },
    { "a primary button", { primary = true }, 4.5 },
    -- Red on dark metal reads as a warning first; it only needs to stand out.
    { "a danger button", { danger = true }, 3.5 },
    { "a primary button with its own dark face", { primary = true, baseColor = { 0.06, 0.07, 0.09, 1 } }, 4.5 },
}
for _, kind in ipairs(kinds) do
    local b = Widgets.CreateButton(Region(), "Scan", function() end, kind[2])
    check(kind[1] .. " is readable at rest",
        Contrast(b.label.textColor, b.background.color) >= kind[3], true)
    b.scripts.OnEnter(b)
    Motion:Step(1)
    check(kind[1] .. " is readable under the mouse",
        Contrast(b.label.textColor, b.background.color) >= kind[3], true)
    b.scripts.OnLeave(b)
    Motion:Step(1)
end

local stepper = Widgets.CreateStepper(Region(), { min = 0, max = 10, value = 0 })
check("a stepper's - is dim at the bottom of its range", Same(stepper.minus.label.textColor, "dim"), true)
stepper.minus.scripts.OnEnter(stepper.minus)
Motion:Step(1)
check("and stays dim under the mouse", Same(stepper.minus.label.textColor, "dim"), true)
check("while its + is gold", Same(stepper.plus.label.textColor, "gilt"), true)
stepper:SetValue(10)
check("at the top the + dims instead", Same(stepper.plus.label.textColor, "dim"), true)
check("and the - comes back, lit under the mouse",
    not Same(stepper.minus.label.textColor, "dim") and not Same(stepper.minus.label.textColor, "gilt"), true)

local box = Widgets.CreateCheckbox(Region(), "Show the arrows", function() end, false)
local square = box.children[1]
check("a checkbox is a dark well", Same(square.background.color, "well"), true)
check("in a metal edge", Same(square.borderTextures[1].color, "metal"), true)
box.scripts.OnClick(box)
check("ticked, its edge lights", Same(square.borderTextures[1].color, "accentHi"), true)
check("and it glows", square.haloTextures[1].shown, true)

Motion:FinishAll()

for key, value in pairs(saved) do _G[key] = value end

--------------------------------------------------------------------------------
-- The windows, loaded as the game loads them
--------------------------------------------------------------------------------

print("")
print("the windows")

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local addon = env.Load()
_G.UnitClass = function() return "HUNTER", "HUNTER" end
env.InstallItems({}, {}, {})

-- Every button the windows make, to check each one's colours.
local made = {}
local CreateButton = addon.Widgets.CreateButton
addon.Widgets.CreateButton = function(...)
    local button = CreateButton(...)
    made[#made + 1] = button
    return button
end

local function Titan(frame) return rawget(frame, "titan") end

addon.UI:Show()
addon.FinderUI:Show()
addon.SettingsUI:Show()
addon.WeightsUI:Show()
addon.QuestPanel:Build()
addon.TrackerPanel:Build()
addon.Toast:Build()
addon.SlotUpgrades:Build()

local gear = Titan(addon.UI.frame)
check("the gear window wears the frame", gear ~= nil, true)
check("with the portrait", rawget(gear, "portrait") ~= nil, true)
check("its name on the plate", gear.plate.label._text, "Blackthornes Equipment")
check("and the close gem", rawget(gear, "closeButton") ~= nil, true)
gear.closeButton:GetScript("OnClick")(gear.closeButton)
check("which closes it", addon.UI.frame:IsShown(), false)

local finder = Titan(addon.FinderUI.frame)
check("the finder wears it too", finder ~= nil and rawget(finder, "portrait") ~= nil, true)
check("named on its plate", finder.plate.label._text, "Blackthornes Equipment")

for _, entry in ipairs({ { "settings", addon.SettingsUI }, { "the stat weights", addon.WeightsUI } }) do
    local dressed = Titan(entry[2].frame)
    check(entry[1] .. " get the plate and close gem",
        dressed ~= nil and rawget(dressed, "plate") ~= nil and rawget(dressed, "closeButton") ~= nil, true)
    check("but no portrait", rawget(dressed, "portrait"), nil)
end

-- The upgrade quest panel was asked to match too (2026-10-04).
local quest = Titan(addon.QuestPanel.frame)
check("the upgrade quest gets the plate and close gem",
    quest ~= nil and rawget(quest, "plate") ~= nil and rawget(quest, "closeButton") ~= nil, true)
check("named on its plate", quest.plate.label._text, "Upgrade quest")
check("with no portrait, to stay small", rawget(quest, "portrait"), nil)

check("the tracker keeps its own look", Titan(addon.TrackerPanel.frame), nil)

-- The upgrade banner wears the rim and the close gem, no plate or portrait.
local banner = Titan(addon.Toast.frame)
check("the upgrade banner wears the rim and close gem",
    banner ~= nil and rawget(banner, "closeButton") ~= nil, true)
check("with no plate or portrait", rawget(banner, "plate") == nil and rawget(banner, "portrait") == nil, true)
addon.Toast.frame:Show()
banner.closeButton:GetScript("OnClick")(banner.closeButton)
check("and its gem closes it", addon.Toast.frame:IsShown(), false)

-- The upgrade list by the character sheet wears the rim, the slot on the
-- plate and the close gem.
local slots = Titan(addon.SlotUpgrades.frame)
check("the slot upgrades list wears the rim and close gem",
    slots ~= nil and rawget(slots, "closeButton") ~= nil, true)
addon.SlotUpgrades.slot = 5
addon.SlotUpgrades:Fill()
check("with the slot on its plate", slots.plate.label:GetText(), "Upgrades: Chest")
addon.SlotUpgrades.frame:Show()
slots.closeButton:GetScript("OnClick")(slots.closeButton)
check("and its gem closes it", addon.SlotUpgrades.frame:IsShown(), false)

-- The test frames keep no texture colours, so each button's face records
-- its own before it is lit. A stepper's - or + dimmed at the end of its
-- range is greyed out on purpose, as a disabled button is.
local unreadable, dimmed = {}, 0
for _, button in ipairs(made) do
    if rawget(button, "dimmed") == true then dimmed = dimmed + 1 end
    rawset(button.background, "SetColorTexture", function(self, r, g, b) self._color = { r, g, b } end)
    for _, p in ipairs({ 0, 1 }) do
        button.Light(p)
        local face, ink = rawget(button.background, "_color"), rawget(button.label, "_color")
        if face and ink and rawget(button, "dimmed") ~= true and Contrast(ink, face) < 3.5 then
            unreadable[#unreadable + 1] = ("%s (%s)"):format(button.label:GetText(), p == 0 and "at rest" or "lit")
        end
    end
end
check("buttons checked across the windows", #made > 20, true)
check("every one readable at rest and lit", table.concat(unreadable, ", "), "")
-- (Settings' word choices are drop-downs now, so none of its buttons is
-- dimmed; a number stepper elsewhere may dim its - or +.)
check("bar the few dimmed at the end of a range", dimmed < 16, true)

addon.Widgets.CreateButton = CreateButton

print("")
print(("%d passed, %d failed"):format(passed, failed))
assert(failed == 0, "titanforged checks failed")
