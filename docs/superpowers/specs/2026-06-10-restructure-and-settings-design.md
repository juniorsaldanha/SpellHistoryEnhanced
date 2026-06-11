# SpellHistoryEnhanced — Restructure + Native Settings + Shift-Drag Design

Date: 2026-06-10

## 1. Goals

1. **Restructure the addon for SOLID / single responsibility.** Today
   `SpellHistoryEnhanced.lua` (~1300 lines) is a monolith: bootstrap, the
   movable bar frame + drag, cast-event capture, GCD/waste/combo analysis, the
   options panel, settings application, and slash commands. Split these into
   focused modules organized by layer.
2. **Decouple the engine from the UI** via a tiny event bus (Dependency
   Inversion): the analyzer no longer calls `HistoryBar`/`Stats` directly.
3. **Rewrite the settings page** using the native WoW Settings API (a main
   vertical-layout category plus Statistics and Ignore List canvas subpages).
4. **Replace lock with Shift-drag** movement for the bar and the stats panel.
5. **Add a gear button + context menu** to the stats panel (Hide / Reset stats /
   Open options).

Behavior already shipped (channel waste fix, channel uptime) must be preserved
exactly through the move.

## 2. Target structure (folders by layer)

```
SpellHistoryEnhanced/
  SpellHistoryEnhanced.toc
  Core/
    Constants.lua     ICON_SIZE, SPACING, GCD_SPELL_ID (61304), colors, print prefix
    Config.lua        SavedVariables defaults + accessors; combat-state flags
    EventBus.lua      Subscribe/Publish
    Init.lua          ADDON_LOADED bootstrap, module wiring, ApplyAllSettings, pet-battle hide
  Engine/
    CastTracker.lua   UNIT_SPELLCAST_* capture, frame batching, channel handling
    GcdAnalyzer.lua   GCD ownership + waste/combo grading; publishes results
  UI/
    Anchor.lua        movable bar frame + Shift-drag + grid
    HistoryBar.lua    icon pool + animation driver
    Animations.lua    animation strategies (unchanged)
    StatsPanel.lua    on-screen stats panel + gear menu
  Options/
    Options.lua       native main settings page
    StatsSubPanel.lua Statistics canvas subpage
    IgnoreSubPanel.lua Ignore List canvas subpage
  Model/
    StatsModel.lua    per-combat accumulator (was Stats.lua)
    IgnoreList.lua    ignore model (moved)
    Profiles.lua      per-spec profiles (moved)
  Commands/
    Slash.lua         /she command
  Locales/
    enUS.lua, ptBR.lua
```

Files are relocated with `git mv` to preserve history. The addon folder name and
`.toc` name stay `SpellHistoryEnhanced` (SavedVariables identity).

### Module responsibilities & dependencies

| Module | Responsibility | Depends on |
|--------|----------------|------------|
| Core/Constants | Shared immutable values | — |
| Core/Config | Defaults, SavedVariables init, typed access, combat flags | Constants |
| Core/EventBus | In-process pub/sub | — |
| Core/Init | Boot sequence, wires modules, ApplyAllSettings orchestration, pet-battle, combat-state events | everything (loaded last) |
| Engine/CastTracker | Capture player cast events; batch per-frame; own the 0.01s timer; track channels; hand the batch to GcdAnalyzer | Config, GcdAnalyzer |
| Engine/GcdAnalyzer | Own GCD detection, waste/combo grading; publish `CAST_GRADED` | Config, EventBus, Constants |
| UI/Anchor | The movable bar frame, Shift-drag, grid snap, position save | Config, Constants, HistoryBar (for SetInteractive) |
| UI/HistoryBar | Icon pool + animations; subscribes `CAST_GRADED` to push icons | Animations, EventBus, Config |
| UI/Animations | Strategy set | — |
| UI/StatsPanel | On-screen readout + gear menu | StatsModel, Config, EventBus(open options) |
| Options/* | Native settings categories | Config, all models, Anchor/HistoryBar getters |
| Model/StatsModel | Accumulator; subscribes `CAST_GRADED` | EventBus |
| Model/IgnoreList | Ignore set | — |
| Model/Profiles | Per-spec profile swap | Config |
| Commands/Slash | `/she` | StatsModel, HistoryBar |

### `.toc` load order

Locales → Core/Constants → Core/Config → Core/EventBus → Model/StatsModel →
Model/IgnoreList → Model/Profiles → Engine/GcdAnalyzer → Engine/CastTracker →
UI/Animations → UI/HistoryBar → UI/Anchor → UI/StatsPanel → Options/Options →
Options/StatsSubPanel → Options/IgnoreSubPanel → Commands/Slash → **Core/Init**
(last; wires and starts everything).

## 3. EventBus (Core/EventBus.lua)

Minimal synchronous pub/sub:

```lua
ns.EventBus = { handlers = {} }
function ns.EventBus:Subscribe(topic, fn) ... end   -- append fn to handlers[topic]
function ns.EventBus:Publish(topic, payload) ... end -- call each handler(payload)
```

CastTracker hands its per-frame batch to `GcdAnalyzer:Process(batch)` directly
(a single internal step it owns via the 0.01s timer). Only the analyzer's
fan-out to the UI and stats model goes through the bus.

Topic used: `"CAST_GRADED"` with payload table:
`{ spellID, wasteTime, isOffGCD, isStart, isPerfect, comboCount, isChannel,
   inCombat, activeChunk }`.

- `GcdAnalyzer` publishes `CAST_GRADED` per spell instead of calling
  `HistoryBar:Push` / `Stats:Record`.
- `HistoryBar` subscribes and pushes an icon.
- `StatsModel` subscribes and records (in-combat, on-GCD only).
- Channel active-time finalization stays where it is (CastTracker on
  `CHANNEL_STOP` → `StatsModel:AddActiveTime`), unchanged.

## 4. Config (Core/Config.lua)

- Owns the defaults table and initializes `SpellHistoryEnhancedDB` keys on
  `ADDON_LOADED` (moving the current default block out of the monolith).
- Exposes `ns.Config.db` (the live working set) and convenience getters used by
  injected closures (e.g. `GetMaxIcons`).
- Holds transient combat/run flags currently floating as upvalues
  (`perfectCombo`, `pendingStart`, `lastGcdEndTime`, `lastGcdStartTime`,
  `lastChannelEndTime`, `pendingChannelActiveStart`) so Engine modules share
  them through one owner instead of file-scoped locals.
- The vestigial `isLocked` / `statsLocked` keys remain in defaults (unused) to
  avoid a SavedVariables migration; `Profiles.PROFILED_KEYS` keeps them too.

Profiles mutates `SpellHistoryEnhancedDB` **in place** (verified), so settings
bound to the table stay valid across spec switches.

## 5. Shift-drag movement (replaces lock)

- **Anchor (bar):** extract the manual cursor-follow drag math into
  `Anchor:BeginDrag()` / `Anchor:EndDrag()`. Gate start on `IsShiftKeyDown()`.
  The anchor stays mouse-enabled at 40×40 (grabs the empty bar). Each icon
  forwards Shift-drag to the bar via callbacks injected through
  `HistoryBar:Init` (`beginDrag`/`endDrag`). Grid overlay shows only during an
  active drag. Hover tooltip: "Shift-drag to move". Remove right-click-to-lock.
- **StatsPanel:** Shift-gate its existing `StartMoving`; mouse always enabled;
  remove right-click-lock and the lock checkbox dependency.
- Lock checkboxes removed from settings entirely.

## 6. StatsPanel gear button + menu

- ~16×16 cog button anchored top-right of the panel.
- Click → `MenuUtil.CreateContextMenu(owner, generator)` (fallback `EasyMenu`):
  - **Hide panel** → `Config.db.statsShown = false`; `StatsPanel:ApplyShown()`;
    sync the Options checkbox if built.
  - **Reset stats** → `StatsModel:Reset()` + `MSG_STATS_RESET` print.
  - **Open options** → `Settings.OpenToCategory(ns.optionsCategory:GetID())`.

## 7. Native settings (Options/)

Verified against installed addons (VoidChimes, Auctionator, RaiderIO).

**Main page** — `Settings.RegisterVerticalLayoutCategory("SpellHistoryEnhanced")`;
store the returned category as `ns.optionsCategory`; `Settings.RegisterAddOnCategory`.

Pattern per setting:
```lua
local setting = Settings.RegisterAddOnSetting(category, uniqueVar, dbKey,
                    ns.Config.db, type(default), label, default)
Settings.SetOnValueChangedCallback(uniqueVar, onChange)
-- checkbox: Settings.CreateCheckbox(category, setting, tooltip)
-- slider:   local o = Settings.CreateSliderOptions(min,max,step)
--           o:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, fmt)
--           Settings.CreateSlider(category, setting, o, tooltip)
-- dropdown: Settings.CreateDropdown(category, setting, GetOptions, tooltip)
-- button:   layout:AddInitializer(CreateSettingsButtonInitializer(name, btn, onClick, tooltip, true))
-- header:   layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(label))
```

Widgets, grouped:

- **Behavior**: Restart timeout (slider 1–60, `restartTimeout`) · Spell queue
  window (slider 0–400, step 10 — backed by a proxy value; change callback
  `SetCVar("SpellQueueWindow", v)`; seeded from the CVar) · Grid snap (checkbox,
  `useGrid`).
- **Appearance**: Max icons (slider 4–12, `maxIcons` → Relayout + bg update) ·
  Background opacity (slider 0–1 → %, `bgAlpha` → bg update) · UI scale (slider
  0.5–2.0 → %, `uiScale` → `anchor:SetScale`) · Animation style (dropdown over
  `ns.Animations:List()`, `animStyle`) · Animation speed (slider 0.1–0.6,
  `animDuration`).
- **Position**: Reset position (button) · Clear history (button).

`refreshOptionsPanel` (profile switch) becomes: for each tracked setting,
`setting:SetValue(ns.Config.db[key])`.

**Statistics subpage** — `Settings.RegisterCanvasLayoutSubcategory(main, frame,
"Statistics")`: Show-stats checkbox, live fight summary, Refresh + Reset buttons.

**Ignore List subpage** — canvas subcategory: add box (id/name/link resolver,
unchanged) + scroll frame of remove-rows; `IgnoreList:SetOnChanged` rebuilds.

## 8. Migration plan (phased; each phase compiles + loads + smoke-tests)

1. **Scaffold Core** — add `Constants`, `Config`, `EventBus`; move defaults and
   shared flags into `Config`; `.toc` updated. No behavior change.
2. **Extract Engine** — move cast capture → `CastTracker`, grading →
   `GcdAnalyzer`; switch to `EventBus` publish; `HistoryBar`/`StatsModel`
   subscribe. Preserve the channel waste/uptime fix verbatim.
3. **Anchor + Shift-drag** — split the bar frame/drag into `UI/Anchor`;
   implement Shift-drag + icon forwarding; remove lock gating.
4. **StatsPanel gear menu.**
5. **Native Options rewrite** — `Options/Options.lua` + the two subpages; delete
   the old `InitializeOptions`; wire `ns.optionsCategory`.

Each phase: `luac -p` on changed files, load in-game, verify the relevant
behavior (casts graded, bar moves via Shift-drag, panel menu works, settings
apply live and persist across `/reload` and spec switch).

## 9. Out of scope (YAGNI)

- No reset-confirmation popups.
- No new stats or display features.
- No removal of vestigial `isLocked`/`statsLocked` SavedVariables keys.
- The git-ignored `spell-history-enhanced/` staging copy is left as-is.

## 10. Risks

- **Load-order / file-scope deps:** mitigated by `Init.lua` loading last and
  modules referencing `ns.*` at call time, not file scope.
- **Native settings ↔ profile switch:** controls cache values; addressed by
  `setting:SetValue` on profile activate.
- **Behavior regression during the move:** mitigated by phasing + per-phase
  smoke tests; the Engine extraction is pure relocation.
- **Menu/Settings API availability on older clients:** `MenuUtil`/`Settings`
  guarded with fallbacks (`EasyMenu`, legacy `InterfaceOptions_AddCategory`).
```

