-- Core/WhatsNewText.lua
-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:
-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.

local _, ns = ...

ns.WHATS_NEW = {
    { version = "0.3.0", lines = {
        "Quest, people, zone and item names now show in your own language.",
        "The Show on Map marker is bigger and easier to spot.",
        "One minimap button now opens all your Blackthornes add-ons.",
    } },
    { version = "0.2.0", lines = {
        "The Take button has a new gold look.",
    } },
    { version = "0.1.0", lines = {
        "Equipment is here for Classic Era. A green arrow shows on any item in your bags that's better than what you wear.",
        "A Put It On button shows when a new upgrade lands in your bags.",
        "Where to Get Upgrades lists upgrades from vendors, quests, dungeons, raids and crafting.",
        "Dungeon Loot and Dungeon Quests show what each dungeon gives.",
    } },
}
