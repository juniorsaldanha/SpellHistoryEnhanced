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

local function addDropdown(category, var, key, label, default, getOptions, onChange)
    local setting = Settings.RegisterAddOnSetting(category, var, key, ns.Config.db, type(default), label, default)
    if onChange then Settings.SetOnValueChangedCallback(var, function() onChange() end) end
    Settings.CreateDropdown(category, setting, getOptions)
    settingRefs[key] = setting
    return setting
end

-- Open the Blizzard color picker seeded with (r,g,b,a); callback(r,g,b,a) runs
-- live as the user edits, and on cancel restores the previous color.
local function ShowColorPicker(r, g, b, a, callback)
    local function onChange()
        local nr, ng, nb = ColorPickerFrame:GetColorRGB()
        local na = ColorPickerFrame.GetColorAlpha and ColorPickerFrame:GetColorAlpha() or 1
        callback(nr, ng, nb, na)
    end
    local info = {
        r = r, g = g, b = b,
        hasOpacity = true,
        opacity = a or 1,
        swatchFunc = onChange,
        opacityFunc = onChange,
        previousValues = { r = r, g = g, b = b, a = a or 1 },
        cancelFunc = function(prev)
            if prev then callback(prev.r, prev.g, prev.b, prev.a or 1) end
        end,
    }
    if ColorPickerFrame.SetupColorPickerAndShow then
        ColorPickerFrame:SetupColorPickerAndShow(info)
    end
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
    addCheckbox(category, "SHE_showTrinkets", "showTrinkets", L["SHOW_TRINKETS"], true, L["SHOW_TRINKETS_TOOLTIP"], nil)
    addCheckbox(category, "SHE_barShown", "barShown", L["SHOW_BAR"], true, L["SHOW_BAR_TOOLTIP"],
        function() ns.Anchor:ApplyShown() end)

    -- ===== Appearance =====
    layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(L["SECTION_APPEARANCE"]))

    addSlider(category, "SHE_maxIcons", "maxIcons", L["MAX_ICONS"], 6, 4, 12, 1,
        function(v) return tostring(v) end,
        function() ns.HistoryBar:Relayout(); ns.Anchor:UpdateBackground(); ns.Anchor:UpdateBorder() end)

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

    -- Border size dropdown.
    addDropdown(category, "SHE_borderSize", "borderSize", L["BORDER_SIZE"], "none",
        function()
            local c = Settings.CreateControlTextContainer()
            c:Add("none", L["BORDER_NONE"])
            c:Add("thin", L["BORDER_THIN"])
            c:Add("normal", L["BORDER_NORMAL"])
            c:Add("heavy", L["BORDER_HEAVY"])
            c:Add("strong", L["BORDER_STRONG"])
            return c:GetData()
        end,
        function() ns.Anchor:UpdateBorder() end)

    -- Border color mode dropdown (class color or custom).
    addDropdown(category, "SHE_borderColorMode", "borderColorMode", L["BORDER_COLOR_MODE"], "class",
        function()
            local c = Settings.CreateControlTextContainer()
            c:Add("class", L["BORDER_COLOR_CLASS"])
            c:Add("custom", L["BORDER_COLOR_CUSTOM"])
            return c:GetData()
        end,
        function() ns.Anchor:UpdateBorder() end)

    -- Custom border color picker (switches the mode to custom).
    layout:AddInitializer(CreateSettingsButtonInitializer(L["BORDER_COLOR_PICK"], L["BORDER_COLOR_PICK"], function()
        local db = ns.Config.db
        ShowColorPicker(db.borderColorR or 1, db.borderColorG or 1, db.borderColorB or 1, db.borderColorA or 1,
            function(r, g, b, a)
                db.borderColorR, db.borderColorG, db.borderColorB, db.borderColorA = r, g, b, a
                db.borderColorMode = "custom"
                ns.Anchor:UpdateBorder()
                if ns.Options and ns.Options.Refresh then ns.Options:Refresh() end
            end)
    end, nil, true))

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
