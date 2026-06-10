# Spell Combo History

A World of Warcraft addon that shows your recent spell casts and grades how
well you chained them together. Every time you cast, the addon measures the
gap between your global cooldowns: cast with no wasted time and you get a
**PERFECT**; keep it going and you build a combo streak.

It's a lightweight, movable bar of spell icons with at-a-glance feedback —
handy for practicing tight rotations and minimizing GCD downtime.

## Features

- **Cast history bar** — the icons of your most recent casts, newest on the
  right, shifting left as you keep casting.
- **GCD grading** — shows the time wasted between globals (e.g. `0.12s`) or
  `PERFECT` when you waste nothing (within your latency).
- **Combo streaks** — consecutive PERFECT casts build tiers: `STREAK`,
  `RAMPAGE`, `INSANE`, `GODLIKE`, `LEGEND`.
- **Animations** — icons animate in as you cast and out as they age off the
  end of the bar. Choose a style (None, Fade, Slide, Bounce) and speed.
- **Ignore list** — exclude spells you don't care about (procs, trinkets,
  racials). Right-click a history icon to ignore it, or manage the list in the
  settings by spell ID, name, or link.
- **Movable & lockable** — drag the bar anywhere; right-click to lock.
- **Grid & snap** — optional alignment grid with snapping for precise placement.
- **In-game settings** — adjust max icons, scale, background transparency,
  restart timeout, the spell queue window, and animation style/speed, all from
  the options panel.
- **Spell tooltips** — hover any icon to see the spell tooltip.
- **Pet battle aware** — hides itself during pet battles.

## Installation

**With an addon manager** (recommended): install via your manager of choice
(CurseForge, WoWUp, etc.) and let it keep the addon updated.

**Manual install:**

1. Download or clone this repository.
2. Copy the folder into your WoW AddOns directory, e.g.
   `World of Warcraft/_retail_/Interface/AddOns/SpellComboHistory`.
3. Make sure the folder is named `SpellComboHistory` and contains
   `SpellComboHistory.toc` at its root.
4. Restart WoW (or `/reload`) and enable the addon at the character select
   screen.

## Usage

- The bar starts **locked** and centered. To move it, open the settings and
  uncheck **Lock Position** (or it's unlocked the first time so you can place
  it).
- While unlocked, **drag** the bar to reposition it and **right-click** it to
  lock again.
- Open the settings via the game's **AddOns options panel**
  (`Esc → Options → AddOns → SpellComboHistory`).

### Settings

| Setting | What it does |
| --- | --- |
| **Restart Timeout** | How long a gap (seconds) before a new cast counts as a fresh `START`/`RESTART` instead of continuing the combo. |
| **Lock Position** | Locks/unlocks dragging. |
| **Use Grid & Snap** | Shows an alignment grid and snaps the bar to it while moving. |
| **Max Icons** | How many past casts to show (4–12). |
| **Background Transparency** | Opacity of the bar background. |
| **UI Scale** | Overall size of the bar (50%–200%). |
| **Spell Queue Window** | Adjusts the game's `SpellQueueWindow` CVar. Higher values queue pre-input spells more smoothly; lower values react faster but are more ping-sensitive. |
| **Animation Style** | How icons enter/leave the bar: None, Fade, Slide, or Bounce. |
| **Animation Speed** | Duration of the animations (0.1s–0.6s). |
| **Ignore List** | Spells excluded from tracking. Add by ID/name/link or right-click a history icon; remove from the list here. |

There are also buttons to check the current queue value, clear the history,
and reset the bar position to center.

## Planned Features

These are on the roadmap and not yet implemented:

- **Stats & session tracking** — a session summary: uptime %, average wasted
  time between globals, best combo, and total casts.
- **Per-spec profiles** — separate settings (position, max icons, scale, ...)
  per character specialization.

Have an idea? Open an issue — see below.

## Contributing

Contributions and translations are welcome! See [CONTRIBUTING.md](CONTRIBUTING.md)
for development setup, code style, and how to add a new language.

## License

Released under the [MIT License](LICENSE).
