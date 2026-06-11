# Restructure + Native Settings + Shift-Drag Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restructure the addon into focused, SOLID modules organized by layer; decouple the engine from the UI via an event bus; add Shift-drag movement and a stats-panel gear menu; and rewrite the settings page with the native WoW Settings API.

**Architecture:** Files move (via `git mv`) into `Core/ Engine/ UI/ Options/ Model/ Commands/ Locales/`. `Core/Init.lua` loads last and wires everything. `Engine/GcdAnalyzer` publishes a `CAST_GRADED` event on `Core/EventBus`; `UI/HistoryBar` and `Model/StatsModel` subscribe (no direct engine→UI calls). Shift-drag replaces the lock toggle; settings become native categories + two canvas subpages.

**Tech Stack:** Lua 5.1 (WoW client), WoW `Settings`/`MenuUtil` APIs. No automated test runner — **verification = `luac -p` compile + in-game `/reload` smoke check**.

**Spec:** `docs/superpowers/specs/2026-06-10-restructure-and-settings-design.md`

**Branch:** `restructure-and-settings` (already created).

---

## Conventions for every task

- **Compile gate:** `luac -p <changed .lua files>` must print nothing (success). If `luac` is unavailable, `luajit -bl <file> >/dev/null`.
- **Smoke gate:** the executor (or user) runs `/reload` in WoW and confirms the named behavior. If the user is unavailable, note "needs in-game verification" on the commit and continue — do NOT claim verified.
- **Module pattern:** every file starts with `local addonName, ns = ...` and attaches its table to `ns`. Reference other modules as `ns.X` **inside functions** (call time), never at file scope, so load order only matters for `Init`.
- Preserve the already-shipped channel waste/uptime fix verbatim when relocating engine code.

---

## Phase 1 — Scaffold Core

### Task 1: Create `Core/Constants.lua`

**Files:**
- Create: `Core/Constants.lua`

- [ ] **Step 1: Write the file**

```lua
-- Core/Constants.lua - shared immutable values.
local _, ns = ...

ns.Constants = {
    ICON_SIZE    = 40,
    SPACING      = 10,
    GCD_SPELL_ID = 61304,            -- the dummy spell that drives the GCD bar
    PRINT_PREFIX = "|cff00ccff[SpellHistory] |r",
}
```

- [ ] **Step 2: Compile**

Run: `luac -p Core/Constants.lua`
Expected: no output (success).

- [ ] **Step 3: Commit**

```bash
git add Core/Constants.lua
git commit -m "Add Core/Constants module"
```

---

### Task 2: Create `Core/EventBus.lua`

**Files:**
- Create: `Core/EventBus.lua`

- [ ] **Step 1: Write the file**

```lua
-- Core/EventBus.lua - minimal synchronous publish/subscribe.
local _, ns = ...

local EventBus = { handlers = {} }
ns.EventBus = EventBus

-- Subscribe fn to a topic. fn receives the published payload.
function EventBus:Subscribe(topic, fn)
    local list = self.handlers[topic]
    if not list then
        list = {}
        self.handlers[topic] = list
    end
    list[#list + 1] = fn
end

-- Publish payload to every subscriber of topic, in subscription order.
function EventBus:Publish(topic, payload)
    local list = self.handlers[topic]
    if not list then return end
    for i = 1, #list do
        list[i](payload)
    end
end
```

- [ ] **Step 2: Compile**

Run: `luac -p Core/EventBus.lua`
Expected: no output.

- [ ] **Step 3: Commit**

```bash
git add Core/EventBus.lua
git commit -m "Add Core/EventBus pub/sub"
```

---

### Task 3: Create `Core/Config.lua`

**Files:**
- Create: `Core/Config.lua`

- [ ] **Step 1: Write the file**

```lua
-- Core/Config.lua - SavedVariables defaults, live working set, and the
-- transient per-run state shared by the engine modules.
local _, ns = ...

local Config = {}
ns.Config = Config

-- Default values seeded into SpellHistoryEnhancedDB on first load. isLocked /
-- statsLocked are vestigial (kept to avoid a SavedVariables migration).
Config.defaults = {
    restartTimeout = 10,
    isLocked       = true,
    maxIcons       = 6,
    bgAlpha        = 0.5,
    uiScale        = 1.0,
    useGrid        = true,
    animStyle      = "slide",
    animDuration   = 0.25,
    statsShown     = true,
    statsLocked    = true,
}

-- Transient grading state, shared by Engine/CastTracker and Engine/GcdAnalyzer.
Config.state = {
    perfectCombo             = 0,
    pendingStart             = false,
    lastGcdEndTime           = 0,
    lastGcdStartTime         = 0,
    lastChannelEndTime       = 0,
    pendingChannelActiveStart = nil,
}

-- Seed missing defaults and expose the live table as Config.db. Call from
-- ADDON_LOADED before any other module reads settings.
function Config:Init()
    SpellHistoryEnhancedDB = SpellHistoryEnhancedDB or {}
    for k, v in pairs(self.defaults) do
        if SpellHistoryEnhancedDB[k] == nil then
            SpellHistoryEnhancedDB[k] = v
        end
    end
    self.db = SpellHistoryEnhancedDB
    return self.db
end
```

- [ ] **Step 2: Compile**

Run: `luac -p Core/Config.lua`
Expected: no output.

- [ ] **Step 3: Commit**

```bash
git add Core/Config.lua
git commit -m "Add Core/Config (defaults + shared run state)"
```

---

### Task 4: Register the three Core files in the `.toc` and route defaults through Config

**Files:**
- Modify: `SpellHistoryEnhanced.toc`
- Modify: `SpellHistoryEnhanced.lua` (ADDON_LOADED defaults block, currently ~1040-1059)

- [ ] **Step 1: Add the Core files at the top of the load list in `SpellHistoryEnhanced.toc`**

Insert these three lines immediately **after** the two `Locales\...` lines and **before** `Animations.lua`:

```
Core\Constants.lua
Core\EventBus.lua
Core\Config.lua
```

- [ ] **Step 2: Replace the per-key default block in `SpellHistoryEnhanced.lua`**

Find the ADDON_LOADED block that sets `SpellHistoryEnhancedDB = SpellHistoryEnhancedDB or {}` followed by the run of `if SpellHistoryEnhancedDB.X == nil then ... end` lines. Replace that entire run (from the `SpellHistoryEnhancedDB = ... or {}` line through the last `statsLocked` default) with:

```lua
        -- Seed defaults and expose the working set via Core/Config.
        ns.Config:Init()
```

Leave the rest of ADDON_LOADED (IgnoreList:Init, Stats:Init, etc.) unchanged.

- [ ] **Step 3: Compile**

Run: `luac -p SpellHistoryEnhanced.lua`
Expected: no output.

- [ ] **Step 4: Smoke test**

`/reload`. Confirm: addon loads with no Lua error, the bar appears, a cast still shows an icon, and `/she` prints stats. (Defaults now come from Config.)

- [ ] **Step 5: Commit**

```bash
git add SpellHistoryEnhanced.toc SpellHistoryEnhanced.lua
git commit -m "Load Core modules; seed defaults via Config"
```

---

## Phase 2 — Extract the Engine (CastTracker + GcdAnalyzer) and wire the EventBus

This is a pure relocation of existing logic plus swapping two direct calls for an
EventBus publish. The grading math (including the channel waste/uptime fix) must
not change.

### Task 5: Create `Model/StatsModel.lua` (move `Stats.lua`) and subscribe to `CAST_GRADED`

**Files:**
- Move: `Stats.lua` → `Model/StatsModel.lua`
- Modify: moved file (add subscription)
- Modify: `SpellHistoryEnhanced.toc`

- [ ] **Step 1: Move the file**

```bash
git mv Stats.lua Model/StatsModel.lua
```

- [ ] **Step 2: Update the `.toc`**

Replace the `Stats.lua` line with `Model\StatsModel.lua`. (Keep it before `StatsPanel.lua`.)

- [ ] **Step 3: Add a subscription at the bottom of `Model/StatsModel.lua`**

After the existing `function Stats:Get() ... end`, append:

```lua
-- Record graded casts arriving from the engine (in-combat, on-GCD only). The
-- channel active-time is added separately by CastTracker at CHANNEL_STOP.
ns.EventBus:Subscribe("CAST_GRADED", function(p)
    if p.inCombat and not p.isOffGCD then
        local activeChunk = p.activeChunk or 0
        Stats:Record(p.isPerfect, p.comboCount, p.isStart, p.wasteTime, activeChunk)
    end
end)
```

- [ ] **Step 4: Compile**

Run: `luac -p Model/StatsModel.lua`
Expected: no output.

- [ ] **Step 5: Commit**

```bash
git add SpellHistoryEnhanced.toc Model/StatsModel.lua
git commit -m "Move Stats -> Model/StatsModel; subscribe to CAST_GRADED"
```

(`Stats` table is still `ns.Stats`; only the file path changed. The subscription is dormant until Task 7 publishes.)

---

### Task 6: Create `Engine/GcdAnalyzer.lua` by moving `ProcessFrameSpells`

**Files:**
- Create: `Engine/GcdAnalyzer.lua`
- Modify: `SpellHistoryEnhanced.lua` (remove the moved function + its globals)
- Modify: `SpellHistoryEnhanced.toc`

- [ ] **Step 1: Create `Engine/GcdAnalyzer.lua`**

Move the body of `ProcessFrameSpells` (currently ~816-1033) into a method
`GcdAnalyzer:Process(spells)`. Apply exactly these substitutions while moving:

- The shared run flags become `ns.Config.state` fields: `perfectCombo` →
  `st.perfectCombo`, `pendingStart` → `st.pendingStart`, `lastGcdEndTime` →
  `st.lastGcdEndTime`, `lastGcdStartTime` → `st.lastGcdStartTime`,
  `lastChannelEndTime` → `st.lastChannelEndTime` (add `local st = ns.Config.state`
  at the top of `Process`).
- `61304` → `ns.Constants.GCD_SPELL_ID`.
- Replace the final two calls (the `ns.Stats:Record(...)` block and
  `ns.HistoryBar:Push(...)`) with a single publish — see Step 2.
- `SpellHistoryEnhancedDB` reads stay as-is (still a valid global).

Skeleton:

```lua
-- Engine/GcdAnalyzer.lua - GCD ownership detection + waste/combo grading.
-- Publishes one CAST_GRADED event per analyzed spell; has no UI knowledge.
local _, ns = ...

local GcdAnalyzer = {}
ns.GcdAnalyzer = GcdAnalyzer

local GetTime               = GetTime
local GetSpellBaseCooldown  = GetSpellBaseCooldown
local InCombatLockdown      = InCombatLockdown
local UnitAffectingCombat   = UnitAffectingCombat
local GetNetStats           = GetNetStats

-- (Keep the GetSpellCooldownDuration helper here too if Process uses it; move
--  it from the main file.)

-- Analyze one frame's batch of spells (newest grouping). `spells` is the array
-- the CastTracker collected.
function GcdAnalyzer:Process(spells)
    local st = ns.Config.state
    -- ... moved body of ProcessFrameSpells, with the substitutions above ...
end
```

- [ ] **Step 2: Replace the per-spell tail (stats record + HistoryBar push) with a publish**

Where the old loop ended with the `if inCombat and not isOffGCD then ... ns.Stats:Record(...) end` block and `ns.HistoryBar:Push(sp.spellID, wasteTime, isOffGCD, isStart, isPerfect, perfectCombo)`, replace BOTH with:

```lua
        -- Compute the channel-aware active chunk here so the model stays dumb.
        local activeChunk
        if sp.isChannel then
            st.pendingChannelActiveStart = sp.castStartTime or now
            activeChunk = 0
        else
            activeChunk = sp.castStartTime and (now - sp.castStartTime) or currentDuration
        end

        ns.EventBus:Publish("CAST_GRADED", {
            spellID    = sp.spellID,
            wasteTime  = wasteTime,
            isOffGCD   = isOffGCD,
            isStart    = isStart,
            isPerfect  = isPerfect,
            comboCount = st.perfectCombo,
            isChannel  = sp.isChannel,
            inCombat   = inCombat,
            activeChunk = activeChunk,
        })
```

(The old code computed `activeChunk` inside the stats `if`; it now always computes it for the payload. `StatsModel` ignores it unless in-combat/on-GCD, preserving behavior. The `pendingChannelActiveStart` assignment that previously lived in the stats block moves here so the channel-uptime fix is preserved.)

- [ ] **Step 3: Remove the now-moved code and globals from `SpellHistoryEnhanced.lua`**

Delete the old `ProcessFrameSpells` function. Delete the file-scoped flag locals that moved to `Config.state` (`lastGcdEndTime`, `lastGcdStartTime`, `lastChannelEndTime`, `perfectCombo`, `pendingStart`, and `pendingChannelActiveStart` if present) — search the file and repoint every remaining reference to `ns.Config.state.<name>` (the combat-state event handlers in Task 8 will use these). Delete the moved `GetSpellCooldownDuration` helper if it is no longer referenced in the main file.

- [ ] **Step 4: Point the processing timer at the new method**

Find where `processingTimer = C_Timer.After(0.01, ProcessFrameSpells)` is set (in the SUCCEEDED handler). Change it to:

```lua
        if not processingTimer then
            processingTimer = C_Timer.After(0.01, function()
                processingTimer = nil
                local batch = frameSpells
                frameSpells = {}
                ns.GcdAnalyzer:Process(batch)
            end)
        end
```

(The reset of `processingTimer`/`frameSpells` that used to happen at the top of `ProcessFrameSpells` now happens here, so remove those two lines from the moved `Process` body.)

- [ ] **Step 5: Register `Engine/GcdAnalyzer.lua` in the `.toc`**

Add `Engine\GcdAnalyzer.lua` **after** the `Model\...` lines and **before** `HistoryBar.lua`.

- [ ] **Step 6: Compile**

Run: `luac -p Engine/GcdAnalyzer.lua SpellHistoryEnhanced.lua`
Expected: no output.

- [ ] **Step 7: Smoke test**

`/reload`, enter combat, cast a few on-GCD spells incl. a channel (e.g. Void Ray). Confirm: icons still appear with PERFECT/wasted text; the spell AFTER a channel shows ~0 waste (channel fix intact); `/she` shows uptime including the channel. No Lua errors.

- [ ] **Step 8: Commit**

```bash
git add SpellHistoryEnhanced.toc Engine/GcdAnalyzer.lua SpellHistoryEnhanced.lua
git commit -m "Extract Engine/GcdAnalyzer; publish CAST_GRADED instead of direct calls"
```

---

### Task 7: Subscribe `HistoryBar` to `CAST_GRADED`

**Files:**
- Modify: `HistoryBar.lua` (add subscription; `Push` signature unchanged)

- [ ] **Step 1: Add a subscription at the bottom of `HistoryBar.lua`**

After `function HistoryBar:SetInteractive(...) end`, append:

```lua
-- Drive the bar from graded casts published by the engine.
ns.EventBus:Subscribe("CAST_GRADED", function(p)
    HistoryBar:Push(p.spellID, p.wasteTime, p.isOffGCD, p.isStart, p.isPerfect, p.comboCount)
end)
```

- [ ] **Step 2: Compile**

Run: `luac -p HistoryBar.lua`
Expected: no output.

- [ ] **Step 3: Smoke test**

`/reload`, cast spells. Icons appear exactly as before. (StatsModel + HistoryBar are now both driven purely by the bus.)

- [ ] **Step 4: Commit**

```bash
git add HistoryBar.lua
git commit -m "HistoryBar subscribes to CAST_GRADED"
```

---

### Task 8: Create `Engine/CastTracker.lua` (move the cast-event capture)

**Files:**
- Create: `Engine/CastTracker.lua`
- Modify: `SpellHistoryEnhanced.lua` (remove the moved event handling)
- Modify: `SpellHistoryEnhanced.toc`

- [ ] **Step 1: Create `Engine/CastTracker.lua`**

Move into this module: the `frame`/event registration for `UNIT_SPELLCAST_SUCCEEDED`, `UNIT_SPELLCAST_START`, `UNIT_SPELLCAST_CHANNEL_START`, `UNIT_SPELLCAST_CHANNEL_STOP`, `PLAYER_REGEN_ENABLED`, `PLAYER_REGEN_DISABLED`, `PET_BATTLE_*`; the `pendingCasts`, `channelCasts`, `frameSpells`, `processingTimer` state; and the SUCCEEDED/channel handler bodies. Apply substitutions:

- shared flags → `ns.Config.state.<name>` (`pendingStart`, `lastGcdEndTime`, etc.).
- the 0.01s timer fires `ns.GcdAnalyzer:Process(batch)` (as written in Task 6 Step 4).
- combat enter/leave keep calling `ns.Stats:BeginCombat/EndCombat`, set
  `ns.Config.state.pendingStart`, reset the run flags, and clear
  `pendingChannelActiveStart` (unchanged logic, just relocated).
- `CHANNEL_STOP` keeps the channel-end correction:
  `ns.Config.state.lastChannelEndTime = channelEnd`; if
  `ns.Config.state.lastGcdEndTime ~= 0` then set it to `channelEnd`; and if
  `ns.Config.state.pendingChannelActiveStart` then
  `ns.Stats:AddActiveTime(channelEnd - start)` and clear it.
- pet-battle `anchor:Hide()/Show()` — for now reference the anchor via
  `ns.Anchor`/the existing global frame; if the anchor is still in the main file
  at this phase, keep these two lines in the main file's event frame instead of
  moving them (move them in Phase 3 with the Anchor). Simplest: leave PET_BATTLE
  handling in the main file until Phase 3.

Skeleton:

```lua
-- Engine/CastTracker.lua - capture player cast events, batch them per frame,
-- track channels, and hand each batch to the GcdAnalyzer.
local _, ns = ...

local GetTime = GetTime
local frame = CreateFrame("Frame", "SpellHistoryEnhancedCastFrame", UIParent)

local pendingCasts = {}
local channelCasts = {}
local frameSpells = {}
local processingTimer = nil

-- ... RegisterEvent calls + OnEvent handler with the moved bodies ...
```

- [ ] **Step 2: Remove the moved event code from `SpellHistoryEnhanced.lua`**

Delete the relocated handlers/state from the main file's `frame:SetScript("OnEvent", ...)`. Keep ADDON_LOADED, PLAYER_LOGIN, spec-changed, logout, and (for now) PET_BATTLE in the main file. If that leaves the main file's `frame` only handling lifecycle events, that is fine.

- [ ] **Step 3: Register `Engine\CastTracker.lua` in the `.toc`** after `Engine\GcdAnalyzer.lua`.

- [ ] **Step 4: Compile**

Run: `luac -p Engine/CastTracker.lua SpellHistoryEnhanced.lua`
Expected: no output.

- [ ] **Step 5: Smoke test**

`/reload`, full combat test (instants, hardcast, channel, entering/leaving combat, START/RESTART after a long pause). Behavior identical to before the refactor. No errors.

- [ ] **Step 6: Commit**

```bash
git add SpellHistoryEnhanced.toc Engine/CastTracker.lua SpellHistoryEnhanced.lua
git commit -m "Extract Engine/CastTracker; main file keeps lifecycle only"
```

---

## Phase 3 — `UI/Anchor` + Shift-drag (replaces lock)

### Task 9: Move the bar frame + drag into `UI/Anchor.lua` and Shift-gate it

**Files:**
- Create: `UI/Anchor.lua`
- Modify: `SpellHistoryEnhanced.lua` (remove anchor creation/drag/grid; keep a reference via `ns.Anchor`)
- Modify: `SpellHistoryEnhanced.toc`

- [ ] **Step 1: Create `UI/Anchor.lua`**

Move into it: the `anchor` frame creation (currently ~100-113), `UpdateMainBackground`, `CreateGrid`/`gridFrame`/`ToggleGrid`, `UpdateDummyFrames`, and the drag handlers. Expose `ns.Anchor` with `frame`, and methods `BeginDrag()`, `EndDrag()`, `ApplyScale()`, `ApplyPosition()`, `ResetPosition()`, `UpdateBackground()`. Constants come from `ns.Constants`.

Convert the drag to Shift-gated and reusable:

```lua
function Anchor:BeginDrag()
    if anchor.dragging then return end
    anchor.dragging = true
    if SpellHistoryEnhancedDB.useGrid then ns.Anchor:ToggleGrid(true) end
    -- ... the existing cursor-follow OnUpdate (block-center math + grid snap) ...
    anchor:SetScript("OnUpdate", onDragUpdate)
end

function Anchor:EndDrag()
    anchor.dragging = false
    anchor:SetScript("OnUpdate", nil)
    ns.Anchor:ToggleGrid(false)
    local point, _, _, x, y = anchor:GetPoint()
    SpellHistoryEnhancedDB.point, SpellHistoryEnhancedDB.x, SpellHistoryEnhancedDB.y = point, x, y
end

anchor:RegisterForDrag("LeftButton")
anchor:SetScript("OnDragStart", function()
    if IsShiftKeyDown() then ns.Anchor:BeginDrag() end
end)
anchor:SetScript("OnDragStop", function() ns.Anchor:EndDrag() end)
anchor:EnableMouse(true)                 -- always live; 40x40 grabs the empty bar
anchor:SetScript("OnMouseDown", nil)     -- remove right-click-to-lock
anchor:SetScript("OnEnter", function()
    GameTooltip:SetOwner(anchor, "ANCHOR_TOP")
    GameTooltip:SetText(ns.L["MOVE_HINT"])
    GameTooltip:Show()
end)
anchor:SetScript("OnLeave", function() GameTooltip:Hide() end)
```

(Move the existing block-center + grid-snap math verbatim into `onDragUpdate`.)

- [ ] **Step 2: Replace `anchor` references in the main file**

In the main file, wherever `anchor` was used (ApplyAllSettings, reset-position button, pet-battle Hide/Show, `HistoryBar:Init({ anchor = anchor })`), replace with `ns.Anchor.frame`. Move PET_BATTLE Hide/Show here too if desired, calling `ns.Anchor.frame:Hide()/Show()`.

- [ ] **Step 3: Register `UI\Anchor.lua` in the `.toc`** before `HistoryBar.lua` (HistoryBar reads `ns.Anchor.frame` at Init time, which runs in Core/Init later, so order is safe; place Anchor before HistoryBar anyway).

- [ ] **Step 4: Compile**

Run: `luac -p UI/Anchor.lua SpellHistoryEnhanced.lua`
Expected: no output.

- [ ] **Step 5: Smoke test**

`/reload`. With at least one icon on the bar: hold **Shift** and left-drag an empty part of the bar → it moves; release → position persists across `/reload`. Without Shift, dragging does nothing and clicks pass through. Right-click no longer locks. Grid appears only while dragging (if grid enabled).

- [ ] **Step 6: Commit**

```bash
git add SpellHistoryEnhanced.toc UI/Anchor.lua SpellHistoryEnhanced.lua
git commit -m "Extract UI/Anchor; Shift-drag replaces lock for the bar"
```

---

### Task 10: Forward Shift-drag from icons to the bar

**Files:**
- Modify: `HistoryBar.lua` (`Init` opts + `CreateIcon`)

- [ ] **Step 1: Accept drag callbacks in `HistoryBar:Init`**

In `HistoryBar:Init(opts)`, store:

```lua
    self.beginDrag = opts.beginDrag
    self.endDrag   = opts.endDrag
```

- [ ] **Step 2: Wire each icon for Shift-drag in `CreateIcon`**

After the icon's existing `OnMouseUp` handler, add:

```lua
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function()
        if IsShiftKeyDown() and HistoryBar.beginDrag then HistoryBar.beginDrag() end
    end)
    f:SetScript("OnDragStop", function()
        if HistoryBar.endDrag then HistoryBar.endDrag() end
    end)
```

Add `local IsShiftKeyDown = IsShiftKeyDown` to the localized-globals block at the top of `HistoryBar.lua`.

- [ ] **Step 3: Pass the callbacks where `HistoryBar:Init` is called**

In the main file's ADDON_LOADED `ns.HistoryBar:Init({ ... })`, add:

```lua
            beginDrag = function() ns.Anchor:BeginDrag() end,
            endDrag   = function() ns.Anchor:EndDrag() end,
```

- [ ] **Step 4: Compile**

Run: `luac -p HistoryBar.lua SpellHistoryEnhanced.lua`
Expected: no output.

- [ ] **Step 5: Smoke test**

`/reload`. Hover **an icon**, hold Shift, drag → the whole bar moves. Without Shift, hovering shows the spell tooltip and right-click still adds to the ignore list.

- [ ] **Step 6: Commit**

```bash
git add HistoryBar.lua SpellHistoryEnhanced.lua
git commit -m "Forward Shift-drag from icons to the bar"
```

---

## Phase 4 — Stats panel: Shift-drag + gear menu

### Task 11: Move `StatsPanel.lua` to `UI/`, Shift-gate its drag, drop lock

**Files:**
- Move: `StatsPanel.lua` → `UI/StatsPanel.lua`
- Modify: moved file
- Modify: `SpellHistoryEnhanced.toc`

- [ ] **Step 1: Move + toc**

```bash
git mv StatsPanel.lua UI/StatsPanel.lua
```
Update the `.toc` line `StatsPanel.lua` → `UI\StatsPanel.lua`.

- [ ] **Step 2: Shift-gate the drag and remove lock**

In `UI/StatsPanel.lua`:
- Change `OnDragStart` to: `f:SetScript("OnDragStart", function(self) if IsShiftKeyDown() then self:StartMoving() end end)` (drop the `panel.db.statsLocked` check).
- Delete the `OnMouseDown` right-click-to-lock handler.
- In `Init`, after creating `f`, call `f:EnableMouse(true)` unconditionally and remove the `ApplyLock` call.
- Replace `ApplyLock` body with a no-op kept for compatibility, OR delete it and remove its callers (the Options page will no longer call it after Phase 5). For now make it:
```lua
function StatsPanel:ApplyLock() end
```
- Update the drag hint text to `ns.L["STATS_MOVE_HINT"]` (already used) — leave the hint shown always or only on hover; simplest: keep the existing bottom hint but reword the locale string in Task 14 to "Shift-drag to move".
- Add `local IsShiftKeyDown = IsShiftKeyDown` near the top.

- [ ] **Step 3: Compile**

Run: `luac -p UI/StatsPanel.lua`
Expected: no output.

- [ ] **Step 4: Smoke test**

`/reload`. Shift-drag the stats panel → moves and persists. Without Shift it does not move.

- [ ] **Step 5: Commit**

```bash
git add SpellHistoryEnhanced.toc UI/StatsPanel.lua
git commit -m "Move StatsPanel to UI/; Shift-drag, drop lock"
```

---

### Task 12: Add the gear button + context menu to the stats panel

**Files:**
- Modify: `UI/StatsPanel.lua`
- Depends on: `ns.optionsCategory` (set in Phase 5 Task 15). Until then, "Open options" guards on its presence.

- [ ] **Step 1: Create the gear button in `StatsPanel:Init` (after the title)**

```lua
    -- Top-right gear button -> context menu.
    local gear = CreateFrame("Button", nil, f)
    gear:SetSize(16, 16)
    gear:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)
    gear:SetNormalTexture("Interface\\GossipFrame\\BinderGossipIcon")
    gear:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    gear:SetScript("OnClick", function() panel:OpenMenu(gear) end)
    self.gear = gear
```

- [ ] **Step 2: Add the menu builder method**

```lua
function StatsPanel:OpenMenu(owner)
    local function build(_, root)
        root:CreateButton(ns.L["MENU_HIDE_PANEL"], function()
            ns.Config.db.statsShown = false
            StatsPanel:ApplyShown()
            if _G["SpellHistoryEnhancedShowStatsCheck"] then
                _G["SpellHistoryEnhancedShowStatsCheck"]:SetChecked(false)
            end
        end)
        root:CreateButton(ns.L["MENU_RESET_STATS"], function()
            ns.Stats:Reset()
            print(ns.Constants.PRINT_PREFIX .. ns.L["MSG_STATS_RESET"])
        end)
        root:CreateButton(ns.L["MENU_OPEN_OPTIONS"], function()
            if ns.optionsCategory and Settings and Settings.OpenToCategory then
                Settings.OpenToCategory(ns.optionsCategory:GetID())
            end
        end)
    end
    if MenuUtil and MenuUtil.CreateContextMenu then
        MenuUtil.CreateContextMenu(owner, build)
    end
end
```

- [ ] **Step 3: Compile**

Run: `luac -p UI/StatsPanel.lua`
Expected: no output.

- [ ] **Step 4: Smoke test**

`/reload`. Click the gear → menu with Hide panel / Reset stats / Open options. Hide hides the panel; Reset zeroes stats and prints; Open options will fully work after Phase 5 (until then it is a no-op guard).

- [ ] **Step 5: Commit**

```bash
git add UI/StatsPanel.lua
git commit -m "Add stats-panel gear button + context menu"
```

---

## Phase 5 — Native settings rewrite

### Task 13: Create `Options/Options.lua` (native main page) and delete `InitializeOptions`

**Files:**
- Create: `Options/Options.lua`
- Modify: `SpellHistoryEnhanced.lua` (remove `InitializeOptions`; call `ns.Options:Build()`)
- Modify: `SpellHistoryEnhanced.toc`

- [ ] **Step 1: Create `Options/Options.lua`**

```lua
-- Options/Options.lua - native Settings API main category.
local _, ns = ...
local L = ns.L

local Options = {}
ns.Options = Options

local settingRefs = {}   -- dbKey -> setting (for profile-switch refresh)

local function addSlider(category, layout, var, key, label, default, min, max, step, fmt, onChange)
    local setting = Settings.RegisterAddOnSetting(category, var, key, ns.Config.db, type(default), label, default)
    Settings.SetOnValueChangedCallback(var, function(_, value) onChange(value) end)
    local o = Settings.CreateSliderOptions(min, max, step)
    o:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, fmt)
    Settings.CreateSlider(category, setting, o)
    settingRefs[key] = setting
    return setting
end

local function addCheckbox(category, var, key, label, default, tooltip, onChange)
    local setting = Settings.RegisterAddOnSetting(category, var, key, ns.Config.db, type(default), label, default)
    Settings.SetOnValueChangedCallback(var, function(_, value) onChange(value) end)
    Settings.CreateCheckbox(category, setting, tooltip)
    settingRefs[key] = setting
    return setting
end

function Options:Build()
    local category, layout = Settings.RegisterVerticalLayoutCategory("SpellHistoryEnhanced")
    ns.optionsCategory = category

    -- Behavior
    layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(L["SECTION_BEHAVIOR"]))
    addSlider(category, layout, "SHE_restartTimeout", "restartTimeout", L["RESTART_TIMEOUT"], 10, 1, 60, 1,
        function(v) return string.format("%ds", v) end, function() end)

    -- Spell queue window (CVar-backed proxy)
    do
        local proxy = { value = tonumber(GetCVar("SpellQueueWindow")) or 400 }
        local setting = Settings.RegisterAddOnSetting(category, "SHE_queue", "value", proxy, "number", L["SPELL_QUEUE_WINDOW"], proxy.value)
        Settings.SetOnValueChangedCallback("SHE_queue", function(_, v) SetCVar("SpellQueueWindow", v) end)
        local o = Settings.CreateSliderOptions(0, 400, 10)
        o:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v) return string.format("%dms", v) end)
        Settings.CreateSlider(category, setting, o)
    end

    addCheckbox(category, "SHE_useGrid", "useGrid", L["USE_GRID_SNAP"], true, nil, function() end)

    -- Appearance
    layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(L["SECTION_APPEARANCE"]))
    addSlider(category, layout, "SHE_maxIcons", "maxIcons", L["MAX_ICONS"], 6, 4, 12, 1,
        function(v) return tostring(v) end,
        function() ns.HistoryBar:Relayout(); ns.Anchor:UpdateBackground() end)
    addSlider(category, layout, "SHE_bgAlpha", "bgAlpha", L["BG_TRANSPARENCY"], 0.5, 0, 1, 0.05,
        function(v) return string.format("%d%%", math.floor(v*100+0.5)) end,
        function() ns.Anchor:UpdateBackground() end)
    addSlider(category, layout, "SHE_uiScale", "uiScale", L["UI_SCALE"], 1.0, 0.5, 2.0, 0.05,
        function(v) return string.format("%d%%", math.floor(v*100+0.5)) end,
        function(v) ns.Anchor.frame:SetScale(v) end)

    -- Animation style dropdown
    do
        local function GetOptions()
            local c = Settings.CreateControlTextContainer()
            for _, strat in ipairs(ns.Animations:List()) do
                c:Add(strat.key, L[strat.labelKey])
            end
            return c:GetData()
        end
        local setting = Settings.RegisterAddOnSetting(category, "SHE_animStyle", "animStyle", ns.Config.db, "string", L["ANIM_STYLE"], "slide")
        Settings.CreateDropdown(category, setting, GetOptions)
        settingRefs.animStyle = setting
    end

    addSlider(category, layout, "SHE_animDuration", "animDuration", L["ANIM_SPEED"], 0.25, 0.1, 0.6, 0.05,
        function(v) return string.format("%.2fs", v) end, function() end)

    -- Position / actions
    layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(L["SECTION_POSITION"]))
    layout:AddInitializer(CreateSettingsButtonInitializer(L["RESET_POSITION"], L["RESET_POSITION"], function()
        ns.Anchor:ResetPosition()
        print(ns.Constants.PRINT_PREFIX .. L["MSG_POSITION_RESET"])
    end, nil, true))
    layout:AddInitializer(CreateSettingsButtonInitializer(L["CLEAR_HISTORY"], L["CLEAR_HISTORY"], function()
        ns.HistoryBar:Clear()
        ns.Config.state.perfectCombo = 0
        print(ns.Constants.PRINT_PREFIX .. L["MSG_HISTORY_CLEARED"])
    end, nil, true))

    Settings.RegisterAddOnCategory(category)

    -- Build the subpages (Task 14).
    if ns.StatsSubPanel then ns.StatsSubPanel:Build(category) end
    if ns.IgnoreSubPanel then ns.IgnoreSubPanel:Build(category) end
end

-- Push live db values back into the controls (after a profile switch).
function Options:Refresh()
    for key, setting in pairs(settingRefs) do
        if ns.Config.db[key] ~= nil then setting:SetValue(ns.Config.db[key]) end
    end
end
```

- [ ] **Step 2: Remove `InitializeOptions` from the main file and call `ns.Options:Build()`**

Delete the entire `InitializeOptions` function and its `refreshOptionsPanel` upvalue. Where ADDON_LOADED called `InitializeOptions()`, call `ns.Options:Build()`. Where the profile-switch path called `refreshOptionsPanel()` (inside `ApplyAllSettings`), call `if ns.Options.Refresh then ns.Options:Refresh() end`.

- [ ] **Step 3: Register `Options\Options.lua` in the `.toc`** after `UI\StatsPanel.lua` and before `Commands\Slash.lua` (Commands added in Task 16; for now before `SpellHistoryEnhanced.lua`).

- [ ] **Step 4: Compile**

Run: `luac -p Options/Options.lua SpellHistoryEnhanced.lua`
Expected: no output.

- [ ] **Step 5: Smoke test**

`/reload`, open ESC → Options → AddOns → SpellHistoryEnhanced. Confirm Behavior/Appearance/Position sections render with native sliders/checkbox/dropdown/buttons; changing each applies live (max icons relayouts, scale changes, bg opacity changes, animation style switches) and persists across `/reload`. Gear-menu "Open options" now opens this page.

- [ ] **Step 6: Commit**

```bash
git add SpellHistoryEnhanced.toc Options/Options.lua SpellHistoryEnhanced.lua
git commit -m "Rewrite settings with native Settings API (main page)"
```

---

### Task 14: Create the Statistics and Ignore List canvas subpages

**Files:**
- Create: `Options/StatsSubPanel.lua`
- Create: `Options/IgnoreSubPanel.lua`
- Modify: `SpellHistoryEnhanced.toc`

- [ ] **Step 1: Create `Options/StatsSubPanel.lua`**

```lua
-- Options/StatsSubPanel.lua - Statistics canvas subcategory.
local _, ns = ...
local L = ns.L
local StatsSubPanel = {}
ns.StatsSubPanel = StatsSubPanel

local function fmtDuration(sec)
    sec = math.floor(sec)
    return string.format("%d:%02d", math.floor(sec/60), sec%60)
end

function StatsSubPanel:Build(parentCategory)
    local f = CreateFrame("Frame", "SpellHistoryEnhancedStatsSubPanel")
    f.name = L["STATS_HEADER"]

    local show = CreateFrame("CheckButton", "SpellHistoryEnhancedShowStatsCheck", f, "ChatConfigCheckButtonTemplate")
    show:SetPoint("TOPLEFT", 16, -16)
    _G[show:GetName().."Text"]:SetText(L["SHOW_STATS"])
    show:SetChecked(ns.Config.db.statsShown)
    show:SetScript("OnClick", function(self)
        ns.Config.db.statsShown = self:GetChecked() and true or false
        ns.StatsPanel:ApplyShown()
    end)

    local summary = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    summary:SetPoint("TOPLEFT", show, "BOTTOMLEFT", 4, -16)
    summary:SetJustifyH("LEFT")
    local function refresh()
        local s = ns.Stats:Get()
        summary:SetText(
            L["STATS_SESSION"]..": "..fmtDuration(s.duration).."\n"..
            L["STATS_UPTIME"]..": "..math.floor(s.uptime+0.5).."%\n"..
            L["PERFECT"]..": "..s.perfects.." ("..math.floor(s.perfectRate+0.5).."%)\n"..
            L["STATS_BEST_COMBO"]..": "..s.bestCombo.."\n"..
            L["STATS_AVG_WASTE"]..": "..string.format("%.2fs", s.avgWaste).."\n"..
            L["STATS_CASTS"]..": "..s.casts)
    end
    refresh()

    local refreshBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    refreshBtn:SetSize(110, 26)
    refreshBtn:SetPoint("TOPLEFT", summary, "BOTTOMLEFT", 0, -16)
    refreshBtn:SetText(L["STATS_REFRESH"])
    refreshBtn:SetScript("OnClick", refresh)

    local resetBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    resetBtn:SetSize(110, 26)
    resetBtn:SetPoint("LEFT", refreshBtn, "RIGHT", 12, 0)
    resetBtn:SetText(L["STATS_RESET"])
    resetBtn:SetScript("OnClick", function()
        ns.Stats:Reset(); refresh()
        print(ns.Constants.PRINT_PREFIX .. L["MSG_STATS_RESET"])
    end)

    f:SetScript("OnShow", refresh)
    Settings.RegisterCanvasLayoutSubcategory(parentCategory, f, f.name)
end
```

- [ ] **Step 2: Create `Options/IgnoreSubPanel.lua`**

Move the ignore-list UI (add box + resolver + pooled rows + `rebuildIgnoreList` + `IgnoreList:SetOnChanged`) from the old `InitializeOptions` into `IgnoreSubPanel:Build(parentCategory)`, parented to a new canvas frame, anchored from the frame's TOPLEFT, in a `ScrollFrame` (`UIPanelScrollFrameTemplate`) so long lists scroll. Register via `Settings.RegisterCanvasLayoutSubcategory(parentCategory, frame, L["IGNORE_LIST"])`. Reuse the exact `resolveSpell`/`commitAdd` logic from the old code (it is correct).

```lua
-- Options/IgnoreSubPanel.lua - Ignore List canvas subcategory.
local _, ns = ...
local L = ns.L
local IgnoreSubPanel = {}
ns.IgnoreSubPanel = IgnoreSubPanel

local GetSpellInfo = GetSpellInfo or function(id) return C_Spell.GetSpellInfo(id) end

function IgnoreSubPanel:Build(parentCategory)
    local f = CreateFrame("Frame", "SpellHistoryEnhancedIgnoreSubPanel")
    f.name = L["IGNORE_LIST"]
    -- ... hint, add box + button (resolveSpell/commitAdd verbatim), scroll frame,
    --     pooled rows, rebuildIgnoreList, ns.IgnoreList:SetOnChanged(rebuild) ...
    Settings.RegisterCanvasLayoutSubcategory(parentCategory, f, f.name)
end
```

- [ ] **Step 3: Register both files in the `.toc`** after `Options\Options.lua`:
```
Options\StatsSubPanel.lua
Options\IgnoreSubPanel.lua
```
(They must load before `Options.lua`'s `Build` runs — but `Build` runs from Core/Init at ADDON_LOADED, after all files are loaded, so any order among Options files is fine. Keep `Options.lua` first for readability and the `if ns.StatsSubPanel` guard handles ordering regardless.)

- [ ] **Step 4: Compile**

Run: `luac -p Options/StatsSubPanel.lua Options/IgnoreSubPanel.lua`
Expected: no output.

- [ ] **Step 5: Smoke test**

`/reload`. Under SpellHistoryEnhanced in the options tree there are **Statistics** and **Ignore List** subpages. Statistics shows the live summary + Refresh/Reset + Show-stats toggle. Ignore List adds/removes spells (and scrolls). The gear menu's Hide unchecks Show-stats here.

- [ ] **Step 6: Commit**

```bash
git add SpellHistoryEnhanced.toc Options/StatsSubPanel.lua Options/IgnoreSubPanel.lua
git commit -m "Add Statistics + Ignore List settings subpages"
```

---

### Task 15: Move `IgnoreList.lua`, `Profiles.lua` to `Model/`; create `Commands/Slash.lua` and `Core/Init.lua`

**Files:**
- Move: `IgnoreList.lua` → `Model/IgnoreList.lua`, `Profiles.lua` → `Model/Profiles.lua`
- Move: `Animations.lua` → `UI/Animations.lua`
- Create: `Commands/Slash.lua` (move the slash command out of the main file)
- Create: `Core/Init.lua` (move the remaining ADDON_LOADED/lifecycle wiring + `ApplyAllSettings`)
- Delete: `SpellHistoryEnhanced.lua` once empty
- Modify: `SpellHistoryEnhanced.toc`

- [ ] **Step 1: Move the model/animation files**

```bash
git mv IgnoreList.lua Model/IgnoreList.lua
git mv Profiles.lua Model/Profiles.lua
git mv Animations.lua UI/Animations.lua
```
Update the matching `.toc` lines to the new paths.

- [ ] **Step 2: Create `Commands/Slash.lua`**

Move the `SLASH_SPELLHISTORYENHANCED*` + `SlashCmdList[...]` block from the main file into this file unchanged, except `print` prefixes use `ns.Constants.PRINT_PREFIX` and `ns.Stats`/`fmtDuration` references resolve as before (keep a local `fmtDuration` copy).

- [ ] **Step 3: Create `Core/Init.lua`**

Move the remaining lifecycle code from `SpellHistoryEnhanced.lua`: the event frame that handles `ADDON_LOADED` (now calling `ns.Config:Init()`, the module `:Init()` calls, `ns.Options:Build()`, `ApplyAllSettings()`), `PLAYER_LOGIN`, `PLAYER_SPECIALIZATION_CHANGED`, `PLAYER_LOGOUT`, and `ApplyAllSettings` itself. `ApplyAllSettings` now delegates: `ns.Anchor:ApplyScale()`, `ns.Anchor:ApplyPosition()`, `ns.Anchor:UpdateBackground()`, `ns.HistoryBar:Relayout()`, `ns.StatsPanel:ApplyPosition/ApplyShown()`, `ns.IgnoreList:Notify()`, `ns.Options:Refresh()`.

- [ ] **Step 4: Delete the emptied main file and update the `.toc`**

If `SpellHistoryEnhanced.lua` is now empty, `git rm SpellHistoryEnhanced.lua` and remove its `.toc` line. Add `Commands\Slash.lua` and `Core\Init.lua` (Init **last**).

- [ ] **Step 5: Compile**

Run: `luac -p Core/Init.lua Commands/Slash.lua Model/IgnoreList.lua Model/Profiles.lua UI/Animations.lua`
Expected: no output.

- [ ] **Step 6: Smoke test (full regression)**

`/reload`: bar + panel appear; cast grading correct (incl. channel); Shift-drag both frames; gear menu works incl. Open options; native settings apply + persist; `/she` and `/she reset` work; switch spec → settings/profile swap and the options controls update.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "Finish restructure: Model/, Commands/Slash, Core/Init; remove monolith"
```

---

### Task 16: Add the new locale strings

**Files:**
- Modify: `Locales/enUS.lua`, `Locales/ptBR.lua`

- [ ] **Step 1: Add keys to `Locales/enUS.lua`** (and translated equivalents to `ptBR.lua`)

```lua
L["SECTION_BEHAVIOR"]   = "Behavior"
L["SECTION_APPEARANCE"] = "Appearance"
L["SECTION_POSITION"]   = "Position"
L["MENU_HIDE_PANEL"]    = "Hide panel"
L["MENU_RESET_STATS"]   = "Reset stats"
L["MENU_OPEN_OPTIONS"]  = "Open options"
```
Reword `L["MOVE_HINT"]` and `L["STATS_MOVE_HINT"]` to "Shift-drag to move". Remove the now-unused `LOCK_POSITION` / `LOCK_STATS` keys only if nothing references them (grep first).

- [ ] **Step 2: Verify no missing keys**

Run: `grep -rho 'L\["[A-Z_]*"\]' --include=*.lua Core Engine UI Options Commands | sort -u > /tmp/used.txt` and confirm each appears in `Locales/enUS.lua`.

- [ ] **Step 3: Compile + smoke**

Run: `luac -p Locales/enUS.lua Locales/ptBR.lua`; `/reload`; confirm section headers, menu items, and the "Shift-drag to move" tooltips read correctly.

- [ ] **Step 4: Commit**

```bash
git add Locales/enUS.lua Locales/ptBR.lua
git commit -m "Add locale strings for sections, menu, and shift-drag hint"
```

---

## Final verification

- [ ] `luac -p` passes on every `.lua` file: `find Core Engine UI Options Model Commands Locales -name '*.lua' -exec luac -p {} +`
- [ ] No stray references to the old globals: `grep -rn "ProcessFrameSpells\|InitializeOptions\|SpellHistoryEnhancedLockCheck\|SpellHistoryEnhancedLockStatsCheck" --include=*.lua Core Engine UI Options Model Commands` returns nothing.
- [ ] Full in-game regression (Task 15 Step 6) passes.
- [ ] Update the `.toc` interface version if needed; confirm the git-ignored `spell-history-enhanced/` staging copy is untouched.
```

