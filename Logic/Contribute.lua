-- Blackthornes Equipment -- Logic/Contribute.lua
-- What a player chooses to send to the addon's maker: the vendors, quests
-- and dungeon quests their Equipment learned that the shipped data lacks.
--
-- Asked 2026-10-18 by the owner, as Farmer does for drops and Tradeskills
-- for disenchants: players who opt in send their own `learnedVendors` and
-- `learnedQuests`, so both can be folded into Data/ForeverVendors.lua and
-- Data/ForeverQuests.lua at a release (tools/forever_vendors.py and
-- tools/forever_quests.py with --shared). Since 2026-10-20 (the owner asked
-- for every quest and its rewards) a quest goes with all it gives, not only
-- gear, and `learnedDungeonQuests` goes too, for Data/ForeverDungeonQuests.lua
-- (tools/forever_dungeon_quests.py --shared). Off by default: one tick box
-- on the About page of Settings. Never announced.
--
-- The conversation, one way (Tradeskills' Logic/Contribute.lua):
--   * A player with it ticked whispers a short hello ("Q<id>:<hash>") to
--     each name in RECIPIENTS, soon after login and every five minutes. The
--     hash says what they have; nothing in chat or Settings says whether
--     anyone was there (Comm hides the game's "No player named ..." line).
--   * Only the characters named in RECIPIENTS answer, and only for a hash
--     they have not taken: "R<id>" asks for it. The sender answers only a
--     recipient asking for its own id, at most every SEND_GAP, with one
--     table ("K"). Nothing ever flows back to the player.
--   * What goes: the sender's own learned vendors, quests and dungeon
--     quests, in the shapes Logic/NPCSpots.lua, Logic/QuestLearn.lua and
--     Logic/DungeonQuests.lua keep them, at most BUDGET bytes (newest quest
--     IDs first past that). Nothing about
--     the player or their characters, and nothing taken from anyone else.
--   * On the receiving side each sender's latest table replaces the one
--     before (`sharedData[id]`), so nothing is ever counted twice. It never
--     joins the receiver's own learned vendors or quests, and nothing in the
--     windows reads it. One sender is taken at a time, the next as soon as
--     one is done (or given up after SYNC_TIMEOUT), each at most every
--     SYNC_GAP, and at most MAX_SENDERS are kept.
--   * When a table comes in, one chat line says so, with a sound and a
--     line on screen. `/beq share log` (typed only) lists them.
--   * Only North American players send (InRegion), since a whisper never
--     crosses regions, and only English clients: vendor, quest and zone
--     names come in the client's language, and the shipped data is English.
--
-- Saved, account wide, never renamed: `shareData` (the player's choice),
-- `shareDataId`, and on a receiving account `sharedData` and
-- `sharedDataLog`.

local _, ns = ...
local L = ns.L or setmetatable({ Format = string.format }, { __index = function(_, key) return key end })

local Contribute = ns.NewModule("Contribute")

local Comm = ns.Comm

-- The characters data is sent to, as Name-Realm. Kept only here, never
-- shown to players. This is the Classic Era copy: the owner's Era
-- characters (2026-10-26), never Forever's; the same two as Farmer's and
-- Tradeskills' Classic lists, change all three together. A whisper on Era
-- only reaches the same realm, so a name is used only by players on its
-- realm (Recipients); anyone else has nobody to send to and sees no tick box.
Contribute.RECIPIENTS = {
    "Blackthornes-Ashkandi",
    "Blacklock-Ashkandi",
}

-- North America only, as in Farmer: GetCurrentRegion's 1 is the Americas;
-- a client that will not say sends nothing.
Contribute.REGIONS = { [1] = true }
Contribute.REGION_NAME = "US"

Contribute.HELLO_SECONDS = 300    -- a hello every five minutes (the owner, 2026-10-26)
Contribute.FIRST_HELLO = 30       -- and this long after login
Contribute.SYNC_GAP = 300         -- one sender taken at most this often
Contribute.SYNC_TIMEOUT = 1800    -- an ask left unanswered this long is given up (a big
                                  -- table takes a while at Comm's pace)
Contribute.SEND_GAP = 300         -- a sender answers a recipient at most this often
Contribute.MAX_SENDERS = 500
Contribute.MAX_QUESTS = 6000      -- quests in one table
Contribute.MAX_DUNGEON_QUESTS = 2000
Contribute.BUDGET = 200000        -- bytes in one table, well under Comm.MAX_CHUNKS
Contribute.MAX_VENDORS = 1000     -- vendors in one table
Contribute.MAX_REWARDS = 12       -- rewards on one quest (QuestLearn's REWARDS_MOST)
Contribute.MAX_STOCK = 200        -- items on one vendor (LearnStock reads 200)
Contribute.MAX_ID = 10000000      -- an ID past this is not one
Contribute.MAX_LEVEL = 100
Contribute.MAX_ITEM_LEVEL = 1000
Contribute.MAX_PRICE = 1000000000 -- copper
Contribute.MAX_XP = 1000000
Contribute.MAX_COUNT = 1000       -- of one reward
Contribute.MAX_TEXT = 100         -- a name or title longer than this is junk
Contribute.LOG_KEEP = 100
Contribute.LOG_SHOW = 20

Contribute.queue = {}      -- receiving: { id, name } waiting their turn
Contribute.sentTo = {}     -- sending: recipient key -> time last answered

local function Now()
    return type(time) == "function" and time() or 0
end

local function ValidId(id)
    return type(id) == "string" and #id >= 6 and #id <= 16 and id:match("^%x+$") ~= nil
end

local function WholeNumber(value, low, high)
    return type(value) == "number" and value == math.floor(value) and value >= low and value <= high
end

--- A name or title as plain text: no colour codes, links or control
--- characters, and not too long. Nil otherwise.
local function Text(value)
    if type(value) ~= "string" or value == "" or #value > Contribute.MAX_TEXT then return nil end
    if value:find("|", 1, true) or value:find("%c") then return nil end
    return value
end

--- A spot on a zone's map, as the game gives it (0 to 100 is room enough).
local function Spot(value)
    return type(value) == "number" and value == value and value >= 0 and value <= 100
end

local SIDES = { A = true, H = true, AH = true }

--------------------------------------------------------------------------------
-- Who and where
--------------------------------------------------------------------------------

--- The recipients as { key, name }; a first name alone is never one.
--- "Ana-Some Realm" -> "somerealm": a name's realm as two realms are
--- compared, or nil when it names none.
local function RealmKey(name)
    local realm = type(name) == "string" and name:match("%-(.+)$") or nil
    if not realm then return nil end
    realm = realm:gsub("[%s%-']", ""):lower()
    return realm ~= "" and realm or nil
end
Contribute.RealmKey = RealmKey

--- The realm of the character playing, as RealmKey gives it, or nil.
local function MyRealm()
    local ok, realm = pcall(function()
        local name = type(GetNormalizedRealmName) == "function" and GetNormalizedRealmName() or nil
        if (not name or name == "") and type(GetRealmName) == "function" then name = GetRealmName() end
        return name .. ""
    end)
    if not ok then return nil end
    return RealmKey("x-" .. realm)
end
Contribute.MyRealm = MyRealm

--- Only names on the realm of the character playing count (a name with no
--- realm counts on any), since a whisper reaches no other; with the realm
--- not read, none that name one.
function Contribute:Recipients()
    local list, seen = {}, {}
    local here
    for _, name in ipairs(self.RECIPIENTS) do
        local key = type(name) == "string" and Comm.NameKey(name)
        local realm = key and RealmKey(name)
        if realm then
            here = here or MyRealm() or false
            if realm ~= here then key = nil end
        end
        if key and not seen[key] then
            seen[key] = true
            list[#list + 1] = { key = key, name = name }
        end
    end
    return list
end

function Contribute:IsRecipient(name)
    local key = Comm.NameKey(name)
    if not key then return false end
    for _, recipient in ipairs(self:Recipients()) do
        if recipient.key == key then return true end
    end
    return false
end

--- True when the character playing is one of the recipients, by its name
--- on its own realm.
function Contribute:Receiving()
    local mine = Comm.PlayerName and Comm.PlayerName()
    if type(mine) ~= "string" or mine == "" then return false end
    return self:IsRecipient(mine)
end

--- The player chose to send.
function Contribute:On()
    return type(ns.db) == "table" and ns.db.shareData == true
end

function Contribute:InRegion()
    if type(GetCurrentRegion) == "function" then
        local ok, region = pcall(GetCurrentRegion)
        if ok and type(region) == "number" then return self.REGIONS[region] == true end
    end
    if type(GetCurrentRegionName) == "function" then
        local ok, name = pcall(GetCurrentRegionName)
        if ok and type(name) == "string" then return name == self.REGION_NAME end
    end
    return false
end

--- Vendor, quest and zone names are kept as the client gives them, so only
--- an English client's can join the shipped data.
local function EnglishClient()
    local W = ns.Waypoints
    return not (W and W.English) or W.English()
end

function Contribute:Sending()
    return self:On() and #self:Recipients() > 0 and EnglishClient() and self:InRegion()
        and not self:Receiving()
end

--- Listening is needed only while sending or receiving.
function Contribute:Active()
    return self:Sending() or self:Receiving()
end

--------------------------------------------------------------------------------
-- What goes, checked the same way on both sides
--------------------------------------------------------------------------------

--- One quest as Logic/QuestLearn.lua keeps it, field by field; nil when it
--- is unusable.
function Contribute.CleanQuest(raw)
    if type(raw) ~= "table" then return nil end
    local title = Text(raw.title)
    if not title then return nil end
    local rec = { title = title, rewards = {} }
    if WholeNumber(raw.level, 1, Contribute.MAX_LEVEL) then rec.level = raw.level end
    if WholeNumber(raw.min, 1, Contribute.MAX_LEVEL) then rec.min = raw.min end
    local giver, zone = Text(raw.giver), Text(raw.zone)
    if giver and zone and Spot(raw.x) and Spot(raw.y) then
        rec.giver, rec.zone, rec.x, rec.y = giver, zone, raw.x, raw.y
    end
    if SIDES[raw.side] then rec.side = raw.side end
    if type(raw.rewards) == "table" then
        for i = 1, math.min(#raw.rewards, Contribute.MAX_REWARDS) do
            local r = raw.rewards[i]
            if type(r) == "table" and WholeNumber(r[1], 1, Contribute.MAX_ID)
                and WholeNumber(r[2] or 0, 0, Contribute.MAX_LEVEL)
                and WholeNumber(r[3] or 0, 0, Contribute.MAX_ITEM_LEVEL) then
                rec.rewards[#rec.rewards + 1] = { r[1], r[2] or 0, r[3] or 0, r[4] == true }
            end
        end
    end
    if type(raw.items) == "table" then
        for i = 1, math.min(#raw.items, Contribute.MAX_REWARDS) do
            local r = raw.items[i]
            if type(r) == "table" and WholeNumber(r[1], 1, Contribute.MAX_ID)
                and WholeNumber(r[2] or 1, 1, Contribute.MAX_COUNT) then
                rec.items = rec.items or {}
                rec.items[#rec.items + 1] = { r[1], r[2] or 1, r[3] == true }
            end
        end
    end
    if WholeNumber(raw.money, 1, Contribute.MAX_PRICE) then rec.money = raw.money end
    if WholeNumber(raw.xp, 1, Contribute.MAX_XP) then rec.xp = raw.xp end
    return rec
end

--- One dungeon quest as Logic/DungeonQuests.lua keeps it, field by field;
--- nil when it is unusable. The dungeon is a map ID, as a string.
function Contribute.CleanDungeonQuest(raw)
    if type(raw) ~= "table" then return nil end
    local title = Text(raw.title)
    local dungeon = type(raw.dungeon) == "string" and #raw.dungeon <= 10
        and raw.dungeon:match("^%d+$") and raw.dungeon
    if not (title and dungeon) then return nil end
    local rec = { dungeon = dungeon, title = title }
    if WholeNumber(raw.level, 1, Contribute.MAX_LEVEL) then rec.level = raw.level end
    if WholeNumber(raw.min, 1, Contribute.MAX_LEVEL) then rec.min = raw.min end
    if SIDES[raw.side] then rec.side = raw.side end
    local giver, zone = Text(raw.giver), Text(raw.zone)
    if giver and zone and Spot(raw.x) and Spot(raw.y) then
        rec.giver, rec.zone, rec.x, rec.y = giver, zone, raw.x, raw.y
    end
    if WholeNumber(raw.reward, 1, Contribute.MAX_ID) then rec.reward = raw.reward end
    return rec
end

--- One vendor as Logic/NPCSpots.lua keeps it, field by field; nil when it
--- is unusable or sells nothing that came through.
function Contribute.CleanVendor(raw)
    if type(raw) ~= "table" or type(raw.items) ~= "table" then return nil end
    local zone = Text(raw.zone)
    if not (zone and Spot(raw.x) and Spot(raw.y)) then return nil end
    local rec = { name = Text(raw.name) or "", zone = zone, x = raw.x, y = raw.y, items = {} }
    if SIDES[raw.side] then rec.side = raw.side end
    local count = 0
    for itemID, row in pairs(raw.items) do
        if count >= Contribute.MAX_STOCK then break end
        if WholeNumber(itemID, 1, Contribute.MAX_ID) and type(row) == "table"
            and WholeNumber(row[1] or 0, 0, Contribute.MAX_PRICE)
            and WholeNumber(row[2] or 0, 0, Contribute.MAX_LEVEL)
            and WholeNumber(row[3] or 0, 0, Contribute.MAX_ITEM_LEVEL) then
            rec.items[itemID] = { row[1] or 0, row[2] or 0, row[3] or 0, row[4] == true }
            count = count + 1
        end
    end
    if count == 0 then return nil end
    return rec
end

--------------------------------------------------------------------------------
-- Sending
--------------------------------------------------------------------------------

--- This account's id, made once and kept.
function Contribute:Id()
    if type(ns.db) ~= "table" then return nil end
    if not ValidId(ns.db.shareDataId) then
        local parts = {}
        for i = 1, 12 do parts[i] = string.format("%x", math.random(0, 15)) end
        ns.db.shareDataId = table.concat(parts)
    end
    return ns.db.shareDataId
end

--- Keys of a table as a list, highest first, so a cut keeps the same ones.
local function KeysHighFirst(list)
    local keys = {}
    for key in pairs(type(list) == "table" and list or {}) do
        if type(key) == "number" then keys[#keys + 1] = key end
    end
    table.sort(keys, function(a, b) return a > b end)
    return keys
end

--- How long a table is once encoded, or nil.
local function Size(value)
    local ok, text = pcall(ns.Serialize.Encode, value)
    return ok and type(text) == "string" and #text or nil
end

--- What goes: the player's own learned quests ("q"), vendors ("v") and
--- dungeon quests ("d"), by quest and NPC ID. Past BUDGET bytes the lowest
--- quest IDs are left out (Forever's own are the highest), so the same
--- learned lists always make the same table.
function Contribute:Payload()
    local payload = { q = {}, v = {}, d = {} }
    local db = type(ns.db) == "table" and ns.db or {}
    local count = 0
    for _, questID in ipairs(KeysHighFirst(db.learnedQuests)) do
        if count >= self.MAX_QUESTS then break end
        local rec = WholeNumber(questID, 1, self.MAX_ID) and self.CleanQuest(db.learnedQuests[questID])
        if rec then
            payload.q[questID] = rec
            count = count + 1
        end
    end
    count = 0
    for _, questID in ipairs(KeysHighFirst(db.learnedDungeonQuests)) do
        if count >= self.MAX_DUNGEON_QUESTS then break end
        local rec = WholeNumber(questID, 1, self.MAX_ID) and self.CleanDungeonQuest(db.learnedDungeonQuests[questID])
        if rec then
            payload.d[questID] = rec
            count = count + 1
        end
    end
    count = 0
    for npcID, raw in pairs(type(db.learnedVendors) == "table" and db.learnedVendors or {}) do
        if count >= self.MAX_VENDORS then break end
        local rec = WholeNumber(npcID, 1, self.MAX_ID) and self.CleanVendor(raw)
        if rec then
            payload.v[npcID] = rec
            count = count + 1
        end
    end
    self.Fit(payload)
    return payload
end

--- Leave out the lowest quest IDs until the table fits BUDGET.
function Contribute.Fit(payload)
    local size = Size(payload)
    if not size or size <= Contribute.BUDGET then return end
    local keys = KeysHighFirst(payload.q)
    local keep = #keys
    while keep > 0 and size and size > Contribute.BUDGET do
        local cut = math.max(1, math.floor(keep * (1 - Contribute.BUDGET / size)) + 1)
        for i = keep, math.max(1, keep - cut + 1), -1 do payload.q[keys[i]] = nil end
        keep = math.max(0, keep - cut)
        size = Size(payload)
    end
end

function Contribute:Hash(payload)
    local ok, text = pcall(ns.Serialize.EncodeCanonical, payload)
    return ok and type(text) == "string" and Comm.Hash(text) or nil
end

--- Nothing to send while every list is empty.
local function Empty(payload)
    return next(payload.q) == nil and next(payload.v) == nil and next(payload.d) == nil
end

function Contribute:Hello()
    if not self:Sending() then return end
    local id = self:Id()
    local payload = self:Payload()
    if not id or Empty(payload) then return end
    local hash = self:Hash(payload)
    if not hash then return end
    for _, recipient in ipairs(self:Recipients()) do
        Comm:Send("Q", id .. ":" .. hash, "WHISPER", recipient.name)
    end
end

--- A recipient asked for this account's table.
function Contribute:OnAsk(sender, body, channel)
    if channel ~= "WHISPER" or not self:Sending() or not self:IsRecipient(sender) then return end
    if body ~= self:Id() then return end
    local key = Comm.NameKey(sender)
    local last = self.sentTo[key]
    if last and Now() - last < self.SEND_GAP then return end
    local payload = self:Payload()
    if Empty(payload) then return end
    self.sentTo[key] = Now()
    payload.i, payload.h = self:Id(), self:Hash(payload)
    Comm:SendTable("K", payload, "WHISPER", sender)
end

--------------------------------------------------------------------------------
-- Receiving
--------------------------------------------------------------------------------

local function Store(create)
    if type(ns.db) ~= "table" then return nil end
    if type(ns.db.sharedData) ~= "table" then
        if not create then return nil end
        ns.db.sharedData = {}
    end
    return ns.db.sharedData
end

--- A hello from a player: ask for their table when it is new to us.
function Contribute:OnHello(sender, body, channel)
    if channel ~= "WHISPER" or not self:Receiving() or Comm.IsMe(sender) then return end
    local id, hash = (body or ""):match("^(%x+):(%w+)$")
    if not ValidId(id) or not Comm.FromBase36(hash) then return end
    -- This account's own characters: what they learned is already here.
    if type(ns.db) == "table" and id == ns.db.shareDataId then return end
    local held = (Store(false) or {})[id]
    if type(held) == "table" then
        if held.hash == hash then return end
        if Now() - (tonumber(held.at) or 0) < self.SYNC_GAP then return end
    end
    for _, waiting in ipairs(self.queue) do
        if waiting.id == id then waiting.name = sender return end
    end
    if #self.queue >= 50 then return end
    self.queue[#self.queue + 1] = { id = id, name = sender }
    self:Next()
end

--- Ask the next one in line, unless one is being waited on.
function Contribute:Next()
    local current = self.current
    if current and Now() - current.at < self.SYNC_TIMEOUT then return end
    self.current = nil
    local waiting = table.remove(self.queue, 1)
    if not waiting then return end
    self.current = { id = waiting.id, key = Comm.NameKey(waiting.name), at = Now() }
    Comm:Send("R", waiting.id, "WHISPER", waiting.name)
    -- One that never answers is given up, and the next asked, without
    -- waiting for another hello.
    if type(C_Timer) == "table" and C_Timer.After then
        C_Timer.After(self.SYNC_TIMEOUT + 1, function() Contribute:Next() end)
    end
end

--- Only the shapes Payload makes; anything else is left out. Nil for a
--- table that is not one, or holds far too much.
function Contribute:Clean(value)
    if type(value) ~= "table" or type(value.q) ~= "table" or type(value.v) ~= "table" then return nil end
    local clean, quests, vendors, dungeons = { q = {}, v = {}, d = {} }, 0, 0, 0
    for questID, raw in pairs(value.q) do
        quests = quests + 1
        if quests > self.MAX_QUESTS then return nil end
        local rec = WholeNumber(questID, 1, self.MAX_ID) and self.CleanQuest(raw)
        if rec then clean.q[questID] = rec end
    end
    for npcID, raw in pairs(value.v) do
        vendors = vendors + 1
        if vendors > self.MAX_VENDORS then return nil end
        local rec = WholeNumber(npcID, 1, self.MAX_ID) and self.CleanVendor(raw)
        if rec then clean.v[npcID] = rec end
    end
    -- A sender from before dungeon quests went sends none.
    for questID, raw in pairs(type(value.d) == "table" and value.d or {}) do
        dungeons = dungeons + 1
        if dungeons > self.MAX_DUNGEON_QUESTS then return nil end
        local rec = WholeNumber(questID, 1, self.MAX_ID) and self.CleanDungeonQuest(raw)
        if rec then clean.d[questID] = rec end
    end
    return clean
end

local function Count(list)
    local n = 0
    for _ in pairs(list) do n = n + 1 end
    return n
end

--- "Got 3 vendors and 5 quests from NAME.", one and many each.
function Contribute.GotLine(vendors, quests, name)
    if vendors == 1 and quests == 1 then
        return L.Format("Got %d vendor and %d quest from %s.", vendors, quests, name)
    elseif vendors == 1 then
        return L.Format("Got %d vendor and %d quests from %s.", vendors, quests, name)
    elseif quests == 1 then
        return L.Format("Got %d vendors and %d quest from %s.", vendors, quests, name)
    end
    return L.Format("Got %d vendors and %d quests from %s.", vendors, quests, name)
end

function Contribute:OnTable(sender, value, channel)
    local current = self.current
    if channel ~= "WHISPER" or not self:Receiving() or not current then return end
    if Comm.NameKey(sender) ~= current.key or type(value) ~= "table" or value.i ~= current.id then return end
    self.current = nil

    local clean = self:Clean(value)
    if clean then
        local store = Store(true)
        store[current.id] = {
            at = Now(),
            hash = type(value.h) == "string" and #value.h <= 12 and value.h or nil,
            quests = clean.q,
            vendors = clean.v,
            dungeons = clean.d,
        }
        self:Trim(store)
        local name = Comm.Plain(sender) or "?"
        name = name:match("^([^%-]+)") or name
        -- Dungeon quests count as quests in the line, each quest once.
        local vendors, quests = Count(clean.v), Count(clean.q)
        for questID in pairs(clean.d) do
            if clean.q[questID] == nil then quests = quests + 1 end
        end
        self:Note(name, vendors, quests)
        local line = self.GotLine(vendors, quests, name)
        ns.Print(line)
        self:Alert(line)
    end
    self:Next()
end

--- Past MAX_SENDERS, the one heard from longest ago goes.
function Contribute:Trim(store)
    local count, oldest, oldestAt = 0, nil, nil
    for id, entry in pairs(store) do
        count = count + 1
        local at = type(entry) == "table" and tonumber(entry.at) or 0
        if not oldestAt or at < oldestAt then oldest, oldestAt = id, at end
    end
    if count > self.MAX_SENDERS and oldest then store[oldest] = nil end
end

--- A sound and a line across the screen as the chat line goes out. Only a
--- receiving character ever gets here.
function Contribute:Alert(line)
    if type(PlaySound) == "function" then
        local kits = type(_G.SOUNDKIT) == "table" and _G.SOUNDKIT or {}
        pcall(PlaySound, kits.IG_QUEST_LIST_COMPLETE or 878)
    end
    -- The house note (UI/Notice.lua), so it never lands on another addon's.
    if ns.Notice and pcall(ns.Notice.Show, ns.Notice, line, { key = "contribute" }) then return end
    local frame = _G.UIErrorsFrame
    if type(frame) == "table" and type(frame.AddMessage) == "function" then
        pcall(frame.AddMessage, frame, line, 1, 0.82, 0.2, 1)
    end
end

function Contribute:Note(name, vendors, quests)
    if type(ns.db) ~= "table" then return end
    if type(ns.db.sharedDataLog) ~= "table" then ns.db.sharedDataLog = {} end
    local log = ns.db.sharedDataLog
    log[#log + 1] = { at = Now(), name = tostring(name), vendors = vendors, quests = quests }
    while #log > self.LOG_KEEP do table.remove(log, 1) end
end

local function LogLine(when, vendors, quests, name)
    if vendors == 1 and quests == 1 then
        return L.Format("%s: %d vendor and %d quest from %s.", when, vendors, quests, name)
    elseif vendors == 1 then
        return L.Format("%s: %d vendor and %d quests from %s.", when, vendors, quests, name)
    elseif quests == 1 then
        return L.Format("%s: %d vendors and %d quest from %s.", when, vendors, quests, name)
    end
    return L.Format("%s: %d vendors and %d quests from %s.", when, vendors, quests, name)
end

--- The shares kept, newest first, as lines for chat.
function Contribute:LogLines()
    local log = type(ns.db) == "table" and ns.db.sharedDataLog
    local lines = {}
    if type(log) ~= "table" then return lines end
    for i = #log, math.max(1, #log - self.LOG_SHOW + 1), -1 do
        local entry = log[i]
        if type(entry) == "table" then
            local ok, when = pcall(date, "%b %d %H:%M", tonumber(entry.at) or 0)
            when = ok and when or "?"
            lines[#lines + 1] = LogLine(when, tonumber(entry.vendors) or 0, tonumber(entry.quests) or 0,
                tostring(entry.name))
        end
    end
    return lines
end

function Contribute:PrintLog()
    local lines = self:LogLines()
    if #lines == 0 then
        ns.Print(L["Nobody has shared data with you yet."])
        return
    end
    for _, line in ipairs(lines) do ns.Print(line) end
end

--------------------------------------------------------------------------------
-- The choice
--------------------------------------------------------------------------------

--- Start or stop listening and the hellos to match the setting.
function Contribute:Apply()
    if self:Active() then Comm:Start() else Comm:Stop() end
    if self:Sending() then
        if not self.ticker and type(C_Timer) == "table" then
            self.ticker = C_Timer.NewTicker(self.HELLO_SECONDS, function() Contribute:Hello() end)
            C_Timer.After(self.FIRST_HELLO, function() Contribute:Hello() end)
        end
    elseif self.ticker then
        pcall(self.ticker.Cancel, self.ticker)
        self.ticker = nil
    end
    if not self:Receiving() then
        self.queue, self.current = {}, nil
    end
end

function Contribute:SetOn(on)
    if type(ns.db) ~= "table" then return end
    ns.db.shareData = on == true
    self:Apply()
end

function Contribute:Describe()
    if self:On() then return L["Sharing your data with Blackthornes is on. Thank you."] end
    return L["Sharing your data with Blackthornes is off."]
end

--- `/beq share [on|off|log]`: typed only, so it stays out of the help list
--- (ns.RegisterCommand would list it).
function Contribute:Command(rest)
    local choice = (rest or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if choice == "log" then return self:PrintLog() end
    if choice == "on" or choice == "off" then self:SetOn(choice == "on") end
    ns.Print(self:Describe())
end

if type(ns.commands) == "table" then
    ns.commands.share = { fn = function(rest) Contribute:Command(rest) end }
end

function Contribute:OnEnable()
    Comm:On("Q", function(...) Contribute:OnHello(...) end)
    Comm:On("R", function(...) Contribute:OnAsk(...) end)
    Comm:OnTable("K", function(...) Contribute:OnTable(...) end)
    self:Apply()
    -- The last name can come in late; look again once the world is up.
    if ns.RegisterEvent then
        ns.RegisterEvent(self, "PLAYER_ENTERING_WORLD", function() Contribute:Apply() end)
    end
end
