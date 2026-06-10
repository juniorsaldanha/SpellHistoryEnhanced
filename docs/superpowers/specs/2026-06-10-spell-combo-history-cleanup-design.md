# Spell Combo History — Cleanup & GitHub-Ready Design

**Date:** 2026-06-10
**Status:** Approved (pending spec review)

## Goal

Prepare the existing **Spell Combo History** WoW addon for open-source
publication on GitHub. The addon tracks the player's spell cast history and
grades global-cooldown usage ("PERFECT" when no time is wasted between
globals), with combo streaks. No gameplay behavior changes — this is a
cleanup, localization, and documentation pass.

## Decisions

- **Korean text:** all user-facing strings become English, routed through a
  simple per-language Lua table. No i18n framework.
- **Korean locale file:** not shipped. English only (`enUS.lua`). The locale
  structure is ready for community translations later.
- **Repo layout:** conventional flat addon layout (main `.toc`/`.lua` at root).
- **License:** MIT, copyright holder **Junior Saldanha**. No credit to any
  prior author anywhere in the project.
- **Roadmap (Planned Features):** animations, ignore list, stats & session
  tracking, per-spec profiles.

## Repo Structure

```
SpellComboHistory.toc          # English Notes, Version, X-License; loads Locales first
SpellComboHistory.lua          # cleaned: English comments, strings via L[]
Locales/
  enUS.lua                     # L table with every user-facing string
README.md
CONTRIBUTING.md                # includes "how to add a translation"
LICENSE                        # MIT
.gitignore
```

`Locales/` is a subfolder, but this is still the conventional flat addon
layout. The `.toc` loads `Locales\enUS.lua` **before** `SpellComboHistory.lua`.

## Localization Mechanism

Uses the addon's private namespace (the second value passed to each addon
file). No globals introduced.

```lua
-- Locales/enUS.lua
local _, ns = ...
ns.L = ns.L or {}
local L = ns.L

L["LOCK_POSITION"] = "Lock Position"
-- ... one entry per user-facing string
```

```lua
-- SpellComboHistory.lua (top of file)
local addonName, ns = ...
local L = ns.L
```

`enUS.lua` is the base locale and sets every key unconditionally. A future
translation (e.g. `Locales/koKR.lua`) guards on `GetLocale()` and overrides
only the keys it translates, falling back to English for anything missing.
This pattern is documented in CONTRIBUTING.md.

## Code Cleanup

### Comments
- All Korean comments translated to concise English, including the logic-flow
  header block at the top of the file.
- Keep the existing comment density (the file is heavily commented); do not
  gut the documentation — it is valuable for contributors. Match the
  surrounding style.

### User-facing strings → `L[...]`
Every user-facing string is extracted into `enUS.lua` and referenced via
`L[...]` in the main file. The Korean half of each bilingual string is dropped.
Strings to extract:

- Anchor help text ("MOVE" / "Right-click to Lock").
- Options panel title and category name.
- Slider labels: Restart Timeout, Max Icons, Background Transparency, UI Scale,
  Spell Queue Window (and their numeric min/max edge labels where they carry
  units).
- Slider help paragraph (the long bilingual explanation of Spell Queue Window).
- Checkbox labels: Lock Position, Use Grid & Snap.
- Button labels: Check Current, Clear History, Reset Position.
- All `print()` chat messages (position locked, history cleared, position
  reset, current SpellQueueWindow value).
- Display words rendered on/near icons: `START`, `RESTART`, `PERFECT`, and the
  combo tier labels (`STREAK`, `RAMPAGE`, `INSANE`, `GODLIKE`, `LEGEND`).

Strings that are formatted with runtime values (e.g. `"%.2fs"`, percentages,
millisecond readouts) keep their `string.format` patterns; the literal/label
portion is what moves into `L`.

### `.toc`
- `## Notes` rewritten in English.
- Add `## Version`.
- Add `## X-License: MIT`.
- Add the `Locales\enUS.lua` load line **before** `SpellComboHistory.lua`.
- `## SavedVariables: SpellComboHistoryDB` unchanged.
- `## Interface` lines unchanged.

No logic, no SavedVariables schema, and no UI behavior changes.

## Documentation

### README.md
- Short description of what the addon does.
- Current features (history bar, GCD/PERFECT grading, combo streaks, movable &
  lockable anchor, grid snap, in-game settings panel).
- Installation (manual / addon manager).
- Usage: drag to move when unlocked, right-click to lock, settings panel
  location, key options explained.
- **Planned Features** section (see Roadmap below).
- Link to CONTRIBUTING.md.
- License section (MIT).
- Screenshot placeholder.

### CONTRIBUTING.md
- Local dev setup (where to drop the folder for testing).
- Code style notes (English comments, strings through `L`).
- How to add a translation (create `Locales/<locale>.lua`, guard on
  `GetLocale()`, override keys, add the load line to the `.toc`).
- Issue reporting and pull-request guidance.

### LICENSE
- Standard MIT text. Copyright line: `Copyright (c) 2026 Junior Saldanha`.

### .gitignore
- Common OS/editor cruft (`.DS_Store`, editor swap files).

## Roadmap (Planned Features — documented in README, not built now)

1. **Animations** — new spell icons fade/slide in when cast; icons fade out as
   they age off the end of the bar.
2. **Ignore list** — user-configurable list of spells to exclude from tracking
   (e.g. trinket on-use, racials, off-GCD utilities the player doesn't care
   about).
3. **Stats & session tracking** — session summary: uptime %, average waste
   time between globals, best combo, total casts.
4. **Per-spec profiles** — separate settings (position, max icons, scale, etc.)
   per character specialization.

## Out of Scope

- No gameplay/logic changes to the GCD detection or combo grading.
- No i18n framework or external libraries.
- No shipped non-English locale.
- The roadmap features are documented only, not implemented in this pass.
```