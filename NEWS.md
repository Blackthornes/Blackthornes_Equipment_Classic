# News

What each release says in the Discord server's #general channel: a few
short bullets per version, in plain words for players, saying what they'll
notice, then one line thanking, by their Discord name, everyone whose
feedback or report led to the changes (each name once; no line when nobody
asked). Each release PR writes the new version's section here next to its
CHANGELOG.md section, and after the upload `tools/post_general.py` posts it
under a line with the addon's name and version that points players to
#announcements for the full list. No link or addon card goes with it. This
is the only report that names players. A version with no section here posts
nothing in #general.
This file does not ship in the addon, but its newest sections do, without
the thanks line: `python tools/make_whatsnew.py` writes them into
Core/WhatsNewText.lua for the in-game What's New window. Run it after
writing a section; the release check refuses a tag while it is behind.

The window shows new features only. Write a section's features first, then
a "Fixes and changes:" line with the fixes and other changes under it: those
go to Discord but stay out of the window, and a section of only fixes puts
nothing in it. Say what each feature does in a few plain words, the way you'd
tell a friend: no hype, no questions to the reader, no exclamation marks
outside the thanks line, no dashes as punctuation, no "now you can". The
tool prints a note for a shipped line that reads like an advert.

## 0.5.0

- Every window has a new look that matches the other Blackthornes add-ons.

Fixes and changes:
- Various bug fixes.

## 0.4.1

Fixes and changes:
- Various bug fixes.

## 0.4.0

- The minimap button has a new Blackthornes badge.
- Show on Map now puts a gold marker on your map.

Fixes and changes:
- Various bug fixes.

## 0.3.0

- Quest, people, zone and item names now show in your own language.
- The Show on Map marker is bigger and easier to spot.
- One minimap button now opens all your Blackthornes add-ons.

## 0.2.3

Fixes and changes:
- Various bug fixes.

## 0.2.2

Fixes and changes:
- Various bug fixes.

## 0.2.1

Fixes and changes:
- Various bug fixes.

## 0.2.0

- The Take button has a new gold look.

Fixes and changes:
- Various bug fixes.

## 0.1.1

Fixes and changes:
- Various bug fixes.

## 0.1.0

- Equipment is here for Classic Era. A green arrow shows on any item in your bags that's better than what you wear.
- A Put It On button shows when a new upgrade lands in your bags.
- Where to Get Upgrades lists upgrades from vendors, quests, dungeons, raids and crafting.
- Dungeon Loot and Dungeon Quests show what each dungeon gives.

Thanks for trying it on Era.
