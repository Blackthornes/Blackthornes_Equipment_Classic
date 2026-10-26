-- Sending vendors and quest rewards to the addon's maker
-- (Logic/Contribute.lua, 2026-10-18).
--
-- What must hold:
--   1. Off by default, North America and English clients only, and a
--      recipient never sends.
--   2. A player who ticked it whispers both recipients; whichever is online
--      asks, takes the table once, says so, and keeps it apart from its own
--      learned vendors and quests.
--   3. The same data again is not asked for; nobody else is answered;
--      junk is left out; nothing flows back to the player.

local saved, stubbed = {}, { "time", "GetTime", "UnitName", "GetUnitSurname", "C_ChatInfo", "C_Timer",
                        "InCombatLockdown", "SendAddonMessage", "ERR_CHAT_PLAYER_NOT_FOUND_S",
                        "GetCurrentRegion", "GetCurrentRegionName", "PlaySound", "UIErrorsFrame", "date",
                        "GetNormalizedRealmName", "GetRealmName" }
for _, name in ipairs(stubbed) do saved[name] = _G[name] end

local passed, failed = 0, 0
local function check(label, got, want)
    if want == nil then want = true end
    if got == want then
        passed = passed + 1
        print(("  ok    %-60s %s"):format(label, tostring(got)))
    else
        failed = failed + 1
        print(("  FAIL  %-60s got %s, want %s"):format(label, tostring(got), tostring(want)))
    end
end

local clock, uptime = 1790000000, 1000
time = function() return clock end
GetTime = function() return uptime end
date = function() return "Oct 18 14:02" end
C_Timer = { NewTicker = function() return { Cancel = function() end } end, After = function() end }
InCombatLockdown = function() return false end
ERR_CHAT_PLAYER_NOT_FOUND_S = "No player named '%s' is currently playing."
SendAddonMessage = nil
GetCurrentRegionName = nil
local region = 1
GetCurrentRegion = function() return region end
-- The owner's Era characters are on Ashkandi; a whisper reaches only there.
local realm = "Ashkandi"
GetNormalizedRealmName = function() return realm end
GetRealmName = nil
local sounds, flashes = 0, {}
PlaySound = function() sounds = sounds + 1 end
UIErrorsFrame = { AddMessage = function(_, text) flashes[#flashes + 1] = text end }

local network, current = {}, nil
C_ChatInfo = {
    RegisterAddonMessagePrefix = function() return true end,
    SendAddonMessage = function(_, text, channel, target)
        -- The server takes "Name-Realm" for a whisper; the realm is not part of
        -- the name these pretend clients go by.
        if type(target) == "string" then target = (target:gsub("%-[^%-]+$", "")) end
        assert(#text <= 255, "a message over 255 bytes went out")
        network[#network + 1] = { from = current.full, text = text, channel = channel, target = target }
        return 0
    end,
}
UnitName = function() return current.first end
GetUnitSurname = function() return current.last end

local english = true

local function NewClient(full)
    -- Era characters have no last name.
    local first, last = full:match("^(%S+) (%S+)$")
    if not first then first = full end
    local ns = { commands = {} }
    ns.NewModule = function(module) local m = {}; ns[module] = m; return m end
    ns.RegisterCommand, ns.RegisterEvent, ns.UnregisterEvent = function() end, function() end, function() end
    local chat = {}
    ns.Print = function(text) chat[#chat + 1] = text end
    ns.PrintRaw, ns.Debug = function() end, function() end
    ns.Waypoints = { English = function() return english end }
    ns.db = {}
    local client = { full = full, first = first, last = last, ns = ns, chat = chat, online = true }
    current = client
    for _, file in ipairs({ "Core/Serialize.lua", "Core/Comm.lua", "Logic/Contribute.lua" }) do
        assert(loadfile(lfs_cwd .. "/" .. file))("Blackthornes_Equipment", ns)
    end
    ns.Contribute:OnEnable()
    return client
end

local clients = {}
local function Run()
    for _ = 1, 600 do
        uptime = uptime + 2
        for _, client in ipairs(clients) do
            current = client
            client.ns.Comm:Pump()
        end
        if #network == 0 then
            local busy = false
            for _, client in ipairs(clients) do
                if client.ns.Comm:Pending() > 0 then busy = true end
            end
            if not busy then return end
        end
        local batch = network
        network = {}
        for _, message in ipairs(batch) do
            for _, client in ipairs(clients) do
                if client.online and message.channel == "WHISPER" and message.target == client.full then
                    current = client
                    client.ns.Comm:CHAT_MSG_ADDON("CHAT_MSG_ADDON", "BEQshare", message.text,
                        message.channel, message.from)
                end
            end
        end
    end
end

local ana = NewClient("Ana Smith")
local farmer = NewClient("Blackthornes")
local wither = NewClient("Blacklock")
local carl = NewClient("Carl Jones")
clients = { ana, farmer, wither, carl }
-- Both of the owner's characters are on one account: one save between them.
wither.ns.db = farmer.ns.db

ana.ns.db.learnedQuests = {
    [90001] = { title = "Skyfall Supplies", level = 12, min = 8, giver = "Vela Brightwind",
        zone = "Zephras Isle", x = 41.2, y = 55.8, side = "A",
        rewards = { { 210001, 10, 18, false }, { 210002, 10, 18, true } } },
    [90002] = { title = "No gear", rewards = {}, items = { { 6948, 3, true }, { -1, 1 } },
        money = 1500, xp = 420 },
    [90003] = { title = "Bad|cffff0000colour", rewards = { { 5, 1, 1 } } }, -- left out
}
ana.ns.db.learnedDungeonQuests = {
    [91001] = { dungeon = "2601", title = "Into the Deep", level = 18, min = 14, side = "A",
        giver = "Rell Stone", zone = "Zephras Isle", x = 12.5, y = 80.1, reward = 210004, at = 5 },
    [91002] = { dungeon = "Deep", title = "Bad dungeon" },                -- left out
}
ana.ns.db.learnedVendors = {
    [800001] = { name = "Orin Gale", zone = "Zephras Isle", x = 30.5, y = 61.0, side = "A",
        items = { [210010] = { 1500, 12, 20, false }, [210011] = { 900, 0, 0, true } }, at = 5 },
    [800002] = { name = "Lost", zone = "Zephras Isle", x = 250, y = 10, items = { [1] = { 1 } } }, -- off the map
}
-- Ana's own record never reaches the recipients' own lists.
farmer.ns.db.learnedVendors = { [700001] = { name = "Mine", zone = "Elwynn Forest", x = 1, y = 1,
    items = { [3] = { 1, 0, 0, false } } } }

print("\nchoosing")
local C = ana.ns.Contribute
check("off by default", C:On(), false)
check("the shipped list names two characters", #C:Recipients(), 2)
realm = "Mankrik"
check("on another realm nobody is named", #C:Recipients(), 0)
realm = nil
check("with the realm not read, nobody is named", #C:Recipients(), 0)
realm = "Ashkandi"
check("realms compare without spaces or case",
    C.RealmKey("Ana-Some Realm") == C.RealmKey("Bob-somerealm") and C.RealmKey("Ana") == nil)
check("no Forever character is named", (function()
    for _, name in ipairs(C.RECIPIENTS) do
        if name:find(" ", 1, true) or not name:find("-Ashkandi$") then return false end
    end
    return true
end)())
current = farmer
check("Blackthornes receives", farmer.ns.Contribute:Receiving())
realm = "Mankrik"
check("the same name on another realm does not", farmer.ns.Contribute:Receiving(), false)
realm = "Ashkandi"
current = wither
check("Blacklock receives", wither.ns.Contribute:Receiving())
current = carl
check("anyone else does not", carl.ns.Contribute:Receiving(), false)
current = ana
check("not sending while off", C:Sending(), false)
C:SetOn(true)
check("sending once ticked", C:Sending())
region = 3
check("Europe sends nothing", C:Sending(), false)
region = 110
check("the Forever test client's 110 is not this copy's", C:Sending(), false)
region = 1
english = false
check("a German client sends nothing", C:Sending(), false)
english = true
current = farmer
farmer.ns.db.shareData = true
check("a recipient never sends", farmer.ns.Contribute:Sending(), false)

print("\nthe command")
current = ana
C:Command("off")
check("off says so", ana.chat[#ana.chat], "Sharing your data with Blackthornes is off.")
check("and turns it off", C:On(), false)
C:Command("on")
check("on thanks the player", ana.chat[#ana.chat], "Sharing your data with Blackthornes is on. Thank you.")
check("it is a hidden command", type(ana.ns.commands.share) == "table")
local chatBefore = #ana.chat

print("\nsending")
farmer.online, wither.online = false, true
current = ana
C:Hello()
Run()
local store = farmer.ns.db.sharedData
local id = ana.ns.db.shareDataId
check("the online character took it", type(store) == "table" and type(store[id]) == "table")
local got = store and store[id] or {}
local quest = got.quests and got.quests[90001]
check("a quest came whole", quest and quest.title, "Skyfall Supplies")
check("with its giver's spot", quest and quest.x, 41.2)
check("and both rewards", quest and #quest.rewards, 2)
local plain = got.quests and got.quests[90002]
check("a quest with no gear still came", plain and plain.title, "No gear")
check("with its other rewards and counts", plain and plain.items and plain.items[1][2], 3)
check("a bad reward item was left out", plain and plain.items and #plain.items, 1)
check("with its money", plain and plain.money, 1500)
check("and its XP", plain and plain.xp, 420)
local dungeon = got.dungeons and got.dungeons[91001]
check("a dungeon quest came", dungeon and dungeon.title, "Into the Deep")
check("with its dungeon", dungeon and dungeon.dungeon, "2601")
check("a dungeon quest with a bad dungeon was left out", got.dungeons and got.dungeons[91002] == nil)
check("a title with colour codes was left out", got.quests and got.quests[90003] == nil)
local vendor = got.vendors and got.vendors[800001]
check("a vendor came whole", vendor and vendor.name, "Orin Gale")
check("with its stock", vendor and vendor.items[210010][1], 1500)
check("a vendor off the map was left out", got.vendors and got.vendors[800002] == nil)
check("one chat line names the sender", wither.chat[#wither.chat], "Got 1 vendor and 3 quests from Ana Smith.")
check("with a sound", sounds, 1)
check("and a line on screen", #flashes, 1)
check("the sender heard nothing back", #ana.chat, chatBefore)
check("it is logged", farmer.ns.db.sharedDataLog and #farmer.ns.db.sharedDataLog, 1)
check("the recipient's own vendors are untouched", farmer.ns.db.learnedVendors[800001] == nil)
check("and still its own", farmer.ns.db.learnedVendors[700001] ~= nil)
check("no learned quests were made for it", farmer.ns.db.learnedQuests == nil)

print("\nagain")
-- One account: only one of the two is ever online at once.
farmer.online, wither.online = true, false
local lines = #wither.chat + #farmer.chat
clock = clock + 3600
current = ana
C:Hello()
Run()
check("the same data again is not asked for", #wither.chat + #farmer.chat, lines)

ana.ns.db.learnedQuests[90004] = { title = "Windward Watch", level = 14,
    rewards = { { 210003, 12, 20, false } } }
clock = clock + 3600
current = ana
C:Hello()
Run()
check("new data is taken once", #wither.chat + #farmer.chat, lines + 1)
check("and says how many", farmer.chat[#farmer.chat], "Got 1 vendor and 4 quests from Ana Smith.")
check("and replaces the old", farmer.ns.db.sharedData[id].quests[90004] ~= nil)

print("\nstrangers and junk")
current = ana
local before = #network
ana.ns.Contribute:OnAsk("Carl Jones", id, "WHISPER")
check("someone not on the list is never answered", #network + ana.ns.Comm:Pending(), before)
current = carl
carl.ns.Contribute:OnHello("Ana Smith", id .. ":abc", "WHISPER")
check("someone not on the list never asks", carl.ns.Comm:Pending(), 0)
current = farmer
farmer.ns.Contribute.current = nil
farmer.ns.Contribute:OnTable("Ana Smith", { i = id, q = {}, v = {} }, "WHISPER")
check("a table nobody asked for is not kept", farmer.ns.db.sharedData[id].quests[90004] ~= nil)
check("junk is refused", farmer.ns.Contribute:Clean({ q = "x", v = {} }) == nil)
local bad = farmer.ns.Contribute.CleanQuest({ title = "T", rewards = { { -4, 1, 1 } } })
check("a bad item ID is left out", bad and #bad.rewards, 0)
check("an older sender with no dungeon quests is still taken",
    farmer.ns.Contribute:Clean({ q = {}, v = {} }) ~= nil)

print("\nfitting")
local F = farmer.ns.Contribute
local big = { q = {}, v = {}, d = {} }
for questID = 1, 400 do
    big.q[questID] = { title = string.rep("x", 60) .. questID, rewards = {} }
end
local budget = F.BUDGET
F.BUDGET = 8000
F.Fit(big)
local kept, lowest = 0, nil
for questID in pairs(big.q) do
    kept = kept + 1
    if not lowest or questID < lowest then lowest = questID end
end
check("a table past the budget is cut", kept < 400 and kept > 0)
check("the lowest quest IDs go first", lowest, 400 - kept + 1)
check("and it then fits", #farmer.ns.Serialize.Encode(big) <= 8000)
F.BUDGET = budget

print("\nthe words")
local G = farmer.ns.Contribute.GotLine
check("many and many", G(3, 5, "Bo Lee"), "Got 3 vendors and 5 quests from Bo Lee.")
check("one and many", G(1, 5, "Bo Lee"), "Got 1 vendor and 5 quests from Bo Lee.")
check("many and one", G(3, 1, "Bo Lee"), "Got 3 vendors and 1 quest from Bo Lee.")

print("\nthe log")
current = farmer
farmer.ns.Contribute:PrintLog()
check("lists who sent data", farmer.chat[#farmer.chat], "Oct 18 14:02: 1 vendor and 3 quests from Ana Smith.")
farmer.ns.db.sharedDataLog = nil
farmer.ns.Contribute:PrintLog()
check("says when nobody has", farmer.chat[#farmer.chat], "Nobody has shared data with you yet.")

-- By name, so a global that was nil before goes back to nil.
for _, name in ipairs(stubbed) do _G[name] = saved[name] end
print(("\n%d passed, %d failed"):format(passed, failed))
if failed > 0 then error(("%d contribute check(s) failed"):format(failed)) end
