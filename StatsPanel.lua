-- StatsPanel.lua - optional movable on-screen statistics readout.
--
-- A thin view over ns.Stats: it owns a movable/lockable frame and refreshes
-- its labels on a throttled OnUpdate while shown. It reads its data from
-- ns.Stats and its show/lock/position from the saved variables passed to Init.
local _, ns = ...
local L = ns.L

local CreateFrame = CreateFrame
local UIParent = UIParent
local floor = math.floor
local format = string.format

local StatsPanel = {}
ns.StatsPanel = StatsPanel

-- The rows shown, top to bottom. `key` matches ns.Stats:Get() / formatting.
local ROWS = {
    { key = "uptime",  labelKey = "STATS_UPTIME" },
    { key = "perfect", labelKey = "PERFECT" },
    { key = "best",    labelKey = "STATS_BEST_COMBO" },
    { key = "avg",     labelKey = "STATS_AVG_WASTE" },
    { key = "casts",   labelKey = "STATS_CASTS" },
    { key = "session", labelKey = "STATS_SESSION" },
}

local function fmtDuration(sec)
    sec = floor(sec)
    return format("%d:%02d", floor(sec / 60), sec % 60)
end

local function rowValue(key, s)
    if key == "uptime" then
        return format("%d%%", floor(s.uptime + 0.5))
    elseif key == "perfect" then
        return format("%d (%d%%)", s.perfects, floor(s.perfectRate + 0.5))
    elseif key == "best" then
        return tostring(s.bestCombo)
    elseif key == "avg" then
        return format("%.2fs", s.avgWaste)
    elseif key == "casts" then
        return tostring(s.casts)
    elseif key == "session" then
        return fmtDuration(s.duration)
    end
end

function StatsPanel:Init(db)
    self.db = db
    if self.frame then
        self:ApplyLock()
        self:ApplyShown()
        self:Refresh()
        return
    end

    local panel = self
    local f = CreateFrame("Frame", "SpellComboHistoryStatsPanel", UIParent)
    self.frame = f
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetFrameStrata("MEDIUM")

    -- Restore the saved position, or use a sensible default.
    if db.statsPoint then
        f:SetPoint(db.statsPoint, UIParent, db.statsPoint, db.statsX or 0, db.statsY or 0)
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 250, -150)
    end

    -- Background.
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.6)

    -- Title.
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, -6)
    title:SetText(L["STATS_PANEL_TITLE"])

    -- Rows: label on the left, value on the right.
    local startY = -28
    local rowH = 18
    f.values = {}
    for i, row in ipairs(ROWS) do
        local y = startY - (i - 1) * rowH
        local label = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("TOPLEFT", f, "TOPLEFT", 12, y)
        label:SetText(L[row.labelKey])
        local value = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        value:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, y)
        value:SetJustifyH("RIGHT")
        f.values[row.key] = value
    end

    -- Drag hint, shown only while unlocked.
    local hint = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hint:SetPoint("BOTTOM", f, "BOTTOM", 0, 5)
    hint:SetText(L["STATS_MOVE_HINT"])
    hint:SetTextColor(1, 0.82, 0)
    self.hint = hint

    f:SetSize(190, 28 + #ROWS * rowH + 22)

    -- Drag to move (only while unlocked).
    f:SetScript("OnDragStart", function(self)
        if not panel.db.statsLocked then self:StartMoving() end
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, _, x, y = self:GetPoint()
        panel.db.statsPoint, panel.db.statsX, panel.db.statsY = point, x, y
    end)
    -- Right-click to lock.
    f:SetScript("OnMouseDown", function(self, button)
        if button == "RightButton" and not panel.db.statsLocked then
            panel.db.statsLocked = true
            panel:ApplyLock()
            if _G["SpellComboHistoryLockStatsCheck"] then
                _G["SpellComboHistoryLockStatsCheck"]:SetChecked(true)
            end
        end
    end)

    -- Throttled refresh while visible (OnUpdate does not fire when hidden).
    f:SetScript("OnUpdate", function(self, elapsed)
        self.elapsed = (self.elapsed or 0) + elapsed
        if self.elapsed < 0.2 then return end
        self.elapsed = 0
        panel:Refresh()
    end)

    self:ApplyLock()
    self:ApplyShown()
    self:Refresh()
end

-- Apply the locked state: locked panels ignore the mouse (click-through) and
-- hide the drag hint.
function StatsPanel:ApplyLock()
    if not self.frame then return end
    local locked = self.db.statsLocked
    self.frame:EnableMouse(not locked)
    if self.hint then self.hint:SetShown(not locked) end
end

function StatsPanel:ApplyShown()
    if not self.frame then return end
    if self.db.statsShown then self.frame:Show() else self.frame:Hide() end
end

-- Re-apply the saved position (used after a profile switch).
function StatsPanel:ApplyPosition()
    if not self.frame then return end
    local db = self.db
    self.frame:ClearAllPoints()
    if db.statsPoint then
        self.frame:SetPoint(db.statsPoint, UIParent, db.statsPoint, db.statsX or 0, db.statsY or 0)
    else
        self.frame:SetPoint("CENTER", UIParent, "CENTER", 250, -150)
    end
end

function StatsPanel:Refresh()
    if not self.frame or not self.frame:IsShown() then return end
    local s = ns.Stats:Get()
    for _, row in ipairs(ROWS) do
        self.frame.values[row.key]:SetText(rowValue(row.key, s))
    end
end
