# Spell History Enhanced — Ignore List Design

**Date:** 2026-06-10
**Status:** Implemented

## Goal

Let users exclude specific spells from tracking — procs, trinket on-use,
racials, and other off-GCD noise — so the history bar only shows what they
care about.

## Architecture

### `IgnoreList.lua` — `ns.IgnoreList`
A small, UI-agnostic model (SRP):
- `Init(db)` — receives the saved-variables table and ensures
  `db.ignoreList = {}` (a set keyed by spell ID).
- `IsIgnored(id)`, `Add(id)`, `Remove(id)` — query/mutate; `Add`/`Remove`
  return whether they changed anything and guard against being called before
  `Init`.
- `GetSorted()` — ignored IDs sorted by spell name (then ID) for stable display.
- `GetSpellNameIcon(id)`, `SpellExists(id)` — static spell helpers (modern
  `C_Spell` API with a legacy fallback).
- `SetOnChanged(cb)` / `Notify()` — a single observer hook so the settings UI
  refreshes live when the list changes.

### Filtering
In `SpellHistoryEnhanced.lua`, the `UNIT_SPELLCAST_SUCCEEDED` handler drops the
cast (and clears its pending data) when `ns.IgnoreList:IsIgnored(spellID)` —
right after the existing "is this a player spell?" gate, so ignored spells
never enter the frame-batch analysis at all.

### Two ways to add (and one to remove)
1. **Right-click a history icon** (`HistoryBar.lua`) — adds that spell and
   prints a confirmation. Icons have no other right-click action while the bar
   is locked, so there is no conflict with the right-click-to-lock on the anchor
   (when unlocked, icons disable mouse so the anchor receives the click).
2. **Settings panel** — an "Add" box that accepts a spell **ID, name, or
   dragged spell link** (`resolveSpell` parses all three), validated with
   `SpellExists`.
3. **Remove** — the settings panel shows a live, pooled list of ignored spells
   (icon + name + Remove button), rebuilt via the `onChanged` observer. An
   empty-state label shows when nothing is ignored. The scroll content grows to
   fit the rows.

## SOLID Notes
- `IgnoreList` is isolated and has no UI dependency; the settings panel and the
  icon both depend on the `ns.IgnoreList` abstraction.
- The observer hook inverts the dependency: the model notifies; it does not know
  what the UI does.

## Localization
Eight new keys in `enUS.lua` and `ptBR.lua`: `IGNORE_LIST`, `IGNORE_HINT`,
`IGNORE_ADD`, `IGNORE_REMOVE`, `IGNORE_EMPTY`, `MSG_IGNORE_ADDED`,
`MSG_IGNORE_REMOVED`, `MSG_IGNORE_INVALID`.

## SavedVariables
`SpellHistoryEnhancedDB.ignoreList` — a table `{ [spellID] = true }`.

## Out of Scope
Remaining roadmap items: stats/session tracking and per-spec profiles.
