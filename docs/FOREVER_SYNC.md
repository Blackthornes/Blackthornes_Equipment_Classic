# Forever sync

Where this Classic Era copy stands against Forever Equipment
(`Blackthornes/Blackthornes_Equipment`). Forever is only ever read from here.

Last Forever commit copied over: `23f0435` (Forever main, 2026-11-02).
The first copy was made from `b871fde` (Forever main, the merge of
its PR #244, 2026-10-23). This copy was made from it with its history on
2026-10-24.
- `9ff6328` Shared minimap button shows the Blackthornes thorn B (2026-10-29,
  taken as it is: `UI/SharedMinimap.lua` at FILE_VERSION 2,
  `Media/Frame/MinimapBadge.tga` and `tools/make_minimap_art.py`, the same
  in all five Classic repos).
- `3975656` Slim the shared minimap menu: names only, sized to fit (2026-10-29,
  taken as it is: `UI/SharedMinimap.lua` at FILE_VERSION 3 and its test, the
  same in all five Classic repos).
- `d77e903` Settings: "Show Descriptions" in Title Case (2026-10-29,
  Forever PR #255, as it is).
- `804f19c` Dress the slot upgrades list in the house frame (2026-10-29,
  Forever PR #254, as it is).
- `e2089ea` Gold rim and close gem on the upgrade banner and the training
  drawer (2026-10-29, Forever PR #253, as it is).
- `7bccd3e` One look across the five addons (2026-10-29, Forever PR #268):
  `UI/HouseKit.lua`, `UI/RowMenu.lua`, `UI/Notice.lua` and
  `UI/SharedChoices.lua` as they are (the same in all five Classic repos),
  Upgrade Hunts' view tabs and panel gems, the upgrade quest's Options
  menu, Transparent for both panels (`UI/SeeThrough.lua`), one-line finder
  rows, Title Case buttons and the General page. Left out: Arrow Size
  (Equipment Classic has none). Show on Map keeps Classic's own pin.
  `UI/Plaque.lua` keeps Classic's own copy with the new `Plaque.TextWidth`,
  the same in Farmer, Pets, Equipment and Tradeskills Classic.
- `75bbd77` One Window steps aside for an open letter (2026-10-31): docked at
  the mailbox it moves beside the letter and back, and tells side panels
  when it docks, moves or undocks (`SharedWindow.Watch`, `DockedFrame`).
  `UI/SharedWindow.lua` is FILE_VERSION 5, the same in all five Classic
  repos.
- `35bf2b0` Set Default under Window Position keeps the one window's tab
  in place (2026-11-02, as it is).
- `23f0435` The gear slot tooltip and Alt-click list follow the upgrade
  window's source filters (2026-11-02, as it is).

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
- `0d0b503` Time arrow flights by their real length (2026-10-29, as it is).
- `9992e47` Show on Map works without the game's pin (2026-10-29, blended
  on top of Classic's own marker; see "Show on map uses Equipment's own pin"
  in `docs/CLASSIC_DIFFERENCES.md`).
- `dea75f5` (Butler's) the way there card's rows grow when a step wraps
  (2026-10-29, `UI/TravelCard.lua` only).
- Picked fixes (2026-11-07, the owner said yes): the folded One Window
  opens full after docking (`UI/SharedWindow.lua` FILE_VERSION 8, the same
  in all five Classic repos) and `9d73ccf` soulbound gear is never offered
  to an alt (`Tooltip:BagSlot` also reads Era's bag buttons, whose bag is
  their frame's ID). `102d211` (white gear for casters) is not taken:
  Classic already weighs weapon damage and armor for casters (`f4a4f22`).
- `0746854` Bear Tank for druids (2026-11-07, the owner said yes): the new
  spec, its six-language name and `tank` meaning Bear Tank for a druid.
  Forever's cat reweighting of Feral Combat is not taken, and Bear Form's
  weapon dps counts only as a tie-breaker on Era (see "Bear Tank weighs
  weapon damage lightly" in `docs/CLASSIC_DIFFERENCES.md`).
- `db40457` The upgrade banner can be dragged and keeps its spot per
  character, right-click puts it back (2026-11-07, the owner said yes; as it
  is, with its six-language hover line).
- Weekly check of 2026-11-14 (the owner said do them all, 2026-11-15):
  `0410c9e` and `cca5fc1` Mute All Sounds and window spots
  (`UI/SharedWindow.lua` FILE_VERSION 9 and `UI/WhatsNew.lua` FILE_VERSION
  7, the same in all five Classic repos; the window test uses Era's
  `AuctionFrame`), `2638eef` Queue It on a later pattern (needs
  Tradeskills' `af0f9af`), and the fixes `0252e00`, `39a97ee`, `02a0b14`,
  `3ffd3da`, `f83b893`, `b49f9dc`, `9e8c4b9`, `5516776`, `7fa5228`,
  `e9d2298`, `121d28b`, `e6f59e1`, `ae7ab5e`, `d71177a` and `890e67e`.
  Kept Classic's own: the talent events (`CHARACTER_POINTS_CHANGED`,
  `PLAYER_TALENT_UPDATE`) wherever Forever lists only
  `TRAIT_CONFIG_UPDATED`, and the healers' weapon damage and armor weights
  (only their spell power halved, see "Healers' spell power" in
  `docs/CLASSIC_DIFFERENCES.md`). Left out for now: set bonuses
  (`72f72d7` and what follows, `ReplacedSlots` and `WithSets` in
  `Compare.lua`) and "its giver no longer offers it" (`NotOffered`).
  The upgrade quest panel redesign came after the mockup (the owner said
  build it, 2026-11-15): `215bfc8`, `53d4d5d`, `323d0c1`, `2b4c6b5`,
  `911fd57`, `01e2083`, `c024185`, `4b2b0b0` and `6955d86`. The map marker
  clicks went on Era's own Show on map pin (`Waypoints.marked`), since
  Classic has no `MapPins:Spotlight`.
