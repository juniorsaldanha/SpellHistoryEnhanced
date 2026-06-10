-- HistoryBar.lua - the on-screen icon bar (display manager).
--
-- Owns a pool of reusable icon frames and an ordered queue of active icons
-- (index 1 = newest). It computes each icon's target slot position and sets
-- its content, but delegates ALL motion to whichever animation strategy the
-- settings currently select. It depends only on the strategy interface, never
-- on a concrete animation, and receives its collaborators through Init().
local _, ns = ...
local L = ns.L

-- Localized globals.
local CreateFrame = CreateFrame
local GameTooltip = GameTooltip
local InCombatLockdown = InCombatLockdown
local UnitAffectingCombat = UnitAffectingCombat
local C_Spell = C_Spell
local GetSpellInfo = GetSpellInfo or function(id) return C_Spell.GetSpellInfo(id) end
local wipe = wipe
local format = string.format

local HistoryBar = {}
ns.HistoryBar = HistoryBar

-- ---------------------------------------------------------------------------
-- Combo tiers: label and color by combo count (a display concern).
-- ---------------------------------------------------------------------------
local COMBO_LEVELS = {
    { count = 50, text = L["COMBO_LEGEND"],  color = {1, 0.2, 0.2} },
    { count = 20, text = L["COMBO_GODLIKE"], color = {0, 1, 1} },
    { count = 10, text = L["COMBO_INSANE"],  color = {1, 0.2, 0.8} },
    { count = 5,  text = L["COMBO_RAMPAGE"], color = {1, 0.5, 0} },
    { count = 2,  text = L["COMBO_STREAK"],  color = {1, 0.8, 0} },
}

-- Return "<count>\n<label>" plus its color for the current combo, or nil.
local function GetComboTextAndColor(combo)
    for _, level in ipairs(COMBO_LEVELS) do
        if combo >= level.count then
            return combo .. "\n" .. level.text, unpack(level.color)
        end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- Setup.
-- ---------------------------------------------------------------------------

-- opts: anchor, iconSize, spacing, getMaxIcons, getAnimation, getDuration.
function HistoryBar:Init(opts)
    self.anchor = opts.anchor
    self.iconSize = opts.iconSize
    self.spacing = opts.spacing
    self.step = opts.iconSize + opts.spacing
    self.getMaxIcons = opts.getMaxIcons
    self.getAnimation = opts.getAnimation
    self.getDuration = opts.getDuration
    self.active = {}      -- ordered, index 1 = newest
    self.pool = {}        -- free icons ready to reuse
    self.interactive = false
end

-- Build a single icon frame. The frame carries its own animatable `state`
-- and an Apply() method that pushes that state onto the real frame.
function HistoryBar:CreateIcon()
    local anchor = self.anchor
    local f = CreateFrame("Frame", nil, anchor)
    f:SetSize(self.iconSize, self.iconSize)

    -- Spell art.
    f.tex = f:CreateTexture(nil, "ARTWORK")
    f.tex:SetAllPoints()

    -- Wasted-time / PERFECT label.
    f.text = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.text:SetPoint("BOTTOM", f, "TOP", 0, 5)
    f.text:SetTextColor(1, 0, 0)
    local font, size = f.text:GetFont()
    f.text:SetFont(font, size, "OUTLINE")
    f.baseFont = font
    f.baseSize = size

    -- Combo tier label.
    f.comboText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.comboText:SetPoint("BOTTOM", f.text, "TOP", 0, 2)
    f.comboText:SetFont(font, size * 0.9, "OUTLINE")
    f.comboText:SetTextColor(1, 0.8, 0)

    -- Tooltip on hover.
    f:EnableMouse(true)
    f:SetScript("OnEnter", function(self)
        if self.spellID then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetSpellByID(self.spellID)
            GameTooltip:Show()
        end
    end)
    f:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- Animatable state and how to apply it.
    f.state = { x = 0, y = 0, alpha = 1, scale = 1 }
    function f:Apply()
        local s = self.state
        self:ClearAllPoints()
        self:SetPoint("CENTER", anchor, "CENTER", s.x, s.y)
        local a = s.alpha
        if a < 0 then a = 0 elseif a > 1 then a = 1 end
        self:SetAlpha(a)
        self:SetScale(s.scale)
    end

    f:Hide()
    return f
end

-- ---------------------------------------------------------------------------
-- Pool management.
-- ---------------------------------------------------------------------------
function HistoryBar:Acquire()
    local icon = table.remove(self.pool)
    if not icon then icon = self:CreateIcon() end
    local s = icon.state
    s.x, s.y, s.alpha, s.scale = 0, 0, 1, 1
    icon:EnableMouse(self.interactive)
    icon:Show()
    return icon
end

function HistoryBar:Release(icon)
    ns.Tween:Stop(icon)
    icon:Hide()
    icon.spellID = nil
    icon.text:SetText("")
    icon.comboText:SetText("")
    table.insert(self.pool, icon)
end

-- Target offset (from the anchor center) for a 0-based slot index.
function HistoryBar:TargetOffset(slot)
    return -(slot * self.step), 0
end

-- ---------------------------------------------------------------------------
-- Content.
-- ---------------------------------------------------------------------------
function HistoryBar:ConfigureContent(icon, spellID, wasteTime, isOffGCD, isStart, isPerfect, comboCount)
    -- Spell texture.
    local tex
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(spellID)
        tex = info and info.iconID
    else
        local _
        _, _, tex = GetSpellInfo(spellID)
    end
    icon.tex:SetTexture(tex)
    icon.spellID = spellID

    local inCombat = InCombatLockdown() or UnitAffectingCombat("player")
    local txt, comboTxt = icon.text, icon.comboText

    if isStart then
        -- (Re)start of a combo.
        txt:SetFont(icon.baseFont, icon.baseSize * 0.8, "OUTLINE")
        txt:SetTextColor(0, 0.6, 1)
        txt:SetText(isStart)
        comboTxt:SetText("")
    elseif not inCombat or isOffGCD then
        -- Out of combat or an off-GCD utility: no grade.
        txt:SetText("")
        comboTxt:SetText("")
    elseif wasteTime and not isPerfect then
        -- Missed PERFECT: show the wasted time.
        txt:SetFont(icon.baseFont, icon.baseSize, "OUTLINE")
        txt:SetTextColor(1, 0, 0)
        txt:SetText(format("%.2fs", wasteTime))
        comboTxt:SetText("")
    else
        -- PERFECT, with the matching combo tier.
        txt:SetFont(icon.baseFont, icon.baseSize * 0.8, "OUTLINE")
        txt:SetTextColor(0, 1, 0)
        txt:SetText(L["PERFECT"])
        local comboStr, r, g, b = GetComboTextAndColor(comboCount)
        comboTxt:SetText(comboStr or "")
        if comboStr then comboTxt:SetTextColor(r, g, b) end
    end
end

-- ---------------------------------------------------------------------------
-- Public operations.
-- ---------------------------------------------------------------------------

-- Add a new cast to the front of the bar and animate everything into place.
function HistoryBar:Push(spellID, wasteTime, isOffGCD, isStart, isPerfect, comboCount)
    local strat = self.getAnimation()
    local duration = self.getDuration()
    local maxIcons = self.getMaxIcons()

    local icon = self:Acquire()
    self:ConfigureContent(icon, spellID, wasteTime, isOffGCD, isStart, isPerfect, comboCount)
    table.insert(self.active, 1, icon)

    -- Drop anything past the limit (animated out below).
    local removed = {}
    while #self.active > maxIcons do
        table.insert(removed, table.remove(self.active))
    end

    -- Animate the new icon in and shift the rest.
    for i, ic in ipairs(self.active) do
        local tx, ty = self:TargetOffset(i - 1)
        if ic == icon then
            strat.PlayIn(self, ic, tx, ty, duration)
        else
            strat.PlayMove(self, ic, tx, ty, duration)
        end
    end

    -- Animate the overflow out, releasing each icon when it finishes.
    for _, old in ipairs(removed) do
        strat.PlayOut(self, old, duration, function() self:Release(old) end)
    end
end

-- Re-apply slot positions (e.g. after the max-icons setting changes).
function HistoryBar:Relayout()
    local strat = self.getAnimation()
    local duration = self.getDuration()
    local maxIcons = self.getMaxIcons()

    local removed = {}
    while #self.active > maxIcons do
        table.insert(removed, table.remove(self.active))
    end
    for i, ic in ipairs(self.active) do
        local tx, ty = self:TargetOffset(i - 1)
        strat.PlayMove(self, ic, tx, ty, duration)
    end
    for _, old in ipairs(removed) do
        strat.PlayOut(self, old, duration, function() self:Release(old) end)
    end
end

-- Remove every icon immediately (no animation).
function HistoryBar:Clear()
    for _, ic in ipairs(self.active) do
        self:Release(ic)
    end
    wipe(self.active)
end

-- Enable/disable mouse interaction on the icons (used while repositioning).
function HistoryBar:SetInteractive(enabled)
    self.interactive = enabled
    for _, ic in ipairs(self.active) do
        ic:EnableMouse(enabled)
    end
end
