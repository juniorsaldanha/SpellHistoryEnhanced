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
    showTrinkets   = true,
}

-- Transient grading state, shared by Engine/CastTracker and Engine/GcdAnalyzer.
Config.state = {
    perfectCombo              = 0,
    pendingStart              = false,
    lastGcdEndTime            = 0,
    lastGcdStartTime          = 0,
    lastChannelEndTime        = 0,
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
