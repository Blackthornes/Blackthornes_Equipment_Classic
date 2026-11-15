-- Blackthornes Equipment -- UI/UpgradeDone.lua
-- Upgrade Done! (the owner said build it from the upgrade quest mockups,
-- card F, 2026-11-13). When the upgrade quest's gear goes on, a gold plaque
-- rises near the top of the screen with the item and its gain, a few gold
-- sparks fly off it, and "Done: N" ticks up under it. A click puts it away,
-- else it fades after HOLD seconds.
--
-- Runs light: one plaque and SPARKS small textures, made once and reused.
-- Effects Full shows it all, Subtle skips the sparks and the rise, Off just
-- shows the plaque. The chime asks ns.Muted() first. Nothing is saved.

local ADDON, ns = ...
local L = ns.L or setmetatable({}, { __index = function(_, key) return key end })

local Done = ns.NewModule("UpgradeDone")

Done.HOLD = 4
Done.FADE = 0.8
Done.SPARKS = 12
Done.TOP = -150

local function Level()
    local motion = ns.Motion
    return motion and motion.Level and motion.Level() or "full"
end

--- The second line: "Ranger's Chain Vest · +8% in Chest".
function Done.Line(quest)
    local name = (ns.Items and ns.Items.ShowLink and ns.Items.ShowLink(quest.link)) or quest.name or "?"
    local slot = quest.slot and ns.Enchants and ns.Enchants.SlotName and ns.Enchants.SlotName(quest.slot)
    if quest.howMuch and slot then
        return L.Format("%s · %s in %s", name, quest.howMuch, slot)
    end
    return name
end

function Done:Build()
    if self.frame then return self.frame end
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetSize(10, 10)
    frame:SetFrameStrata("HIGH")
    frame:SetPoint("TOP", UIParent, "TOP", 0, Done.TOP)
    frame:Hide()
    self.frame = frame

    local plaque = ns.Plaque.Create(frame, { minWidth = 220 })
    plaque:SetPoint("TOP", frame, "TOP", 0, 0)
    plaque:SetScript("OnClick", function() Done:Hide() end)
    self.plaque = plaque

    local count = ns.Theme.CreateLabel(frame, "small", "gilt", "CENTER")
    count:SetPoint("TOP", plaque, "BOTTOM", 0, -4)
    self.count = count

    self.sparks = {}
    for index = 1, Done.SPARKS do
        local spark = plaque:CreateTexture(nil, "OVERLAY")
        spark:SetSize(4, 4)
        spark:SetColorTexture(ns.Theme.Unpack("gilt"))
        spark:Hide()
        self.sparks[index] = spark
    end

    local timer = CreateFrame("Frame", nil, frame)
    timer:SetScript("OnUpdate", function(_, elapsed) Done:Step(elapsed) end)
    timer:Hide()
    self.timer = timer
    return frame
end

--- Show it for this quest; `count` is how many are done now. Answers true
--- when it showed, so the upgrade quest skips its usual banner.
function Done:Show(quest, count)
    if type(quest) ~= "table" or not ns.Plaque or not ns.Theme then return false end
    self:Build()
    local plaque, frame = self.plaque, self.frame
    plaque:SetLines(L["Upgrade Done!"], Done.Line(quest))
    pcall(plaque.SetIcon, plaque, quest.link and GetItemIcon and GetItemIcon(quest.link) or nil)
    count = tonumber(count) or 0
    local level = Level()

    frame:SetAlpha(1)
    frame:Show()
    plaque:Show()
    self.shown = 0
    self.timer:Show()

    local motion = ns.Motion
    if level == "full" and motion then
        -- Rises a little and "Done" ticks up from the last count.
        motion:Run(frame, "rise", 0.5, function(p)
            frame:SetPoint("TOP", UIParent, "TOP", 0, Done.TOP - 16 * (1 - p))
        end, { ease = motion.EaseOutBack })
        self.count:SetText(L.Format("Done: %d", math.max(0, count - 1)))
        motion:Run(self.count, "tick", 0.6, function(p)
            if p >= 1 then self.count:SetText(L.Format("Done: %d", count)) end
        end, { delay = 0.4 })
        self:Sparks()
        pcall(plaque.Flash, plaque)
    else
        frame:SetPoint("TOP", UIParent, "TOP", 0, Done.TOP)
        self.count:SetText(L.Format("Done: %d", count))
        for _, spark in ipairs(self.sparks) do spark:Hide() end
        if level == "subtle" then pcall(plaque.Flash, plaque) end
    end

    if type(_G.PlaySound) == "function" and not (ns.Muted and ns.Muted()) then
        local kit = _G.SOUNDKIT and _G.SOUNDKIT.IG_QUEST_LIST_COMPLETE
        pcall(_G.PlaySound, kit or 878, "Master")
    end
    return true
end

--- The sparks fly out from the plaque's middle and fade (Full only).
function Done:Sparks()
    local motion = ns.Motion
    for index, spark in ipairs(self.sparks) do
        local angle = (index / #self.sparks) * math.pi * 2
        local reach = 40 + (index % 3) * 18
        spark:ClearAllPoints()
        spark:SetPoint("CENTER", self.plaque, "CENTER", 0, 0)
        spark:SetAlpha(1)
        spark:Show()
        motion:Run(spark, "fly", 0.7 + (index % 4) * 0.1, function(p)
            spark:SetPoint("CENTER", self.plaque, "CENTER", math.cos(angle) * reach * p, math.sin(angle) * reach * 0.6 * p)
            spark:SetAlpha(1 - p)
        end, { done = function() spark:Hide() end })
    end
end

function Done:Step(elapsed)
    if not self.frame or not self.frame:IsShown() then
        if self.timer then self.timer:Hide() end
        return
    end
    -- Held while the mouse is on it.
    local okOver, over = pcall(self.plaque.IsMouseOver, self.plaque)
    if okOver and over then self.shown = 0; self.frame:SetAlpha(1); return end
    self.shown = (self.shown or 0) + elapsed
    if self.shown > Done.HOLD then
        local fade = (self.shown - Done.HOLD) / Done.FADE
        if fade >= 1 then self:Hide() else self.frame:SetAlpha(1 - fade) end
    end
end

function Done:Hide()
    if self.frame then self.frame:Hide() end
    if self.timer then self.timer:Hide() end
end
