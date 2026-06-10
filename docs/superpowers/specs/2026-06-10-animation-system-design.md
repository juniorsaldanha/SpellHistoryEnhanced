# Spell Combo History — Animation System Design

**Date:** 2026-06-10
**Status:** Implemented

## Goal

Add a full icon animation system (in / move / out) with selectable styles
(None, Fade, Slide, Bounce) and adjustable speed, built with clean module
boundaries and SOLID principles.

## Motivation / Constraint

The original `UpdateHistory` model copied texture/text **data between N fixed
icon slots**. That makes per-cast motion impossible — there are no persistent
moving objects, just repainted slots. The animation system therefore requires
switching to a **queue of independent, moving icon frames**.

## Architecture

Three modules, each with one responsibility, communicating through the addon's
private namespace (`ns`):

### `Animations.lua`
- **`ns.Easing`** — pure easing functions (`linear`, `outQuad`, `outCubic`,
  `outBack`).
- **`ns.Tween`** — a generic numeric interpolation engine driven by a single
  `OnUpdate`. It interpolates the named fields of an object's `state` table and
  calls the object's `Apply()` method. It knows nothing about frames or icons.
  - `Tween:Start(obj, duration, target, easing, onComplete)` — duration `0`/nil
    applies instantly.
  - `Tween:Stop(obj)` — cancel without firing completion.
- **`ns.Animations`** — a registry of animation strategies.
  - `Register(strategy)`, `Get(key)` (falls back to `none`), `List()` (ordered).
  - A strategy implements `PlayIn`, `PlayMove`, `PlayOut`, all sharing the same
    signature, plus `key` and `labelKey`.
  - Built-ins: `none` (instant, reproduces old behavior), `fade`, `slide`,
    `bounce`.

### `HistoryBar.lua` — `ns.HistoryBar`
The display manager. Owns an icon pool and an ordered `active` queue
(index 1 = newest). Responsibilities:
- `Init(opts)` — dependency injection: `anchor`, `iconSize`, `spacing`, and the
  settings getters `getMaxIcons`, `getAnimation`, `getDuration`.
- `CreateIcon` / `Acquire` / `Release` — frame pooling. Each icon carries a
  numeric `state` (`x`, `y`, `alpha`, `scale`) and an `Apply()` that pushes that
  state onto the real frame.
- `ConfigureContent` — sets the icon's texture and result text (START/RESTART,
  PERFECT, wasted seconds, combo tier). Ported verbatim from the old
  `UpdateHistory` content branch.
- `Push(...)` — add a cast to the front, trim overflow, then delegate motion:
  `PlayIn` for the new icon, `PlayMove` for the rest, `PlayOut` for the overflow.
- `Relayout` (max-icons change), `Clear` (clear button), `SetInteractive`
  (mouse on/off while repositioning).

The bar depends only on the **strategy interface** (DIP); it never references a
concrete animation.

### `SpellComboHistory.lua`
Slimmed to events, GCD/combo analysis, the settings panel, and wiring. It calls
`ns.HistoryBar:Push(...)` in place of the removed inline `UpdateHistory`, and
removed `CreateIcon`, `COMBO_LEVELS`, `GetComboTextAndColor` (moved to
`HistoryBar.lua`) and the `icons` table.

## SOLID Mapping

- **S**: Tween (interpolation), Strategy (one animation style), HistoryBar
  (queue + content), main file (events/analysis/settings) are each isolated.
- **O**: New animation styles are added by registering a strategy; no existing
  code changes, and the settings cycle button picks them up automatically.
- **L**: All strategies are interchangeable behind the same `Play*` interface.
- **I**: The strategy interface is just `PlayIn` / `PlayMove` / `PlayOut`.
- **D**: HistoryBar depends on the abstraction (`getAnimation()` → a strategy),
  not on concrete animations or globals (collaborators are injected via `Init`).

## Settings

- **Animation Style** — a cycle button (None → Fade → Slide → Bounce). A cycle
  button (not a dropdown) was chosen for reliability across client versions; it
  reuses the same `UIPanelButtonTemplate` as the existing buttons.
- **Animation Speed** — slider, 0.1s–0.6s, default 0.25s.
- SavedVariables: `animStyle` (default `"slide"`), `animDuration` (default
  `0.25`).

## Localization

Six new keys in `enUS.lua` and `ptBR.lua`: `ANIM_STYLE`, `ANIM_SPEED`,
`ANIM_NONE`, `ANIM_FADE`, `ANIM_SLIDE`, `ANIM_BOUNCE`.

## Behavior Preservation

- `none` style + the ported `ConfigureContent` reproduce the original visuals
  and grading exactly.
- Discarding casts beyond `maxIcons` matches the original (it never populated
  slots beyond the max either).

## Out of Scope

- Remaining roadmap items (ignore list, stats/session tracking, per-spec
  profiles).
