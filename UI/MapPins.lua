-- Blackthornes Equipment -- UI/MapPins.lua
-- Pins on the world map where each tracked upgrade comes from: the vendor,
-- the quest giver, or the trainer who teaches a crafted piece. The upgrade
-- quest's next place to go gets one too.
--
-- A pin is the item's own icon in a gold ring with a soft glow, the size of
-- the game's own pins at any zoom. Hover one for the item and where it is;
-- click it to put the game's map pin there. Only hunts with an exact spot
-- get one, and only on the map of their zone. Drawn as plain frames on the
-- map's canvas, the way Farmer draws its gathering markers, and every map
-- call is in a pcall: a map this cannot read simply shows no pins. Switched
-- off with the "Map pins" setting (`mapPins`).
--
-- The place Show on map asked for (`Waypoints.marked`, Era has no game pins)
-- gets a bigger marker of its own (a player asked, 2026-10-28): the icon in
-- dark glass inside a gold rim with a red gem on top, a soft beam of light
-- above it, a glow and gold ripples at its foot, and the place's name on a
-- small plate under it. The glow breathes and the ripples run only with
-- Effects on Full (`Motion.Level`), as animations the game plays by itself;
-- nothing is drawn again for them.

local _, ns = ...
local L = ns.L

local MapPins = ns.NewModule("MapPins")

local Theme = ns.Theme

local SIZE = 22
local STEP = 0.2
local ROUND = [[Interface\CharacterFrame\TempPortraitAlphaMask]]
local GLOW = ([[Interface\AddOns\%s\Media\Frame\Glow]]):format((...))

--- The Show on map marker: how big, and how its light moves.
MapPins.MARK_SIZE = 42
MapPins.RIPPLE_EVERY = 1.6
MapPins.BREATHE = 1.2

function MapPins:IsEnabled()
    return not (ns.db and ns.db.mapPins == false)
end

local function Number(value)
    local ok, copy = pcall(function() return tonumber(value) end)
    return ok and copy or nil
end

--- What the world map is showing: { canvas, mapID, name, scale, width,
--- height }, or nil when it is shut or cannot be read.
function MapPins:View()
    local map = _G.WorldMapFrame
    if type(map) ~= "table" then return nil end
    local okShown, shown = pcall(map.IsShown, map)
    if not (okShown and shown) then return nil end

    local canvas
    if type(map.GetCanvas) == "function" then
        local ok, value = pcall(map.GetCanvas, map)
        if ok then canvas = value end
    end
    canvas = canvas or (map.ScrollContainer and map.ScrollContainer.Child)
    if type(canvas) ~= "table" then return nil end

    local mapID
    if type(map.GetMapID) == "function" then
        local ok, value = pcall(map.GetMapID, map)
        if ok then mapID = Number(value) end
    end
    if not mapID then return nil end

    local name
    local info = _G.C_Map and _G.C_Map.GetMapInfo
    if type(info) == "function" then
        local ok, value = pcall(function()
            local data = info(mapID)
            if type(data) == "table" and type(data.name) == "string" then return data.name .. "" end
        end)
        if ok then name = value end
    end

    local scale = 1
    local scroll = map.ScrollContainer
    if type(scroll) == "table" and type(scroll.GetCanvasScale) == "function" then
        local ok, value = pcall(scroll.GetCanvasScale, scroll)
        scale = ok and Number(value) or 1
    end
    if not scale or scale <= 0 then scale = 1 end

    local okW, width = pcall(canvas.GetWidth, canvas)
    local okH, height = pcall(canvas.GetHeight, canvas)
    width, height = okW and Number(width), okH and Number(height)
    if not (width and height and width > 0 and height > 0) then return nil end

    return { canvas = canvas, mapID = mapID, name = name, scale = scale, width = width, height = height }
end

--- The hunts with an exact spot on the map named `zone`.
function MapPins:HuntsOn(zone)
    local list = {}
    if not (zone and ns.Tracking) then return list end
    for _, hunt in ipairs(ns.Tracking:List()) do
        local place = hunt.place
        if place and place.zone == zone and place.x and place.y and not hunt.got then
            list[#list + 1] = hunt
        end
    end
    -- The upgrade quest's next place to go, when it has an exact spot.
    local quest = ns.UpgradeQuest and ns.UpgradeQuest:IsEnabled() and ns.UpgradeQuest:Current()
    local spot = quest and ns.UpgradeQuest:NextPlace()
    if spot and spot.zone == zone and spot.x and spot.y then
        local names = ns.Names
        local shown = spot.name and names and names:NPC(names:Zone(spot.name)) or spot.name
        list[#list + 1] = {
            link = quest.link, quest = true,
            place = { zone = spot.zone, x = spot.x, y = spot.y, name = spot.name,
                text = shown and L.Format("Upgrade quest: go to %s", shown) or L["Upgrade quest"] },
        }
    end
    -- The place Show on map was last asked for, where the game takes no pin
    -- of its own (Era), unless a pin above already sits there.
    local marked = ns.Waypoints and ns.Waypoints.marked
    if marked and marked.zone == zone and marked.x and marked.y then
        local same = false
        for _, hunt in ipairs(list) do
            if hunt.place.x == marked.x and hunt.place.y == marked.y then same = true end
        end
        if not same then list[#list + 1] = { link = marked.link, marked = true, place = marked } end
    end
    return list
end

function MapPins:MakePin(canvas)
    local pin = CreateFrame("Button", nil, canvas)
    pin:SetSize(SIZE, SIZE)

    local glow = pin:CreateTexture(nil, "BACKGROUND")
    glow:SetPoint("CENTER")
    glow:SetSize(SIZE + 14, SIZE + 14)
    glow:SetTexture(ROUND)
    glow:SetVertexColor(Theme.Unpack("good"))
    glow:SetAlpha(0.45)
    pcall(glow.SetBlendMode, glow, "ADD")

    local ring = pin:CreateTexture(nil, "BORDER")
    ring:SetPoint("CENTER")
    ring:SetSize(SIZE, SIZE)
    ring:SetTexture(ROUND)
    ring:SetVertexColor(Theme.Unpack("accent"))

    local icon = pin:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("CENTER")
    icon:SetSize(SIZE - 5, SIZE - 5)
    pcall(icon.SetMask, icon, ROUND)
    pin.icon = icon

    pin:SetScript("OnEnter", function(self)
        local hunt = self.hunt
        if not hunt then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if hunt.link then
            pcall(GameTooltip.SetHyperlink, GameTooltip, hunt.link)
            GameTooltip:AddLine(" ")
        elseif hunt.place.name then
            GameTooltip:AddLine(hunt.place.name, Theme.Unpack("accent"))
        end
        if not hunt.marked then
            GameTooltip:AddLine(hunt.quest and L["Upgrade quest"] or L["Tracked upgrade"], Theme.Unpack("accent"))
        end
        if hunt.place.text then GameTooltip:AddLine(ns.Tracking.PlaceText(hunt.place), Theme.Unpack("text")) end
        -- Only where the game takes a pin of its own (never on Era).
        if ns.Waypoints and ns.Waypoints:GamePins(self.mapID) then
            GameTooltip:AddLine(L["Click to pin it on your map"], Theme.Unpack("muted"))
        end
        GameTooltip:Show()
    end)
    pin:SetScript("OnLeave", function() GameTooltip:Hide() end)
    pin:SetScript("OnClick", function(self)
        if self.hunt and ns.Waypoints and ns.Waypoints:GamePins(self.mapID) then
            ns.Waypoints:Pin(self.hunt.place, self.hunt.link)
        end
    end)
    return pin
end

-- The name the place shows in the player's language; the data keeps English.
local function ShownName(name)
    local names = ns.Names
    if not (name and names) then return name end
    return names:NPC(names:Zone(name))
end

local function Animate(region, looping)
    if type(region.CreateAnimationGroup) ~= "function" then return nil end
    local ok, group = pcall(region.CreateAnimationGroup, region)
    if not (ok and type(group) == "table") then return nil end
    pcall(group.SetLooping, group, looping)
    return group
end

local function Step(group, kind, duration, delay)
    local ok, step = pcall(group.CreateAnimation, group, kind)
    if not (ok and type(step) == "table") then return nil end
    pcall(step.SetDuration, step, duration)
    if delay then pcall(step.SetStartDelay, step, delay) end
    return step
end

local function Light(parent, layer, width, height, alpha, key)
    local texture = parent:CreateTexture(nil, layer)
    texture:SetSize(width, height)
    texture:SetTexture(GLOW)
    texture:SetVertexColor(Theme.Unpack(key or "accentHi"))
    texture:SetAlpha(alpha)
    pcall(texture.SetBlendMode, texture, "ADD")
    return texture
end

--- One gold ripple that spreads out from the marker's foot and fades.
local function Ripple(marker, delay)
    local size = MapPins.MARK_SIZE
    local ripple = CreateFrame("Frame", nil, marker)
    ripple:SetSize(size + 10, (size + 10) * 0.45)
    ripple:SetPoint("CENTER", marker, "BOTTOM", 0, 4)
    local light = Light(ripple, "BACKGROUND", size + 10, (size + 10) * 0.45, 1, "accent")
    light:SetAllPoints(ripple)
    ripple:SetAlpha(0)

    local group = Animate(ripple, "REPEAT")
    if group then
        local grow = Step(group, "Scale", MapPins.RIPPLE_EVERY, delay)
        if grow then
            pcall(grow.SetScaleFrom, grow, 0.4, 0.4)
            pcall(grow.SetScaleTo, grow, 2.2, 2.2)
            pcall(grow.SetFromScale, grow, 0.4, 0.4)
            pcall(grow.SetToScale, grow, 2.2, 2.2)
            pcall(grow.SetSmoothing, grow, "OUT")
        end
        local fade = Step(group, "Alpha", MapPins.RIPPLE_EVERY, delay)
        if fade then
            pcall(fade.SetFromAlpha, fade, 0.9)
            pcall(fade.SetToAlpha, fade, 0)
            pcall(fade.SetSmoothing, fade, "OUT")
        end
    end
    ripple.motion = group or false
    return ripple
end

function MapPins:MakeMarker(canvas)
    local size = self.MARK_SIZE
    local marker = self:MakePin(canvas)
    marker:SetSize(size, size)
    marker.big = true

    -- The small pin's own textures make way for the bigger ones.
    for _, region in ipairs({ marker:GetRegions() }) do
        if region ~= marker.icon and type(region.Hide) == "function" then pcall(region.Hide, region) end
    end

    local beam = Light(marker, "BACKGROUND", 18, size * 2.4, 0.55)
    beam:SetPoint("BOTTOM", marker, "CENTER", 0, 0)

    local glow = Light(marker, "BACKGROUND", size * 2, size * 2, 0.8, "accent")
    glow:SetPoint("CENTER")

    -- The ripples, then the face over them: rim, glass, icon and gem.
    marker.ripples = { Ripple(marker, 0), Ripple(marker, self.RIPPLE_EVERY / 2) }
    local face = CreateFrame("Frame", nil, marker)
    face:SetAllPoints(marker)
    marker.face = face
    marker.icon:SetParent(face)

    local rim = face:CreateTexture(nil, "BORDER", nil, 1)
    rim:SetPoint("CENTER")
    rim:SetSize(size, size)
    rim:SetTexture(ROUND)
    rim:SetVertexColor(Theme.Unpack("accentHi"))
    local rimInner = face:CreateTexture(nil, "BORDER", nil, 2)
    rimInner:SetPoint("CENTER")
    rimInner:SetSize(size - 3, size - 3)
    rimInner:SetTexture(ROUND)
    rimInner:SetVertexColor(Theme.Unpack("metal"))
    local glass = face:CreateTexture(nil, "BORDER", nil, 3)
    glass:SetPoint("CENTER")
    glass:SetSize(size - 7, size - 7)
    glass:SetTexture(ROUND)
    glass:SetVertexColor(Theme.Unpack("glassAlt"))

    marker.icon:SetSize(size - 13, size - 13)

    local gem = face:CreateTexture(nil, "OVERLAY", nil, 1)
    gem:SetSize(11, 11)
    gem:SetPoint("CENTER", face, "TOP", 0, -1)
    gem:SetTexture(ROUND)
    gem:SetVertexColor(Theme.Unpack("loss"))
    local gemRim = face:CreateTexture(nil, "OVERLAY", nil, 0)
    gemRim:SetSize(14, 14)
    gemRim:SetPoint("CENTER", gem)
    gemRim:SetTexture(ROUND)
    gemRim:SetVertexColor(Theme.Unpack("accentHi"))
    local gemShine = Light(face, "OVERLAY", 6, 6, 0.9, "text")
    gemShine:SetDrawLayer("OVERLAY", 2)
    gemShine:SetPoint("CENTER", gem, "CENTER", -1, 1)

    -- The name plate: dark glass with a gold edge, gold words.
    local plate = CreateFrame("Frame", nil, marker)
    marker.icon:SetDrawLayer("ARTWORK")
    plate:SetPoint("TOP", marker, "BOTTOM", 0, -6)
    plate:SetHeight(18)
    Theme.Fill(plate, "glassAlt", 0.92)
    Theme.Border(plate, "accent", 0.9)
    local name = Theme.CreateLabel(plate, "small", "accentHi", "CENTER")
    name:SetPoint("CENTER")
    plate.text = name
    marker.plate = plate

    marker.glow, marker.beam = glow, beam
    local breathe = Animate(glow, "BOUNCE")
    if breathe then
        local fade = Step(breathe, "Alpha", self.BREATHE)
        if fade then
            pcall(fade.SetFromAlpha, fade, 0.8)
            pcall(fade.SetToAlpha, fade, 0.35)
            pcall(fade.SetSmoothing, fade, "IN_OUT")
        end
    end
    local shimmer = Animate(beam, "BOUNCE")
    if shimmer then
        local fade = Step(shimmer, "Alpha", self.BREATHE * 1.5)
        if fade then
            pcall(fade.SetFromAlpha, fade, 0.55)
            pcall(fade.SetToAlpha, fade, 0.25)
            pcall(fade.SetSmoothing, fade, "IN_OUT")
        end
    end
    marker.motions = {}
    if breathe then marker.motions[#marker.motions + 1] = breathe end
    if shimmer then marker.motions[#marker.motions + 1] = shimmer end
    return marker
end

--- The name under the marker, and its light moving only with Effects on Full.
function MapPins:DressMarker(marker, hunt)
    local okLevel, level = pcall(marker.GetFrameLevel, marker)
    level = okLevel and Number(level) or 1
    for _, ripple in ipairs(marker.ripples) do ripple:SetFrameLevel(level + 1) end
    marker.face:SetFrameLevel(level + 3)
    marker.plate:SetFrameLevel(level + 3)

    local name = ShownName(hunt.place.name)
    if name and name ~= "" then
        marker.plate.text:SetText(name)
        local okW, width = pcall(marker.plate.text.GetStringWidth, marker.plate.text)
        width = okW and Number(width) or 60
        marker.plate:SetWidth(math.max(40, width + 14))
        marker.plate:Show()
    else
        marker.plate:Hide()
    end

    local Motion = ns.Motion
    local moving = not Motion or Motion.Level() == "full"
    marker.moving = moving
    for _, group in ipairs(marker.motions) do
        if moving then pcall(group.Play, group) else pcall(group.Stop, group) end
    end
    for _, ripple in ipairs(marker.ripples) do
        if moving and ripple.motion then
            ripple:Show()
            pcall(ripple.motion.Play, ripple.motion)
        else
            if ripple.motion then pcall(ripple.motion.Stop, ripple.motion) end
            ripple:Hide()
        end
    end
end

function MapPins:Draw()
    local view = self:IsEnabled() and self:View() or nil

    local key = view and ("%d:%s:%s:%s:%d"):format(view.mapID, view.scale, view.width, view.height,
        self.version or 0) or "none"
    if key == self.key then return end
    self.key = key

    -- The hunts are only gathered again for a new map or a change to them:
    -- the upgrade quest's next place reads the quest log and bags, and a
    -- zoom changes the scale five times a second while the map is open, so
    -- a zoom only re-places the pins it has.
    local huntsKey = view and ("%d:%s:%d"):format(view.mapID, tostring(view.name), self.version or 0) or "none"
    if huntsKey ~= self.huntsKey or not self.hunts then
        self.huntsKey = huntsKey
        self.hunts = view and self:HuntsOn(ns.Waypoints and ns.Waypoints:DataZone(view.name, view.mapID)
            or view.name) or {}
    end
    local hunts = self.hunts

    self.pins = self.pins or {}
    self.markers = self.markers or {}
    for _, pin in ipairs(self.pins) do pin:Hide() end
    for _, marker in ipairs(self.markers) do marker:Hide() end
    if not view or #hunts == 0 then return end

    local okLevel, level = pcall(view.canvas.GetFrameLevel, view.canvas)
    level = (okLevel and Number(level) or 1) + 20
    local scale = 1 / view.scale

    local pinCount, markCount = 0, 0
    for _, hunt in ipairs(hunts) do
        local pool, index, make = self.pins, nil, self.MakePin
        if hunt.marked then
            markCount = markCount + 1
            pool, index, make = self.markers, markCount, self.MakeMarker
        else
            pinCount = pinCount + 1
            index = pinCount
        end
        local pin = pool[index]
        if not pin or pin.canvas ~= view.canvas then
            pin = make(self, view.canvas)
            pin.canvas = view.canvas
            pool[index] = pin
        end
        pin.hunt = hunt
        pin.mapID = view.mapID
        pin.icon:SetTexture(Theme.ItemIcon(hunt.link)
            or (hunt.marked and [[Interface\GossipFrame\AvailableQuestIcon]])
            or [[Interface\Icons\INV_Misc_QuestionMark]])
        pin:SetScale(scale)
        pin:SetFrameLevel(hunt.marked and level + 5 or level)
        if pin.big == true then self:DressMarker(pin, hunt) end
        pin:ClearAllPoints()
        pin:SetPoint("CENTER", view.canvas, "TOPLEFT",
            hunt.place.x / 100 * view.width / scale, -hunt.place.y / 100 * view.height / scale)
        pin:Show()
    end
end

function MapPins:OnUpgradeQuestChanged()
    self:OnTrackingChanged()
end

function MapPins:OnTrackingChanged()
    self.version = (self.version or 0) + 1
    self.key = nil
end

function MapPins:Step(elapsed)
    self.since = (self.since or 0) + (elapsed or 0)
    if self.since < STEP then return end
    self.since = 0
    local ok, err = pcall(self.Draw, self)
    if not ok then ns.Debug("map pins:", tostring(err)) end
end

function MapPins:OnEnable()
    local driver = CreateFrame("Frame", nil, UIParent)
    driver:SetScript("OnUpdate", function(_, elapsed) MapPins:Step(elapsed) end)
    driver:Show()
    self.driver = driver
end
