-- Options/Options.lua - native Settings API main category.
local _, ns = ...
local L = ns.L

local Options = {}
ns.Options = Options

-- dbKey -> setting object, so a profile switch can push values back.
local settingRefs = {}

-- Register a slider bound to ns.Config.db[key]. onChange (no args) runs live
-- side-effects after the setting has already written the new value to the db.
local function addSlider(category, var, key, label, default, minV, maxV, step, fmt, onChange)
    local setting = Settings.RegisterAddOnSetting(category, var, key, ns.Config.db, type(default), label, default)
    Settings.SetOnValueChangedCallback(var, function() if onChange then onChange() end end)
    local o = Settings.CreateSliderOptions(minV, maxV, step)
    o:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, fmt)
    Settings.CreateSlider(category, setting, o)
    settingRefs[key] = setting
    return setting
end

local function addCheckbox(category, var, key, label, default, tooltip, onChange)
    local setting = Settings.RegisterAddOnSetting(category, var, key, ns.Config.db, type(default), label, default)
    Settings.SetOnValueChangedCallback(var, function() if onChange then onChange() end end)
    Settings.CreateCheckbox(category, setting, tooltip)
    settingRefs[key] = setting
    return setting
end

function Options:Build()
    local category, layout = Settings.RegisterVerticalLayoutCategory("SpellHistoryEnhanced")
    ns.optionsCategory = category

    -- ===== Behavior =====
    layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(L["SECTION_BEHAVIOR"]))

    addSlider(category, "SHE_restartTimeout", "restartTimeout", L["RESTART_TIMEOUT"], 10, 1, 60, 1,
        function(v) return string.format("%ds", v) end, nil)

    -- Spell queue window is a CVar, not a db key: back it with a proxy value.
    do
        local proxy = { value = tonumber(GetCVar("SpellQueueWindow")) or 400 }
        local setting = Settings.RegisterAddOnSetting(category, "SHE_queueWindow", "value", proxy, "number", L["SPELL_QUEUE_WINDOW"], proxy.value)
        Settings.SetOnValueChangedCallback("SHE_queueWindow", function()
            SetCVar("SpellQueueWindow", proxy.value)
        end)
        local o = Settings.CreateSliderOptions(0, 400, 10)
        o:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v) return string.format("%dms", v) end)
        Settings.CreateSlider(category, setting, o)
    end

    addCheckbox(category, "SHE_useGrid", "useGrid", L["USE_GRID_SNAP"], true, nil, nil)

    -- ===== Appearance =====
    layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(L["SECTION_APPEARANCE"]))

    addSlider(category, "SHE_maxIcons", "maxIcons", L["MAX_ICONS"], 6, 4, 12, 1,
        function(v) return tostring(v) end,
        function() ns.HistoryBar:Relayout(); ns.Anchor:UpdateBackground() end)

    addSlider(category, "SHE_bgAlpha", "bgAlpha", L["BG_TRANSPARENCY"], 0.5, 0, 1, 0.05,
        function(v) return string.format("%d%%", math.floor(v * 100 + 0.5)) end,
        function() ns.Anchor:UpdateBackground() end)

    addSlider(category, "SHE_uiScale", "uiScale", L["UI_SCALE"], 1.0, 0.5, 2.0, 0.05,
        function(v) return string.format("%d%%", math.floor(v * 100 + 0.5)) end,
        function() ns.Anchor:ApplyScale() end)

    -- Animation style dropdown (bound directly to db.animStyle).
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

    addSlider(category, "SHE_animDuration", "animDuration", L["ANIM_SPEED"], 0.25, 0.1, 0.6, 0.05,
        function(v) return string.format("%.2fs", v) end, nil)

    -- ===== Position / actions =====
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

    -- Subpages.
    if ns.StatsSubPanel then ns.StatsSubPanel:Build(category) end
    if ns.IgnoreSubPanel then ns.IgnoreSubPanel:Build(category) end
end

-- Push live db values back into the controls (after a profile/spec switch).
function Options:Refresh()
    for key, setting in pairs(settingRefs) do
        if ns.Config.db[key] ~= nil then
            setting:SetValue(ns.Config.db[key])
        end
    end
    if ns.StatsSubPanel and ns.StatsSubPanel.Refresh then ns.StatsSubPanel:Refresh() end
    if ns.IgnoreSubPanel and ns.IgnoreSubPanel.Rebuild then ns.IgnoreSubPanel:Rebuild() end
end
