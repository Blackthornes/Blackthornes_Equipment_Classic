# Blackthornes Equipment

A WoW: Forever addon that answers one question: **should I wear this?**

It looks at the gear in your bags and the rewards a quest is offering, weighs
each piece for your class and spec against what you have on, and says which
one to equip.

Built for the WoW: Forever client (`## Interface: 16001`), without Ace3 or
LibStub, matching
[Blackthornes Tradeskills](https://github.com/Blackthornes/Blackthornes_Tradeskills)
and [Blackthornes Farmer](https://github.com/Blackthornes/Blackthornes_Farmer).
The three share a palette and a framework on purpose.

So far it judges the gear in your bags: hovering a piece says on its tooltip
whether it beats what you wear and by how much, and an upgrade you can wear
now gets a green arrow on its icon in the bags. When a quest lets you choose a
reward, the biggest upgrade among them gets the same arrow, and chat names it
when you hand the quest in; a **Take** button under the quest window takes
the biggest upgrade (or, with none, the reward that sells for the most) in
one click. Gear up for a group loot roll gets the arrow too,
with how much better it is under the icon, so you know when to Need. When an upgrade you can wear now lands in your
bags (looted, bought, mailed or traded), chat says so once, with how much
better it is, and its banner has a **Put it on** button. The gear window lists
every slot with what you wear and the biggest upgrade for it in your bags;
click an upgrade there to put it on. A slot with nothing better in your bags
shows a better piece you already own elsewhere instead, in your bank or in
another of your characters' bags or bank (when it can be mailed), so you
know to fetch it. Hovering gear that does nothing for you says which of
your other characters it would be an upgrade for, and by how much.

Its **Find upgrades** button (or `/beq find`) opens "Where to get upgrades":
for each slot, the best gear a vendor sells, a quest gives or a dungeon or
raid boss drops that beats what you wear, judged the same way, and where to
go for it (the vendor and their spot on the map with the price, the quest and
who gives it, or the boss, dungeon and drop chance). It offers what the
character can get: their own faction's vendors and quest givers, quests open
at their level they have not turned in, dungeons whose recommended levels
start at or below theirs, and raids at 60. Gear that needs a reputation is
listed once the character could buy or earn it, and before then in amber,
after everything else, saying which standing it needs. Hovering a row shows
the item and every place to get it; somewhere in the zone you are standing in
is listed first.

**Quest level**, on the row under the source buttons, sets how far above
your level a quest may be and still be offered: up to 4 levels by default,
from "Up to my level" to "Any". Beside it, tick **Solo quests only** (also
in Settings under Upgrade quest) to leave out quests that need a group, a dungeon, a raid or a
battleground, and quests that come after one, say while you get ready for a
dungeon run. The upgrade quest follows both. Which quests need others comes
from Classic's quest data: its own group, dungeon, raid and PvP marks, plus
quests whose kills, objects or items are inside an instance and quests to
kill an elite, which count as group quests. Forever may have changed some.
Tick **This zone only** on the same row to list just the upgrades from the
zone you are in (a vendor, a quest giver or a dungeon's entrance there, and
gear you can make anywhere); the list changes as you travel. It is the
window's own switch, apart from the upgrade quest panel's.

Crafted gear is listed too, under **Crafted**: what you can make now, what
an alt on your side can make (when Blackthornes Tradeskills is loaded and
has seen their recipes), what you could learn (the trainer, the recipe's
vendor or the mob that drops it, with the price), and what a crafter
elsewhere could make for you. Each says what the materials cost, from
vendor prices and Tradeskills' auction prices. Bind on pickup gear from a
profession you do not have is left out, since nobody could hand it to you.

Gear that can drop with a random roll ("of the Monkey") is judged at the
best roll for you, and the row says how often that roll drops and how often
the item drops as an upgrade at all. The tooltip names a rolled item's roll
from the stats it adds, since Forever's tooltips leave the name off.

The **Plan ahead** stepper looks up to ten levels past yours and lists gear
you can wear by then, in amber with the level it waits on.

**Upgrade hunts.** Right-click a row to track it. Tracked upgrades go on a
small tracker panel with where to get each, get a pin on the world map at the
vendor, quest giver or trainer, and a banner says so the moment one lands in
your bags; once you wear it the hunt is done and moves to the finished list.
Click a tracker row (or Alt-click a finder row) to put the game's map pin on
the spot. On the character sheet, hovering a gear slot lists its best
upgrades on offer, and Alt-clicking it opens a panel of them with Track and
Map buttons. The green arrow also marks upgrades on a vendor's page and in
the loot window. Each of these has a switch under Settings > Upgrade hunts.

**Upgrade quest.** Turn it on under Settings > Upgrade quest (or type
`/beq quest`) and Equipment hands you a quest for your best next upgrade:
the one most worth the trip, weighing how much better it is against how
easy it is to get. A panel like the quest tracker lists the steps (travel
there, find the vendor, pick up the quest, enter the dungeon, gather the
materials, put it on), lights the one to do now and ticks each off as the
game shows it done. A quest reward at the end of a quest chain starts
from the first quest you have not done, and a long chain counts as more
work when the upgrade is picked. **Show on map** pins the next place to go, **Ignore**
drops that upgrade for good on this character and moves on to the next
best (Settings > Upgrade quest > **Ignored** lists what you ignored, with
**Restore** on each and **Restore all**), and once you wear it a banner says the
quest is complete and the next one is picked. The panel wears the gold
house frame and has a tab for each kind of source: **Vendor**, **Quest**,
**Dungeons and Raids** and **Crafted**. Each tab keeps its own upgrade, so
you can flip between them as you like (or type `/beq quest vendor`,
`quest`, `dungeon` or `crafted`); the first time, the tab most worth the
trip is shown. To pick one yourself, click it in **Where to get upgrades**:
it becomes the quest on its tab and the panel opens on it (this turns the
quest on if it was off). The red gem closes the panel and turns the quest off,
keeping its quests for when you turn it back on. When you level up, the
quest you are on stays, but if the new level opens an upgrade clearly more
worth the trip, a gold **New upgrade unlocked** box offers it: **Switch**
follows it instead (or `/beq quest switch`), **Keep current** stays put. It
is off unless you turn it on, and the quest is kept per character.
Settings > Upgrade quest has Open (the panel), Ignored (the list to restore
from) and the panel's size; Ignore, Switch and the tab are on the panel, or
typed. To make the panel bigger or smaller, text and all, drag
the gold grip below its bottom-right corner, anywhere from 50% to 150%;
right-click it for the normal size, or type `/beq quest size` with `small`,
`normal`, `large` or a percent. It never grows past the screen.
Under the tabs, tick **This zone only** to have each tab pick only from the
zone you are in (a vendor, a quest giver or a dungeon's entrance there); the
tabs pick again as you travel, and an upgrade you clicked in Where to get
upgrades stays wherever you go. Untick **Change on a new zone** (or
Settings > Upgrade quest > Quest Filters > Zone Swap) to keep your quests as
you travel instead; a tab with nothing to chase still picks from the zone
you are in. Untick This zone only to look anywhere again. Beside it
are the same **Solo quests only** and **Quest level** as in Where to get
upgrades (changing either here changes it there), and a **Settings** button.

**Quest log.** The panel's fifth tab, **Quest log** (or `/beq quest log`),
shows every quest in your log the way the game's quest tracker does, grouped
by zone with the zone you are in in green: each quest's level and title in
the game's colours, its objectives (ticked green when done), and "Ready to
hand in" with who to hand it to once it is. Tick a quest's box to track it,
tick **Tracked only** to list only those, and click a zone's heading (or
**Fold all**) to fold it. A quest with an item to use gets a button for it;
in a fight the button can't move, so if you scroll or drag the panel then,
it fades and comes back in place when the fight ends. Right-click a quest
for **Show on map**, **Point the arrow here**, **Track** or **Untrack**,
**Open in quest log**, **Share with party** (in a group) and **Abandon
quest** (through the game's own "are you sure" box). Click a quest to pick
it for the buttons under the list, and shift-click it to link it in chat.
A quest on the way to one of your upgrade quests says so. Tick **Hide the
game's quest tracker** (on the tab, or Settings > Upgrade quest > Hide Game's
Tracker) to hide the game's own tracker while the panel is up; untick it and
the game's tracker comes back. It is off unless you tick it, and it never
hides it in the middle of a fight.

**Quest arrow.** The panel's **Arrow** button (or `/beq arrow`, or
Settings > Upgrade quest > Quest Arrow) brings up a gold dial that turns as
you turn and points the way to the next place in the steps: the vendor, the
quest giver, the trainer, with the distance in yards and a green check once
you are there. A step with a zone and no spot points at the middle of the
zone and says so; on the other continent it only names the zone. Click a
step with a place on the panel to point the arrow there, click the dial for
the next tab's quest, right-click it for the next place, and drag it
anywhere. It hides inside dungeons, and its red gem turns it off. It is
Farmer's goal arrow, brought over; Pets has it too, and only one of the
three is on screen at a time: the one turned on or aimed last shows, and
the others wait until it is put away. `/beq arrow check` lists what it can
read where you stand. With TomTom installed, the quest arrow hands its place to TomTom as a
waypoint and its own dial stays hidden, so only TomTom's arrow is on screen;
places TomTom cannot point at show on the dial as before. Untick **Use
TomTom** in Settings, or type `/beq arrow tomtom off`, to keep the dial.

Where gear comes from is `Data/Sources.lua`, generated from Classic 1.12
data by `tools/make_sources.py` (see below), and what can be crafted is
`Data/Crafts.lua` and `Data/Rolls.lua`, generated by `tools/make_crafts.py`;
the game supplies each item's stats when it is asked, so the verdicts are
Forever's own.

## Install

### Linked to your working copy (recommended while developing)

Run this once, and from then on testing a branch is pulling it and typing
`/reload`:

```powershell
.\tools\link.ps1
```

It junctions `Interface\AddOns\Blackthornes_Equipment` to this folder, so the
client reads your checkout directly. Nothing is copied, so there is no deploy
step to forget.

Two things `/reload` will **not** pick up, because the client only reads them at
startup:

- a file that was **added, removed or renamed**
- any change to **`Blackthornes_Equipment.toc`**

After pulling a branch that did either, restart the client once.

### Copied into the client

```powershell
.\deploy.ps1              # syntax check, lint, then mirror into Interface\AddOns
.\deploy.ps1 -SkipCheck   # skip the checks (not recommended)
```

Both scripts default to `D:\Blizzard\World of Warcraft\_classic_beta_`. Pass
`-GamePath` if the client lives somewhere else.

The addon folder name has to stay `Blackthornes_Equipment`, matching the `.toc`
inside it. If they differ, the client ignores the folder and says nothing.

## Use

```
/beq            open the gear window (so does clicking the minimap button)
/beq help       list every command
/beq spec       show the spec your gear is judged for
/beq spec mm    judge it as Marksmanship instead (bm, mm, sv, or auto to go back)
/beq bags       list every piece of gear in your bags with its verdict
/beq find       where to get upgrades: vendors, quests, dungeons and crafting
/beq tracked    the upgrades you are tracking (/beq tracked clear stops them all)
/beq quest      a quest for your next upgrade (/beq quest off, ignore, ignored, restore, switch, size, or a tab: vendor, quest, dungeon, crafted, log)
/beq arrow      an arrow to the upgrade quest's next place (on, off, next, check, tomtom, reset)
/beq weights    change how much each stat counts (also in the settings window)
/beq probe      check what this client supports; it only reads
/beq perf       what took longest this session, if the game hitches (/beq perf clear starts over; also Settings > Speed Check)
/beq settings   open the settings window (so does right-clicking the minimap button)
```

The settings window is also under the game's Options > AddOns. Its pages
(Gear, Upgrade hunts, Upgrade quest, General) are picked along the top.
Hover a setting to see what it does, or tick **Show descriptions** to see
it under every row; **Find a setting** searches every page. **Text size**
on the General page makes all of the addon's text a point or two bigger
after a `/reload`. Every command above has a button there too.

Every classic class has stat weights: warrior, paladin, hunter, rogue,
priest, shaman, mage, warlock and druid, three specs each. On WoW: Forever a
character's spec is the one with the most talent points spent in it (a
class's three specs share one talent tree, side by side). Until level 10
there are none, so gear is judged as the class's levelling default (Arms,
Retribution, Beast Mastery, Combat, Shadow, Enhancement, Frost, Affliction,
Feral) unless you pick otherwise with `/beq spec <name>`. Each class is held
to classic's armour and weapon rules, so a priest is told it can't use
leather and plate waits for level 40.

A weapon your class can learn but you have not trained yet says where to
learn it, under the verdict: "Learn Daggers from the weapon master in
Orgrimmar or Undercity". Only your own faction's cities are listed, from
classic's weapon masters.

Each item gets one score (every stat times what it is worth to your spec)
and is measured against what you wear in its slot. Rings and trinkets are
measured against the weaker of your two, and a two-hander against both hands.
Anything within 1% is called the same. The best quest reward is the one that
adds the most score, so a small gain on an important slot can beat a big
percentage on a minor one. The tooltip line, the arrows and the chat line
for a new upgrade can each be switched off in the settings.

The chat line is only for gear that is new in your bags: what you carried at
login, after a `/reload` or a loading screen, what you move between bags, and
a piece you take off are never announced, nor is gear you already had that
becomes an upgrade later (a level up or a spec change). Only the backpack and
the four bags beside it count, not the bank.

The built-in weights are a starting guess. **Settings > Stat Weights >
Change** (or `/beq weights`) lists each stat's weight for any class
and spec: type a number or use - and +, and every verdict (tooltips, bag
arrows, the quest reward, the gear window, and Tradeskills' arrows) uses yours
at once. Changed stats are marked in gold; **Use the built-in weights** puts a
spec back. Your weights are kept account wide by class and spec in
`BlackthornesEquipmentDB.customWeights`, only for the stats you changed, so a
later version's tuning still reaches the rest. Updates never clear them.

Under the stats, **Weapon types** lists each kind of weapon the class can
hold, all at 1. Set daggers to 1.2 and a dagger's whole score counts a fifth
higher, so a rogue who prefers daggers is steered to them over a slightly
better sword; 0.8 counts a kind lower and 0 leaves it out. These are kept in
`BlackthornesEquipmentDB.weaponTypeWeights`, and the same reset puts them back.

`/equipment` works too.

## Layout

| Folder | What is in it |
|---|---|
| `Core/` | Namespace, module registry, event dispatch, slash commands, saved variables |
| `Data/` | Everything read from the game: bags, equipped gear, quest rewards, item stats; classic's weapon masters and what each teaches; where gear comes from (`Sources.lua`, generated); what can be crafted and how to learn it (`Crafts.lua`, generated); random rolls (`Rolls.lua`, generated) |
| `Logic/` | Stat weights per class and spec (`Weights.lua`), judging an item against what is worn (`Compare.lua`), and which weapon skills are known and where to learn the rest (`WeaponSkills.lua`), where to get an upgrade (`Finder.lua`), crafted gear (`Crafting.lua`), random rolls (`Rolls.lua`), tracked upgrades (`Tracking.lua`), map pins (`Waypoints.lua`), the upgrade quest (`UpgradeQuest.lua`) and its arrow (`QuestArrow.lua`) |
| `UI/` | Theme, widgets, the minimap button, the gear window, the "Where to get upgrades" window, the settings window, the stat weights window, the tooltip lines, the bag arrows, the quest-reward arrow, the loot roll arrow, the chat line for a new upgrade, the upgrade quest panel and the quest arrow's dial |
| `Probe/` | `/beq probe`, which checks what the running game actually supports instead of guessing |
| `tools/` | Checks, tests and the link script. Not shipped to the client |
| `docs/` | What the Forever client actually does, found with `/beq probe`. Not shipped |

`Blackthornes_Equipment.toc` lists every Lua file in load order. A file that is
not in it does not load, and WoW says nothing about it.

## Development

```bash
python tools/syntaxcheck.py   # parse every Lua file with a real 5.1 parser
python tools/lintcalls.py     # find calls to methods, and constants, never defined
python tools/runtests.py      # run the logic tests outside WoW
```

`tools/` requires `lupa` (`python -m pip install --user lupa`).

The checks exist because WoW silently disables an addon whose first TOC file
fails to compile, and because a call to a method that no longer exists is valid
Lua that fails only when that line runs. `deploy.ps1` runs the first two before
it copies anything, and `.github/workflows/tests.yml` runs all of them on every
push.

`Data/Sources.lua` is generated, never edited by hand. To rebuild it, check
out [mangoszero/database](https://github.com/mangoszero/database) and
[shagu/pfQuest](https://github.com/shagu/pfQuest) anywhere and run:

```bash
python tools/make_sources.py <mangoszero database> <pfQuest>
```

The script's opening comment says what it keeps and leaves out.

`Data/Crafts.lua` and `Data/Rolls.lua` are generated too, from the vmangos
world database (`world_full_14_june_2021.sql` from
[brotalnia/database](https://github.com/brotalnia/database)) and pfQuest.
Run `make_sources.py` first, since `Rolls.lua` also covers the gear in
`Sources.lua`, then:

```bash
python tools/make_crafts.py <world_full_14_june_2021.sql> <pfQuest>
```

What bosses really drop on Forever comes from Blackthornes Farmer's loot
records. With a Farmer checkout beside this one (its `Data/Data_Harvested.lua`
brought up to date by its `tools/harvest_import.py`), run:

```bash
python tools/forever_drops.py ../Blackthornes_Farmer
```

It writes `Data/ForeverDrops.lua`: every item looted from a mob inside a
dungeon or raid, by mob and dungeon. The finder tags those drops [Forever],
uses Forever's drop rate once enough corpses were counted, and offers gear
Classic never had at that boss. Item stats are never copied from anywhere;
the game always supplies them, so gear Forever changed is judged as it is
now. The dungeon
level ranges, and the few bosses a script summons rather than spawns, are the
only parts typed in by hand, at the top of the script.

The upgrade quest's directions come from pfQuest and the same Farmer
checkout. After `make_sources.py`, run:

```bash
python tools/make_quest_starts.py <pfQuest> ../Blackthornes_Farmer
python tools/make_quest_ends.py <pfQuest> ../Blackthornes_Farmer
```

`Data/QuestStarts.lua` says where to get the item that starts a quest, and
`Data/QuestEnds.lua` where each quest is done and who takes it back, so a
quest in the log points at its objective or its hand-in rather than its
giver. Every spot is a real spawn from the data; none is made up.

Where vendors and trainers stand on Forever is learned in game: whenever a
merchant or trainer window opens, the addon keeps the NPC's ID, the map and
the spot the character stands on in the account save (`npcSpots`), and the
finder shows that spot ahead of the Classic one. To share them with every
player, log out and run the tool on the account's saved file:

```bash
python tools/forever_npcs.py <WTF/Account/<account>/SavedVariables/Blackthornes_Equipment.lua>
```

It writes `Data/ForeverNPCs.lua`, keeping the spots already there and
leaving out any that match the Classic data. Only NPC IDs, NPC names, map
names and numbers are copied. A spot read off the map by hand can be added
with `--spot <NPC ID> "<Map>" <x> <y>`.

Gear Forever changed (a required level, item level, the classes or races
that can use it, a vendor price) is read from the Forever client's game
tables, exported as CSV, one file per table:

```bash
python tools/forever_items.py <tables folder> --build <client build>
```

It reads only `ItemSparse.csv` and writes `Data/ForeverItems.lua`: just the
items whose numbers differ from `Data/Sources.lua` or `Data/Crafts.lua`,
which the finder lays over the Classic rows as the addon loads. Rerun it
after `make_sources.py` or `make_crafts.py`, and when the client changes.
The tables themselves never go in the repository.

The tests load the addon against a stub client (`tools/testenv.lua`), reading
the file list straight from the TOC. A new test is a new `tools/test_*.lua`
file and nothing else.

## Releasing

Releases are cut by pushing a tag like `v0.1.0`.
`.github/workflows/release.yml` then:

1. refuses the tag unless `CHANGELOG.md` opens with a `## 0.1.0` section
   (`tools/check_release.py`);
2. runs the tests;
3. builds the player-facing zip with the
   [BigWigs packager](https://github.com/BigWigsMods/packager), uploading
   nothing;
4. checks that zip is clear to post (`tools/check_package.py`): only the
   addon's own files, and nothing that looks private, such as a Windows path,
   an email address, a saved-variables dump or a token;
5. only then uploads that same zip to each site with a token, and attaches it
   to a GitHub release.

To release from GitHub Desktop: add the new version's section to the top of
`CHANGELOG.md` and merge it to `main`, pull `main`, then **History**, right-click
the newest commit, **Create Tag...**, name it `v0.1.0`, and **Push origin**.

The version is never typed by hand. The TOC says
`## Version: @project-version@` and the packager fills in the tag. Running
straight from a clone there is no packager, so the addon shows
`ns.RELEASED_VERSION` from `Core/Init.lua`, the newest version in
CHANGELOG.md: the release PR changes both, and `tools/check_release.py`
refuses a tag they disagree with. The middle number moves for new
behaviour, the last for fixes alone; a tag like `v0.2.0-beta1` is uploaded as a beta.

`.pkgmeta` leaves `tools/`, `docs/`, `deploy.ps1`, `CLAUDE.md` and this README
out of the zip. The CurseForge project is 1763347, the Equipment Classic project (never
Forever's 1720051), on the `X-Curse-Project-ID` line of the TOC.
Uploading also needs a `CF_API_KEY` repository secret in the repository's
settings on github.com. Without both, the workflow
still builds and checks the zip but uploads nothing to CurseForge.
