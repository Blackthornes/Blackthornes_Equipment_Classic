# Classic differences

Every place this Classic Era copy differs from Forever Equipment, and why.
Keep it short and current: a PR that adds a Classic-only change adds its
line here in the same breath.

## The catch-up rule

Every Forever catch-up checks this note first, before sorting commits into
"fits Era", "Forever only, skip" or "needs changes for Era".

- A Forever commit that touches nothing listed here comes over as it is.
- A Forever commit that touches only a file Classic leaves out of the TOC
  (below), or its `tools/forever_*.py`, is "Forever only, skip", unless it
  also changes how the readers that ask for it behave.
- A Forever commit that lands on something listed here is a clash. Show the
  owner both versions side by side and offer three choices:
  - **Keep Classic's:** skip the Forever change.
  - **Take Forever's:** only when it really replaces what Classic did.
  - **Blend them (the usual pick):** bring Forever's idea over on top of
    Classic's version.
- Whatever is picked, nothing below gets lost by accident. If a pick changes
  a line here, the same PR changes the note.
- The data files are huge. Never open one whole to compare; diff or grep it.

## What differs

### The TOC
- `## Interface: 11509`, what the owner's Era client reports. Forever is 16001.
- `## X-Curse-Project-ID: 1763347`, Equipment Classic's own project.
  Forever's 1720051 must never be here: `tools/check_release.py` refuses a
  tag that has it (tested in `tools/test_check_release.py`;
  `tools/test_era.lua` checks the Classic ID is there).
- The folder and TOC (`Blackthornes_Equipment`), saved data
  (`BlackthornesEquipmentDB`, `BlackthornesEquipmentCharDB`), the global and
  `/beq` are the same as Forever's, on purpose. Never rename them.

### Forever data and sharing left out of the TOC
The files and their `tools/forever_*.py` stay in the repo so Forever changes
merge cleanly; Era never loads them. Every reader asks for the table first,
so Classic's data stands alone, and what is learned in game is still laid
over it.
- `Data/ForeverItems.lua`, `ForeverDrops.lua` (its dungeons and drops),
  `ForeverNPCs.lua`, `ForeverQuests.lua`, `ForeverGoneQuests.lua`,
  `ForeverVendors.lua`, `ForeverDungeonQuests.lua`.
- `tools/test_era.lua` checks the TOC and that the finder, Dungeon Loot and
  Dungeon Quests work without them. `tools/test_foreveritems.lua`,
  `test_gonequests.lua`, `test_dungeonquests.lua` and `test_settings.lua`
  were changed to match (no gone list, no Forever dungeon quests).

### Sending vendors and quests to Blackthornes goes to Era characters
The owner asked for it on Era (2026-10-26). `Logic/Contribute.lua` is
Forever's (through `90074aa`) with Era's changes:
- `RECIPIENTS` are the owner's Era characters, as Name-Realm, since Era
  whispers need the realm. Era names have no surname, so `Receiving`
  matches the name alone.
- A whisper reaches only the sender's own realm, so `Recipients()` keeps
  only names on the player's realm (`MyRealm`, `RealmKey`), none when the
  realm can't be read, and the About page's box shows only then.
- `REGIONS` is North America (1) only; Forever's test region 110 is gone.
- `Core/Comm.lua` gets Tradeskills' `WithRealm`, so a whisper target
  carries the realm.
- The fold-in tools (`forever_quests.py --shared` and the others) write
  Forever's data files, which Era's TOC leaves out. Where Era's shared
  data goes is a question for the owner at release.
- Tested in `tools/test_contribute.lua`, `tools/test_settings.lua` and
  `tools/test_era.lua`.

### Learned lists still lay without the shipped ones
- `QuestLearn:LayAll` (`Logic/QuestLearn.lua`) and `NPCSpots:LayAllVendors`
  (`Logic/NPCSpots.lua`) pass a missing shipped list to `ipairs` as `false`
  (`ns.ForeverQuests or false`, `ns.ForeverVendors or false`), never nil,
  or the learned list after it would be skipped. A Forever change to either
  function is a clash to blend; keep the `or false`.

### Mail and plate learned later
- Forever's `d55c65e` (only from 38) came over blended with Classic's PR #6.
  Classic keeps one rule, `Weights:KindTooFar` (`Weights.KIND_SOON`, 2),
  where Forever has `Compare.LATER_ARMOR_WITHIN`. `Compare:Judge` asks it
  (`result.laterArmor`, no tooltip line), and `Alts:Judge` asks it for
  every caller, so `Alts:BestFor` takes no `soonOnly`. Butler's own check
  stays as a guard. On a catch-up, keep `KindTooFar` and drop Forever's
  constant.

### Notes and docs
- `CLAUDE.md` opens with "This repo is the Classic Era copy".
- `README.md` names the Classic CurseForge project.

### Discord release posts
- `tools/announce_discord.py` and `tools/post_general.py` start both
  posts with "Classic Era: " (their `GAME`), where Forever's start with
  "Forever: ", so the two games' releases read apart. A catch-up that
  touches these tools keeps Classic's word. Tested in
  `tools/test_announce_discord.py` and `tools/test_post_general.py`.

### No Forever words for players
- The owner asked (2026-10-24) for no "Forever" a player can see. The
  finder's `[Forever]` tag (`FinderUI.SourceLine`), "Seen dropping on
  Forever." in the upgrade quest's steps, and "New on Forever" under a
  dungeon in Dungeon Quests and Dungeon Loot (`Levels`, `DQUI.Where`) are
  gone. The `forever` fields stay for clean merges. A catch-up that brings
  them back keeps Classic's. Tested in `tools/test_finder.lua` and
  `tools/test_upgradequest.lua`.
- The About thank-you (`About.THANKS`) has no "WoW Forever is almost here"
  paragraph (the owner, 2026-10-24). `UI/About.lua` is shared with Forever;
  a catch-up that brings the paragraph back keeps Classic's.

### Class training leaves Forever's spells out
`Logic/ClassTraining.lua` is Butler Classic's copy: `CT.Spells(class)` drops
Forever's own spells (IDs from `FOREVER_FIRST`, 1,000,000) and any the client
says it lacks, pointing a rank's "rank before" past the dropped ones. A
catch-up that brings Forever's file keeps `CT.Spells` and its four callers.
Tested in `tools/test_era.lua`.

### The upgrade quest reads Era's quest log
`OnQuest` and `QuestReady` in `Logic/UpgradeQuest.lua` fall back to
`QuestLog:Find` (the classic quest log calls) when the newer quest calls
don't answer, so a quest in the log, and done, counts on Era. A catch-up
that brings Forever's file keeps the fallbacks. Tested in `tools/test_era.lua`.

## Not yet done
- Talent tabs, stats and the shared class training come next, a small PR
  each (the project's `equipment-classic-plan.md`). Each adds its line here.
- Skyborne races in `Finder.Side` and `FOREVER_DUNGEON_PLACES` are left in;
  they are harmless on Era.
- Not yet seen in an Era client. Client calls are read in a pcall.
