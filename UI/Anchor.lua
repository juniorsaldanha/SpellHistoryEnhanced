-- UI/Anchor.lua - the movable bar frame. Owns positioning, Shift-drag, the
-- alignment grid, and the bar background. Movement is gated on holding Shift
-- (the old lock toggle is gone); the icons forward their own Shift-drag here.
local _, ns = ...
local L = ns.L

local CreateFrame        = CreateFrame
local UIParent           = UIParent
local GetCursorPosition  = GetCursorPosition
local IsShiftKeyDown     = IsShiftKeyDown
local GameTooltip        = GameTooltip

local ICON_SIZE = ns.Constants.ICON_SIZE
local SPACING   = ns.Constants.SPACING

local Anchor = {}
ns.Anchor = Anchor

-- The movable handle frame (also icon slot 1). Mouse-enabled at 40x40 so the
-- empty bar can be grabbed; clicks elsewhere pass through.
local anchor = CreateFrame("Frame", "SpellHistoryEnhancedAnchor", UIParent)
Anchor.frame = anchor
anchor:SetSize(ICON_SIZE, ICON_SIZE)
anchor:SetPoint("CENTER", 0, 0)
anchor:SetMovable(true)
anchor:EnableMouse(true)
anchor:RegisterForDrag("LeftButton")

-- Cursor-to-frame offset captured at drag start.
local dragOffsetX, dragOffsetY = 0, 0

-- ---------------------------------------------------------------------------
-- Alignment grid (shown only during an active drag).
-- ---------------------------------------------------------------------------
local gridFrame
local function CreateGrid()
    if gridFrame then return end
    gridFrame = CreateFrame("Frame", nil, UIParent)
    gridFrame:SetAllPoints()
    gridFrame:SetFrameStrata("BACKGROUND")

    local w, h = UIParent:GetWidth(), UIParent:GetHeight()
    for i = 0, h, 40 do
        local t = gridFrame:CreateTexture(nil, "BACKGROUND")
        t:SetHeight(1)
        t:SetPoint("LEFT", gridFrame, "LEFT")
        t:SetPoint("RIGHT", gridFrame, "RIGHT")
        t:SetPoint("BOTTOM", gridFrame, "BOTTOM", 0, i)
        t:SetColorTexture(1, 1, 1, 0.15)
    end
    for i = 0, w, 40 do
        local t = gridFrame:CreateTexture(nil, "BACKGROUND")
        t:SetWidth(1)
        t:SetPoint("TOP", gridFrame, "TOP", 0, 0)
        t:SetPoint("BOTTOM", gridFrame, "BOTTOM", 0, 0)
        t:SetPoint("LEFT", gridFrame, "LEFT", i, 0)
        t:SetColorTexture(1, 1, 1, 0.15)
    end
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

function Anchor:ToggleGrid(show)
    if show and ns.Config.db.useGrid then
        CreateGrid()
        gridFrame:Show()
    elseif gridFrame then
        gridFrame:Hide()
    end
end

-- ---------------------------------------------------------------------------
-- Background bar.
-- ---------------------------------------------------------------------------
anchor.mainBg = anchor:CreateTexture(nil, "BACKGROUND")
anchor.mainBg:SetColorTexture(0, 0, 0, 0.5)

function Anchor:UpdateBackground()
    local db = ns.Config.db
    local maxIcons = (db and db.maxIcons) or 6
    local blockWidth = ICON_SIZE + (maxIcons - 1) * (ICON_SIZE + SPACING)

    anchor.mainBg:ClearAllPoints()
    anchor.mainBg:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", 5, 5)
    anchor.mainBg:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", -(blockWidth - ICON_SIZE) - 5, -5)

    local alpha = db and db.bgAlpha
    if alpha == nil then alpha = 0.5 end
    anchor.mainBg:SetColorTexture(0, 0, 0, alpha)
end

-- ---------------------------------------------------------------------------
-- Shift-drag movement.
-- ---------------------------------------------------------------------------
-- Per-frame cursor follow: keep the whole icon block centered under the cursor
-- and snap to a 10px grid when enabled.
local function onDragUpdate(self)
    local nx, ny = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    nx, ny = nx / scale, ny / scale

    local newLeft = nx - dragOffsetX
    local newBottom = ny - dragOffsetY

    local maxIcons = (ns.Config.db and ns.Config.db.maxIcons) or 6
    local currentScale = self:GetScale()
    local visualIconSize = ICON_SIZE * currentScale
    local totalOffset = (maxIcons - 1) * (ICON_SIZE + SPACING) * currentScale

    local anchorCenterX = newLeft + visualIconSize / 2
    local anchorCenterY = newBottom + visualIconSize / 2

    local blockCenterX = anchorCenterX - (totalOffset / 2)
    local blockCenterY = anchorCenterY

    local finalAnchorCenterX = blockCenterX + (totalOffset / 2)
    local finalLeft = finalAnchorCenterX - visualIconSize / 2
    local finalBottom = blockCenterY - visualIconSize / 2

    if ns.Config.db.useGrid then
        finalLeft = math.floor(finalLeft / 10 + 0.5) * 10
        finalBottom = math.floor(finalBottom / 10 + 0.5) * 10
    end

    self:ClearAllPoints()
    self:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", finalLeft, finalBottom)
end

function Anchor:BeginDrag()
    local cx, cy = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    cx, cy = cx / scale, cy / scale
    dragOffsetX = cx - anchor:GetLeft()
    dragOffsetY = cy - anchor:GetBottom()
    self:ToggleGrid(true)
    anchor:SetScript("OnUpdate", onDragUpdate)
end

function Anchor:EndDrag()
    anchor:SetScript("OnUpdate", nil)
    self:ToggleGrid(false)
    local point, _, _, x, y = anchor:GetPoint()
    ns.Config.db.point, ns.Config.db.x, ns.Config.db.y = point, x, y
end

anchor:SetScript("OnDragStart", function()
    if IsShiftKeyDown() then Anchor:BeginDrag() end
end)
anchor:SetScript("OnDragStop", function() Anchor:EndDrag() end)

-- Hover hint (only place a non-icon grab is exposed is the empty bar).
anchor:SetScript("OnEnter", function()
    GameTooltip:SetOwner(anchor, "ANCHOR_TOP")
    GameTooltip:SetText(L["MOVE_HINT"])
    GameTooltip:Show()
end)
anchor:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- ---------------------------------------------------------------------------
-- Settings application.
-- ---------------------------------------------------------------------------
function Anchor:ApplyScale()
    anchor:SetScale(ns.Config.db.uiScale or 1.0)
end

function Anchor:ApplyPosition()
    local db = ns.Config.db
    anchor:ClearAllPoints()
    if db.point then
        anchor:SetPoint(db.point, UIParent, db.point, db.x or 0, db.y or 0)
    else
        anchor:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
end

function Anchor:ResetPosition()
    anchor:ClearAllPoints()
    anchor:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    local point, _, _, x, y = anchor:GetPoint()
    ns.Config.db.point, ns.Config.db.x, ns.Config.db.y = point, x, y
end
