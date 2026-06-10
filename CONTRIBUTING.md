# Contributing to Spell Combo History

Thanks for your interest in improving Spell Combo History! This guide covers
how to set up for development, the conventions the project follows, and how to
add a translation.

## Project Layout

```
SpellComboHistory.toc     # addon manifest; declares load order
SpellComboHistory.lua     # events, GCD/combo analysis, settings panel, wiring
Animations.lua            # tween engine + pluggable animation strategies
IgnoreList.lua            # the set of spells excluded from tracking
Stats.lua                 # per-combat statistics model
StatsPanel.lua            # optional on-screen stats readout (view over Stats)
HistoryBar.lua            # the on-screen icon bar (display manager)
Locales/
  enUS.lua                # English (base) strings
  ptBR.lua                # Brazilian Portuguese
README.md
CONTRIBUTING.md
LICENSE
```

Files load in the order declared in the `.toc`: locales first (so the string
table exists), then the modules (`Animations.lua`, `IgnoreList.lua`,
`Stats.lua`, `StatsPanel.lua`, `HistoryBar.lua`, which expose `ns.Tween`,
`ns.Animations`, `ns.IgnoreList`, `ns.Stats`, `ns.StatsPanel`, and
`ns.HistoryBar` on the addon's private namespace), and finally
`SpellComboHistory.lua`, which wires everything together.

### Adding an animation style

Animations are pluggable. Register a new strategy in `Animations.lua` — no
other file needs to change:

```lua
ns.Animations:Register({
    key = "myStyle",          -- stored in SavedVariables
    labelKey = "ANIM_MYSTYLE", -- a locale key for the display name
    PlayIn  = function(bar, icon, tx, ty, duration) ... end,
    PlayMove = function(bar, icon, tx, ty, duration) ... end,
    PlayOut = function(bar, icon, duration, onComplete) ... end,
})
```

Add the `ANIM_MYSTYLE` key to the locales, and it automatically appears in the
settings cycle button. Use `ns.Tween:Start(icon, duration, target, easing,
onComplete)` to animate the icon's `state` fields (`x`, `y`, `alpha`, `scale`).

## Development Setup

1. Clone the repository.
2. Symlink or copy the project folder into your WoW AddOns directory as
   `SpellComboHistory`:
   `World of Warcraft/_retail_/Interface/AddOns/SpellComboHistory`.
   A symlink lets you edit in place and just `/reload` to test.
3. In game, type `/reload` after each change to pick it up.
4. Use `/console scriptErrors 1` (or an error-display addon like BugSack) to
   surface Lua errors while testing.

If you have a Lua toolchain installed, you can syntax-check files before
loading them in game:

```sh
luac -p SpellComboHistory.lua
luac -p Locales/enUS.lua
```

(WoW runs Lua 5.1; `luac -p` only parse-checks, it does not run the addon.)

## Code Style

- **English only** in code and comments. Keep comments clear and concise, and
  match the density of the surrounding code.
- **No new globals.** Use the addon's private namespace (`local _, ns = ...`)
  and locals. The few intentional globals (frame names, `UpdateDummyFrames`)
  are pre-existing and named with the `SpellComboHistory` prefix.
- **All user-facing text goes through the locale table.** Never hardcode a
  displayed string; add a key to `Locales/enUS.lua` and reference it via
  `L["KEY"]`. This includes chat messages, button/label text, and any words
  drawn on screen.
- Localize frequently used global functions as upvalues at the top of the file
  (the existing pattern) when adding hot-path code.

## Adding a Translation

The addon uses a simple per-language Lua table — no localization library.

1. Create `Locales/<locale>.lua`, where `<locale>` is the WoW locale code
   (e.g. `koKR`, `deDE`, `frFR`, `zhCN`).
2. Guard the file on the active locale and override only the keys you
   translate. Anything you omit falls back to the English text in `enUS.lua`:

   ```lua
   if GetLocale() ~= "koKR" then return end
   local _, ns = ...
   local L = ns.L

   L["LOCK_POSITION"] = "..."  -- your translation
   -- ...override only what you translate
   ```

3. Add the file to `SpellComboHistory.toc`, **after** `Locales\enUS.lua` so it
   overrides the English defaults:

   ```
   Locales\enUS.lua
   Locales\koKR.lua
   SpellComboHistory.lua
   ```

4. `/reload` in a client set to that locale and verify the strings.

Use `enUS.lua` as the canonical list of keys to translate. Please don't remove
or rename keys — that would break other locales and the main file.

## Reporting Issues

When opening an issue, please include:

- A clear description of the problem or suggestion.
- Steps to reproduce (for bugs), and what you expected to happen.
- Your WoW version/flavor and any error text (from BugSack or
  `/console scriptErrors 1`).

## Pull Requests

- Keep PRs focused on a single change.
- Make sure both Lua files parse (`luac -p`) and that you've tested in game
  with `/reload`.
- Match the existing code style and comment conventions.
- For user-facing changes, update the README if relevant.

Thanks for contributing!
