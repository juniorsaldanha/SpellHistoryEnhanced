-- [[ SpellComboHistory - Logic Flow ]]
--
--  1. Event handling (OnEvent)
--     - UNIT_SPELLCAST_START: record the cast's start time (pendingCasts)
--     - UNIT_SPELLCAST_SUCCEEDED: drop the spell into the basket (frameSpells)
--       and arm a 0.01s timer
--
--  2. Buffering / collection (C_Timer 0.01s)
--     - Group spells that fire on the same frame (rapid input or macros) so
--       they are processed together
--
--  3. Core analysis (ProcessFrameSpells)
--     - [GCD detection]: watch the shared GCD cooldown (61304) for changes
--       (0.1s threshold)
--     - [Owner search]: find which spell in the frame actually triggered the
--       GCD (gcdSpellIndex)
--     - [Waste calc]: (this spell's start time) - (previous spell's GCD end
--       time) = wasted time (wasteTime)
--     - [Grading]: if wasteTime <= world latency (ping) it is a PERFECT and
--       combo +1
--
--  4. UI refresh (UpdateHistory)
--     - [Shift icons]: push existing icons one slot to the left
--     - [New icon]: build the latest spell's icon in slot 1 and set its texture
--     - [Text]: show the result (START, PERFECT, wasted seconds) and combo tier
--       (STREAK, etc.)
--
--  5. Settings (InitializeOptions)
--     - React to user settings (lock, count, transparency, ...) and refresh the
--       background (UpdateMainBackground) and guides (UpdateDummyFrames) live
-- -----------------------------------------------------------------------------------------------------------------------

-- [SpellComboHistory] addon entry point.
-- Addon-private namespace and localized string table.
local addonName, ns = ...
local L = ns.L

-- Localize frequently used globals for performance (upvalues).
local GetTime = GetTime
-- Function that returns a spell's base cooldown info.
local GetSpellBaseCooldown = GetSpellBaseCooldown
-- Returns whether the player is currently in combat lockdown.
local InCombatLockdown = InCombatLockdown
-- Returns combat state from the unit itself.
local UnitAffectingCombat = UnitAffectingCombat
-- Returns network stats (including ping info).
local GetNetStats = GetNetStats

-- Spell info function, with a fallback for the modern C_Spell API.
local GetSpellInfo = GetSpellInfo or function(id) return C_Spell.GetSpellInfo(id) end
-- Spell cooldown function, with a fallback for the modern C_Spell API.
local GetSpellCooldown = GetSpellCooldown or function(id) return C_Spell.GetSpellCooldown(id) end

-- Helper that safely returns just a spell's cooldown duration.
local function GetSpellCooldownDuration(spellID)
    -- Prefer the modern C_Spell API when available.
    if C_Spell and C_Spell.GetSpellCooldown then
        -- Fetch cooldown info via the modern API.
        local cd = C_Spell.GetSpellCooldown(spellID)
        -- Return the duration if present, otherwise 0.
        return cd and cd.duration or 0
    end
    -- Fall back to the legacy API for the duration.
    local _, dur = GetSpellCooldown(spellID)
    -- Return the result, or 0 if missing.
    return dur or 0
end

-- Create the main frame that receives events.
local frame = CreateFrame("Frame", "SpellComboHistoryFrame", UIParent)
-- Register the spell-cast-succeeded event.
frame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
-- Register channel start/stop events.
frame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")
frame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")

-- Estimated end time of the previous spell's global cooldown.
local lastGcdEndTime = 0
-- Start time of the previous spell's global cooldown.
local lastGcdStartTime = 0
-- End time of the previous channeled spell.
local lastChannelEndTime = 0
-- Current run of consecutive PERFECT casts.
local perfectCombo = 0
-- Whether to show "START" on the first cast after entering combat.
local pendingStart = false
-- Table holding the created icon objects.
local icons = {}
-- On-screen icon size, in pixels.
local ICON_SIZE = 40
-- Spacing between icons, in pixels.
local SPACING = 10

-- Movable handle frame used to reposition the icon block.
local anchor = CreateFrame("Frame", "SpellComboHistoryAnchor", UIParent)
-- Match the handle size to the default icon size.
anchor:SetSize(ICON_SIZE, ICON_SIZE)
-- Default to screen center.
anchor:SetPoint("CENTER", 0, 0)
-- Allow the frame to be moved with the mouse.
anchor:SetMovable(true)
-- Ignore mouse clicks by default (only enabled while unlocked).
anchor:EnableMouse(false)
-- Allow left-button dragging.
anchor:RegisterForDrag("LeftButton")

-- Stores the cursor-to-frame offset while dragging.
local dragOffsetX, dragOffsetY = 0, 0

-- Frame used to draw the on-screen alignment grid.
local gridFrame
local function CreateGrid()
    if gridFrame then return end
    gridFrame = CreateFrame("Frame", nil, UIParent)
    gridFrame:SetAllPoints()
    gridFrame:SetFrameStrata("BACKGROUND")

    local w, h = UIParent:GetWidth(), UIParent:GetHeight()
    -- Horizontal lines (40px apart).
    for i = 0, h, 40 do
        local t = gridFrame:CreateTexture(nil, "BACKGROUND")
        t:SetHeight(1)
        t:SetPoint("LEFT", gridFrame, "LEFT")
        t:SetPoint("RIGHT", gridFrame, "RIGHT")
        t:SetPoint("BOTTOM", gridFrame, "BOTTOM", 0, i)
        t:SetColorTexture(1, 1, 1, 0.15)
    end
    -- Vertical lines (40px apart).
    for i = 0, w, 40 do
        local t = gridFrame:CreateTexture(nil, "BACKGROUND")
        t:SetWidth(1)
        t:SetPoint("TOP", gridFrame, "TOP", 0, 0)
        t:SetPoint("BOTTOM", gridFrame, "BOTTOM", 0, 0)
        t:SetPoint("LEFT", gridFrame, "LEFT", i, 0)
        t:SetColorTexture(1, 1, 1, 0.15)
    end
    -- Center crosshair (brighter white, used as a guide).
    gridFrame.vCenter = gridFrame:CreateTexture(nil, "ARTWORK")
    gridFrame.vCenter:SetWidth(2)
    gridFrame.vCenter:SetPoint("TOP", gridFrame, "TOP", 0, 0)
    gridFrame.vCenter:SetPoint("BOTTOM", gridFrame, "BOTTOM", 0, 0)
    gridFrame.vCenter:SetPoint("CENTER", gridFrame, "CENTER")
    gridFrame.vCenter:SetColorTexture(1, 1, 1, 0.4)

    gridFrame.hCenter = gridFrame:CreateTexture(nil, "ARTWORK")
    gridFrame.hCenter:SetHeight(2)
    gridFrame.hCenter:SetPoint("LEFT", gridFrame, "LEFT")
    gridFrame.hCenter:SetPoint("RIGHT", gridFrame, "RIGHT")
    gridFrame.hCenter:SetPoint("CENTER", gridFrame, "CENTER")
    gridFrame.hCenter:SetColorTexture(1, 1, 1, 0.4)
end

local function ToggleGrid(show)
    if show and SpellComboHistoryDB.useGrid then
        CreateGrid()
        gridFrame:Show()
    elseif gridFrame then
        gridFrame:Hide()
    end
end
-- Script run when a drag starts.
anchor:SetScript("OnDragStart", function(self)
    -- Get the current cursor position.
    local cx, cy = GetCursorPosition()
    -- Read the UI scale to correct the coordinates.
    local scale = UIParent:GetEffectiveScale()
    -- Apply scale to get the real cursor position.
    cx, cy = cx / scale, cy / scale
    -- Get the handle frame's current left/bottom coordinates.
    local left, bottom = self:GetLeft(), self:GetBottom()
    -- Compute the cursor-to-frame offset.
    dragOffsetX = cx - left
    -- Compute the cursor-to-frame offset.
    dragOffsetY = cy - bottom

    -- While dragging, update the position every frame.
    self:SetScript("OnUpdate", function(self)
        -- Re-read the cursor position.
        local nx, ny = GetCursorPosition()
        -- Re-apply the UI scale.
        local scale = UIParent:GetEffectiveScale()
        -- Corrected cursor position.
        nx, ny = nx / scale, ny / scale

        -- New frame position = cursor minus offset.
        local newLeft = nx - dragOffsetX
        -- New frame position = cursor minus offset.
        local newBottom = ny - dragOffsetY

        -- Current max icon count.
        local maxIcons = (SpellComboHistoryDB and SpellComboHistoryDB.maxIcons) or 6
        -- Current UI scale.
        local currentScale = self:GetScale()
        -- Visual size of icon 1 (the anchor).
        local visualIconSize = ICON_SIZE * currentScale
        -- Total offset including spacing (center of icon 1 to center of icon N).
        local totalOffset = (maxIcons - 1) * (ICON_SIZE + SPACING) * currentScale

        -- Anchor center derived from the current mouse position.
        local anchorCenterX = newLeft + visualIconSize / 2
        local anchorCenterY = newBottom + visualIconSize / 2

        -- Geometric center of the whole icon block.
        -- Icons extend to the left, so the block center sits half the total
        -- offset to the left of icon 1's center.
        local blockCenterX = anchorCenterX - (totalOffset / 2)
        local blockCenterY = anchorCenterY

        -- Screen width and height.
        local screenWidth = UIParent:GetWidth()
        local screenHeight = UIParent:GetHeight()

        -- Recompute the anchor's BOTTOMLEFT from the (snapped) block center.
        local finalAnchorCenterX = blockCenterX + (totalOffset / 2)
        local finalLeft = finalAnchorCenterX - visualIconSize / 2
        local finalBottom = blockCenterY - visualIconSize / 2

        -- Grid snap (align to 10px steps when enabled).
        if SpellComboHistoryDB.useGrid then
            finalLeft = math.floor(finalLeft / 10 + 0.5) * 10
            finalBottom = math.floor(finalBottom / 10 + 0.5) * 10
        end

        -- Clear the existing anchor points.
        self:ClearAllPoints()
        -- Reposition using the final computed coordinates.
        self:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", finalLeft, finalBottom)
    end)
end)

-- Script run when a drag stops.
anchor:SetScript("OnDragStop", function(self)
    -- Remove the per-frame update script.
    self:SetScript("OnUpdate", nil)
    -- Read the frame's final position.
    local point, relativeTo, relativePoint, xOfs, yOfs = self:GetPoint()
    -- Save the anchor point.
    SpellComboHistoryDB.point = point
    -- Save the X offset.
    SpellComboHistoryDB.x = xOfs
    -- Save the Y offset.
    SpellComboHistoryDB.y = yOfs
end)

-- Right-click to lock the position immediately.
anchor:SetScript("OnMouseDown", function(self, button)
    if button == "RightButton" then
        -- Enable the position lock.
        SpellComboHistoryDB.isLocked = true
        -- Disable mouse interaction.
        self:EnableMouse(false)
        -- Hide the guide frames and grid.
        UpdateDummyFrames(false)
        -- Sync the settings checkbox state.
        if _G["SpellComboHistoryLockCheck"] then
            _G["SpellComboHistoryLockCheck"]:SetChecked(true)
        end
        print("|cff00ccff[SpellCombo] |r" .. L["MSG_POSITION_LOCKED"])
    end
end)

-- High-level frame for the handle's text, so it draws above the icons.
anchor.textFrame = CreateFrame("Frame", nil, anchor)
anchor.textFrame:SetAllPoints()
anchor.textFrame:SetFrameLevel(100) -- above the icon frames
anchor.textFrame:EnableMouse(false) -- let clicks pass through to the anchor below

-- Text shown on the handle.
anchor.text = anchor.textFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
-- Move/lock instructions.
anchor.text:SetText(L["MOVE_HINT"])
-- Center the text.
anchor.text:SetJustifyH("CENTER")
-- The text frame is hidden by default.
anchor.textFrame:Hide()

-- Background texture spanning the whole icon bar.
anchor.mainBg = anchor:CreateTexture(nil, "BACKGROUND")
-- Default semi-transparent black.
anchor.mainBg:SetColorTexture(0, 0, 0, 0.5)

-- Refresh the background bar's size and transparency from settings.
local function UpdateMainBackground()
    -- Current max icon count.
    local maxIcons = (SpellComboHistoryDB and SpellComboHistoryDB.maxIcons) or 6
    -- Total width occupied by the icons.
    local blockWidth = ICON_SIZE + (maxIcons - 1) * (ICON_SIZE + SPACING)

    -- Clear the background's existing points.
    anchor.mainBg:ClearAllPoints()
    -- Top-right anchor (5px padding).
    anchor.mainBg:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", 5, 5)
    -- Bottom-left anchor at the end of the icon block (5px padding).
    anchor.mainBg:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", -(blockWidth - ICON_SIZE) - 5, -5)

    -- Read the configured background transparency.
    local alpha = (SpellComboHistoryDB and SpellComboHistoryDB.bgAlpha)
    -- Default to 0.5 when unset.
    if alpha == nil then alpha = 0.5 end
    -- Apply the final transparency.
    anchor.mainBg:SetColorTexture(0, 0, 0, alpha)
end

-- Show or hide the setup guides (used while unlocked).
function UpdateDummyFrames(show)
    -- When hiding the guides.
    if not show then
        -- Hide the instruction text frame.
        if anchor.textFrame then anchor.textFrame:Hide() end
        -- Restore the default mouse hit area.
        anchor:SetHitRectInsets(0, 0, 0, 0)
        -- Hide the grid.
        ToggleGrid(false)
        -- Restore icon mouse interaction.
        for i = 1, #icons do
            if icons[i] then icons[i]:EnableMouse(true) end
        end
        -- Done.
        return
    end

    -- Show the grid.
    ToggleGrid(true)

    -- Current max icon count.
    local maxIcons = (SpellComboHistoryDB and SpellComboHistoryDB.maxIcons) or 6
    -- Total width.
    local blockWidth = ICON_SIZE + (maxIcons - 1) * (ICON_SIZE + SPACING)
    -- Center the text over the whole icon block.
    anchor.text:ClearAllPoints()
    anchor.text:SetPoint("CENTER", anchor, "CENTER", -((blockWidth - ICON_SIZE) / 2), 0)
    -- Show the instruction text frame (drawn above the icons).
    anchor.textFrame:Show()

    -- Expand the draggable hit area to cover the whole bar.
    anchor:SetHitRectInsets(-(blockWidth - ICON_SIZE), 0, 0, 0)

    -- Disable icon mouse interaction so it does not block dragging.
    for i = 1, #icons do
        if icons[i] then
            icons[i]:EnableMouse(not show)
        end
    end
end

-- Create a single spell icon frame.
local function CreateIcon()
    -- New frame parented to the anchor (so it scales together).
    local f = CreateFrame("Frame", nil, anchor)
    -- Default icon size.
    f:SetSize(ICON_SIZE, ICON_SIZE)

    -- Texture object that shows the spell art.
    f.tex = f:CreateTexture(nil, "ARTWORK")
    -- Fill the frame with the texture.
    f.tex:SetAllPoints()

    -- Font string for the wasted time or PERFECT label.
    f.text = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    -- Place it just above the icon (5px padding).
    f.text:SetPoint("BOTTOM", f, "TOP", 0, 5)
    -- Default to red (wasted-time color).
    f.text:SetTextColor(1, 0, 0)

    -- Read the default font and size.
    local font, size = f.text:GetFont()
    -- Add an outline for readability.
    f.text:SetFont(font, size, "OUTLINE")
    -- Store the original font for later resizing.
    f.baseFont = font
    -- Store the original size.
    f.baseSize = size

    -- Separate font string for the combo tier label (STREAK, etc.).
    f.comboText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    -- Place it above the wasted-time text.
    f.comboText:SetPoint("BOTTOM", f.text, "TOP", 0, 2)
    -- Slightly smaller than the base font.
    f.comboText:SetFont(font, size * 0.9, "OUTLINE")
    -- Gold-ish color for the combo tier.
    f.comboText:SetTextColor(1, 0.8, 0)

    -- Enable mouse enter/leave events.
    f:EnableMouse(true)
    -- Show the spell tooltip on mouse-over.
    f:SetScript("OnEnter", function(self)
        -- Only if this icon has a spell ID.
        if self.spellID then
            -- Anchor the tooltip above the icon.
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            -- Load the spell's tooltip info.
            GameTooltip:SetSpellByID(self.spellID)
            -- Show the tooltip.
            GameTooltip:Show()
        end
    end)
    -- Hide the tooltip when the mouse leaves.
    f:SetScript("OnLeave", function(self)
        -- Hide the tooltip.
        GameTooltip:Hide()
    end)

    -- Hidden until used.
    f:Hide()
    -- Return the created icon frame.
    return f
end

-- Combo tiers: label and color by combo count.
local COMBO_LEVELS = {
    -- 50+ combo: legendary.
    {count = 50, text = L["COMBO_LEGEND"], color = {1, 0.2, 0.2}},
    -- 20+ combo: godlike.
    {count = 20, text = L["COMBO_GODLIKE"], color = {0, 1, 1}},
    -- 10+ combo: insane.
    {count = 10, text = L["COMBO_INSANE"], color = {1, 0.2, 0.8}},
    -- 5+ combo: rampage.
    {count = 5,  text = L["COMBO_RAMPAGE"], color = {1, 0.5, 0}},
    -- 2+ combo: streak.
    {count = 2,  text = L["COMBO_STREAK"],  color = {1, 0.8, 0}},
}

-- Return the label and color matching the current combo count.
local function GetComboTextAndColor(combo)
    -- Check tiers from highest to lowest.
    for _, level in ipairs(COMBO_LEVELS) do
        -- If the combo meets this tier's threshold.
        if combo >= level.count then
            -- Return "<count>\n<label>" plus the color.
            return combo .. "\n" .. level.text, unpack(level.color)
        end
    end
    -- Below the lowest threshold: nothing.
    return nil
end

-- Update the cast history and place icons on screen.
local function UpdateHistory(spellID, wasteTime, isOffGCD, isStart, isPerfect)
    -- Max icons to display.
    local maxIcons = (SpellComboHistoryDB and SpellComboHistoryDB.maxIcons) or 6
    -- Shift existing icons one slot to the left (reverse order).
    for i = maxIcons, 2, -1 do
        -- If the previous slot has a visible icon.
        if icons[i-1] and icons[i-1]:IsShown() then
            -- Create this slot's icon if missing.
            if not icons[i] then icons[i] = CreateIcon() end
            -- Copy the previous slot's spell art.
            icons[i].tex:SetTexture(icons[i-1].tex:GetTexture())
            -- Copy the previous slot's wasted-time text.
            icons[i].text:SetText(icons[i-1].text:GetText())
            -- Copy the previous slot's text color.
            icons[i].text:SetTextColor(icons[i-1].text:GetTextColor())
            -- Copy the previous slot's combo tier text.
            icons[i].comboText:SetText(icons[i-1].comboText:GetText())
            -- Copy the previous slot's combo tier color.
            icons[i].comboText:SetTextColor(icons[i-1].comboText:GetTextColor())
            -- Copy the previous slot's spell ID (for tooltips).
            icons[i].spellID = icons[i-1].spellID

            -- Copy the previous slot's font settings (size, flags, ...).
            local font, size, flags = icons[i-1].text:GetFont()
            -- Apply them to this slot.
            icons[i].text:SetFont(font, size, flags)

            -- Push this slot further left from the anchor.
            icons[i]:SetPoint("CENTER", anchor, "CENTER", -((i-1) * (ICON_SIZE + SPACING)), 0)
            -- Show the icon.
            icons[i]:Show()
        end
    end

    -- Create slot 1 (the latest spell) if missing.
    if not icons[1] then
        -- New icon.
        icons[1] = CreateIcon()
    end
    -- Place icon 1 at the anchor center.
    icons[1]:SetPoint("CENTER", anchor, "CENTER", 0, 0)

    -- Texture ID for the new spell's icon.
    local tex
    -- Try the modern spell info API.
    if C_Spell and C_Spell.GetSpellInfo then
        -- Fetch spell info.
        local spellInfo = C_Spell.GetSpellInfo(spellID)
        -- Extract the icon ID if present.
        tex = spellInfo and spellInfo.iconID
    else
        -- Fetch the icon via the legacy API.
        local _
        _, _, tex = GetSpellInfo(spellID)
    end
    -- Apply the spell art to icon 1.
    icons[1].tex:SetTexture(tex)
    -- Store the spell ID on icon 1.
    icons[1].spellID = spellID

    -- Re-check the player's combat state.
    local inCombat = InCombatLockdown() or UnitAffectingCombat("player")
    -- Local reference to icon 1.
    local icon1 = icons[1]
    -- Local references to the text objects.
    local txt, comboTxt = icon1.text, icon1.comboText

    -- This spell starts/restarts a combo.
    if isStart then
        -- Slightly smaller font for emphasis.
        txt:SetFont(icon1.baseFont, icon1.baseSize * 0.8, "OUTLINE")
        -- Blue-ish color.
        txt:SetTextColor(0, 0.6, 1)
        -- Show START or RESTART.
        txt:SetText(isStart)
        -- Hide the combo tier (it just reset).
        comboTxt:SetText("")
    -- Out of combat, or an off-GCD utility spell.
    elseif not inCombat or isOffGCD then
        -- Hide the wasted-time text.
        txt:SetText("")
        -- Hide the combo tier text.
        comboTxt:SetText("")
    -- Missed PERFECT and there is wasted time.
    elseif wasteTime and not isPerfect then
        -- Restore the base font size.
        txt:SetFont(icon1.baseFont, icon1.baseSize, "OUTLINE")
        -- Red to signal the waste.
        txt:SetTextColor(1, 0, 0)
        -- Show the wasted time to two decimals.
        txt:SetText(string.format("%.2fs", wasteTime))
        -- Combo broke, so hide the tier text.
        comboTxt:SetText("")
    -- PERFECT.
    else
        -- Smaller font to keep it tidy.
        txt:SetFont(icon1.baseFont, icon1.baseSize * 0.8, "OUTLINE")
        -- Green to signal success.
        txt:SetTextColor(0, 1, 0)
        -- Show PERFECT.
        txt:SetText(L["PERFECT"])
        -- Get the tier label and color for the current combo.
        local comboStr, r, g, b = GetComboTextAndColor(perfectCombo)
        -- Show the label if any, otherwise blank.
        comboTxt:SetText(comboStr or "")
        -- Apply the tier color only when there is a label.
        if comboStr then comboTxt:SetTextColor(r, g, b) end
    end
    -- Finally show icon 1.
    icon1:Show()
end

-- Build the addon's settings panel.
local function InitializeOptions()
    local panel = CreateFrame("Frame", "SpellComboHistoryOptionsPanel")
    panel.name = "SpellComboHistory"

    -- [1] Scroll frame.
    local scrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 10, -10)
    scrollFrame:SetPoint("BOTTOMRIGHT", -30, 10)

    -- [2] Content frame that actually holds the widgets.
    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(600, 750) -- adjust this height if you add more settings
    scrollFrame:SetScrollChild(content)

    -- Title.
    local title = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -20)
    title:SetText(L["OPTIONS_TITLE"])

    -- Restart timeout slider.
    local slider = CreateFrame("Slider", "SpellComboHistoryRestartSlider", content, "OptionsSliderTemplate")
    slider:SetPoint("TOP", 0, -80)
    slider:SetMinMaxValues(1, 60)
    slider:SetValueStep(1)
    slider:SetObeyStepOnDrag(true)
    slider:SetValue(SpellComboHistoryDB.restartTimeout)
    _G[slider:GetName() .. "Low"]:SetText("1s")
    _G[slider:GetName() .. "High"]:SetText("60s")
    _G[slider:GetName() .. "Text"]:SetText(L["RESTART_TIMEOUT"] .. ": " .. SpellComboHistoryDB.restartTimeout .. "s")
    slider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value)
        SpellComboHistoryDB.restartTimeout = value
        _G[self:GetName() .. "Text"]:SetText(L["RESTART_TIMEOUT"] .. ": " .. value .. "s")
    end)

    -- Lock position checkbox.
    local lockCheck = CreateFrame("CheckButton", "SpellComboHistoryLockCheck", content, "ChatConfigCheckButtonTemplate")
    lockCheck:SetPoint("TOP", -80, -130)
    _G[lockCheck:GetName() .. "Text"]:SetText(L["LOCK_POSITION"])
    lockCheck:SetChecked(SpellComboHistoryDB.isLocked)
    lockCheck:SetScript("OnClick", function(self)
        local isLocked = self:GetChecked()
        SpellComboHistoryDB.isLocked = isLocked
        anchor:EnableMouse(not isLocked)
        UpdateDummyFrames(not isLocked)
    end)

    -- Grid mode checkbox.
    local gridCheck = CreateFrame("CheckButton", "SpellComboHistoryGridCheck", content, "ChatConfigCheckButtonTemplate")
    gridCheck:SetPoint("TOP", -80, -165)
    _G[gridCheck:GetName() .. "Text"]:SetText(L["USE_GRID_SNAP"])
    gridCheck:SetChecked(SpellComboHistoryDB.useGrid)
    gridCheck:SetScript("OnClick", function(self)
        local useGrid = self:GetChecked()
        SpellComboHistoryDB.useGrid = useGrid
        if not SpellComboHistoryDB.isLocked then
            ToggleGrid(useGrid)
        end
    end)

    -- Max icons slider.
    local maxIconsSlider = CreateFrame("Slider", "SpellComboHistoryMaxIconsSlider", content, "OptionsSliderTemplate")
    maxIconsSlider:SetPoint("TOP", 0, -220)
    maxIconsSlider:SetMinMaxValues(4, 12)
    maxIconsSlider:SetValueStep(1)
    maxIconsSlider:SetObeyStepOnDrag(true)
    maxIconsSlider:SetValue(SpellComboHistoryDB.maxIcons)
    _G[maxIconsSlider:GetName() .. "Low"]:SetText("4")
    _G[maxIconsSlider:GetName() .. "High"]:SetText("12")
    _G[maxIconsSlider:GetName() .. "Text"]:SetText(L["MAX_ICONS"] .. ": " .. SpellComboHistoryDB.maxIcons)
    maxIconsSlider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value)
        SpellComboHistoryDB.maxIcons = value
        _G[self:GetName() .. "Text"]:SetText(L["MAX_ICONS"] .. ": " .. value)
        for i = value + 1, #icons do
            if icons[i] then icons[i]:Hide() end
        end
        if not SpellComboHistoryDB.isLocked then
            UpdateDummyFrames(true)
        end
        UpdateMainBackground()
    end)

    -- Background transparency slider.
    local bgAlphaSlider = CreateFrame("Slider", "SpellComboHistoryBgAlphaSlider", content, "OptionsSliderTemplate")
    bgAlphaSlider:SetPoint("TOP", 0, -290)
    bgAlphaSlider:SetMinMaxValues(0, 1)
    bgAlphaSlider:SetValueStep(0.05)
    bgAlphaSlider:SetObeyStepOnDrag(true)
    bgAlphaSlider:SetValue(SpellComboHistoryDB.bgAlpha or 0.5)
    _G[bgAlphaSlider:GetName() .. "Low"]:SetText("0%")
    _G[bgAlphaSlider:GetName() .. "High"]:SetText("100%")
    local alphaPercent = math.floor((SpellComboHistoryDB.bgAlpha or 0.5) * 100)
    _G[bgAlphaSlider:GetName() .. "Text"]:SetText(L["BG_TRANSPARENCY"] .. ": " .. alphaPercent .. "%")
    bgAlphaSlider:SetScript("OnValueChanged", function(self, value)
        SpellComboHistoryDB.bgAlpha = value
        local percent = math.floor(value * 100)
        _G[self:GetName() .. "Text"]:SetText(L["BG_TRANSPARENCY"] .. ": " .. percent .. "%")
        UpdateMainBackground()
    end)

    -- UI scale slider (keeps aspect ratio).
    local uiScaleSlider = CreateFrame("Slider", "SpellComboHistoryUiScaleSlider", content, "OptionsSliderTemplate")
    uiScaleSlider:SetPoint("TOP", 0, -360)
    uiScaleSlider:SetMinMaxValues(0.5, 2.0)
    uiScaleSlider:SetValueStep(0.05)
    uiScaleSlider:SetObeyStepOnDrag(true)
    uiScaleSlider:SetValue(SpellComboHistoryDB.uiScale or 1.0)
    _G[uiScaleSlider:GetName() .. "Low"]:SetText("50%")
    _G[uiScaleSlider:GetName() .. "High"]:SetText("200%")
    local scalePercent = math.floor((SpellComboHistoryDB.uiScale or 1.0) * 100)
    _G[uiScaleSlider:GetName() .. "Text"]:SetText(L["UI_SCALE"] .. ": " .. scalePercent .. "%")
    uiScaleSlider:SetScript("OnValueChanged", function(self, value)
        SpellComboHistoryDB.uiScale = value
        local percent = math.floor(value * 100)
        _G[self:GetName() .. "Text"]:SetText(L["UI_SCALE"] .. ": " .. percent .. "%")
        anchor:SetScale(value)
    end)

    -- Spell queue window slider.
    local queueSlider = CreateFrame("Slider", "SpellComboHistoryQueueSlider", content, "OptionsSliderTemplate")
    queueSlider:SetPoint("TOP", 0, -450)
    queueSlider:SetMinMaxValues(0, 400)
    queueSlider:SetValueStep(10)
    queueSlider:SetObeyStepOnDrag(true)
    local currentQueue = tonumber(GetCVar("SpellQueueWindow")) or 400
    queueSlider:SetValue(currentQueue)
    _G[queueSlider:GetName() .. "Low"]:SetText("0ms")
    _G[queueSlider:GetName() .. "High"]:SetText("400ms")
    _G[queueSlider:GetName() .. "Text"]:SetText(L["SPELL_QUEUE_WINDOW"] .. ": " .. currentQueue .. "ms")
    queueSlider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value)
        SetCVar("SpellQueueWindow", value)
        _G[self:GetName() .. "Text"]:SetText(L["SPELL_QUEUE_WINDOW"] .. ": " .. value .. "ms")
    end)

    -- Help text.
    local helpText = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    helpText:SetPoint("TOP", queueSlider, "BOTTOM", 0, -20)
    helpText:SetJustifyH("CENTER")
    helpText:SetText(L["QUEUE_HELP"])

    -- Button to print the current value.
    local checkButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    checkButton:SetSize(200, 30)
    checkButton:SetPoint("TOP", helpText, "BOTTOM", 0, -15)
    checkButton:SetText(L["CHECK_CURRENT"])
    checkButton:SetScript("OnClick", function()
        local val = GetCVar("SpellQueueWindow")
        print("|cff00ccff[SpellCombo] |r" .. L["MSG_CURRENT_QUEUE"] .. " |cffffffff" .. val .. "ms")
    end)
    -- Button to clear the history.
    local clearButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    clearButton:SetSize(200, 30)
    clearButton:SetPoint("TOP", checkButton, "BOTTOM", 0, -10)
    clearButton:SetText(L["CLEAR_HISTORY"])
    clearButton:SetScript("OnClick", function()
        for i = 1, #icons do
            if icons[i] then
                icons[i]:Hide()
                icons[i].spellID = nil
            end
        end
        perfectCombo = 0
        print("|cff00ccff[SpellCombo] |r" .. L["MSG_HISTORY_CLEARED"])
    end)

    -- Button to reset the position.
    local resetPosButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    resetPosButton:SetSize(200, 30)
    resetPosButton:SetPoint("TOP", clearButton, "BOTTOM", 0, -10)
    resetPosButton:SetText(L["RESET_POSITION"])
    resetPosButton:SetScript("OnClick", function()
        -- Move the frame to screen center.
        anchor:ClearAllPoints()
        anchor:SetPoint("CENTER", UIParent, "CENTER", 0, 0)

        -- Save the current position.
        local point, _, _, x, y = anchor:GetPoint()
        SpellComboHistoryDB.point = point
        SpellComboHistoryDB.x = x
        SpellComboHistoryDB.y = y

        print("|cff00ccff[SpellCombo] |r" .. L["MSG_POSITION_RESET"])
    end)

    if Settings and Settings.RegisterCanvasLayoutCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
        Settings.RegisterAddOnCategory(category)
    else
        InterfaceOptions_AddCategory(panel)
    end

end

-- [Main analysis] State used to group a frame's spells and grade GCD/combo.
local pendingCasts = {}
-- Additional events.
frame:RegisterEvent("ADDON_LOADED")
-- Spell cast start event.
frame:RegisterEvent("UNIT_SPELLCAST_START")
-- Combat end event.
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
-- Combat start event.
frame:RegisterEvent("PLAYER_REGEN_DISABLED")
-- Pet battle events.
frame:RegisterEvent("PET_BATTLE_OPENING_START")
frame:RegisterEvent("PET_BATTLE_CLOSE")

-- Temporary basket for spells collected within one frame.
local frameSpells = {}
-- Timer handle that runs analysis after a 0.01s wait.
local processingTimer = nil

-- Core function: analyze a frame's spells to find GCD ownership and compute
-- combo / wasted time.
local function ProcessFrameSpells()
    -- Reset the timer state for the next batch.
    processingTimer = nil
    -- Reference the accumulated spell basket.
    local spells = frameSpells
    -- Empty the original basket.
    frameSpells = {}

    -- Current state of the shared GCD bar (61304).
    local currentStart = 0
    -- Shared GCD duration.
    local currentDuration = 0
    -- Try the modern API.
    if C_Spell and C_Spell.GetSpellCooldown then
        -- Get info for 61304 (the dummy spell used for the global cooldown).
        local cooldownInfo = C_Spell.GetSpellCooldown(61304)
        -- Assign each field when present.
        if cooldownInfo then
            currentStart = cooldownInfo.startTime
            currentDuration = cooldownInfo.duration
        end
    else
        -- Get GCD info via the legacy API.
        local start, duration = GetSpellCooldown(61304)
        -- Assign the start.
        currentStart = start or 0
        -- Assign the duration.
        currentDuration = duration or 0
    end

    -- Detect whether a new GCD cycle began (0.1s threshold).
    local gcdTriggered = false
    -- Only count as a new trigger if the start time is valid and differs from
    -- the previous record by at least 0.1s.
    if currentStart > 0 and math.abs(currentStart - lastGcdStartTime) >= 0.1 then
        -- New GCD trigger confirmed.
        gcdTriggered = true
    end

    -- Which spell in this frame actually "owns" the GCD.
    local gcdSpellIndex = -1
    -- If a new GCD just started.
    if gcdTriggered then
        -- Scan the spells in order.
        for i = 1, #spells do
            -- Pull out one spell.
            local sp = spells[i]
            -- A cast (with a cast time) is the first candidate for ownership.
            if sp.castStartTime then
                -- Mark it as the owner.
                gcdSpellIndex = i
                -- Stop searching.
                break
            end

            -- Get this spell's own current cooldown duration.
            local d = GetSpellCooldownDuration(sp.spellID)

            -- Use pcall to guard the numeric comparison.
            if pcall(function() return d + 0 end) then
                -- If this spell's duration ~matches the shared GCD (within 0.01s).
                if d > 0 and currentDuration > 0 and math.abs(d - currentDuration) < 0.01 then
                    -- This spell is the owner.
                    gcdSpellIndex = i
                    -- Stop searching.
                    break
                end
            end
        end

        -- If no exact match was found (off by more than 0.01s).
        if gcdSpellIndex == -1 then
            -- Scan again with a looser criterion.
            for i = 1, #spells do
                -- Pull out the spell.
                local sp = spells[i]
                -- Get its duration.
                local d = GetSpellCooldownDuration(sp.spellID)

                -- Guard the comparison again.
                if pcall(function() return d + 0 end) then
                    -- If its duration is >= the shared GCD (or about equal).
                    if d >= currentDuration - 0.01 then
                        -- Choose it as the owner.
                        gcdSpellIndex = i
                        -- Stop searching.
                        break
                    end
                end
            end
        end

        -- If no owner was found after all attempts (possible on very fast input).
        if gcdSpellIndex == -1 then
            -- Fall back to the first spell as the owner.
            gcdSpellIndex = 1
        end
    end

    -- Use world ping to set the PERFECT threshold.
    local _, _, _, lagWorld = GetNetStats()
    -- Convert milliseconds to seconds (e.g. 50ms -> 0.05s).
    local threshold = lagWorld / 1000

    -- Final grading and UI output for each spell in the basket.
    for i, sp in ipairs(spells) do
        -- Whether this spell has a global cooldown per the game data.
        local _, gcdMS = GetSpellBaseCooldown(sp.spellID)
        -- A GCD value of 0 means an off-GCD spell.
        local isOffGCD = (gcdMS == 0)

        -- A spell with a cast time is always treated as a GCD spell.
        if sp.castStartTime then
            -- Force off-GCD to false.
            isOffGCD = false
        end

        -- Wasted time since the previous spell.
        local wasteTime = 0
        -- Current system time.
        local now = GetTime()
        -- Use the cast start time for casts, otherwise "now" for instants.
        local actionStartTime = sp.castStartTime or now
        -- Whether this is a (re)start.
        local isStart = false
        -- Whether this was a PERFECT.
        local isPerfect = false
        -- Diff against the last channel end (init large).
        local channelWaste = 999

        -- Re-check actual combat state.
        local inCombat = InCombatLockdown() or UnitAffectingCombat("player")

        -- Only run combo logic while in combat.
        if inCombat then
            -- First spell right after entering combat.
            if pendingStart then
                -- Show START.
                isStart = L["START"]
                -- Clear the pending flag.
                pendingStart = false
                -- Start the combo count.
                perfectCombo = 1
                -- Reset the channel end record.
                lastChannelEndTime = 0
                -- The first spell always counts as PERFECT.
                isPerfect = true
            -- A GCD spell with a valid start time.
            elseif not isOffGCD and actionStartTime > 0 then
                -- Restart timeout from settings (default 10s).
                local timeout = (SpellComboHistoryDB and SpellComboHistoryDB.restartTimeout) or 10

                -- No prior data, or the spell came after a long gap (timeout).
                if lastGcdEndTime == 0 or actionStartTime > lastGcdEndTime + timeout then
                    -- Use START or RESTART as appropriate.
                    isStart = (lastGcdEndTime == 0) and L["START"] or L["RESTART"]
                    -- Reset the combo count to 1.
                    perfectCombo = 1
                    -- The first spell of a restart counts as PERFECT.
                    isPerfect = true
                -- Normal consecutive use (combo in progress).
                else
                    -- [Step 5] Compute wasteTime and grade PERFECT.
                    if actionStartTime > lastGcdEndTime then
                        -- Actual wasted time.
                        wasteTime = actionStartTime - lastGcdEndTime
                    end

                    -- PERFECT if the wasted time is within the ping threshold.
                    isPerfect = (wasteTime <= threshold)

                    -- Or PERFECT if it roughly matches the last channel end.
                    if not isPerfect and lastChannelEndTime > 0 then
                        channelWaste = math.abs(actionStartTime - lastChannelEndTime)
                        if channelWaste <= threshold then
                            isPerfect = true
                        end
                    end

                    -- +1 on success, reset to 0 on failure.
                    perfectCombo = isPerfect and (perfectCombo + 1) or 0
                end
            end

            -- If this spell was a GCD spell, update timers for the next one.
            if not isOffGCD and actionStartTime > 0 then
                -- Sync the last GCD start to the current arrival time.
                lastGcdStartTime = now

                -- Record when this spell's GCD will end (for the next PERFECT check).
                if sp.castStartTime then
                    -- For casts, the success time is the GCD end time.
                    lastGcdEndTime = now
                else
                    -- For instants, end = arrival time + shared GCD duration.
                    lastGcdEndTime = now + currentDuration
                end
            end
        else
            -- Out of combat: reset records to avoid stale data.
            perfectCombo = 0
            -- Reset wasted time.
            wasteTime = 0
            -- Reset grade.
            isPerfect = false
        end

        -- Send all the info (spell ID, waste, off-GCD, ...) to refresh the UI.
        UpdateHistory(sp.spellID, wasteTime, isOffGCD, isStart, isPerfect)
    end
end

-- Final event handler registration.
frame:SetScript("OnEvent", function(self, event, unit, castID, spellID)
    -- On first load (login).
    if event == "ADDON_LOADED" and unit == "SpellComboHistory" then
        -- Create the saved-variables table if missing.
        SpellComboHistoryDB = SpellComboHistoryDB or {}
        -- Default restart timeout.
        if SpellComboHistoryDB.restartTimeout == nil then SpellComboHistoryDB.restartTimeout = 10 end
        -- Default lock state.
        if SpellComboHistoryDB.isLocked == nil then SpellComboHistoryDB.isLocked = true end
        -- Default max icon count.
        if SpellComboHistoryDB.maxIcons == nil then SpellComboHistoryDB.maxIcons = 6 end
        -- Default background transparency.
        if SpellComboHistoryDB.bgAlpha == nil then SpellComboHistoryDB.bgAlpha = 0.5 end
        -- Default UI scale.
        if SpellComboHistoryDB.uiScale == nil then SpellComboHistoryDB.uiScale = 1.0 end
        -- Default grid mode.
        if SpellComboHistoryDB.useGrid == nil then SpellComboHistoryDB.useGrid = true end

        -- Apply the UI scale.
        anchor:SetScale(SpellComboHistoryDB.uiScale)

        -- Restore the saved position if any.
        if SpellComboHistoryDB.point then
            -- Clear existing points.
            anchor:ClearAllPoints()
            -- Apply the saved anchor and offsets.
            anchor:SetPoint(SpellComboHistoryDB.point, UIParent, SpellComboHistoryDB.point, SpellComboHistoryDB.x, SpellComboHistoryDB.y)
        end

        -- Enable/disable mouse input based on lock state.
        anchor:EnableMouse(not SpellComboHistoryDB.isLocked)
        -- Show the setup guides if unlocked.
        UpdateDummyFrames(not SpellComboHistoryDB.isLocked)
        -- Refresh the background bar size and transparency.
        UpdateMainBackground()

        -- Build the options panel.
        InitializeOptions()
        -- Done.
        return
    end
    -- When the player leaves combat.
    if event == "PLAYER_REGEN_ENABLED" then
        -- Clear the start flag.
        pendingStart = false
        -- Reset the last GCD end record.
        lastGcdEndTime = 0
        -- Reset the last GCD start record.
        lastGcdStartTime = 0
        -- Reset the combo count.
        perfectCombo = 0
        -- Reset the channel end record.
        lastChannelEndTime = 0
        -- Done.
        return
    end
    -- When the player enters combat.
    if event == "PLAYER_REGEN_DISABLED" then
        -- Flag the next spell as START.
        pendingStart = true
        -- Reset the channel end record.
        lastChannelEndTime = 0
        -- Done.
        return
    end

    -- Hide the addon during pet battles.
    if event == "PET_BATTLE_OPENING_START" then
        anchor:Hide()
        return
    end
    -- Show the addon again after pet battles.
    if event == "PET_BATTLE_CLOSE" then
        anchor:Show()
        return
    end

    -- Ignore events that are not about the player.
    if unit ~= "player" then return end

    -- A cast or channel started.
    if event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START" then
        -- Record the start time keyed by cast ID (compared on success later).
        if castID then
            pendingCasts[castID] = GetTime()
        end
        -- Done.
        return
    end

    -- A channel ended (naturally or interrupted).
    if event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        -- Record the current time as the channel end.
        lastChannelEndTime = GetTime()
        -- Done.
        return
    end

    -- A spell cast finally succeeded.
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        -- Only count spells the player actually knows (filters trinket procs,
        -- internal talent auras, etc.).
        local isPlayerSpell = (C_SpellBook and C_SpellBook.IsSpellInSpellBook and C_SpellBook.IsSpellInSpellBook(spellID))
                           or (IsPlayerSpell and IsPlayerSpell(spellID))

        -- Not a player spell: nothing to do.
        if not isPlayerSpell then
            -- Drop the cast data.
            if castID then
                pendingCasts[castID] = nil
            end
            -- Done.
            return
        end

        -- [1] Read the recorded cast start time (if any) and clear it.
        local castStartTime = castID and pendingCasts[castID]
        -- Discard the data.
        if castID then
            pendingCasts[castID] = nil
        end

        -- [2] Capture the GCD (61304) start time at success (sync helper data).
        local syncStart = 0
        -- Modern API.
        if C_Spell and C_Spell.GetSpellCooldown then
            -- Get the GCD bar info.
            local cd = C_Spell.GetSpellCooldown(61304)
            -- Assign the start time.
            if cd then syncStart = cd.startTime end
        else
            -- Legacy API.
            local s = GetSpellCooldown(61304)
            -- Assign the start time.
            syncStart = s or 0
        end

        -- [3] Add the spell info to this frame's basket.
        table.insert(frameSpells, {spellID = spellID, castStartTime = castStartTime, syncStart = syncStart})

        -- [4] Arm the 0.01s analysis timer if not already running.
        if not processingTimer then
            -- Run the core analysis after 0.01s.
            processingTimer = C_Timer.After(0.01, ProcessFrameSpells)
        end
    end
end)
