-- IgnoreList.lua - the set of spells excluded from tracking.
--
-- A small, UI-agnostic model: it owns the ignored-spell set (persisted in the
-- saved variables), exposes query/mutate operations, and notifies a single
-- observer when it changes so the settings panel can refresh live.
local _, ns = ...

local C_Spell = C_Spell
local GetSpellInfo = GetSpellInfo or function(id) return C_Spell.GetSpellInfo(id) end

local IgnoreList = {}
ns.IgnoreList = IgnoreList

-- Resolve a spell's display name and icon from its ID.
function IgnoreList.GetSpellNameIcon(spellID)
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(spellID)
        if info then return info.name, info.iconID end
    end
    local name, _, icon = GetSpellInfo(spellID)
    return name, icon
end

-- Does a spell with this ID exist in the game?
function IgnoreList.SpellExists(spellID)
    if C_Spell and C_Spell.DoesSpellExist then
        return C_Spell.DoesSpellExist(spellID)
    end
    return GetSpellInfo(spellID) ~= nil
end

-- db: the saved-variables table. Ensures the storage sub-table exists.
function IgnoreList:Init(db)
    self.db = db
    db.ignoreList = db.ignoreList or {}
end

function IgnoreList:IsIgnored(spellID)
    return self.db and self.db.ignoreList[spellID] == true
end

-- Add a spell. Returns true if it was newly added.
function IgnoreList:Add(spellID)
    if not self.db or not spellID or self.db.ignoreList[spellID] then return false end
    self.db.ignoreList[spellID] = true
    self:Notify()
    return true
end

-- Remove a spell. Returns true if it was present.
function IgnoreList:Remove(spellID)
    if not self.db or not self.db.ignoreList[spellID] then return false end
    self.db.ignoreList[spellID] = nil
    self:Notify()
    return true
end

-- The ignored spell IDs, sorted by display name (then ID) for stable display.
function IgnoreList:GetSorted()
    local list = {}
    for spellID in pairs(self.db.ignoreList) do
        list[#list + 1] = spellID
    end
    table.sort(list, function(a, b)
        local na = IgnoreList.GetSpellNameIcon(a) or ""
        local nb = IgnoreList.GetSpellNameIcon(b) or ""
        if na == nb then return a < b end
        return na < nb
    end)
    return list
end

-- Register the (single) change observer used to refresh the UI.
function IgnoreList:SetOnChanged(callback)
    self.onChanged = callback
end

function IgnoreList:Notify()
    if self.onChanged then self.onChanged() end
end
