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
- `Logic/Contribute.lua`: its recipients are Forever characters, so nothing
  is sent and the About page shows no share box. Ask the owner before an
  Era version.
- `tools/test_era.lua` checks the TOC and that the finder, Dungeon Loot and
  Dungeon Quests work without them. `tools/test_foreveritems.lua`,
  `test_gonequests.lua`, `test_dungeonquests.lua` and `test_settings.lua`
  were changed to match (no gone list, no Forever dungeon quests, no share
  box on Era).

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

## Not yet done
- Talent tabs, stats and the shared class training come next, a small PR
  each (the project's `equipment-classic-plan.md`). Each adds its line here.
- `Logic/ClassTraining.lua` is still Forever's here. Butler Classic's copy
  already leaves Forever's own spells out (`CT.Spells`); when Equipment's
  gets the same, note it here, since Forever keeps the file the same in both.
- Skyborne races in `Finder.Side` and `FOREVER_DUNGEON_PLACES` are left in;
  they are harmless on Era.
- Not yet seen in an Era client. Client calls are read in a pcall.
