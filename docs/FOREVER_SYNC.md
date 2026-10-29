# Forever sync

Where this Classic Era copy stands against Forever Equipment
(`Blackthornes/Blackthornes_Equipment`). Forever is only ever read from here.

Last Forever commit copied over: `b871fde` (Forever main, the merge of its
PR #244, 2026-10-23). This copy was made from it with its history on
2026-10-24.
- `9ff6328` Shared minimap button shows the Blackthornes thorn B (2026-10-29,
  taken as it is: `UI/SharedMinimap.lua` at FILE_VERSION 2,
  `Media/Frame/MinimapBadge.tga` and `tools/make_minimap_art.py`, the same
  in all five Classic repos).
- `3975656` Slim the shared minimap menu: names only, sized to fit (2026-10-29,
  taken as it is: `UI/SharedMinimap.lua` at FILE_VERSION 3 and its test, the
  same in all five Classic repos).

Every catch-up reads `docs/CLASSIC_DIFFERENCES.md` first, and the PR that
brings Forever commits over updates the line above to the newest one it took.

Brought over one at a time since:

- `d55c65e` "Keep mail and plate as later upgrades only from level 38",
  blended with Classic's PR #6 (see "Mail and plate learned later" in
  `docs/CLASSIC_DIFFERENCES.md`).
- `3308557` Start release posts with the game name (2026-10-24, copied
  by hand with "Classic Era" in place of "Forever"; see
  "Discord release posts" in `docs/CLASSIC_DIFFERENCES.md`).
- `65e6c1e`, `80b98c4` and `90074aa` (sending vendors and quests to
  Blackthornes, 2026-10-26), with Classic's own recipients; see "Sending
  vendors and quests to Blackthornes goes to Era characters" in
  `docs/CLASSIC_DIFFERENCES.md`.
- `c281a6e` One minimap button for every Blackthornes addon (2026-10-28,
  Forever PR #261, cherry-picked as it is; `UI/SharedMinimap.lua` and its test
  are the same in all five Classic repos).
