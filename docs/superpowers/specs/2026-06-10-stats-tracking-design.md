# Spell History Enhanced — Stats & Session Tracking Design

**Date:** 2026-06-10
**Status:** Implemented

## Goal

Track and surface performance statistics for a fight: GCD uptime %, PERFECT
count and rate, best combo, average wasted time between globals, total casts,
and session (fight) length.

## Decisions

- **Surfacing:** an on-screen movable/lockable panel, **plus** a `/she` slash
  command, **plus** a summary in the settings panel. (All three.)
- **Session = one combat** (per-combat reset): stats reset when a fight starts
  and the panel keeps showing the last fight's numbers until the next begins.
  Not persisted across reloads.

## Architecture

### `Stats.lua` — `ns.Stats` (model)
A UI-agnostic accumulator.
- `Init` / `Reset`, `BeginCombat(now)`, `EndCombat(now)`.
- `Record(isPerfect, combo, isStart, wasteTime, activeChunk)` — called once per
  in-combat, on-GCD cast. Starts the clock lazily if needed (covers a `/reload`
  mid-combat where `BeginCombat` never fired). (Re)starts are not counted as
  waste samples.
- `Duration()` — live while in combat, frozen after.
- `Get()` — derived, display-ready values: `uptime` (%, = active time / combat
  time, clamped), `casts`, `perfects`, `perfectRate` (%), `bestCombo`,
  `avgWaste` (s), `duration` (s).

`activeChunk` is the time a cast kept the GCD/cast busy: the cast's duration for
cast-time spells (`now - castStartTime`), otherwise the shared GCD duration.
Uptime is the sum of those over the combat length.

### `StatsPanel.lua` — `ns.StatsPanel` (view)
A thin view over `ns.Stats`.
- `Init(db)` — builds a movable frame; restores `statsPoint/x/y`; default
  position offset from center.
- Drag to move while unlocked; right-click to lock; `ApplyLock` /`ApplyShown`
  honor `db.statsLocked` / `db.statsShown` (locked = click-through, hides the
  drag hint).
- Refreshes its rows on a throttled `OnUpdate` (0.2s) — which only fires while
  shown, so it costs nothing when hidden.

### `SpellHistoryEnhanced.lua` (wiring)
- `PLAYER_REGEN_DISABLED` → `Stats:BeginCombat`; `PLAYER_REGEN_ENABLED` →
  `Stats:EndCombat`.
- In `ProcessFrameSpells`, after grading, records in-combat on-GCD casts.
- `Stats:Init()` + `StatsPanel:Init(db)` in `ADDON_LOADED`.
- Settings: Show/Lock checkboxes, a static summary with Refresh + Reset.
- Slash: `/she` (and `/spellhistory`) prints stats; `/she reset` clears them.

## SOLID Notes
- Model (`Stats`) and view (`StatsPanel`) are separate; the model has no UI
  dependency. The panel, settings summary, and slash command are three
  independent consumers of the same `ns.Stats:Get()` abstraction.

## SavedVariables
`statsShown` (default true), `statsLocked` (default true), and the panel
position `statsPoint` / `statsX` / `statsY`. The statistics themselves are
in-memory (per fight), not persisted.

## Localization
15 new keys in `enUS.lua` and `ptBR.lua` (panel title, row labels, hint,
settings labels, and the reset message). `STATS_PANEL_TITLE` is kept as the
brand string "Spell History".

## Out of Scope
The last roadmap item: per-spec profiles.
