-- enUS.lua - English (base) locale for Spell Combo History.
-- This file sets every user-facing string unconditionally and serves as the
-- fallback for all other locales. To add a translation, create a sibling file
-- (e.g. koKR.lua), guard it on GetLocale(), and override only the keys you
-- translate; anything you omit falls back to the English text defined here.
local _, ns = ...
ns.L = ns.L or {}
local L = ns.L

-- Movable anchor hint shown while the bar is unlocked.
L["MOVE_HINT"] = "MOVE\nRight-click to Lock"

-- Options panel.
L["OPTIONS_TITLE"] = "Spell Combo History Settings"
L["RESTART_TIMEOUT"] = "Restart Timeout"
L["LOCK_POSITION"] = "Lock Position"
L["USE_GRID_SNAP"] = "Use Grid & Snap"
L["MAX_ICONS"] = "Max Icons"
L["BG_TRANSPARENCY"] = "Background Transparency"
L["UI_SCALE"] = "UI Scale"
L["SPELL_QUEUE_WINDOW"] = "Spell Queue Window"
L["QUEUE_HELP"] = "Higher values allow pre-input spells to trigger smoothly but make it difficult to change skills urgently.\nLower values are directly affected by ping, potentially wasting time between spells."
L["CHECK_CURRENT"] = "Check Current"
L["CLEAR_HISTORY"] = "Clear History"
L["RESET_POSITION"] = "Reset Position"
L["ANIM_STYLE"] = "Animation Style"
L["ANIM_SPEED"] = "Animation Speed"
L["ANIM_NONE"] = "None"
L["ANIM_FADE"] = "Fade"
L["ANIM_SLIDE"] = "Slide"
L["ANIM_BOUNCE"] = "Bounce"

-- Chat messages (printed after the "[SpellCombo]" prefix).
L["MSG_POSITION_LOCKED"] = "Position locked via Right-click."
L["MSG_CURRENT_QUEUE"] = "Current SpellQueueWindow:"
L["MSG_HISTORY_CLEARED"] = "History has been cleared."
L["MSG_POSITION_RESET"] = "Position has been reset to center."

-- Display words rendered on/near the icons.
L["START"] = "START"
L["RESTART"] = "RESTART"
L["PERFECT"] = "PERFECT"

-- Combo tier labels, shown as the streak grows.
L["COMBO_STREAK"] = "STREAK"
L["COMBO_RAMPAGE"] = "RAMPAGE"
L["COMBO_INSANE"] = "INSANE"
L["COMBO_GODLIKE"] = "GODLIKE"
L["COMBO_LEGEND"] = "LEGEND"
