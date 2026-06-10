# Spell Combo History — Per-Spec Profiles Design

**Date:** 2026-06-10
**Status:** Implemented

## Goal

Save every setting (bar position/size/lock, animations, ignore list, stats
panel, ...) separately per specialization, switching automatically when the
player changes spec.

## Key constraint

Every module already reads its settings as flat keys on `SpellComboHistoryDB`
(the "working set"). Rewriting all those read sites to go through a profile
object would be large and risky. So the design keeps the flat working set and
adds a manager that swaps its values per spec — no read sites change.

## Architecture

### `Profiles.lua` — `ns.Profiles`
- `Init(db)` — ensures `db.profiles = {}`.
- `CurrentSpecKey()` — the current spec's global spec ID (stable), or `0` when
  no spec (e.g. a low-level character).
- `SaveTo(key)` / `LoadFrom(key)` — copy the `PROFILED_KEYS` (and a copy of
  `ignoreList`) between the working set and `db.profiles[key]`. `LoadFrom`
  keeps a live default if an older profile lacks a newer key.
- `Activate(key, onApply)` — if the spec changed: save the outgoing spec, then
  load the incoming one (or **seed a brand-new spec from the current settings**
  so a fresh spec inherits rather than resets), then call `onApply`.
- `SaveCurrent()` — persist the active profile (on logout).

`PROFILED_KEYS`: restartTimeout, isLocked, maxIcons, bgAlpha, uiScale, useGrid,
animStyle, animDuration, statsShown, statsLocked, bar position (point/x/y),
stats position (statsPoint/statsX/statsY). `ignoreList` is copied separately.
The spell queue window is a game CVar and is intentionally not profiled.

### Wiring (`SpellComboHistory.lua`)
- `ADDON_LOADED`: set defaults, init modules, `Profiles:Init`, build options,
  `ApplyAllSettings()`.
- `PLAYER_LOGIN` and `PLAYER_SPECIALIZATION_CHANGED`: `Profiles:Activate(nil,
  ApplyAllSettings)`.
- `PLAYER_LOGOUT`: `Profiles:SaveCurrent()`.
- **`ApplyAllSettings()`** — re-applies all runtime state from the working set
  (bar scale/position/lock/background, history relayout, stats panel
  position/lock/visibility, ignore-list rebuild) and calls
  `refreshOptionsPanel()` so an open settings panel updates live.
- **`refreshOptionsPanel()`** — assigned by `InitializeOptions`; re-syncs every
  widget (sliders/checkboxes/buttons/summary/ignore rows) from the working set.

## Migration

Existing users have flat settings and no profiles. The first `Activate` seeds
the current spec's profile from those settings, so nothing is lost.

## SOLID Notes

- `Profiles` owns only data movement; it knows nothing about frames. The single
  `onApply` callback inverts the dependency — the manager triggers a re-apply
  without knowing what it does.

## SavedVariables

`SpellComboHistoryDB.profiles[specID]` holds each spec's settings. The flat keys
remain as the live working set (equal to the active spec's profile).

## Localization

One new key in `enUS.lua`/`ptBR.lua`: `PROFILE_NOTE` (shown in the options
panel).

## Out of Scope

The original roadmap is now complete.
