-- Profiles.lua - per-specialization settings profiles.
--
-- The addon keeps its live settings as flat keys on SpellComboHistoryDB (the
-- "working set" every module already reads). This manager stores a copy of
-- those keys per specialization under db.profiles[specID] and swaps them when
-- the player changes spec:
--   * switching away saves the working set into the old spec's profile,
--   * switching in loads the new spec's profile into the working set
--     (seeding a brand-new spec from the current settings).
-- Existing settings migrate into the current spec's profile on first run.
local _, ns = ...

local Profiles = {}
ns.Profiles = Profiles

-- The flat keys that belong to a profile. (ignoreList is a table, copied
-- separately; queue window is a game CVar and is not stored here.)
local PROFILED_KEYS = {
    "restartTimeout", "isLocked", "maxIcons", "bgAlpha", "uiScale", "useGrid",
    "animStyle", "animDuration", "statsShown", "statsLocked",
    "point", "x", "y", "statsPoint", "statsX", "statsY",
}

local function copySet(src)
    local out = {}
    if src then
        for k in pairs(src) do out[k] = true end
    end
    return out
end

function Profiles:Init(db)
    self.db = db
    db.profiles = db.profiles or {}
    self.active = nil
end

-- A stable key for the current spec (its global spec ID), or 0 if unknown
-- (e.g. a low-level character with no specialization yet).
function Profiles:CurrentSpecKey()
    if GetSpecialization then
        local index = GetSpecialization()
        if index then
            local id = GetSpecializationInfo(index)
            if id then return id end
        end
    end
    return 0
end

-- Copy the live working set into profile `key`.
function Profiles:SaveTo(key)
    local p = self.db.profiles[key] or {}
    for _, k in ipairs(PROFILED_KEYS) do
        p[k] = self.db[k]
    end
    p.ignoreList = copySet(self.db.ignoreList)
    self.db.profiles[key] = p
end

-- Load profile `key` into the live working set.
function Profiles:LoadFrom(key)
    local p = self.db.profiles[key]
    if not p then return false end
    for _, k in ipairs(PROFILED_KEYS) do
        -- Keep the live default if an older profile lacks a newer key.
        if p[k] ~= nil then self.db[k] = p[k] end
    end
    self.db.ignoreList = copySet(p.ignoreList)
    return true
end

-- Make `key` (default: current spec) the active profile, applying via onApply.
function Profiles:Activate(key, onApply)
    key = key or self:CurrentSpecKey()
    if self.active == key then return end
    -- Persist the spec we are leaving.
    if self.active ~= nil then
        self:SaveTo(self.active)
    end
    if self.db.profiles[key] then
        self:LoadFrom(key)
    else
        -- First time on this spec: seed it from the current settings.
        self:SaveTo(key)
    end
    self.active = key
    if onApply then onApply() end
end

-- Persist the active profile (call on logout).
function Profiles:SaveCurrent()
    if self.active ~= nil then
        self:SaveTo(self.active)
    end
end
