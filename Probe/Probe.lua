-- Blackthornes Equipment -- Probe/Probe.lua
-- /beq probe: ask the running client what it actually supports, rather than
-- trusting documentation written for another version of the game.
--
-- Same idea as Tradeskills' /bts probe. It only reads: nothing is changed,
-- saved or sent anywhere. Every call is inside a pcall, because Forever hands
-- out secret values in instances that raise when touched.

local _, ns = ...

local Probe = ns.NewModule("Probe")

-- The equipment slots worth looking at for a hunter: main hand, off hand and
-- ranged. Forever may have no separate ranged slot; the probe says so.
local SLOTS = { { 16, "main hand" }, { 17, "off hand" }, { 18, "ranged" } }

-- The calls worth knowing about. Talents on Forever turned out to be the
-- newer trait system (C_ClassTalents, C_Traits), not the classic tabs.
local APIS = {
    "UnitClass", "UnitLevel", "CanDualWield", "GetNumTalentTabs", "GetTalentTabInfo",
    "GetNumTalents", "GetTalentInfo", "GetSpecialization",
    "C_SpecializationInfo.GetSpecialization", "C_ClassTalents.GetActiveConfigID",
    "C_Traits.GetConfigInfo", "C_Traits.GetTreeCurrencyInfo", "C_Traits.GetTreeNodes",
    "C_Item.GetItemStats", "GetItemStats", "GetInventoryItemLink",
    "GetQuestItemLink", "GetNumQuestChoices", "GetNumQuestRewards", "GetQuestReward",
    "C_Item.EquipItemByName", "EquipItemByName",
    "C_Traits.GetNodeInfo", "C_Traits.GetEntryInfo", "C_Traits.GetDefinitionInfo",
    "C_Spell.GetSpellName", "GetSpellInfo",
    "C_Item.GetItemInfo", "C_Item.GetItemInfoInstant", "GetItemInfo",
    "C_Container.GetContainerItemLink", "GetContainerItemLink", "ContainerFrame_Update",
    "TooltipDataProcessor.AddTooltipPostCall", "TooltipUtil.GetDisplayedItem",
    "C_Texture.GetAtlasInfo", "QuestInfo_Display", "C_CreatureInfo.GetClassInfo",
    "UnitFactionGroup", "C_SpellBook.IsSpellKnown", "IsPlayerSpell", "IsSpellKnown",
    "GetNumSkillLines", "GetSkillLineInfo",
    -- The upgrade finder: who the character is, where they stand, which
    -- quests they have done, and asking the server about unseen items.
    "UnitRace", "GetRealZoneText", "C_QuestLog.IsQuestFlaggedCompleted",
    "IsQuestFlaggedCompleted", "C_Item.IsItemDataCachedByID",
    "C_Item.RequestLoadItemDataByID", "C_Reputation.GetFactionDataByID",
    "GetFactionInfoByID",
    -- Crafted upgrades, show on map, and the vendor and loot window arrows.
    "C_TradeSkillUI.GetAllProfessionTradeSkillLines", "C_TradeSkillUI.GetProfessionInfoBySkillLineID",
    "C_Map.GetBestMapForUnit", "C_Map.GetMapInfo", "C_Map.GetMapChildrenInfo",
    "C_Map.SetUserWaypoint", "UiMapPoint.CreateFromCoordinates",
    "C_SuperTrack.SetSuperTrackedUserWaypoint", "OpenWorldMap",
    "C_Map.CanSetUserWaypointOnMap", "C_Map.GetMapRectOnMap", "C_Map.HasUserWaypoint",
    "GetMerchantItemLink", "MerchantFrame_UpdateMerchantInfo", "GetLootSlotLink", "LootFrame_Update",
    -- The upgrade quest: is a quest in the log, are its objectives done,
    -- and how many of an item the bags hold.
    "C_QuestLog.IsOnQuest", "C_QuestLog.GetLogIndexForQuestID", "C_QuestLog.IsComplete",
    "C_QuestLog.ReadyForTurnIn", "C_Item.GetItemCount", "GetItemCount",
    -- Learning where vendors and trainers stand (Logic/NPCSpots.lua).
    "C_Map.GetPlayerMapPosition",
    -- Learning what vendors charge, and whether the character can pay.
    "GetMerchantNumItems", "C_MerchantFrame.GetItemInfo", "GetMerchantItemInfo", "GetMerchantItemID",
    "GetMoney",
    -- The quest arrow (Logic/QuestArrow.lua): world coordinates, a map's
    -- size in yards, and which way the character faces.
    "C_Map.GetWorldPosFromMapPos", "C_Map.GetMapWorldSize", "CreateVector2D", "GetPlayerFacing",
    "IsInInstance",
}
-- The Quest log tab (Logic/QuestLog.lua) adds its own list below.

local function Has(path)
    local value = _G
    for part in path:gmatch("[^.]+") do
        if type(value) ~= "table" then return false end
        value = value[part]
    end
    return type(value) == "function"
end

local function Line(label, value)
    local ok, text = pcall(tostring, value)
    ns.PrintRaw(("  |c%s%s|r  %s"):format(ns.COLORS.muted, label, ok and text or "(unreadable)"))
end

--- Walk the active talent config as far as the client lets us: its id, its
--- trees, and for each tree how many points are spent and how many nodes it
--- has. This is what decides how Weights will read the spec on Forever.
function Probe:Traits()
    if not Has("C_ClassTalents.GetActiveConfigID") then return end

    local ok, configID = pcall(C_ClassTalents.GetActiveConfigID)
    if not ok or not configID then
        Line("talent config", "none active (no points yet?)")
        return
    end
    Line("talent config", configID)

    if not Has("C_Traits.GetConfigInfo") then return end
    local okInfo, info = pcall(C_Traits.GetConfigInfo, configID)
    if not okInfo or type(info) ~= "table" then
        Line("config info", "not readable")
        return
    end

    local trees = type(info.treeIDs) == "table" and info.treeIDs or {}
    Line("config", ("type %s, name %s, %d tree(s)"):format(
        tostring(info.type), tostring(info.name), #trees))

    for index, treeID in ipairs(trees) do
        local parts = { "id " .. tostring(treeID) }

        if Has("C_Traits.GetTreeCurrencyInfo") then
            local okCur, currencies = pcall(C_Traits.GetTreeCurrencyInfo, configID, treeID, false)
            if okCur and type(currencies) == "table" then
                for _, currency in ipairs(currencies) do
                    parts[#parts + 1] = ("spent %s of %s"):format(
                        tostring(currency.spent), tostring(currency.maxQuantity or currency.quantity))
                end
            end
        end

        local nodes
        if Has("C_Traits.GetTreeNodes") then
            local okNodes, list = pcall(C_Traits.GetTreeNodes, treeID)
            if okNodes and type(list) == "table" then
                nodes = list
                parts[#parts + 1] = #nodes .. " nodes"
            end
        end

        Line("  tree " .. index, table.concat(parts, ", "))
        if nodes then self:Nodes(configID, nodes) end
    end
end

--- The name of the talent a node grants, or nil. Node, entry, definition,
--- spell: four calls, any of which may be missing or raise.
function Probe:NodeName(configID, info)
    local entryID = type(info.entryIDs) == "table" and info.entryIDs[1]
    if not entryID or not Has("C_Traits.GetEntryInfo") then return nil end

    local ok, entry = pcall(C_Traits.GetEntryInfo, configID, entryID)
    if not ok or type(entry) ~= "table" or not entry.definitionID then return nil end
    if not Has("C_Traits.GetDefinitionInfo") then return nil end

    local okDef, definition = pcall(C_Traits.GetDefinitionInfo, entry.definitionID)
    if not okDef or type(definition) ~= "table" then return nil end
    if type(definition.overrideName) == "string" and definition.overrideName ~= "" then
        return definition.overrideName
    end

    local spellID = definition.spellID
    if not spellID then return nil end
    if Has("C_Spell.GetSpellName") then
        local okName, name = pcall(C_Spell.GetSpellName, spellID)
        if okName and type(name) == "string" then return name end
    end
    if Has("GetSpellInfo") then
        local okName, name = pcall(GetSpellInfo, spellID)
        if okName and type(name) == "string" then return name end
    end
    return "spell " .. tostring(spellID)
end

--- How the nodes of one tree are laid out, so the three specs can be told
--- apart: each column (by horizontal position) with its node count and the
--- name of its top talent, and every talent with points in it.
function Probe:Nodes(configID, nodes)
    if not Has("C_Traits.GetNodeInfo") then return end

    local columns, purchased = {}, {}
    for _, nodeID in ipairs(nodes) do
        local ok, info = pcall(C_Traits.GetNodeInfo, configID, nodeID)
        if ok and type(info) == "table" and type(info.posX) == "number" then
            local x = math.floor(info.posX + 0.5)
            local column = columns[x]
            if not column then
                column = { x = x, count = 0 }
                columns[x] = column
            end
            column.count = column.count + 1

            local y = tonumber(info.posY) or 0
            if not column.topY or y < column.topY then
                column.topY = y
                column.top = self:NodeName(configID, info)
            end

            local ranks = tonumber(info.ranksPurchased) or tonumber(info.currentRank) or 0
            if ranks > 0 then
                purchased[#purchased + 1] = ("%s %d at x%d"):format(
                    self:NodeName(configID, info) or ("node " .. tostring(nodeID)), ranks, x)
            end
        end
    end

    local sorted = {}
    for _, column in pairs(columns) do sorted[#sorted + 1] = column end
    table.sort(sorted, function(a, b) return a.x < b.x end)

    local parts = {}
    for _, column in ipairs(sorted) do
        parts[#parts + 1] = ("x%d: %d (%s)"):format(column.x, column.count, column.top or "?")
    end
    Line("  columns", #parts > 0 and table.concat(parts, "; ") or "no positions readable")
    Line("  spent in", #purchased > 0 and table.concat(purchased, "; ") or "nothing yet")
end

--- The raw table GetItemStats returns for a link, from whichever version of
--- the call the client has, or nil.
function Probe:ItemStats(link)
    if Has("C_Item.GetItemStats") then
        local ok, stats = pcall(C_Item.GetItemStats, link)
        if ok and type(stats) == "table" then return stats end
    end
    if Has("GetItemStats") then
        local ok, stats = pcall(GetItemStats, link)
        if ok and type(stats) == "table" then return stats end
    end
    return nil
end

--- Every class this client knows, as class tokens, with any this addon has
--- no weights for marked. Forever may have classes classic did not.
function Probe:Classes()
    if not Has("C_CreatureInfo.GetClassInfo") then return "not readable" end

    local names = {}
    for id = 1, 30 do
        local ok, info = pcall(C_CreatureInfo.GetClassInfo, id)
        if ok and type(info) == "table" and type(info.classFile) == "string" then
            local token = info.classFile
            if not ns.Weights.SPECS[token] then token = token .. " (no weights)" end
            names[#names + 1] = token
        end
    end
    return #names > 0 and table.concat(names, ", ") or "none listed"
end

function Probe:Run()
    ns.Print("probe: what this client supports")

    -- Two lines rather than one per call, so the whole probe fits in the
    -- chat window without scrolling.
    local present, missing = {}, {}
    for _, api in ipairs(APIS) do
        if Has(api) then
            present[#present + 1] = api
        else
            missing[#missing + 1] = api
        end
    end
    Line("has", #present > 0 and table.concat(present, ", ") or "none of them")
    Line("missing", #missing > 0 and table.concat(missing, ", ") or "nothing")

    if Has("UnitLevel") then
        local ok, level = pcall(UnitLevel, "player")
        Line("level", ok and level or "unreadable")
    end

    if Has("C_SpecializationInfo.GetSpecialization") then
        local ok, index = pcall(C_SpecializationInfo.GetSpecialization)
        Line("spec index", ok and tostring(index) or "raised")
    end

    self:Traits()
    self:QuestLog()

    local Weights = ns.Weights
    Line("class", Weights:PlayerClass() or "unknown")
    Line("classes", self:Classes())
    if type(CanDualWield) == "function" then
        local ok, can = pcall(CanDualWield)
        Line("can dual wield", ok and tostring(can) or "raised")
    else
        Line("can dual wield", "no CanDualWield, using classic's levels")
    end

    local points = Weights:TreePoints(Weights:PlayerClass())
    if points then
        local parts = {}
        for tab, spent in ipairs(points) do parts[tab] = tostring(spent) end
        Line("points per spec", table.concat(parts, " / "))
    else
        Line("points per spec", "no talents to read")
    end

    if ns.WeaponSkills then
        local skills = ns.WeaponSkills
        Line("faction", skills:Faction() or "unknown")
        local ok, known = pcall(skills.Known, skills)
        local names = {}
        if ok and known then
            for subclassID in pairs(known) do
                names[#names + 1] = ns.WeaponTrainers.SKILLS[subclassID].name
            end
            table.sort(names)
        end
        Line("weapon skills", #names > 0 and table.concat(names, ", ")
            or "none read, so no trainer lines")
    end

    if ns.Enchants then
        -- The enchant on each worn piece, read off its link, and how many
        -- of them the enchant data knows.
        local parts, known = {}, 0
        for _, slot in ipairs(ns.Enchants.SLOTS) do
            local ok, link = pcall(function() return ns.Items:Equipped(slot) end)
            local enchant = ok and link and ns.Enchants.EnchantOf(link) or nil
            if enchant then
                parts[#parts + 1] = slot .. "=" .. enchant
                if ns.EnchantData and ns.EnchantData.EFFECTS[enchant] then known = known + 1 end
            end
        end
        Line("worn enchants", #parts > 0 and (table.concat(parts, ", ") .. " (" .. known .. " known)")
            or "none read")
    end

    if ns.DungeonQuests then
        local ok, text = pcall(ns.DungeonQuests.Describe, ns.DungeonQuests)
        Line("dungeon quests", ok and text or "could not read")
        local okTitles, titles = pcall(ns.DungeonQuests.DescribeTitles, ns.DungeonQuests)
        Line("quest names", okTitles and titles or "could not read")
    end
    if ns.DungeonDoors then
        local ok, text = pcall(ns.DungeonDoors.Describe, ns.DungeonDoors)
        Line("dungeon doors", ok and text or "could not read")
    end
    if ns.Names then
        local ok, text = pcall(ns.Names.ProbeText, ns.Names)
        Line("names", ok and text or "could not read")
    end

    local spec, why = Weights:CurrentSpec()
    Line("judged as", spec and (spec .. " (" .. why .. ")") or "no weights for this class")

    if ns.BagIcons then
        local frames, hooks = ns.BagIcons:Describe()
        Line("bag windows", frames)
        Line("bag hooks", hooks)
        Line("arrows showing", ns.BagIcons.lastShown or "bags not looked at yet")
    end
    if ns.LootRolls then
        local frames, hooks = ns.LootRolls:Describe()
        Line("loot roll windows", frames)
        Line("loot roll hooks", hooks)
    end
    if ns.Tooltip and ns.Tooltip.fired then
        local parts = {}
        for source, count in pairs(ns.Tooltip.fired) do
            parts[#parts + 1] = ("%s %d"):format(source, count)
        end
        Line("tooltip lines added", #parts > 0 and table.concat(parts, ", ") or "none yet")
    end
    pcall(self.Upgrades, self)

    -- The Blizzard window style draws with the game's own art; this says
    -- which pieces the client has (UI/BlizzardLook.lua).
    if ns.BlizzardLook then
        local ok, lines = pcall(ns.BlizzardLook.ProbeLines)
        for _, text in ipairs(ok and lines or {}) do
            local name, value = text:match("^(.-): (.*)$")
            Line(name or "window style", value or text)
        end
    end

    -- Ratings, the hit cap and racials (Weights:RatingPer, Compare:CurrentHit,
    -- Weights:Racials).
    pcall(function()
        local parts = {}
        for _, key in ipairs({ "ITEM_MOD_HIT_RATING_SHORT", "ITEM_MOD_CRIT_RATING_SHORT",
            "ITEM_MOD_DODGE_RATING_SHORT", "ITEM_MOD_DEFENSE_SKILL_RATING_SHORT" }) do
            local rating = Weights.RATINGS and Weights.RATINGS[key]
            if rating then
                parts[#parts + 1] = ("%s=%.2f"):format(key:gsub("^ITEM_MOD_", ""):gsub("_SHORT$", ""):lower(),
                    Weights:RatingPer(rating))
            end
        end
        Line("rating for 1%", #parts > 0 and table.concat(parts, ", ") or "none")
        local melee, spell = ns.Compare:CurrentHit("melee"), ns.Compare:CurrentHit("spell")
        Line("hit now", ("weapons %s, spells %s"):format(melee and ("%.2f%%"):format(melee) or "unknown",
            spell and ("%.2f%%"):format(spell) or "unknown"))
        local racial = {}
        for stat, factor in pairs(Weights:Racials()) do
            racial[#racial + 1] = ("%s x%.2f"):format(stat, factor)
        end
        table.sort(racial)
        Line("racial stat bonuses", #racial > 0 and table.concat(racial, ", ") or "none")
    end)

    if not Has("GetInventoryItemLink") then return end

    for _, slot in ipairs(SLOTS) do
        local ok, link = pcall(GetInventoryItemLink, "player", slot[1])
        if not ok or not link then
            Line(slot[2], "empty or not readable")
        else
            local stats = self:ItemStats(link)
            if not stats then
                Line(slot[2], "no stats readable")
            else
                local keys = {}
                for key, value in pairs(stats) do
                    keys[#keys + 1] = ("%s=%s"):format(tostring(key), tostring(value))
                end
                table.sort(keys)
                Line(slot[2], table.concat(keys, ", "))

                local _, unknown = Weights:Normalize(stats)
                if #unknown > 0 then
                    Line("  not weighted", table.concat(unknown, ", "))
                end

                -- School spell damage, read off the tooltip (Items:SchoolDamage).
                local schools = ns.Items and ns.Items:SchoolDamage(link)
                if schools and next(schools) then
                    local parts = {}
                    for name, amount in pairs(schools) do
                        parts[#parts + 1] = ("%s=%d"):format(name, amount)
                    end
                    table.sort(parts)
                    Line("  school damage", table.concat(parts, ", "))
                end
            end
        end
    end
end

--- The Quest log tab (Logic/QuestLog.lua, UI/QuestLogTab.lua): which quest
--- log calls and tracker frames this client has, and what reading the log
--- found. Only reads.
function Probe:QuestLog()
    local log = ns.QuestLog
    if not log then return end
    local present, missing = {}, {}
    for _, name in ipairs(log.CALLS) do
        local value = _G
        for part in name:gmatch("[^.]+") do
            value = type(value) == "table" and rawget(value, part) or nil
        end
        if type(value) == "function" or type(value) == "table" then
            present[#present + 1] = name
        else
            missing[#missing + 1] = name
        end
    end
    Line("quest log has", #present > 0 and table.concat(present, ", ") or "none of them")
    Line("quest log missing", #missing > 0 and table.concat(missing, ", ") or "nothing")
    local ok, text = pcall(log.Describe, log)
    Line("quest log", ok and text or "raised")
end

--- The upgrade hunt and crafting features: the professions read, whether a link
--- with a random roll gives that roll's stats, and whether a zone's map
--- can be found for a pin.
function Probe:Upgrades()
    if ns.Crafting then
        local parts = {}
        for line, skill in pairs(ns.Crafting:Professions()) do
            parts[#parts + 1] = ("%s %d"):format(ns.Crafts.PROFESSIONS[line] or line, skill)
        end
        table.sort(parts)
        Line("professions", #parts > 0 and table.concat(parts, ", ") or "none read")
        Line("Tradeskills recipes", next(ns.Crafting:Known()) and "read" or "none (not loaded, or no window opened yet)")
    end
    local data = ns.RollData
    local itemID, group = next(data and data.ITEMS or {})
    if itemID and ns.Rolls then
        local roll = data.GROUPS[group][1]
        local name, stats = ns.Rolls:Describe(ns.Rolls.Link(itemID, roll))
        Line("random roll stats", stats and ((name or "unnamed") .. ": " .. stats)
            or "not readable (the item may not be cached yet; try again)")
    end
    self:RollReadLine()
    if ns.Waypoints then
        local zone = _G.GetRealZoneText and select(2, pcall(_G.GetRealZoneText))
        local mapID = type(zone) == "string" and ns.Waypoints:MapFor(zone)
        local takes = ""
        local map = _G.C_Map
        if mapID and map and type(map.CanSetUserWaypointOnMap) == "function" then
            local ok, can = pcall(map.CanSetUserWaypointOnMap, mapID)
            takes = ok and (can == false and ", takes no pin" or ", takes a pin") or ""
        end
        Line("map pin", ns.Waypoints:CanPin() and ("can pin; this zone's map " .. tostring(mapID or "not found") .. takes)
            or "this client cannot pin")
    end
    if ns.NPCSpots then
        -- Target a vendor (or any NPC) before probing to see what would be kept.
        local spots = ns.NPCSpots
        local zone, x, y, mapID = spots:Here()
        Line("standing at", zone and ("%s (%s, %s), map %s"):format(zone, x, y, tostring(mapID))
            or "not readable here (inside an instance?)")
        local seen = spots:Read("target")
        Line("target NPC", seen and ("%s, ID %d"):format(seen.name or "unnamed", seen.npcID)
            or "none (target an NPC to see its ID)")
        Line("vendor spots learned", spots:Count())
        Line("vendor prices learned", spots:PriceCount())
    end
    if ns.ClassTraining then
        local ok, text = pcall(ns.ClassTraining.ProbeText, ns.ClassTraining)
        Line("class training", ok and text or "error")
    end
end

ns.RegisterHiddenCommand("probe", function()
    ns.KeepCheck("probe", Probe.Run, Probe)
end)

--- How the first rolled gear in the bags is read: the game's own stats for
--- it, what its tooltip adds, and which way the tooltip was read.
function Probe:RollReadLine()
    local items = ns.Items
    if not items then return end
    local getLink = _G.C_Container and _G.C_Container.GetContainerItemLink or _G.GetContainerItemLink
    local getSlots = _G.C_Container and _G.C_Container.GetContainerNumSlots or _G.GetContainerNumSlots
    if type(getLink) ~= "function" or type(getSlots) ~= "function" then return end
    local rolled
    for bag = 0, 4 do
        local okSlots, slots = pcall(getSlots, bag)
        for slot = 1, okSlots and tonumber(slots) or 0 do
            local ok, link = pcall(getLink, bag, slot)
            link = ok and items.PlainLink(link)
            if link and items.RollID(link) then rolled = link break end
        end
        if rolled then break end
    end
    Line("tooltip data calls", ("C_TooltipInfo %s, SurfaceArgs %s"):format(
        tostring(Has("C_TooltipInfo.GetHyperlink")), tostring(Has("TooltipUtil.SurfaceArgs"))))
    if not rolled then
        Line("rolled gear in bags", "none")
        return
    end
    local function Keys(stats)
        local parts = {}
        for key, value in pairs(stats or {}) do parts[#parts + 1] = key .. "=" .. tostring(value) end
        table.sort(parts)
        return #parts > 0 and table.concat(parts, ", ") or "none"
    end
    local okApi, api = pcall(_G.GetItemStats, rolled)
    Line("rolled gear in bags", (rolled:match("%[(.-)%]") or rolled) .. ", roll " .. tostring(items.RollID(rolled)))
    Line("game's stats for it", okApi and Keys(api) or "not readable")
    local data = items.TooltipData(rolled)
    local first = data and type(data.lines) == "table" and data.lines[2]
    Line("tooltip data", data and (("%d lines, line 2 has leftText %s, args %s"):format(
        type(data.lines) == "table" and #data.lines or 0, tostring(first and type(first.leftText)),
        tostring(first and type(first.args)))) or "none")
    local scan = items.ScanTooltip(rolled)
    Line("hidden tooltip", scan and (#scan.lines .. " lines") or "none")
    local okShown, shown = pcall(items.TooltipStats, items, rolled)
    Line("roll stats read", okShown and Keys(shown) or "error")
    local read = items.rollRead or {}
    Line("roll read by", tostring(read.how) .. ", " .. tostring(read.lines) .. " lines")
    local okStats, stats = pcall(items.Stats, items, rolled)
    Line("stats counted", okStats and Keys(stats) or "error")
end
