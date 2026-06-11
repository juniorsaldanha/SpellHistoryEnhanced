-- Core/Init.lua - addon bootstrap. Loads last: seeds config, wires every
-- module together at ADDON_LOADED, handles profile lifecycle + pet battles,
-- and orchestrates ApplyAllSettings.
local addonName, ns = ...

local ICON_SIZE = ns.Constants.ICON_SIZE
local SPACING   = ns.Constants.SPACING

-- Re-apply every runtime setting from the live working set. Used at login and
-- after a profile (spec) switch. Each module applies its own concern.
local function ApplyAllSettings()
    ns.Anchor:ApplyScale()
    ns.Anchor:ApplyPosition()
    ns.Anchor:UpdateBackground()
    ns.Anchor:UpdateBorder()
    ns.Anchor:ApplyShown()
    ns.HistoryBar:Relayout()
    ns.StatsPanel:ApplyPosition()
    ns.StatsPanel:ApplyShown()
    ns.IgnoreList:Notify()
    if ns.Options and ns.Options.Refresh then ns.Options:Refresh() end
end
ns.ApplyAllSettings = ApplyAllSettings

local frame = CreateFrame("Frame", "SpellHistoryEnhancedFrame", UIParent)
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
frame:RegisterEvent("PLAYER_LOGOUT")
frame:RegisterEvent("PET_BATTLE_OPENING_START")
frame:RegisterEvent("PET_BATTLE_CLOSE")

frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        -- Seed defaults and expose the working set.
        ns.Config:Init()
        local db = ns.Config.db

        -- Models.
        ns.IgnoreList:Init(db)
        ns.Stats:Init()
        ns.Profiles:Init(db)

        -- UI.
        ns.StatsPanel:Init(db)
        ns.HistoryBar:Init({
            anchor = ns.Anchor.frame,
            iconSize = ICON_SIZE,
            spacing = SPACING,
            getMaxIcons = function() return (ns.Config.db and ns.Config.db.maxIcons) or 6 end,
            getAnimation = function() return ns.Animations:Get(ns.Config.db.animStyle) end,
            getDuration = function() return (ns.Config.db and ns.Config.db.animDuration) or 0.25 end,
            beginDrag = function() ns.Anchor:BeginDrag() end,
            endDrag = function() ns.Anchor:EndDrag() end,
        })

        -- Settings page, then apply everything to the UI.
        ns.Options:Build()
        ApplyAllSettings()
        return
    end

    if event == "PLAYER_LOGIN" then
        ns.Profiles:Activate(nil, ApplyAllSettings)
        return
    end
    if event == "PLAYER_SPECIALIZATION_CHANGED" then
        ns.Profiles:Activate(nil, ApplyAllSettings)
        return
    end
    if event == "PLAYER_LOGOUT" then
        ns.Profiles:SaveCurrent()
        return
    end

    if event == "PET_BATTLE_OPENING_START" then
        ns.Anchor.frame:Hide()
        return
    end
    if event == "PET_BATTLE_CLOSE" then
        ns.Anchor:ApplyShown()
        return
    end
end)
