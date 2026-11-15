-- Core/WhatsNewText.lua
-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:
-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.

local _, ns = ...

ns.WHATS_NEW = {
    { version = "0.9.0", lines = {
        "The upgrade quest panel says why an upgrade was picked and what it asks of you.",
        "How You Gear Up picks a style for your upgrade quests.",
        "An Upgrade Done plaque shows when the gear goes on.",
        "Quest log rows show which rewards are upgrades.",
        "Queue It on a pattern you learn later queues the craft once you learn it.",
        "Mute All Sounds quiets every Blackthornes sound at once.",
        "Windows remember where you drag them.",
    } },
    { version = "0.8.0", lines = {
        "Druids can judge gear as a Bear Tank.",
        "The upgrade banner can be dragged and remembers its place.",
    } },
    { version = "0.7.0", lines = {
        "Item icons now have a ring and a name colour that match their quality.",
        "Stack counts show on the corner of item icons.",
        "Items show a small mark and colour for what to do with them.",
    } },
}
