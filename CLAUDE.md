# Notes for Claude

Read this before working in this repo. The owner runs one Claude project per
addon: this one (**Blackthornes_Equipment**), **Blackthornes_Tradeskills**
(`Blackthornes/Blackthornes_Tradeskills`) and **Blackthornes_Farmer**
(`Blackthornes/Blackthornes_Farmer`). The projects cannot read each other's
memory, so what one needs to know about another lives in the repos, in this
file and in theirs. Keep them current: when a change here leans on something
new in another addon, or a standing rule from the owner applies to all of them,
add it to each file.

Nothing private goes in this file (no local paths, emails or account names).
It never ships: `.pkgmeta` leaves it out of the zip and
`tools/check_package.py` refuses it.

## This repo is the Classic Era copy

`Blackthornes/Blackthornes_Equipment_Classic` is Equipment for WoW Classic
Era, copied from `Blackthornes/Blackthornes_Equipment` (Forever) with its
history on 2026-10-24 (the owner said build it, after Farmer's and Butler's
Era copies). Its releases, tests and CurseForge page are its own. Forever
comes first, and nothing done here may ever touch the Forever addon. So:

- Never push to, or open PRs on, the Forever repo from work here. Changes
  come over from Forever on purpose (cherry-pick or copy), never the other
  way.
- The addon folder and TOC stay `Blackthornes_Equipment`, the saved data
  `BlackthornesEquipmentDB` and `BlackthornesEquipmentCharDB`, so nothing
  is renamed.
- The TOC names Era's interface, `## Interface: 11509` (what the owner's
  Era client reports, 2026-10-24).
- Never put Forever's CurseForge ID (1720051) in the TOC:
  `tools/check_release.py` refuses a tag that does. The owner makes the Era
  project himself: Equipment Classic is **1763347** (2026-10-24), on the
  TOC's `X-Curse-Project-ID` line, and `tools/test_era.lua` checks it is there.
- What only Forever has is left out of the TOC: `Data/ForeverItems.lua`,
  `ForeverDrops.lua` (its dungeons and drops), `ForeverNPCs.lua`,
  `ForeverQuests.lua`, `ForeverGoneQuests.lua`, `ForeverVendors.lua`,
  `ForeverDungeonQuests.lua`. The files
  and their `tools/forever_*.py` stay in the repo so Forever changes merge
  cleanly. Every reader asks for the table first, so Classic's data stands
  alone, and what is learned in game (quests, vendors, spots, dungeon
  quests) is still laid over it: a shipped list that is not there is
  passed to `ipairs` as `false`, never nil, or the learned list after it
  is skipped (`QuestLearn:LayAll`, `NPCSpots:LayAllVendors`).
  `tools/test_era.lua` checks the TOC and that the finder, Dungeon Loot
  and Dungeon Quests work without them.
- Sending vendors and quests to Blackthornes is in (the owner, 2026-10-26):
  `Logic/Contribute.lua` names the owner's Era characters as Name-Realm,
  and a player whose realm is not theirs sends nothing and sees no box,
  since Era whispers reach only the same realm. `Core/Comm.lua` adds the
  realm to a whisper's name (`WithRealm`, Tradeskills'). See
  `docs/CLASSIC_DIFFERENCES.md`.
- Not yet seen in an Era client. The talent tabs, stats and the shared
  class training come next, a small PR each.
- The rest of this file describes the Forever addon; read it as the
  starting point, not as what Era has.

## How this repo was set up

It copies its sisters on purpose, so check them before inventing a
convention:

- **Layout** `Core/ Data/ Logic/ UI/ tools/`, one module per file through
  `ns.NewModule`, no Ace3 or LibStub. `Core/Init.lua` is Farmer's, renamed.
  The global is `_G.BlackthornesEquipment`, the commands `/beq` and
  `/equipment`, the saved data `BlackthornesEquipmentDB` (account) and
  `BlackthornesEquipmentCharDB` (per character: the picked spec lives there).
- **Palette** is Tradeskills' and Farmer's (`ns.COLORS`), with `upgrade` and
  `downgrade` in Tradeskills' profit green and loss red. `UI/Theme.lua` and
  `UI/Widgets.lua` are Farmer's (Widgets trimmed to button, checkbox and
  stepper); the minimap button and settings window copy Farmer's too. The
  button starts at 230 degrees, clear of Farmer's at 200, Tradeskills' at
  170 and Pets' at 260.
- **Tools** (`syntaxcheck`, `lintcalls`, `runtests`, `check_release`,
  `check_package` and their tests) are Tradeskills' with the names changed.
  If one of them gets a fix in either sister repo, bring it here too.
- **Tests** are `tools/test_*.lua`, found by name. `tools/testenv.lua` loads
  the files the TOC lists, so there is no second list to keep.
- **PRs** follow the sisters' habit: a "Before:" and an "After:" paragraph
  in plain words, then a short "How" naming the functions and tests touched,
  that the checks pass, and whether `/reload` is enough. Release PRs are
  `release/X.Y.Z` branches titled "Changelog for X.Y.Z".
- **Tradeskills' `docs/FOREVER_API_FINDINGS.md`** records what the Forever
  client actually does. Read it before relying on an API.

## What Tradeskills calls here

Tradeskills draws the green upgrade arrow on item icons across its windows
(`Logic/Upgrades.lua`, `Theme.SetItemIcon` there). It shows only when this
addon is loaded (`## OptionalDeps: Blackthornes_Equipment` in its TOC) and
calls, inside a pcall:

```lua
_G.BlackthornesEquipment.Compare:IsUpgrade(item)   -- item ID or link; true or false
```

`IsUpgrade` answers exactly what the bag arrow answers (`IsUpgradeNow`: an
upgrade that can be worn now), and by item ID it says false for anything
already worn, so a worn ring is never an upgrade over the other ring. It never
raises. Keep the global, `Compare` and `IsUpgrade(item)` stable; if one has to
change, change Tradeskills' `Logic/Upgrades.lua` too.

Its Level Up tab also puts the arrow, and "For you: Chest +3%", on an
enchanting recipe that beats what is on the gear worn (2026-10-16; see
"Enchants for your gear"):

```lua
_G.BlackthornesEquipment.Enchants:ForRecipe(recipeID)
  -- { slot (shown name), slotID, gain (whole percent, nil for an empty
  --   slot's), current (enchant on it now), best (the top pick) }, or nil
```

A fresh table, never raises, laid out once per gear or weights change. Keep
it stable; if it changes, change Tradeskills' `Upgrades:EnchantFor` too.

Forever's CurseForge project ID is **1720051** (the owner created it 2026-09-30).
The Classic Era copy is **1763347**, on the TOC's `X-Curse-Project-ID` line;
never Forever's. The first release is 0.1.0.

## What Butler calls here

Blackthornes Butler (`Blackthornes/Blackthornes_Butler`) tells the player
what to do with each item in the bags. When this addon is loaded it asks,
once per carried item, inside a pcall and read only (its
`Logic/Sisters.lua`):

```lua
_G.BlackthornesEquipment.Butler:Advise(link, bag, slot)   -- link or item ID; bag and slot optional
```

`Logic/Butler.lua` answers nil for anything that is not gear (or not
loaded yet) after two cheap item calls, unless it is a known tool, and
otherwise a table:

- `upgrade`: "now" when the bag arrow shows (`Compare:JudgeCarried`,
  `Compare.WearableUpgrade`), "later" for an upgrade waiting on a level or
  on training, nil otherwise. Armor of a kind the class learns later (mail
  for a hunter or shaman, plate for a warrior or paladin, at 40) is
  "later" only from `Weights.KIND_SOON` (2) levels before; earlier it is
  nil, so Butler sorts it as any other gear (the owner, 2026-10-24,
  `Weights:KindTooFar`). `Compare:Judge` asks the same rule, so before
  then the armor is "cantuse" (`result.laterArmor`, the level it opens)
  and the tooltip shows no line for it; `Alts:Judge` asks it for each
  other character too, so `alt` and the tooltip's alt line follow.
  Tested in `tools/test_laterarmor.lua`.
- `gain`: the upgrade's size as a whole percent, nil when there is none to
  give (an empty slot) or it is no upgrade.
- `sell`: true when the bag's sell coin would show on it (`BagIcons:Sells`,
  so false while "Sell coins" is unticked). Soulbound can only be told from
  the bag slot, so without `bag` and `slot` green and better gear is never
  `sell`.
- `tool`: true for gathering and profession tools (`BagIcons.IsTool`,
  `BagIcons.TOOLS`) and fishing poles; a tool is never `sell`.
- `alt`: only when it is no upgrade here, `{ key, gain, level }` for the
  other character it helps most (`Alts:BestFor`, the owner asked
  2026-10-11): `key` that character's GUID (Butler names it from
  Tradeskills' record), `gain` a whole percent (nil for an empty slot),
  `level` when it waits on that character's level. Butler mails it there.
  Armor goes only to a character whose heaviest kind it is
  (`Weights:IsBestArmor`, the owner asked 2026-10-13: no cloth for a
  leather wearer); cloaks, rings, necks, trinkets and shields are not
  asked.

Each character keeps a note of itself when it plays (`Logic/Alts.lua`,
account wide in `BlackthornesEquipmentDB.characterGear[guid]` = `{ class,
level, spec, realm, faction, worn = { [slot] = link }, at, name, spare,
bank, bankAt }`; never rename it or its fields), written 1 second after a
burst of gear, level or talent events and at logout. Only characters on the
same realm and side are judged, with their own class, spec, level and worn
gear, through `Compare:ScoreOf`; a character counts once it has logged in
with this version. A read that finds nothing worn (the client can answer
nil for every slot on a /reload or logout) keeps the last note's `worn`
and, when the bags read empty too, its `spare`; and `Alts:Judge` answers
nil for a note with no worn gear, so nothing is called an upgrade (and
mailed by Butler) for "an empty slot" it only looks empty because of a
blank record (2026-10-11).

Upgrades you already own (the owner, 2026-10-11, "do the work for the
player"): the note also keeps `name` (`UnitName`), `spare` (links of gear
in bags 0 to 4 that is not soulbound, `Alts.GearIn`, at most
`Alts.SPARE_MOST`) and, read 0.5 s after `BANKFRAME_OPENED`, `bank` (`{
link, bound }` each, `Alts:ReadBank`, kept by later notes) with `bankAt`.
`Alts:BetterElsewhere` judges, only while the gear window draws, the
character's own bank and the other characters' unbound spare and bank gear
for the character playing; a slot the bags leave without an upgrade then
shows it with "(in your bank)" or "(on NAME)", and the footer counts them.
`Alts:NameOf(key)` gives the whole name, Tradeskills' record first. The
tooltip adds "Upgrade for NAME: +N%" (`Tooltip:AltLine`, `Alts:BestFor`,
the answer Butler mails by) on gear that is no upgrade here; "Upgrades for
your alts" in Settings (`altTooltipLine`, account wide, on unless unticked,
never rename it). Tested in `tools/test_alts.lua`. Not yet seen in game.

Characters skipped for upgrades (a player asked, the owner agreed
2026-10-14, for crafting alts): `Alts:SetSkipped(guid, on)`, kept account
wide in `BlackthornesEquipmentDB.skipUpgrades[guid] = true` and, for the
character playing, `BlackthornesEquipmentCharDB.skipUpgrades` (read when a
dungeon keeps the GUID back; copied from the account's answer at each
note). Never rename either. On a skipped character `Compare:Judge` and
`JudgeCarried` say `verdict = "skipped"` (with `skipped = true`) where
they would say "upgrade", so no bag arrow, banner, finder row, upgrade
quest pick, Butler "now" or Tradeskills arrow; the tooltip then shows the
alt line instead, and `BagIcons:Sells` puts no coin on gear another
character wants. `Alts:BestFor` never names a skipped character. Settings,
Gear page, YOUR CHARACTERS (a picker by whole name and a tick), and `/beq
skip [on|off|list]`. Tested in `tools/test_skipupgrades.lua`. Not yet seen
in game.

Advise never raises, scans no bags and, past the notes above, keeps nothing new: scores, sell prices
and tools are the per-link caches the bag icons already keep, since Butler
asks a hundred times in a burst. Keep the global, `Butler:Advise` and these
fields stable; if one has to change, change Butler's `Logic/Sisters.lua`
too.

## What this addon calls in Tradeskills

When a player changes a stat weight or picks a spec (`Weights:Changed` in
`Logic/Weights.lua`, which the Settings spec stepper and `/beq spec` call
too), Tradeskills' kept upgrade answers are stale, so it calls, inside a
pcall and only when Tradeskills is loaded:

```lua
_G.BlackthornesTS.Upgrades:RedrawSoon()   -- forget kept answers, redraw what shows arrows
```

If Tradeskills renames `Upgrades:RedrawSoon`, its arrows only catch up on
the next gear or talent change; change `Weights:Changed` too.

Crafted upgrades (`Logic/Crafting.lua`) read Tradeskills too, inside a
pcall, read only, and only when it is loaded:

```lua
ts.Recipes:GetAccountWide(true)        -- [recipeID] = { knownBy = { charKey, ... } }; recipe ID = spell ID
ts.Recipes:GetCharacterName(key)       -- "Bob Wither", for "Bob Wither can make this"
ts.Recipes:GetShortCharacterName(key)  -- only when GetCharacterName is missing
ts.Config:GetCharacterKey()            -- the character playing
ts.db.characters[key].faction          -- alts of the other faction are left out
ts.Prices:GetValue(itemID)             -- material and auction prices, copper
ts.RecipeBook:GetSkill(recipeID)       -- the skill a recipe needs on Forever, or nil
```

Character names are always shown whole, first and last (the owner,
2026-10-11: Forever characters have last names), so never "Bob" or
"Bob B.".

Recipes Forever added (Merchant's Favor ones among them, a player found
2026-10-16) are not in `Data/Crafts.lua`, so `Crafting:LayLearned` (asked
by `Finder:Candidates` and the tooltip) lays a learned one into
`Crafts.ITEMS` at runtime, never saved, from the `GetAccountWide` record's
`outputItemID`, `skillLineID` and `reagents` (`{ itemID, quantity }`),
with level, item level and bind type from the client. Such a row has
`learned = true` and is offered only as "known" or "alt"; nothing here
says how to learn it. If Tradeskills renames those fields, change
`Logic/Crafting.lua` too.

`GetSkill` (2026-10-09): Forever moved some recipes to other skill levels,
and Tradeskills reads the right one from the recipe item's tooltip.
`Crafting:Skill` uses it over `Data/Crafts.lua`'s Classic skill.

Without Tradeskills, crafted gear is still listed, known recipes are read
from the spellbook, and materials are priced at vendor only. If one of these
changes in Tradeskills, change `Logic/Crafting.lua` too.

Queue it (a player asked on Discord, the owner agreeing 2026-10-10): crafted
rows in Where to get upgrades and a crafted upgrade on the Upgrade quest
panel get a **Queue it** button while Tradeskills is loaded with these
calls. `Logic/TradeskillsQueue.lua` calls, inside a pcall:

```lua
ts.Queue:Ensure(recipeID, quantity)         -- at least that many queued; true, or nil and why
ts.Queue:EnsureBuy(itemID, count, forItem)  -- that many on the list to buy for forItem; true, or nil and why
ts.Queue:ForUpgrade(itemID)                 -- "craft", "buy" or nil; the button then reads Queued
ts.Queue:ShowQueue()                        -- a click on Queued opens the Queue tab
```

Gear the character or an alt can make (`known`, `alt`) is queued as a
craft; gear still to learn (`learn`, `skill`) has its `Data/Crafts.lua`
materials put on the list; gear nobody makes (`other`) goes on the list
itself. A craft Tradeskills has not read yet falls back to its materials.
The source is read again on each click (`TradeskillsQueue.Fresh`), since
the upgrade quest keeps one from when it was picked. If these change in
Tradeskills, change `Logic/TradeskillsQueue.lua` too.

The Enchants view (see "Enchants for your gear") uses the same `Ensure`
and `EnsureBuy` for its Queue it, and asks where a recipe is learned:

```lua
ts.LearnNext:WhereFor(recipeID)       -- { kind, name, zone, x, y, price }, or nil
ts.LearnNext:ShowTheWayFor(recipeID)  -- the Level Up tab's pin and chat line; true when set
```

If these change in Tradeskills, change `Logic/Enchants.lua` too. Nothing
else here calls the other addons, apart from the shared arrow table (see
the quest arrow below) and the whispers of "Sending vendors and quests to
Blackthornes", which only talk to Equipment.

## Enchants for your gear

A player asked (2026-10-15, the owner said build it) for the best enchant
for each worn piece, by spec and level, and a way into Tradeskills for an
enchanter. `Data/Enchants.lua` is written by `tools/make_enchants.py
<tables folder> --build <build> [--learnspots <Tradeskills'
Data/LearnSpots.lua>]` from the Forever client's game tables
(SpellItemEnchantment, SpellEquippedItems, SpellEffect, SpellReagents,
SkillLineAbility, ItemEffect, ItemXItemEffect, Item, ItemSparse); never
edit it by hand, never commit the tables or name where they came from.
It holds Enchanting recipes, armor kits and scopes (oils and stones left
for later), each with its slots, materials and skill, and what each
enchant gives; a resistance or a proc alone is never offered.

`Logic/Enchants.lua` reads each worn piece's enchant from its link, weighs
every enchant that fits with the gear's own stat weights (`Weights:Score`)
and keeps those more than `MIN_PERCENT` better (`Enchants:Plans`, laid out
again when the gear or weights move). Who can get it is read as crafted
gear's is (`known`, `alt`, `learn`, `skill`, `other`); when a better piece
is coming for a slot, the cheapest good enchant is offered instead. Gear
upgrades are still judged without enchants.

It shows as an Enchants filter in Where to get upgrades (`FinderUI:
PresentEnchants`; the gear controls hide there), with Queue it and Show
the way (the calls above), and as "Best enchant: NAME (+3%)" on the
tooltip of a piece you wear ("Best Enchant" on the Gear page,
`enchantTooltip`, on unless unticked, never rename it). `/beq probe` has a
"worn enchants" line. Tested in `tools/test_enchants.lua` and
`tools/test_make_enchants.py`. Not yet seen in game.

## Where to get upgrades (the finder)

`Logic/Finder.lua` and `UI/FinderWindow.lua` (`/beq find`, `/beq`) list gear from vendors, quest rewards and
dungeon drops that `Compare:Judge` calls an upgrade now. Where gear comes
from is `Data/Sources.lua`, generated by `tools/make_sources.py` from the
mangoszero world database (items, quest rewards, creature maps, loot tables)
and pfQuest's database (vendors, NPC and object positions); never edit it by
hand, rerun the script. The game supplies each item's stats: an item the
client has not seen is asked for (`C_Item.RequestLoadItemDataByID`, 40 per
scan) and the window scans again on `GET_ITEM_INFO_RECEIVED`. Defaults the owner's
project chose (2026-10-03): own faction only, nothing above the player's
level (a dungeon counts from its lowest recommended level). The owner then asked
for raid drops (open at 60) and reputation gear: gear whose standing the
character has not reached is still listed, after the rest, in amber with the
standing it needs (`Finder:Needs`, read through
`C_Reputation.GetFactionDataByID` or `GetFactionInfoByID`). Not yet seen in
game.

One window (a player asked for fewer windows, the owner approved the
mockup, 2026-10-22): the gear window and Where to get upgrades are one
window, `UI/FinderWindow.lua`, with hanging tabs (Upgrades, Enchants,
Dungeon Quests, Dungeon Loot, Settings; `FinderUI:HangTabs`; the owner
picked the two dungeon tabs 2026-10-23). Dungeon Quests, Dungeon Loot and
Settings are their own windows that wear the same tabs and open in its
place at the same spot (`FinderUI.STAND_INS`, `FinderUI:ShowTab`, their
`asTab`); `/beq dungeons`, `/beq loot` and the Settings buttons open them
the same way. Upgrade quest and Training are in the header. The slot list shows YOU WEAR and UP; the slot picked lists IN
YOUR BAGS first (`UI:ReadBags`: the best in the bags, else your bank or
another character, `FinderUI.OwnedWhere`; Put it on only for bag gear
that needs no training, `FinderUI.CanPutOn`), then TO GO AND GET. A gear
line you follow shows a Following tag. `UI/MainWindow.lua` keeps the old
names (`UI:Show`, `UI:Refresh`, `UI.frame`) as a facade. The place is
`finderPoint`, else the old gear window's. Every tab is one size and one scale
(the owner, 2026-10-23: the window jumped as the tabs were clicked): the
gear window's `FinderUI.WIDTH` by `HEIGHT`, or more when a tab says it
needs it (`FinderUI:Need`, Settings' fullest page), set on each tab as it
shows (`FinderUI:FitTab`); Dungeon Quests and Dungeon Loot lay out as many
rows as that height holds, and Settings' two columns span the width.
Every tab's size grip saves `finderScale` and scales the others
(`FinderUI:ScaleChanged`); `dungeonQuestsScale`, `dungeonLootScale` and
`settingsScale` stay in the save, unread. Dungeon Quests opens from
Settings and `/beq dungeons`. The Stat Weights window picks class and
spec from dropdowns. Tested in `tools/test_mainwindow.lua`.

Slot by slot (a player asked, the owner said build it from a mockup,
2026-10-20): the window lists the slots down the left
(`FinderUI.SLOT_GROUPS`, 15 lines; both rings are one line and both
trinkets another, `GROUP_OF`), each with how many upgrades it has, and the
slot picked shows every upgrade for it from `found.all`, best first
(`Finder.Order`: gear waiting on a standing last, then the shown percent,
then nearest), with "You wear:" and, when filters hide some, "Your
filters hide N more." Headings over the rows (ITEM, LEVEL, WHERE, GAIN;
`FinderUI.COLUMNS`, the owner approved the mockup 2026-10-21) sort it as
Pets' compendium does: a click sorts, a second flips, a third goes back to
best first (`FinderUI:SortBy`, `SortLines` on a copy, kept for the session
only, nothing saved); the Sort line and the heading carry a small arrow
(`Media/Frame/SortArrow.tga`, `tools/make_frame_art.py`). Level is
`FinderUI.LevelOf` (the level waited for, else the client's, else the
data's), Where is `WhereOf` (a drop's dungeon, a craft's profession, else
the zone). The Enchants view hides the headings.
`FinderUI:Groups` builds the lines once a scan; the tick boxes only
re-present it. One scan covers every source: tick boxes for Vendor, Quest,
Dungeons, Raids and Crafted (`FinderUI.SOURCE_BOXES`, a raid told by its
dungeon row's 6th field) keep what is unticked in `finderSourcesOff`
(`{ [kind] = true }`, nil until one is unticked), "Only what I can get
now" (`finderGetNow`, off unless ticked; `FinderUI.GetsNow`) leaves out
gear waiting on a standing, a level or a craft nobody of yours makes yet,
and the slot last clicked is `finderSlot` (on open, an empty one gives way
to the first slot with upgrades). `finderShow` is now "all" or "enchant";
an older one-source value reads as gear. Enchants use the same slot
column. All account wide; never rename them. Tested in
`tools/test_finderslots.lua`.

Solo quests (a player asked, the owner agreed 2026-10-06): a quest's
11th field in `Sources.QUESTS` says what it needs besides the player
("group", "dungeon", "raid", "battleground", or nothing), worked out by
`make_sources.py` from Classic's quest type, suggested players, and
objectives inside an instance or on an elite. "Solo quests only"
(`soloQuestsOnly`, account wide, off by default; `Finder:SetSoloOnly`) is a
tick box in the finder and a Settings row; `Finder:SourcesFor` leaves out
quests that need others or come after one, and the upgrade quest lets such
a quest go (not skipped) when it is ticked. Asked the same day, the
finder's "Quest level" stepper (`questLevelsAbove`, 0 to 10 levels above
the character, 11 for any, default 4; `Finder:QuestAllowed`) works the same
way. The upgrade quest panel (asked 2026-10-07) shows both under its tabs,
sharing the same saved values, beside "This zone only"
(`upgradeQuestZoneOnly`, account wide, off by default;
`UpgradeQuest:SetZoneOnly`): `Choose` then looks only at sources in the
zone the character is in (`UpgradeQuest.InZone`; a dungeon counts from its
entrance's zone and inside, a craft with no place anywhere), across every
pick (`found.all`, not the finder's top three per slot), and
`ZONE_CHANGED_NEW_AREA` lets go of tabs' quests elsewhere (not on a
flight, which waits for `PLAYER_CONTROL_GAINED` at the landing, and not
inside a dungeon or raid: `UpgradeQuest.Passing`). A quest followed
from the finder (`quest.followed`) stays; quests picked while ticked
(`quest.here`) are let go when it is unticked. A Settings button sits
beside them. "Change on a new zone" (`upgradeQuestZoneSwap`, account wide,
on unless unticked; `UpgradeQuest:ZoneSwap`, the owner asked 2026-10-08) is
a third tick box there and "Zone swap" in Settings: unticked, a zone change
lets nothing go, though an empty tab still picks from the zone it is in.
A player found it stale (2026-10-09), so: a quest that starts from an item
is in the zone where the item is got (`UpgradeQuest.SourceZone`, from
`Sources.STARTS`), and one whose start is not known is in none; a flight's
landing is also caught by the next event or a ticker (`WatchLanding`) in
case `PLAYER_CONTROL_GAINED` never comes; and `PLAYER_ENTERING_WORLD`
(login, reload, loading screen) counts as a new zone.
The finder has its own "This zone only" (a player asked, 2026-10-09;
`finderZoneOnly`, account wide, off by default; `FinderUI:ZoneOnly`), kept
apart from the panel's so ticking it never lets a quest go:
`FinderUI:Groups` then reads `found.all` through `UpgradeQuest.InZone`, and
`ZONE_CHANGED_NEW_AREA` refreshes the window.
Asked the same day: picks that show the same whole percent sort nearest
first (`Finder.Nearness`: in the zone, by map distance when
`Finder.Spot` can read where the character stands on that zone's own
map, never a guessed spot), and `FinderUI.MarkZone` names the zone the
character is in green on every row, tooltip and the character sheet's list.
Weapons the character has not trained (a player asked, the owner agreed
2026-10-10) show a red "Train" where the gain shows, in the finder, the
character sheet's list and the upgrade quest panel
(`WeaponSkills:NeedsTraining`, true only when the client says the skill is
unknown). `WeaponSkills:Known` is kept and forgotten on
`SKILL_LINES_CHANGED`, `LEARNED_SPELL_IN_TAB` and `SPELLS_CHANGED`, so a
list asks the client once, not once a row.
Such a weapon is still an upgrade (the owner's call, 2026-10-02), but
`Compare:Judge` marks it `skill` (the skill's name), so its tooltip says
"once you train Staves", Put it on refuses it and Butler hears "later".
Its banner (a player found a staff offered to a warrior without Staves;
the owner asked 2026-10-11 for a choice) has no Put it on but **Show the
trainer** (`WeaponSkills:ShowMaster`: the quest arrow, through
`QuestArrow:AimAtQuest` with no quest ID, at the weapon master in the city
the character is in, else the first listed; `Data/WeaponTrainers.lua`
carries Classic's NPC IDs and spots from pfQuest, a Forever spot learned
by `NPCSpots` winning) and **Ignore Staves** (`WeaponSkills:Ignore`, per
character in `BlackthornesEquipmentCharDB.ignoredWeaponTypes[subclassID]`,
never rename it): `Judge` then answers "cantuse" with `ignoredSkill`, so
it is no upgrade anywhere until the skill is learned. Learning a skill
(`WeaponSkills:Learned` on `SKILL_LINES_CHANGED` or `LEARNED_SPELL_IN_TAB`)
judges again only the untrained upgrades the banner announced
(`UpgradeChat:SkillsChanged`, a second later) and shows "Ready to wear"
with Put it on. "Untrained Weapons:" on the Gear page of Settings is a
Show or Hide stepper (a player's report, 2026-10-20): Hide keeps every
untrained weapon out of the upgrades for this character
(`BlackthornesEquipmentCharDB.hideUntrainedWeapons`, never rename it;
`WeaponSkills:HidesAll`, `IsHidden`, `HideAll`), and reads Hide too while a
type is ignored from a banner; Show clears both (`ShowAll`). `/beq weapons
[show|hide]` does the same. Tested in `tools/test_untrained.lua`.
Not yet seen in game.

Forever's own boss drops: `tools/forever_drops.py` reads Farmer's
`Data/Data_Harvested.lua` (no player names in it) and writes
`Data/ForeverDrops.lua`, rows looted inside a known dungeon or raid by mob
name. The finder tags them [Forever] and prefers their rate. The owner asked
(2026-10-03) for this to be refreshed at least once a week: bring Farmer's
harvest up to date from his saved data first (he attaches it; see Farmer's
`tools/harvest_import.py`), then rerun this. Stats always come from the
game, never from data, so a Forever stat change needs nothing.

Facts known before anyone here loots them (the owner said pull them in,
2026-10-22): `tools/forever_facts.json` holds Forever dungeons' level
ranges, which boss drops which new gear (by item ID) and dungeon quests
(by quest ID, with side, giver, spot and reward). Each was looked up by
hand, one at a time, and kept only when the Forever client's game tables
have its ID (`--tables` checks items again; `forever_dungeon_quests.py`
checks quests against QuestV2). Never name where a fact came from, and
never fill it from another author's addon. `forever_drops.py` lays the
loot in at rate 0 (Farmer's own rate always wins; at Classic's
dungeons only gear Classic never listed as a drop) and the ranges on the
`Sources.DUNGEONS` row; `forever_dungeon_quests.py` reads the quests
first, so the game's own readings win. `DQ.Dungeon` takes a Forever
dungeon's levels, and a door its place lacks, from that row. Hall of
Thanes' door is Ironforge and City of Dalaran's Alterac Mountains
(`FOREVER_DUNGEONS`). Tested in `tools/test_forever_drops.py`,
`tools/test_forever_dungeon_quests.py` and `tools/test_dungeonquests.lua`.

Forever's own dungeons and raids (the owner asked 2026-10-14, after
"can equipment learn drops inside a new dungeon?"): Classic's list in
`Sources.DUNGEONS` lacks them, so their drops used to be thrown away.
`FOREVER_DUNGEONS` in `tools/forever_drops.py` names them by the
instance's map ID from the Forever client's game tables (what
`GetInstanceInfo` gives inside, as Classic's are keyed), with the zone the
door is in when known (else the dungeon's own name, so nobody is sent
anywhere) and a raid flag. One Farmer saw drops in is written into
`Data/ForeverDrops.lua` as a `Sources.DUNGEONS` row, its levels from the
mobs looted there (1 to 60 when none were read). Still only at each
release's fold-in; a new Forever dungeon needs one line there. Tested in
`tools/test_forever_drops.py`.

Gear Forever changed (the owner said "do it all", 2026-10-12, to using
the Forever client's game tables in every addon): `tools/forever_items.py
<tables folder> --build <build>` reads only the client's `ItemSparse.csv`
(required level, item level, classes, races, vendor price) and writes
`Data/ForeverItems.lua` (`ns.ForeverItems[itemID] = { req, ilvl, classes,
races, price }`), only items that differ from `Sources.ITEMS` or
`Crafts.ITEMS`. `Finder.LayForeverItems` lays them over the Classic rows
once at load, so the finder's level, class and race checks and its vendor
price read Forever's; the price only for gear a vendor sells.
Reputations are left alone (the vendor asks for the standing, not the
item), and so are items the client's table lacks. Stats still come from
the game. Never commit the tables, and never name where they were
downloaded: say "the Forever client's game tables". Rerun it after
`make_sources.py` or `make_crafts.py` and when the client tables are
pulled again; it touches no other data file, so the weekly drops refresh
(`forever_drops.py`) is unaffected. Tested in `tools/test_foreveritems.lua`
and `tools/test_forever_items.py`.

Quests the Forever client does not have (the owner said yes,
2026-10-16): `tools/forever_gone_quests.py <tables folder> --build <build>`
reads only the client's `QuestV2.csv` and writes
`Data/ForeverGoneQuests.lua`, the Classic quests in `Sources.QUESTS` it
lacks (95 at build 70338, all level 55 to 60). `Finder.DropGoneQuests`
takes them out of `Sources.QUESTS` and the items' `q`/`g` lists once at
load, before `QuestLearn:LayAll`, so a quest learned in game still shows.
Never by hand; rerun it after `make_sources.py` and when the tables are
pulled again. Tested in `tools/test_gonequests.lua` and
`tools/test_forever_gone_quests.py`.

Vendor and trainer spots on Forever (the owner asked 2026-10-07, after Varg
Windwhisper turned out to stand elsewhere): `Logic/NPCSpots.lua` keeps,
whenever a merchant or trainer window opens, the NPC ID from
`UnitGUID("npc")`, the map name and the character's spot, account wide in
`BlackthornesEquipmentDB.npcSpots[npcID] = { name, map, x, y }` (never
rename it). `NPCSpots:Place` lays a learned spot, then the shipped
`Data/ForeverNPCs.lua`, over the Classic one wherever the finder and
`Logic/Crafting.lua` make a place from an NPC ID. Before a release, fold
the owner's learned spots in: he attaches his account save
(`Blackthornes_Equipment.lua`), and `tools/forever_npcs.py <save>` reads
only `npcSpots` and rewrites `Data/ForeverNPCs.lua`; never hand-edit it
(`--spot ID "Map" x y` adds one he reads off the map). Quest givers have
no NPC ID in the data, so their spots are not learned. Not yet seen in
game; `/beq probe` shows the target's NPC ID and the spot it would keep.

Vendor prices on Forever (the owner asked 2026-10-08): the same merchant
window keeps the gold price of gear the finder knows a vendor for, account
wide in `BlackthornesEquipmentDB.vendorPrices[itemID]` = copper (never
rename it; token and honor items are skipped). `NPCSpots:Price` beats the
Classic price in `Finder:SourcesFor` and the upgrade quest's Buy step.
When the character's money (`Finder.Short`, `GetMoney`) falls short, the
Buy step's note and the finder row say how much more is needed; it never
changes which upgrade is picked. `PLAYER_MONEY` only redraws (the finder)
or refreshes a shown vendor quest. Not yet seen in game.

Crafted gear and random rolls (the owner asked 2026-10-03 for crafted gear as
upgrades): `Data/Crafts.lua` and
`Data/Rolls.lua` are generated by `tools/make_crafts.py` from the vmangos
world dump (brotalnia/database) and pfQuest; never edit them by hand. The
finder lists crafted gear in four states (you can make it, an alt can, you
can learn it, someone else makes it), never bind on pickup gear from a
profession the player lacks, and judges random-roll gear at its best roll.
The house rule (2026-10-03): never name other addons in this repo, its PRs or
its commits; `tools/check_package.py` refuses a package
that names the one these features were asked to match.

Upgrade hunts, kept per character in `BlackthornesEquipmentCharDB.tracked`
and `.trackedDone` (never rename them): `Logic/Tracking.lua`,
`UI/TrackerPanel.lua`, `UI/MapPins.lua`, `UI/Toast.lua`,
`Logic/Waypoints.lua` (map IDs found by zone name at runtime; on a
client in another language, Classic's map IDs in `Waypoints.ZONE_MAPS`,
and `Waypoints:DataZone` turns the client's zone name into the data's for
every "zone you are in" check),
`UI/SlotUpgrades.lua` (character sheet) and `UI/MoreMarks.lua` (vendor and
loot arrows). None of it has been seen in game yet; `/beq probe` reports the
calls they need.

## Quests learned in game

The owner asked (2026-10-13) for the upgrade quest to learn quests and
their rewards as they are met, and for what the client shows to be rolled
into the updates. `Logic/QuestLearn.lua`: at `QUEST_DETAIL` and
`QUEST_COMPLETE` it reads the quest window (ID, title, level, the gear
offered or given, and for an offer who stands in front of the player and
where) and keeps what Classic's data lacks, account wide, in
`BlackthornesEquipmentDB.learnedQuests[questID]` (never rename it). For a
quest Classic's data has, only gear it lacks is kept; a quest the data
lacks is kept whole (the owner, 2026-10-20: "all quests and their
rewards"), its gear in `rewards` and also its other reward items with
counts (`items = { { itemID, count, given } }`), `money` and `xp`, read as
first seen. Only gear is laid over the data. The
records are laid over `Sources.QUESTS` and `Sources.ITEMS` at login and as
each is learned, so the finder and the upgrade quest offer them; nothing
Classic says is replaced. Nothing is shared with other players.
Each record notes the side it was offered to (`side`: "A", "H" or "AH";
an older record without it is offered to both), and a quest seen by one
side only is laid with that side's Classic race bits (2026-10-14).
Forever's Skyborne (High Order, race ID 95, Alliance; Windshapers, 96,
Horde) share the race name "Skyborne", which Classic's race bits lack:
`Finder.Side` reads the side from `UnitFactionGroup`, else the race ID,
and gives a race Classic never had every race bit of its side, so
race-limited quests and gear stay on that side.
Before a release, `tools/forever_quests.py <save>` reads only
`learnedQuests` from the owner's account save and rewrites
`Data/ForeverQuests.lua` (never by hand; no names, IDs of players or
characters), keeping what is there and dropping what Classic already has.
Tested in `tools/test_questlearn.lua` and `tools/test_forever_quests.py`.

Learning more (the owner said build it, 2026-10-14, for Zephras Isle,
where Classic's data has nothing): `QuestLearn:LearnLog` reads every quest
in the log the same way, a few a frame, 6 and 30 seconds after login and
one second after `QUEST_ACCEPTED` (`ReadLogQuest` picks the quest through
`QuestLog.Pick` and puts the old pick back; no giver). And when a merchant
window opens, `NPCSpots:LearnStock` keeps gear the data does not list for
that vendor, account wide, in `BlackthornesEquipmentDB.learnedVendors[npcID]
= { name, zone, x, y, side, items = { [itemID] = { price, req, ilvl,
limited } }, at }` (never rename it; `side` from `UnitFactionGroup("npc")`,
"AH" for a vendor of neither side; `ilvl` 0 until the item loads, laid as
999 so it is judged at any level). `NPCSpots:LayVendor` lays it, and
`Data/ForeverVendors.lua`, over `Sources.NPCS` and `Sources.ITEMS` at
login and as each is learned. Before a release, `tools/forever_vendors.py
<save>` reads only `learnedVendors` and rewrites `Data/ForeverVendors.lua`
(never by hand), the same way as the quests. Tested in
`tools/test_learnmore.lua` and `tools/test_forever_vendors.py`.

## Sending vendors and quests to Blackthornes

The owner said do it (2026-10-18), as Farmer's "Sending drops to
Blackthornes" and Tradeskills' "Sending data to Blackthornes": players can
opt in to send the vendors, quests and rewards their Equipment learned
(`learnedVendors`, `learnedQuests`, and since 2026-10-20 every quest the
data lacks and `learnedDungeonQuests`, see "Quests learned in game" and
"Dungeon Quests") to his
characters, for the shipped data. Off by default (`shareData`, never
rename it), never announced: one tick box on the About page of Settings,
"Share your data with Blackthornes to improve the Equipment AddOn.", no
hover, only on North American clients (`Contribute:InRegion`,
`GetCurrentRegion` 1 or 110, else `GetCurrentRegionName` "US"), and
`/beq share on|off|log` (typed only, set straight in `ns.commands`, so it
is not in the help line or Settings' command list). Only English clients
send (names come in the client's language). `Logic/Contribute.lua`
whispers a hello (`Q<id>:<hash>`) to each name in `Contribute.RECIPIENTS`
(full names, only in code, never shown; the same two as Farmer's and
Tradeskills' lists, change all three together) 30 s after login and every
half hour. Only those characters ask (`R<id>`), one sender at a time, each
at most every half hour, and the sender answers only a recipient asking
for its own id. The table (`K`, `{ q, v, d }` in the saved shapes; an
older sender's has no `d`) is checked field by field (`CleanQuest`,
`CleanVendor`, `CleanDungeonQuest`: plain text, spots 0 to 100, whole
numbers in range) and kept apart on the receiver in `sharedData[id] = {
at, hash, quests, vendors, dungeons }`, each sender's newest replacing the last
(at most `MAX_SENDERS`); it never joins the receiver's own learned lists
and nothing in the windows reads it. A chat line, a sound and a screen
line say "Got 3 vendors and 5 quests from NAME." (dungeon quests counted
as quests), and `sharedDataLog`
(`/beq share log`, the newest `LOG_KEEP`) keeps who sent. Never rename
`shareDataId`, `sharedData` or `sharedDataLog`. At a release,
`tools/forever_quests.py --shared`, `tools/forever_vendors.py --shared`
and `tools/forever_dungeon_quests.py --shared` fold `sharedData` in before
the save's own records (the save is never
changed, sender ids never read as names). Never announce the fold-in.
A table is kept under `Contribute.BUDGET` bytes (the lowest quest IDs
left out first, Forever's own being the highest) and a transfer may take
up to `SYNC_TIMEOUT` (30 minutes) at Comm's pace.
`Core/Comm.lua` (prefix `BEQshare`) and `Core/Serialize.lua` are Farmer's
copies of Tradeskills' files; a fix to the wire or the serializer belongs
in all three. Tested in `tools/test_contribute.lua`,
`tools/test_forever_quests.py`, `tools/test_forever_vendors.py` and
`tools/test_forever_dungeon_quests.py`. Not
yet seen in game.

## The upgrade quest

`Logic/UpgradeQuest.lua` and `UI/QuestPanel.lua` (`/beq quest`, a setting
under Upgrade hunts): the owner asked (2026-10-04) for an optional quest for the
next upgrade with a guide to get it. Off by default (`upgradeQuest`). It
picks from `Finder:Scan()` by gain times how easy the source is, keeps that
pick until it is worn, and works out the steps live from the saved source
and the game (zone, quest log, bags). Gear tied to a reputation (`Finder.Rep`,
the item's `r` or the craft's `f`, reached or not; picks carry `rep`)
comes last (the owner asked 2026-10-08): `Choose` takes it only when nothing
else on the tab will do, and looks past the finder's short list in a slot
that reputation gear filled. Gear whose standing is not reached is never
picked; reached gear can still be followed from the finder by hand. Kept per character in
`BlackthornesEquipmentCharDB.upgradeQuest`, `.upgradeQuestTabs`, `.upgradeQuestTab`, `.upgradeQuestSkipped` and
`.upgradeQuestsDone` (never rename them). Completed quests: the finder asks
`C_QuestLog.IsQuestFlaggedCompleted` (unverified on Forever) and also
remembers hand-ins it sees (`QUEST_TURNED_IN`) in `.questsTurnedIn`; an
upgrade quest whose quest was handed in without its reward is dropped and
skipped. Quest chains (the owner asked 2026-10-04): `Sources.QUESTS` also
carries the quests before a reward quest (`p` = the quest before), and
`Finder:Chain` walks back past what is done; the upgrade quest lists them
as steps first and counts each as extra work when it picks. When something
as good or better is worn first, the quest closes with a "You already beat
this one" banner (not counted as done) and the next one is picked. On a level up the quest stays
(the owner asked 2026-10-04): `UpgradeQuest:LookForBetter` rescans for a short
while and, when an upgrade is worth 1.5 times the quest's (gain times
ease), offers it in a box on the panel (Switch, Keep current; kept past
ones are not offered again that session). Not yet seen in
game; `/beq probe` lists the quest log calls it reads. Tabs (asked
2026-10-04): one quest per kind of source (Vendor, Quest, Dungeons and
Raids, Crafted) in `.upgradeQuestTabs[tab]`, the tab shown in
`.upgradeQuestTab`; `.upgradeQuest` is kept as a copy of the shown tab's
quest, and a quest saved there before the tabs is read once onto its tab.
The panel wears the Titanforged plate and close gem (the close gem turns
the quest off). A plain click on a finder row (asked 2026-10-06, a player's
request) follows that upgrade: `UpgradeQuest:Follow` puts it on its source's
tab, shows that tab and turns the quest on; `UpgradeQuest.CanFollow` says why
not for gear that waits on a reputation, a level or another player's craft.
Right-click still tracks and Alt-click still pins. Settings has the quest's Open and Ignored; Ignore, Switch and the tab are on the panel and typed (the owner, 2026-10-15).
Quests that start from an item (the owner asked 2026-10-08: "it starts from
Demon Scarred Cloak" said nothing): `Data/QuestStarts.lua`
(`Sources.STARTS`), generated by `tools/make_quest_starts.py <pfQuest>
[Farmer]` after `make_sources.py`, never by hand, lists for each such
quest the mobs, objects, dungeon bosses or vendors with the item, Farmer's
Forever drops first, each with a real spawn spot; `UpgradeQuest.Starter`
reads it and the steps say "Get X from Mob (level, rare) in Zone (x, y)",
then "Right-click X in your bags". Rerun it with `forever_drops.py`.
Where a quest is done and handed in (the owner asked 2026-10-08, when the
arrow sent him back to The Ravaged Caravan's giver): `Data/QuestEnds.lua`
(`Sources.ENDS`), generated by `tools/make_quest_ends.py <pfQuest>
[Farmer]` the same way and rerun with it, gives each quest's hand-in NPC or
object and one objective place (a mob, an object, or where an objective
item drops, Forever's drops first), real spawns in the quest's own zone
first. `UpgradeQuest.Ender` reads it: a quest in the log points at its
objective, else its hand-in, and the hand-in once it is ready, never at
its giver; with nothing known it has no place.
A quest with several objectives carries a place for each (`m` beside `o`,
2026-10-19, after the arrow stayed on Logging Rope once Warsong Supplies
had it): `UpgradeQuest.OpenGoal` reads the log's objectives
(`LogObjectives`, `QuestLog:Find`) and picks the first place whose item or
mob name a line marked done does not name, so the step, arrow and pin move
on; a line it can't match (another language) counts as not done. The
quest log tab's `QuestLog.Place` uses the same. An item objective prefers
a source in the quest's own zone, Forever's before Classic's. Tested in
`tools/test_questobjectives.lua`.
A hand-in step whose quest is ready (`QuestReady`) carries `turnIn`, and
the panel then shows the game's yellow ? (`ActiveQuestIcon`) on that step
and in its header instead of the ! (the owner asked 2026-10-10), read on
the same debounced quest log refresh as the steps.
Closing and bringing it back (the owner asked 2026-10-13: "an easy way
for someone to close upgrade quest but also bring it back"):
`UpgradeQuest:TurnOn`, `:TurnOff` and `:Toggle` are the one way to do
either, its quests always kept. The panel's close gem says how to bring it
back (`QuestPanel:ExplainClose`, a hook, so the shared Titanforged file is
untouched), the gear window's header has an Upgrade quest button (green
while it is up, `UI:OnUpgradeQuestToggled`), and Shift-click on the
minimap button toggles it. Tested in `tools/test_questtoggle.lua`.
Ignore (the owner asked 2026-10-08) is the old Skip renamed: the same
`.upgradeQuestSkipped` list, never offered again until restored.
`UI/IgnoredWindow.lua` (Settings > Upgrade quest > Ignored, `/beq quest
ignored`) lists it with Restore on each (`UpgradeQuest:Restore`) and Restore
all (`RestoreAll`, `/beq quest restore`); `skip` and `reset` still work.

The quest arrow (the owner asked 2026-10-08 for Farmer's goal arrow here):
`Logic/QuestArrow.lua` and `UI/QuestArrow.lua` are Farmer's
`Logic/Arrow.lua` and `UI/Arrow.lua` brought over as a copy (no call into
Farmer), and `tools/make_arrow_art.py` is Farmer's tool, drawing the same
`Media/Arrow/*.tga`. It follows the quest on the tab shown and points at
the places its steps carry (`UpgradeQuest:Steps`), from the step to do now
on, a spot beating a zone-only step for the same zone; a zone with no spot
gets its middle, labelled so; it never makes up a coordinate. Off by default
(`questArrow`, account wide; spot `questArrowX`/`questArrowY`); the panel's
Arrow button, a click on a step with a place (`QuestArrow:Aim`), `/beq
arrow` and a Settings row turn it on. A fix to the dial in one addon belongs
in the other. Not yet seen in game; `/beq arrow check` reports the calls it
reads (`GetWorldPosFromMapPos`, `GetMapWorldSize`, `GetPlayerFacing`).
Pets has the same dial (its beast arrow).

The dial lies back like a compass on the ground (the owner picked it
2026-10-13 from `previews/arrow-3d/` in the project files). A tilted view
cannot be turned with SetRotation, so `tools/make_arrow_art.py` (numpy)
draws `Ring.tga` once and the blade with its shadow at 64 headings in
`Blade.tga` (8 a row, frame 0 straight ahead, then anticlockwise), its
glow in `BladeGlow.tga`; the dial shows the nearest frame with
SetTexCoord (`ArrowUI.FrameFor`), only when the frame changes. The blade
carries its own gold, so only its glow is tinted. Not yet seen in game.

TomTom (a player asked, the owner agreed 2026-10-09, then asked for it in
every addon with an arrow): with TomTom installed, each arrow hands its
place to TomTom (`Logic/TomTom.lua` in Farmer, Equipment and Pets, read
through `_G.TomTom:AddWaypoint`/`RemoveWaypoint` inside a pcall, waypoints
never persistent). "Use TomTom" (`useTomTom`, account wide, on unless
unticked; `arrow tomtom` on each addon's command) hides the dial while
TomTom shows the way, and the waypoint goes whenever the dial would hide,
so the one-arrow rule holds. The files are the same apart from names
(Farmer's reads the goal arrow's `x`/`y`, the others `mx`/`my`); a fix to
one belongs in all three.

The dial takes no clicks and shows no hover text (the owner,
2026-10-23: the clicks confused players): drag moves it, the red gem
closes it, and nothing else. Never add a click or tooltip to it again
unasked; the same in every addon with an arrow.

Only one Blackthornes arrow is on screen at a time (the owner asked
2026-10-08): Farmer's goal arrow, Equipment's quest arrow and Pets' beast
arrow agree through one global table, `_G.BlackthornesArrows`
(`wants[addon]` while that arrow has something to show, `claims[addon]` the
`GetTime()` it was last turned on or aimed). The one wanting to show with
the latest claim is drawn; the others wait hidden. The lines are the same
in each dial's file (`ArrowUI:Claim`, `ArrowUI.Wins`); a change to them
belongs in all three.

## The way there (arrows across zones and the sea)

The owner said build it (2026-10-21, from a mockup) in every addon with an
arrow: a quest arrow aimed at a place in another zone or on the other
continent leads the way step by step (flights this character knows, the
boats and zeppelins of its side, its Hearthstone, walks through the zones
between) instead of pointing straight over mountains and sea. On unless
unticked: "Guide Me:" on the Upgrade quest page (`arrowRoute`, account wide,
never rename it) and `/beq arrow route [on|off]`. `Logic/Travel.lua`,
`Data/Travel.lua`, `Data/TravelZones.lua`, `UI/TravelCard.lua`,
`UI/TravelMap.lua`, `Media/Frame/TravelDot.tga`, `tools/make_travel.py`
and `tools/make_travel_zones.py` are Farmer's files, the same in every
addon (a fix to one belongs in all; Farmer's `CLAUDE.md` has the details).
What differs is `ns.TravelHost` at the end of `Logic/QuestArrow.lua`;
`QuestArrow:TripState` turns a trip into the dial's words and gives
`trip.point` its `mx`/`my`, which TomTom gets (`TomTomLink.Point`). Every
copy reads the flights, crossings and Hearthstone spot the others saved
(`travelFlights`, `travelCrossings`, `travelHearth`, never renamed).
Tested in `tools/test_travel.lua`. Not yet seen in game.

## Dungeon Quests

The owner said build it (2026-10-20, from a mockup): every quest done
inside a dungeon or raid, and which this character has done.
`Data/DungeonQuests.lua` (`ns.DUNGEON_QUESTS[questID] = { dungeon key,
title, min, level, side, classes, giver, zone, x, y, reward, prev }`, and
`ns.FOREVER_DUNGEON_PLACES` from `forever_drops.py`'s `FOREVER_DUNGEONS`)
is written by `tools/make_dungeon_quests.py <mangoszero> <pfQuest>
--tables <tables folder>`, never by hand: Classic's quests filed under a
dungeon's zone (AreaTable's ContinentID is the instance) or whose
objectives are inside one, kept only when the Forever client's QuestV2
table has them. The tables hold IDs only, no names, so Forever's own
dungeon quests are learned in game (`Logic/DungeonQuests.lua`,
`DQ:LearnLog`): a quest in the log under a heading naming a dungeon, or
accepted while inside one, is kept account wide in
`learnedDungeonQuests[questID]`. At each release
`tools/forever_dungeon_quests.py --tables <tables folder> --cache
<questcache.wdb> [save]` folds them into `Data/ForeverDungeonQuests.lua`
(`ns.FOREVER_DUNGEON_QUESTS`, the same row shape; never by hand), so every
player gets them: from the game's English quest cache on the owner's PC
(`Cache\WDB\enUS\questcache.wdb` beside `WTF`, read only: ID, title,
levels, the area it is filed under, which counts when AreaTable puts it
inside a dungeon the addon knows, and the quest after it), and from
`learnedDungeonQuests` in his account save (side, giver, spot). Never
commit the cache or name it in public. `DQ:All` reads Classic's, then the
shipped Forever ones, then what this account learned (which fills in a
shipped quest's giver). Tested in `tools/test_forever_dungeon_quests.py`. Other authors' Forever quest pages may be
read as a checklist only, never copied into the data or named.
Status is Done (`Finder:QuestDone`), In Log or To Do. `UI/DungeonQuestsWindow.lua`
(`/beq dungeons`, the gear window's Dungeon Quests tab, Settings >
Upgrade quest) lists the dungeons and the picked one's quests; Follow aims
the quest arrow, Show the Way the game's map pin. Saved, account wide,
never rename them: `learnedDungeonQuests`, `dungeonQuestsHideDone` (off
unless ticked), `dungeonQuestsMyLevel` (false when unticked),
`dungeonQuestsPick` and the window's `dungeonQuestsPoint`,
`dungeonQuestsRelPoint`, `dungeonQuestsX`, `dungeonQuestsY`. `/beq probe`
has a "dungeon quests" line. Tested in `tools/test_dungeonquests.lua` and
`tools/test_make_dungeon_quests.py`. Not yet seen in game.

Names and doors from the game (the owner picked them, 2026-10-22): a
quest's row and the arrow show the game's own title
(`DQ:TitleOf`: `C_QuestLog.GetTitleForQuestID`, kept for the session,
else the data's; one the game has not loaded is asked for once with
`RequestLoadQuestByID`, and `QUEST_DATA_LOAD_RESULT` redraws a shown
window). Sorting still uses the data's title. `Logic/DungeonDoors.lua`
learns where each door stands: the spot outside, noted on zone changes,
as a loading screen starts and every `NOTE_EVERY` seconds (`Doors:Note`,
on the zone's own map; the loading screen alone kept nothing on Forever,
2026-10-23), is kept when `PLAYER_ENTERING_WORLD`, or a look again
`RETRIES` seconds later, finds a dungeon the addon knows
(`DQ.Inside`), account wide in `dungeonDoors[key].spots` (at most
`KEEP`; never rename it). A spot counts only in the door zone the data
names, or, with none named, once two agree (`NEAR`), so a hearth or a
summon is never taken for a door. `DungeonDoors:Fill` lays it on the
upgrade quest's door places (a dungeon drop, a boss that starts or ends
a quest), which were a zone's middle. `/beq probe` has "quest names" and
"dungeon doors" lines. Nothing new is shown to players in words. Before
any walk in, the door comes from `Data/DungeonDoorSpots.lua`
(`ns.DUNGEON_DOOR_SPOTS[key] = { zone, x, y }`, `DungeonDoors.Shipped`),
written by `tools/make_dungeon_doors.py <tables folder> --build <build>`
from the Forever client's game tables (Map's entrance spot, AreaPOI's
label first, UiMapAssignment for the zone map); never by hand, rerun when
the tables are pulled again. A spot is kept only in the door's own zone
(Blackrock Mountain's in Searing Gorge, else Burning Steppes, and a
shipped spot brings its zone to `Fill`). A walked-in spot always wins.
Tested in `tools/test_dungeonquests.lua` and
`tools/test_make_dungeon_doors.py`. Not yet seen in game.

Boss drops on the tooltip (the owner approved the words, 2026-10-22):
"Drops from BOSS in DUNGEON" under the item's other lines
(`Tooltip.DropLine`: Forever's own drop with the best rate from
`Sources.FOREVER`, else the Classic boss most likely to drop it from the
item's `d`, the dungeon named by `DQ.Dungeon`). "Boss Drops:" on the
Gear page, Off, Shift or Always (`dropsTooltip`, on unless unticked,
never rename it; Shift key "drops"). Tested in `tools/test_tooltip.lua`.

Dungeon Loot (the owner said build it, 2026-10-22, from a mockup whose
words he approved): what each dungeon's bosses drop, upgrades marked.
`Logic/DungeonLoot.lua` lays the drops out by dungeon once
(`DungeonLoot:Index`, Classic's from each item's `d`, Forever's own from
`Sources.FOREVER`, which wins) and judges each piece through the finder's
kept verdicts (`Finder:JudgeOnce`, `Compare.WearableUpgrade`), asking the
server for items not loaded (`ASK` a list). `UI/DungeonLootWindow.lua`
(`/beq loot`, the gear window's Dungeon Loot tab, Settings > Upgrade
quest) lists the dungeons for this side on the left; the picked one shows
its door and levels, Armor: and Stat: chips (cloth, leather and mail chips
leave out other body armor only), Upgrades Only, sortable ITEM, SLOT,
BOSS, GAIN heads (a third click is best first), "N shown. M are upgrades
for you.", Follow (the quest arrow to the door, `DungeonDoors` spot when
learned) and Show the Way (the map pin). Chips, the tick box and the sort
last the session. Saved, account wide, never rename them:
`dungeonLootPick`, `dungeonLootScale`, `dungeonLootPoint`,
`dungeonLootRelPoint`, `dungeonLootX`, `dungeonLootY`. Tested in
`tools/test_dungeonloot.lua`. Not yet seen in game.

## The Quest log tab

The owner asked (2026-10-10) for the game's quest tracker inside the
upgrade quest panel, picked the mockup
(`previews/equipment-quest-log-tab-mockup.png` in the project files) and
the wider panel: `QuestPanel.WIDTH` is 384 (was 340) so a fifth tab fits. `Logic/QuestLog.lua` reads the log
(retail `C_QuestLog` calls first, classic ones after, all in a pcall) and
does the actions: track, share, abandon (only through the game's own
`ABANDON_QUEST` box), open in the log, show on map, aim the arrow
(`QuestArrow:AimAtQuest`, a quest log quest the arrow follows until a step
is aimed at, the next tab is picked, or the quest leaves the
log). `UI/QuestLogTab.lua` draws it. The tab is not one of
`UpgradeQuest.TABS`: it shows while the character's `questLogTab` is set,
and `UpgradeQuest:SelectTab` clears it. Folded zones are per character in
`questLogFolded`; "Tracked only" (`questLogTrackedOnly`) and "Hide the
game's quest tracker" (`hideQuestTracker`, hidden only while the panel is
up) are account wide and off by default. Never rename them.

The game's tracker is never moved, re-parented, hidden or shown: while
the setting is on it is made see-through and its lines stop taking the
mouse (`ns.Veil:Cover`, `UI/Veil.lua`), caught again 0.2 s after a burst
of quest events, and put back as it was when the panel closes; a
protected line waits for combat to end. Quest item buttons are secure buttons parented to
UIParent and placed over their row by screen position (Pets' Feed button
does the same), so the panel stays free to move and close in combat; in
combat a button whose row moved fades (alpha 0) until
`PLAYER_REGEN_ENABLED` puts it back; a faded button shows no tooltip but
can still be clicked until the fight ends, since nothing insecure can
hide it then. Quest events only mark the log stale;
it is read once, 0.2 s later, and only while the tab shows, and rows are
filled again only when their key (title, objectives, tracked, item) changed.
The probe (2026-10-10) found the C_QuestLog calls on Forever and none of
the classic globals, so the tab reads the retail way (see
`docs/FOREVER_API_FINDINGS.md`); the tab itself not yet seen in game.

The step to do now (the owner asked 2026-10-13): when it is a quest in the
log (a chain quest's or the reward quest's Complete or Hand in step,
`step.questID`), `UpgradeQuest:Steps` reads that one quest
(`QuestLog:Find`, by `GetLogIndexForQuestID`, else by reading the log)
into `step.progress`, and the panel shows it as the tracker does
(`QuestPanel:FillProgress`): a tick box that tracks it, its title (a click
opens it in the quest log, shift-click links it) and its objectives with
their counts (`QuestLog.ObjectiveLines`, shared with the tab). The counts
are in `UpgradeQuest:Shows`, so the debounced quest log update draws the
panel again only when one moves. Tested in `tools/test_questprogress.lua`.
Not yet seen in game.

"Current step only" (the owner asked 2026-10-13): a tick box on the panel
beside "Change on a new zone", and "Steps shown" on the Upgrade quest page
of Settings (`upgradeQuestStepOnly`, account wide, off unless ticked, never
rename it; `UpgradeQuest:StepOnly`/`SetStepOnly`). Ticked, `FillBody` lays
out only the step to do now (the last when none is left), the item row and
buttons stay, and the panel shrinks to fit. It only redraws the panel and
Settings, never scans. Tested in `tools/test_queststeponly.lua`.

## Class training

The owner said build it (2026-10-13), in Equipment and Butler: which class
spells the character (and the other characters) can train now and soon,
and what they cost. `Logic/ClassTraining.lua`, `Data/ClassSpells.lua` and
`tools/make_class_spells.py` are the same files in both addons (a fix to
one belongs in both); neither calls the other for it. The data is
generated from the Forever client's game tables (`make_class_spells.py
<tables folder> --build <build>`; never edit it by hand, never commit the
tables): each class's trainable spells with level, rank, races and the rank
before. With `--prices <Classic world database dump> --learn <a Classic
client's SpellEffect table>` it also writes `CLASS_SPELL_PRICES`,
Classic's trainer prices (the full price where Classic had a discount),
which stand in until a trainer shows its own (`ClassTraining.PriceOf`,
`spell.guess`); never name where either came from. Real prices, which spells no trainer teaches and where the trainer
stands are kept the first time a class trainer's window opens, account
wide, in `classTrainingData` (never rename it). "Class training" on the
Gear page (`classTraining`, on unless unticked, never rename it) and `/beq
training [on|off]`.

Here it is the gear window's Training button ("Training (4)" while spells
wait) and `UI/TrainingDrawer.lua`, a drawer against the window's right
edge (left open in `trainingDrawer`): READY NOW and AT LEVEL N with each
spell's cost, WEAPON SKILLS for untrained weapon upgrades in the bags
(`UI.untrained`, a click shows the weapon master), and the other
characters' on this realm and side (`ClassTraining.SameSide`: each note
keeps its `realm` and `faction`, an older one takes them from
`characterGear` or Tradeskills' `Holdings`, else it waits until that
character logs in; a player saw the other side's, 2026-10-18). Show the way aims the quest arrow at the class trainer
(`ClassTraining.Guide` = `TrainingDrawer.Guide`). Tested in
`tools/test_classtraining.lua`. Not yet seen in game.
A spell is known when the client says so, when a class trainer showed it
as learned (kept by GUID in `classTrainingData.learned`, never rename it),
or when a higher rank of the same name is known (the data skips a rank now
and then; a player was told to train spells known a long time,
2026-10-19). A trainer line in another language matches by name and the
rank's number.
Skipping a spell (a player asked, the owner said build it,
2026-10-22): right-click a spell in Equipment's Training drawer to skip
it, and again to bring it back. Kept account wide in
`classTrainingData.skipped[guid][spellID] = time` (minus the time when
brought back; never rename it); the newest change wins between
Equipment's and Butler's saves (`CT.SISTERS`). A skipped spell leaves the
plan, Train all and the gold goal. Tested in
`tools/test_classtraining.lua`.

## What Farmer calls here

Farmer's XP bar (2026-10-13) reads class training for its level-up cheer,
inside a pcall, read only, after Butler's copy when Butler is loaded:

```lua
_G.BlackthornesEquipment.ClassTraining:IsOn()
_G.BlackthornesEquipment.ClassTraining:Plan()   -- ready, cost, unknown
```

Keep these names and fields stable (they are the shared
`Logic/ClassTraining.lua`'s, so Butler's too); if one has to change,
change Farmer's XP bar in the same breath.

## Put it on, and Take the reward

The owner's goal (2026-10-11): the addons should do the work for the
player. `Logic/Wear.lua` puts an upgrade on in one click: the upgrade
banner's **Put it on** button (`UI/Toast.lua`, shown when the banner was
made with `wear = true` and `Wear:Can` says yes) and a click on the gear
window's best-in-bags cell. `Wear:Can` checks combat, that the client has
`C_Item.EquipItemByName` or `EquipItemByName`, that the item is still in
the bags (`Wear.Find`, bags 0 to 4) and that `Compare:JudgeCarried` still
calls it a wearable upgrade; the slot it was judged for is passed on, so a
ring goes over the weaker one. Gear that binds when worn still shows the
game's own box. On the hand-in page a **Take** button under the quest
window (`QuestRewards:UpdateTake`, our own button on UIParent placed by
screen position, never on the quest frame) names the biggest upgrade, or
with none what sells for the most, and calls `GetQuestReward(choice)`.
"Take reward button" in Settings (`rewardButton`, account wide, on unless
unticked; never rename it). `/beq probe` lists the calls. Not yet seen in
game.

Put on upgrades (the owner asked 2026-10-15): with "Put on upgrades"
ticked (`autoEquip`, account wide, off unless ticked, never rename it;
Settings > Gear, `/beq autoequip [on|off]`), an upgrade that
`UpgradeChat:Consider` finds new in the bags goes on through `Wear:Auto`,
the same `Wear:Can` as Put it on. Held back to the usual line and banner
(`Wear:HoldBack`): gear not soulbound that would bind when worn (bind type
not 0), gear a Farmer goal names (`Goals:Find`) and gear Tradeskills'
`Butler:Advise` says a queued craft needs (`need` or `mailTo`), all read in
a pcall. Never in a fight (waits for `PLAYER_REGEN_ENABLED`); one piece at
a time, each judged again once the one before is worn (`Wear.SETTLE`), and
a piece the game would not put on falls back to the banner. A What's New
card (`autoEquip`) offers to turn it on once. Tested in
`tools/test_autoequip.lua`. Not yet seen in game.

## Sell coins in the bags

The owner asked (2026-10-10) for a gold coin on bag gear worth selling:
`BagIcons:Sells` puts the quest reward coin's look on gear judged and found
no upgrade, now or later (`Compare:JudgeCarried`), that a vendor pays for
(`Items:SellPrice`, kept per link): white gear, and soulbound green or
better gear when the character cannot disenchant (`BagIcons:CanDisenchant`:
the Disenchant spell, the profession list or classic's skill list, kept
until a skill or spell event). Greys, shirts, tabards, fishing poles and
gathering or profession tools (`BagIcons.IsTool`: known tool IDs, and gear
whose tooltip adds to Mining, Skinning, Herbalism or Fishing; the owner
asked 2026-10-10) get none. "Sell coins" in Settings (`bagSellCoins`, account wide, on unless
unticked). Not yet seen in game.

## The controller bag button

Forever's client draws a controller bag button (`GamepadBackpackButton`,
on its `GamepadBagBar`, from Blizzard's own bag bar file) over the combined
backpack's sort button. The owner asked (2026-10-09) to hide it:
`BagIcons:ApplyGamepadBag` makes it see-through and lets clicks through
to the sort button (`ns.Veil:Cover`) while "Bag sort button" in Settings
(`hideGamepadBag`, account wide, on unless unticked) is ticked; unticking
puts it back as it was. A protected button waits for combat to end.

Why never Hide or Show (0.18.0, 2026-10-10): calling them on a game frame
runs the game's OnHide/OnShow code as this addon. The tracker and the bag
bar are Edit Mode frames, so the taint stayed in Edit Mode's layout and its
next update read auras as Equipment: "GetAuraDataByIndex(): Auras cannot
be accessed when secret while tainted by 'Blackthornes_Equipment'". Calling
the game's update functions (`ObjectiveTracker_Update`) does the same. To
put a game frame out of sight, use `ns.Veil`: SetAlpha and the mouse calls
run no game code. The same holds in every addon.

## Best Armor Only

A player-facing choice the owner asked for (2026-10-18): a character that
wears a heavier armor can stop being offered lighter kinds. "Best Armor
Only:" on the Gear page under JUDGING GEAR, kept per character in
`BlackthornesEquipmentCharDB.bestArmorOnly` (off unless ticked, never
rename it; `Compare.BestArmorOnly`, `Compare:SetBestArmorOnly`). Ticked,
`Compare:Judge` answers "cantuse" with `lighterArmor` (no tooltip line) for
cloth, leather or mail lighter than `Weights:IsLighterArmor` allows: the
heaviest kind open at the character's level, where a kind learned later
(plate or mail at 40) counts in a slot only once that slot holds a piece
of it (`Weights.WornArmorRank(slots)`, the owner 2026-10-18), so a warrior
past 40 still sees mail for every slot plate has not replaced yet.
Cloaks, rings, necks, trinkets, shields and weapons are never touched.
Everything that judges through `Judge` follows (arrows, gear window,
finder, quest rewards, Butler, Tradeskills' arrows); an upgrade quest
picked for lighter armor is let go quietly (`UpgradeQuest:LighterArmor`).
Alts keep `Weights:IsBestArmor` as before. Tested in
`tools/test_bestarmor.lua`.

## Gear for other classes only

A player's report (2026-10-22): a druid was told Hunter-only shoulders
were an upgrade. `Compare:ClassAllows(class, link)` reads the item's class
mask (`Compare.ClassMask`: `ForeverItems`, then `Sources.ITEMS`, then
`Crafts.ITEMS`), else, for gear no data knows, the item's own "Classes:"
tooltip line (`Items:ClassesOnTooltip`, by `ITEM_CLASSES_ALLOWED`, kept per
item ID), and lets anything unknown through. `Judge` answers "cantuse" for
gear limited to other classes (so the tooltip, bag arrows, finder, Butler
and Tradeskills follow), `Alts:Judge` never offers it to an alt of another
class, and `Finder.Wearable` leaves it out. Tested in
`tools/test_classonly.lua`.

## Ratings, the hit cap and racials

Asked 2026-10-16, after the 10-15 patch changed the racials. Forever gear
gives hit and crit as ratings: `Weights.RATINGS` and `Weights:RatingPer`
turn them into the percent they give (the client's rate first, else the
usual table scaled by level), so the weights stay per 1%; plain hit and
crit rating count as spell hit and crit too (`EITHER`). `Weights:Score`
returns the score and the hit it holds; `Compare:ScoreOf` returns score,
hit and what the hit adds, and `Against` the hit worn there. Hit past the
cap (`Compare.HIT_CAP`: 5 weapons, 3 spells; with two weapons half up to
`DUAL_WIELD_CAP` 24) is taken off both sides in `Judge`, `JudgeCarried`
and `BestInBags` (`Capped`, `result.hitCapped`), from the hit the client
says the character has (`Compare:CurrentHit`); unread, nothing is capped.
Racials (`Weights.RACIALS`: Tauren Stamina, Human Spirit, Gnome Intellect,
5% unless the spell text says otherwise) are laid on in
`Weights:ForPlayer` through `WithRacials`, a copy; `Get`, the weights
window and `customWeights` are untouched. Alts get neither. Since the patch
no racial favours a weapon kind. Tested in `tools/test_ratingsandcap.lua`.
A weekly patch check looks for racial, rating and cap changes.

## Players' own stat weights

Kept in `BlackthornesEquipmentDB.customWeights[CLASS][spec][stat]`, account
wide, only for stats the player changed (`Weights:Get` lays them over
`SPECS`). The house rule: saved data is never lost or renamed in an update, so
never rename that key, never reshape it without keeping the old values, and
never delete a value the code cannot read (it is skipped instead).

Weapon types (a player asked, the owner agreed 2026-10-09): one number per
kind of weapon, by class and spec, multiplying that weapon's whole score in
`Compare:ScoreOf` (`Weights:FactorFor`), 1 for no change. Kept apart in
`BlackthornesEquipmentDB.weaponTypeWeights[CLASS][spec][subclassID]` (never
rename it), only for kinds changed, so `customWeights` never holds a table.
The weights window lists the kinds the class can hold (`SPECS.<CLASS>.weapons`)
under its stats; its reset clears both.

## The shared minimap button

A player asked, the owner said build it from a mockup (2026-10-28), in all
five addons: one minimap button for every Blackthornes addon loaded, whose
click opens a small menu (the house frame, "BLACKTHORNES" on the plate, a
dark glass row for each addon with its icon, name and what it does). A
row's left-click opens the addon, right-click its settings; Farmer's
middle-click brings back its panels and Equipment's Shift-click toggles
the upgrade quest. `UI/SharedMinimap.lua` is the same file in all five (a
fix to it belongs in all five), and so is `tools/test_sharedminimap.lua`.
There is no shared core addon: every copy signs up in
`_G.BlackthornesMinimap`, each addon joins with its own button
(`SharedMinimap:Join`), and the copy with the highest `FILE_VERSION` draws
the shared button and menu. It is on by default (the owner, 2026-10-28):
"Combine Addon Buttons:" in each addon's Settings, ticked unless unticked;
unticked, every addon keeps its own button. Only our own buttons are hidden
or shown, never the game's. Saved in every loaded addon's account save,
account wide, never rename them: `minimapButton` ("shared" or "each", nil
reads as shared), `minimapButtonAt` (the newest answer wins) and
`minimapSharedAngle`. Never call it "One for All" (another addon's name).
Every addon's own button also takes left-click to open and right-click for
settings. Not yet seen in game.

## The settings pages (from Tradeskills)

The owner asked (2026-10-09) for Tradeskills' Settings upgrade in Pets,
Equipment and Farmer. `UI/SettingsPages.lua` is the same file in all three
(a fix to it belongs in all three): category pages along the top
(`settingsPage`, the one left on: Gear, Upgrade hunts, Upgrade quest,
General), two columns a page, what a setting does as the row's tooltip
("Show descriptions", `settingsDescriptions`, off by default, puts it back
under the rows), "Find a setting" (`Widgets.CreateSearchBox`, Pets' copy of
Farmer's), and Text size (`textSize` normal/large/larger adds 0/1/2 to
`Theme.sizes`, now a lookup over `Theme.BASE_SIZES`; read once, so it waits
for /reload). The window fits its fullest page, so no page scrolls. Add a
setting with `pages:Row(page, column, label, description)` and
`pages:Section(page, column, "HEADING")` in `UI/Settings.lua`; a row whose
words change (the spec row, the panel size row) calls
`row:SetDescription(text)`. Every `/beq` command has a button there,
but for those that only list things in chat (`bags`, `tracked`, `help`,
`training` with no word) or do what a panel already has a button for: those
are typed only (the owner, 2026-10-15; `tools/test_settings.lua` keeps the
list). Labels are Title Case ending in ":" ("Text Size:"), tick boxes say
"On" or "Show", buttons one word ("Open"), and a row has a hover only
when it needs one (an empty description shows nothing). The minimap button
always shows; there is no `/beq minimap`, and a saved `minimapHidden` is
kept but not read.
Word choices are drop-downs, never < > pickers or word steppers (the
owner, 2026-10-23): `Widgets.CreateChoice` takes a stepper's opts
(min, max, step, value, format, onChange) on Pets' `Widgets.CreateDropdown`
and answers `SetValue(value, silent)`, `GetValue()`, `.text` and
`:Pick(value)` (what a menu click does); only numbers keep a +/- stepper.

## Off, Shift or Always for tooltip lines

A player asked, the owner said yes (2026-10-18), in all five addons: each
tooltip line gets Off, Shift or Always in Settings, Shift showing it only
while Shift is held. `UI/TooltipShift.lua` is the same file in all five (a
fix to it belongs in all five). No one's settings change: whether a line is
on stays in its own key, so a line that was on reads Always and one that
was off reads Off; only a Shift pick is new, kept account wide in
`tooltipShift[key] = true` (never rename it). Equipment's keys
(`TooltipShift.KEYS` in `UI/Tooltip.lua`): "upgrade" (Tooltip Line,
`tooltipLine`: the verdict and the weapon master line), "suffix" (Random
Roll Names, `suffixLine`), "alt" (Upgrades for Alts, `altTooltipLine`),
"enchant" (Best Enchant, `enchantTooltip`) and "drops" (Boss Drops,
`dropsTooltip`). Each line carries `line.key`;
`Tooltip:Decorate` asks `TooltipShift:Shows` as it adds them, so the kept
lines (`LinesFor`) never hold the Shift answer, and a line held back adds
"Hold Shift for more." once (`TooltipShift:Held`). The shared frame redraws
the tooltip when Shift moves, only while some line is on Shift. The
Settings rows are steppers (`ShiftStepper` in `UI/Settings.lua`, synced on
Refresh). Tested in `tools/test_tooltipshift.lua`.

## German translation

The owner said yes (2026-10-12) to German in Equipment, after Pets' pilot
and Farmer. Players are told the language as "Deutsch"; the code names
stay `deDE` and `Locale/deDE.lua`.

- **English is the key and the fallback.** `Locale/Locale.lua` (first in
  the TOC, Pets' file) makes `ns.L`, whose missing keys answer the key
  itself; `L.Format(key, ...)` is `string.format` on the translation and
  puts values named by place (`%2$s ... %1$d`) in order.
- **Adding a string:** `L["English text"]` or `L.Format("English %s",
  value)`, a literal where it is written, one whole sentence a key (never
  pieces joined with `..`), both forms for a plural; add its line to
  `Locale/deDE.lua` (informal "du" and the game's words: Verbesserung,
  Ausrüstung, Händler, Quest, Dungeon, Schlachtzug, Ruf, Stufe, Gebiet)
  and run `python tools/check_locale.py` (warns only; keep it at 0
  missing). `tools/test_locale.lua` loads Equipment as a German client.
- **Spec and stat names stay English inside** (`SPECS`, saved weights,
  `customWeights`); only `Weights.Label(name)` and `Weights:SpecName(class,
  spec)` show them. `result.specName` is for showing only.
- **Left in English on purpose:** slash command words, saved and internal
  keys (verdicts, kinds, `Finder.NEEDS`), anything compared against data or
  the client, data names (items, zones, NPCs, professions, trainers),
  random-roll suffixes ("of the Monkey", from the data), "[Forever]",
  debug lines and the checks players run for a report (`/beq probe`,
  `/beq arrow check`).
- German runs about 30% longer: buttons grow to fit, settings rows wrap,
  and a new fixed width must wrap or grow, never end in "...".

## Names in the player's language

A player asked (2026-10-28) for the upgrade quest's steps to name quests,
people, zones and items in their own language. `Logic/Names.lua`
(`ns.Names`) turns a name the data has in English into the game's own,
only on a client in another language and only as it goes into words: the
data, the places, the saved quests and every check keep the English name.
Zones by their map (`Waypoints.ZONE_MAPS`), dungeons by
`GetRealZoneText(instanceID)`, quests by the client's title for the ID,
creatures by a hidden tooltip on `unit:Creature-...-ID`, items by item
info, professions by their spell. The data has names but no creature or
item IDs, so `Data/NameIDs.lua` gives them, written by
`tools/make_name_ids.py <mangoszero database>` (never by hand; rerun it
after the other data tools). Objects stay English: the client cannot name
one by its ID. Every answer is kept; a miss stays English, is asked again
at most every `Names.RETRY` seconds, and the upgrade quest panel draws again
once it comes in. Callers: the upgrade quest's steps, the quest arrow, the
finder, crafting lines, the tooltip's boss line, Dungeon Quests and Dungeon
Loot, map pins and Show the way's chat lines. `/beq probe` has a "names"
line. Tested in `tools/test_names.lua`. Not yet seen in game.

The Show on map marker (the same player asked, the owner said build it
from a mockup, 2026-10-28): on Era the place Show on map asks for
(`Waypoints.marked`) is Equipment's own pin, and it is now bigger than the
hunt pins (`MapPins.MARK_SIZE`, `MapPins:MakeMarker`): the icon in dark
glass in a gold rim, a red gem on top, a soft beam above, a glow and two
gold ripples at its foot, and the place's name in the player's language on
a small plate under it (`DressMarker`). Only `Media/Frame/Glow.tga`, no new
art. The glow breathes and the ripples run only with Effects on Full, as
looping animations the game plays itself; Subtle and Off hold still. No
new words. Tested in `tools/test_hunts.lua`. Not yet seen in game.

## Simplified Chinese, French, Spanish and Russian

The owner said yes (2026-10-18) to these four in every addon, after Pets'
Simplified Chinese pilot. They are written by us from the English keys:
never take a translation file or text from a player or anyone outside.
Talk to the owner about the languages by name ("Simplified Chinese",
"French"); the code names are `zhCN`, `frFR`, `esES` and `ruRU`, each a
`Locale/` file that works like `Locale/deDE.lua` and loads only on its own
client. One Spanish file serves both Spanish clients (`esES` and `esMX`).
The voice is informal (tu, tú, ты), the game's own words, metres in French,
Spanish and Russian and 码 in Chinese. Every new string gets a line in each
of the five files; `tools/check_locale.py` checks them all. Tested in
`tools/test_locale.lua`. Not yet seen in game.

## The house frame (Titanforged)

The owner picked this look for all four addons on 2026-10-04 from two mockups
(the other was "Arcane Glass"). It's the game's own window shape with the
light turned up: a gold metal rim with corner gems, a round portrait with
the addon's emblem, the name on a plate across the top edge, a red close
gem, and gold-edged metal buttons. The main action is solid gold with dark
"ink" lettering; a primary button given its own dark face (`baseColor`)
keeps a gold label, so it never reads as an empty box
(`tools/test_titanforged.lua` checks every button's contrast).

`UI/Titanforged.lua` (`Titanforged:Dress(frame, opts)`, `:Opened(frame)`)
and `tools/make_frame_art.py` are Tradeskills' copies; the art is
`Media/Frame/*.tga`, which the tool writes. Equipment's emblem is the
shield (`EMBLEM = "shield"`): a rimmed heater shield with the upgrade arrow
cut out, redrawn here (`heater_shield`, `EMBLEM_RIM`) so it reads at the
36 pixels the portrait shows it at. The Lua differs from Tradeskills' only
where Equipment's differs: `Theme.TextWidth(size, text)`, and optional
pieces read with `rawget`, because this repo's test frames answer any
missing field with a function. A fix to the frame in one addon belongs in
all four.

The gear window and the finder wear the whole frame (portrait, plate,
close gem), with their lists sunk in a well (`Theme.Recess`); settings and
the stat weights get the plate and close gem only, and so does the upgrade
quest panel (asked 2026-10-04; its quest sits in a well too). The other
panels that stay on screen while playing (tracker, toasts, the character
sheet's slot list) keep `Theme.Window` and only share the restyled
buttons. "Effects:" under EFFECTS on the General page (2026-10-21, as
Farmer's) picks Full, Subtle or Off: `effectsLevel` (nil for Full, so
nobody's windows changed; account wide, never rename it), read by
`Motion.Level()`. Subtle drops the glint and the rise, Off holds still.

Every window wears the house size grip (2026-10-21, as Farmer's):
`Widgets.WindowGrip(frame, key, done)` scales it 50% to 150% from its top
left, right-click is normal size. Saved in percent, account wide, never
renamed: `windowScale`, `finderScale`, `weightsScale`,
`dungeonQuestsScale`, `ignoredScale`, `settingsScale` (the quest panel
had its own before). A new window gets one too. The finder's rows show every line in full: each
grows to fit (`FinderUI:FitRow`, at least `ROW_HEIGHT`) and `Draw`
stacks them until the list is full; how far it scrolls is measured on a
row kept out of sight (`MostOffset`). `FinderUI.Fit` (cut at a whole
word, no "...") is left for the tracker and the character sheet's list.

List rows in the gear window and the finder are dark glass (the owner
picked it 2026-10-10 over a gold glow that lit every row; Tradeskills'
lists have the same): `glass`/`glassAlt` bands in the well with a fine
line under each, `glassHover` and the gold wash only under the mouse. A
gradient that fades goes through `Theme.LightGradient`, which hides it at
0; faded with SetAlpha alone it stayed lit on Forever.

## The gold plaque

Buttons that sit out on the screen on their own wear the gold plaque (the
owner picked it from a mockup, 2026-10-27, "Option B"): a gold rim with a
red gem at each end round dark glass, the item's icon in a small gold
frame, a first line saying what the click does and a second under it, and
a soft glow that breathes while it waits (Effects Full; still on Subtle,
none on Off). `UI/Plaque.lua` is the same file in Pets, Equipment and
Farmer (a fix to it belongs in all three): `Plaque.Create(parent, { name,
template, width })` and `:SetLines`, `:SetIcon`, `:SetGlowing`, `:Flash`.
Here it is the Take button under the quest window: "Take NAME", then
"+N% over what you wear" in green, or "Sells for X" (`QuestRewards:Pick`).
Tested in `tools/test_questrewards.lua`. Not yet seen in game.

## The fold gem

A player asked, the owner picked the mockup (2026-10-24), in all five
addons: a small gold gem left of a window's red close gem folds the window
down to its plate and opens it back up. `UI/FoldWindow.lua` is the same
file in all five (a fix to it belongs in all five), and so are
`tools/make_fold_art.py` (draws `Media/Frame/FoldGem.tga`; rerun it, never
edit the TGA) and `tools/test_foldwindow.lua`. `FoldWindow:Add(frame,
{ onToggle, canFold })` after `Titanforged:Dress`; it sits on the trim, so
`Titanforged.lua` and `BlizzardLook.lua` are untouched. Folded, the window
keeps its place and width and is `FoldWindow.HEIGHT` tall: the rim, fill
and halo stay (`FoldWindow.Keeps`, by where each lies), the bottom corners
and everything else on it hide and stay hidden while folded, and it can
still be dragged. The gem again, closing it, or opening it by a command or
the minimap button opens it full (`Unfold`). In a fight it will not fold
over a button the game guards. With the Blizzard style it is the game's
own minimize and maximize art when the client has it. Tooltips "Collapse
this window" and "Expand this window"; nothing is saved. Here: the gear window and its stand-in tabs (`UI/FinderWindow.lua`, `UI/DungeonQuestsWindow.lua`, `UI/DungeonLootWindow.lua`, `UI/Settings.lua`); the upgrade quest panel keeps its own fold button.

## The Blizzard window style

The owner asked (2026-10-10) for a choice of the game's own look beside
Titanforged, in all four addons. "Window style" in Settings (`windowStyle`,
`titanforged` or `blizzard`, Titanforged by default; read once at login,
so a change waits for /reload, as Text size does). `UI/BlizzardLook.lua`
is the same file in all four (a fix to it belongs in all four): picked, it
lays the game's colours over `Theme.colors` (grey metal, the game's gold,
plain rows with a blue bar for the one picked) and puts out the halos;
`Titanforged:Dress` hands the window to `BlizzardLook.Dress` (silver rim,
a title tab where the plate sits, a silver-ringed portrait and the game's
`UIPanelCloseButton`, with the same trim fields); and the widgets call
`BlizzardLook.Button`, `.Checkbox` and `.Thumb` (the finder's scroll
thumb) to wear the game's own texture files. Equipment's Settings have no
hanging tabs, so `.Tab`/`.SelectTab` go unused there, and the setting is
a drop-down on the General page beside a Reload button. It never touches a
Blizzard frame. Each file is checked once (`BlizzardLook.HasArt`); a
client without one keeps that widget in the house look, and `/beq probe`
lists what is missing. Not yet seen in game. New widgets should look right
in both styles.

## Reading the probe

The owner asked (2026-10-10) for check results without screenshots, in all
four addons. `ns.KeepCheck(name, fn)` in `Core/Init.lua` runs a check that
prints to chat, keeps every line it prints (colours and links taken out, a
secret value kept as "(secret)") and saves them in the account save as
`lastProbe = { check, at, version, lines }`, replacing the last one; chat
adds "Saved for Claude, /reload to write it." It wraps `/bts probe`
(Tradeskills, saved under `BlackthornesTSDB.global`), `/beq probe` and
`/beq arrow check` (Equipment), `/bpet probe` and `/bpet arrow check`
(Pets), and `/farm arrow check` and `/farm gathering check` (Farmer, which
has no probe). None has a Settings button (the owner, 2026-10-23: checks and debug are typed only, so players never see them; `RegisterHiddenCommand` keeps them out of help, Tradeskills' short help leaves them out). Never rename `lastProbe`; a new
check that players run for a report goes through `ns.KeepCheck` too, and a
fix to it belongs in all four.

When the owner says "read the probe": he has run the check and typed
`/reload` (or logged out). In the thread, connect to his device, ask for
his game's WTF folder (already approved; the path is in the project's
memory) and stage the addon's account save from
`WTF\Account\<account>\SavedVariables\` (`Blackthornes_TS.lua`,
`Blackthornes_Farmer.lua`, `Blackthornes_Equipment.lua` or
`Blackthornes_Pets.lua`), read only. Read its `lastProbe`: `check` says
which one ran and `at` when; one older than his message means the save was
not written yet, so ask him to `/reload`. Use only the probe lines; never
commit the save or copy anything else out of it.

## Discord

The addons share a Discord server, Blackthornes AddOns (public invite
https://discord.gg/f2geDecrw2, set up 2026-10-05). After a release uploads,
`release.yml` runs `tools/announce_discord.py`, which posts the version's
CHANGELOG section to the server's #announcements through a channel webhook
kept in the `DISCORD_WEBHOOK_URL` repository secret. The owner sets that secret
himself; never ask him to paste the webhook address anywhere. Without it the
step does nothing, and a failed post never undoes the upload. The tool is the
same in all four repos; a fix to it belongs in all four.

The owner asked (2026-10-09) for one post in #general per release too,
and (2026-10-10) for it to be short: a few bullets in plain words, a
sixth-grade reading level, warm, in his voice (short, contractions, no
jargon, no file or setting names, never his name), saying what players will
notice. Each release PR writes the new version's section in `NEWS.md`
(`## X.Y.Z`, like CHANGELOG.md; it never ships) next to the CHANGELOG
section: the bullets, then one line of thanks. After the upload
`tools/post_general.py` scans it with `check_package.py`'s PRIVATE list and
posts it through the `DISCORD_GENERAL_WEBHOOK_URL` secret, which the owner
sets himself, under a line with the addon's name and version (so each
addon's bullets are their own group) and "(full list of changes in
#announcements)". It carries no CurseForge link and no card (link previews
are turned off). No section or no secret means no post.
A player's name never goes in a report (the owner, 2026-10-09): no
CHANGELOG, #announcements post, commit or PR text names a player, and
`check_release.py` refuses a CHANGELOG section that credits one
(`names_a_player` in `post_general.py`). The #general post is the one
exception: its last line thanks, by their Discord name, everyone who asked
for or reported the changes, each name once ("Thanks Ana and Bob for the
ideas and reports!"); leave it out when nobody asked. Find who asked from
the project's threads.
The thanks line no longer goes out with the webhook post (the owner,
2026-10-13: thank each player with a real @mention, so they get a
notification): `post_general.py` leaves out the paragraph that starts
"Thanks" (`without_thanks`), and the owner's bot, on his PC, posts it under
the release post with the mentions once he approves the wording, looking
the Discord names up there. Discord IDs never go in a repo. NEWS.md keeps
the thanks line, by Discord name, as before; ask the owner for any name
that isn't known.
This tool is also the same in all four repos.
Changes to the Discord bots, the digest or the release posting tools
(like this one) never go in a CHANGELOG, #announcements or #general
section (the owner, 2026-10-10): they are not changes to the addon.

The language is "Deutsch" in every post (the owner, 2026-10-11): a
CHANGELOG.md or NEWS.md section about the German translation or German
clients says "Deutsch", or "Deutsch (German)" where English readers need
the hint, never "German" alone. `tools/check_release.py` warns (it does
not refuse) when this version's CHANGELOG.md or NEWS.md section says
German without Deutsch. This rule is in every addon's notes; keep them
the same.

## What's New

The owner asked (2026-10-12) for the Discord #general post to show in game,
the first time it loads after an update, in one window for every addon.
`UI/WhatsNew.lua` is the same file in all five (a fix to it belongs in all
five), and so are `tools/test_whatsnew.lua`, `tools/make_whatsnew.py` and
`tools/test_make_whatsnew.py`. There is no shared core addon: every copy
signs up in `_G.BlackthornesWhatsNew` as it loads, the first to reach
PLAYER_LOGIN starts the only timer (`WhatsNew.DELAY`, 5 s, never in a
fight), and that one check gathers what is new in all of them. The copy
with the highest `FILE_VERSION` draws the window (first in
`WhatsNew.ADDONS` on a tie); raise it when a change needs the newer copy.

The words are NEWS.md's: it never ships, so `tools/make_whatsnew.py` writes
its newest three sections, bullets only (the thanks line names players and
never ships), into `Core/WhatsNewText.lua` (`ns.WHATS_NEW`; never edit it by
hand). The window shows new features only (the owner,
2026-10-13): a section's
fixes and other changes go under a "Fixes and changes:" line, which go to
Discord but not the window, and every line is plain words with no hype,
no questions to the reader, no exclamation marks and no dashes as
punctuation (the tool notes one that trips `STYLE`). **Every release PR that writes a NEWS.md section runs
`python tools/make_whatsnew.py` too**; `check_release.py` refuses a tag
while the file is behind, and `tools/test_make_whatsnew.py` fails on every
push. The bullets stay in English, also on a German client.

Shown once a version: each addon keeps the newest version shown in its own
account save (`whatsNewSeen`); after an update the sections newer than that
(at most three) show, and an addon that never kept one shows its newest.
"After an update" (`whatsNewPopup`) and "What's New motion"
(`whatsNewMotion`) are on unless unticked, off in all when off in any;
`whatsNewScale` is the size grip's, where the addon has one. Never rename
them. The `whatsnew` command and a Settings button open it any time, with
each addon's newest. It rises in, its divider draws out, each addon's card
slides up with its icon popping and a light crossing it, and the Got it
button glows (one looping animation the game plays, only while it shows);
Motion off lands it all at once. Not yet seen in game.

## The About page and the note

The owner asked (2026-10-13) for a note on how the addons are made, once at
the top of What's New and kept on an About page in every addon's Settings.
`UI/About.lua` is the same file in all five (a fix to it belongs in all
five): `About.NOTE` is the owner's wording, a paragraph a key; change it
only when he asks, in all five, with each `Locale/deDE.lua`. `About:Note`
and `About:Info` build the page's two columns (the version, the Discord in
a box to copy, how to report a bug, a thank-you that names no player, a
What's New button and the other Blackthornes addons from
`SisterNote.ADDONS`); each addon's Settings places them on its "about"
page. `UI/WhatsNew.lua` (FILE_VERSION 3) puts the note at the top of the
next window that comes up by itself, alone when nothing is new, then sets
`aboutNoteSeen` in every sister's account save (never rename it); with the
window turned off it waits. Tested in `tools/test_whatsnew.lua`.

One-time cards (the owner, 2026-10-13): an addon can put cards in
`ns.WHATS_NEW_TIPS`, each `{ key, title, icon, paragraphs, hint, button,
run, due }`. The next window that comes up by itself shows each one after
the note, only when `due()` says so (in a pcall), with a button that calls
`run()` and closes the window. Looked at once either way: the key goes in
that addon's account save as `whatsNewTipsSeen[key]` (never rename it), so
a card never comes back; with the window turned off it waits.
`UI/WhatsNew.lua` is at FILE_VERSION 4 for it. Equipment's
`Logic/UpgradeQuest.lua` has the first, for the upgrade quest, due while
it is off.

## The sister note

The owner asked (2026-10-11) for the addons to say, once, which of the
others a player does not have. `Core/SisterNote.lua` is the same file in
all five (a fix to it belongs in all five), and so is
`tools/test_sisternote.lua`. Every copy signs up in `_G.BlackthornesSisterNote`
as it loads; the first to reach PLAYER_LOGIN starts the only timer
(`SisterNote.DELAY`, 8 s, no ticker), and that one check prints one line for
all of them: the sisters not installed (`C_AddOns.DoesAddOnExist`, else
`GetAddOnInfo`'s "MISSING"), each with what it adds. One installed but
turned off is never named. Once per account: what it named is kept in every
loaded addon's account save as `sisterNoteTold[folder] = true`, so only a
sister never named before (one released later) brings it back. "Sister
addons" in Settings (`sisterNote`, on unless unticked) and the `sisters`
command on each addon: off in any is off in all, and changing it writes all.
Never rename `sisterNote` or `sisterNoteTold`. A new addon goes in
`SisterNote.ADDONS` in all the copies. It names only our own addons.

## One key per character

The owner asked (2026-10-11) that a character can never be mistaken for
another again. Old records had sent errands to the character playing:
Butler filled a mail to itself and told a player to mail Medium Leather to,
and log out for, the character they were on (an old "Name-Realm" record of
Tradeskills' beside the GUID one), and a reload wiped alts' saved gear in
Equipment. The rule, in every addon:

- **A character is its GUID** (`UnitGUID("player")`) in saved data and in
  every call between the addons. Never a first name, "Name-Realm" or a
  short name: Forever lets characters share a first name. Names are for
  showing and for a mail's To line only, always first and last.
- **A GUID the client won't read (a dungeon) means "not sure who's
  playing":** write nothing under another key, and offer nothing for an
  alt. Tradeskills remembers each character's GUID in its own file
  (`BlackthornesTSCharDB.guid`) for that case.
- **Old records stay readable and count as the same character; nothing is
  deleted.** Tradeskills folds an old "Name-Realm" record into the GUID one
  at login, once (`Config:AdoptLegacyCharacter`): it is kept whole in
  `formerCharacters[old key]` with `retiredInto` (never rename either), what
  the GUID record lacks is filled from it when it carries that GUID, and
  the queue's references to the old key follow. Farmer reads a goal tagged
  "Name-Realm" as the character's and tags it with the GUID once the
  character gathers toward it or changes it.
- **One test per addon answers "the same character?" and "the one
  playing?"; never compare keys or names by hand.** Tradeskills:
  `Characters:Same`, `:IsPlaying` and `:Canonical` (`Core/Characters.lua`),
  and `playing` on each `Butler:Holdings()` entry. Butler:
  `Errands:IsMe(name)` (full name, first name alone, any old record's name,
  any case, with or without a realm). Farmer: `Goals:IsOwner`. Equipment:
  `Alts.PlayerGUID()`.
- **Every errand that targets a character asks that test right before it
  acts and refuses the character playing:** a mail, a gold top-up, a Log
  out, an alt's upgrade, a learned habit, the disenchanter.
- Tested in Tradeskills' `tools/test_onecharacter.lua`, Butler's
  `tools/test_notme.lua`, Farmer's `tools/test_goals.lua` and Equipment's
  `tools/test_alts.lua`. This rule is in every addon's notes; keep them the
  same.

## Writing for players

Every word a player reads (labels, buttons, tooltips, Settings rows and
their descriptions, empty lists, chat lines, slash command help) reads the
way a friend who plays would say it: plain, warm and human. Write it at a sixth grade reading level. Short
sentences in everyday words, contractions welcome. Say what the player
sees or does, not how the addon works inside. No hype or sales words
("seamlessly", "effortlessly", "now you can", "powerful"), no filler, no
em-dashes, and no questions to the reader. The German in
`Locale/deDE.lua` changes with the English, in the same informal "du"
voice. Farmer's play cheers keep their "!" (drop-quality cheers, goal
marks, streaks, "Up to #N!", "Goal done: X!"), and `About.NOTE` is the
owner's own wording. This rule is in every addon's notes; keep them the
same.

## The owner's standing rules (all three addons)

- **Every list is dark glass** (the owner, 2026-10-12: "keep this as the
  standard across all Blackthornes addons", after Farmer's Kills & Loot
  panel was given the look of Tradeskills' queue). Rows or lines take
  `glass` and `glassAlt` in turn, by place, with a 1 px `border` line
  (alpha 0.6) under each; under the mouse `glassHover` and a gold edge,
  only on that row; the row picked or open is `glassActive` with a bright
  gold edge down its left. Never the older `row`/`rowAlt` bands for a
  list, a panel's lines or cards. A gradient fades through
  `Theme.LightGradient` or is hidden, never with SetAlpha alone (it stayed
  lit on Forever). This rule is in every addon's notes; keep them the same.
- **"Always check that it's clear to post."** Anything that goes public (a
  release, a CurseForge page, a post) is checked for private or unexpected
  content first, and nothing is published or uploaded without the owner's
  go-ahead. He tags releases himself.
- **Keep his data safe.** Never commit saved variables, tokens or anything
  from his machine; the upload keys are repository secrets he sets himself,
  so never ask him to paste one anywhere.
- **Changelogs come from git history.** Work out what changed since the last
  tag from the merged PRs and commits (`git log vX.Y.Z..origin/main --merges`);
  never ask the owner what went in. Claude drafts the CHANGELOG section in a PR;
  The owner merges, pulls `main`, tags and pushes.
- **A checkout shows the real version number** (the owner,
  2026-10-12). `ns.RELEASED_VERSION` in `Core/Init.lua` is the newest
  `## X.Y.Z` in CHANGELOG.md, shown when the packager has not filled in the
  TOC's `@project-version@` (he plays from a clone). The release PR that
  writes the CHANGELOG section changes it too; `tools/check_release.py`
  refuses a tag it does not match, and `tools/test_check_release.py` fails
  while the two disagree. This rule is in every addon's notes.
- **Every reply that ships code ends with the GitHub Desktop steps,** naming
  the branch: merge the PR on github.com (Ready for review, then Merge pull
  request); in GitHub Desktop switch **Current branch** to **main** and click
  **Pull origin**; then say whether the game needs `/reload` or a full restart
  (a full restart when a file is added, removed or renamed, or the TOC
  changes). For a release, add: History, right-click the newest commit,
  Create Tag, `vX.Y.Z`, Push origin. Remind him to pull `main` first, or the
  tag lands on an old commit and nothing runs.
- **CurseForge descriptions are features only.** Leave out privacy notes and
  any explanation of public emotes or their switches. Those belong in the
  README and CHANGELOG.
- **Forever is not retail for classes either.** The owner: "keep in mind this is
  WoW: Forever." Hunters have classic-style talent trees (Beast Mastery,
  Marksmanship, Survival; Survival fights in melee), not a spec picked from a
  menu, so `Logic/Weights.lua` judges by the spec with the most points. Never
  assume a retail API or stat exists: check with `/beq probe` and record what
  it finds in `docs/FOREVER_API_FINDINGS.md`. Forever has no classic
  talent-tab calls: each class has one trait tree (`C_ClassTalents`,
  `C_Traits`) holding all its specs side by side, so `Weights:TraitPoints`
  counts ranks by column, split where `SPECS.<CLASS>.columns` says. All nine
  classes' layouts have been probed (2026-09-30): the same split
  (`CLASSIC_COLUMNS`) in classic's tab order.
- **Smooth play comes first, but never at the cost of looks** (the owner,
  2026-10-09, after a hitch while crafting). Nothing on a timer or
  OnUpdate rebuilds or re-places a whole list, map or set of markers when
  only one thing moved: keep what is drawn, and redo only rows or pins
  whose inputs changed (a per-row key, a version number). Bag, loot,
  cast, skill and profession-list events arrive in bursts, several per
  craft or loot: coalesce them, read only what they changed, and skip
  work for windows that are hidden. Work over hundreds of items (recipes,
  sources, saved spots) is spread over frames (a worker with a small
  per-frame budget) rather than done in one frame, and shown when done.
  Clicks and typing still answer at once. The two causes found: Farmer's
  minimap markers gathered, sorted and re-placed every saved spot once a
  second because the clock second was in their redraw key (now only the
  fade moves, `MapMarkers:FadeMinimap`); and on every craft Tradeskills
  re-read every recipe in the profession window and repriced the whole
  craft pane in one frame (now `Recipes:NothingNewMidCraft` skips the
  re-read mid-run and `CraftPanel:RefreshInSlices` spreads the pane over
  frames). Visuals and usability are never traded away for speed. This
  rule is in all four addons' notes; keep them the same.
- **The client is WoW: Forever, a retail engine** (`## Interface: 16001`,
  modern Lua), not 1.12. Instances hand addons secret values that raise when
  compared, concatenated or formatted, so read client values inside a pcall.
  Registering an event the client does not know raises too, which is why
  `ns.RegisterEvent` wraps it.
