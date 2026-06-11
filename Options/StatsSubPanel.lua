-- Options/StatsSubPanel.lua - Statistics canvas subcategory: show-panel
-- toggle, a live fight summary, and refresh/reset buttons.
local _, ns = ...
local L = ns.L

local StatsSubPanel = {}
ns.StatsSubPanel = StatsSubPanel

local function fmtDuration(sec)
    sec = math.floor(sec)
    return string.format("%d:%02d", math.floor(sec / 60), sec % 60)
end

function StatsSubPanel:Build(parentCategory)
    local f = CreateFrame("Frame", "SpellHistoryEnhancedStatsSubPanel")
    f.name = L["STATS_HEADER"]

    local title = f:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText(L["STATS_HEADER"])

    local show = CreateFrame("CheckButton", "SpellHistoryEnhancedShowStatsCheck", f, "ChatConfigCheckButtonTemplate")
    show:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -12)
    _G[show:GetName() .. "Text"]:SetText(L["SHOW_STATS"])
    show:SetChecked(ns.Config.db.statsShown)
    show:SetScript("OnClick", function(self)
        ns.Config.db.statsShown = self:GetChecked() and true or false
        ns.StatsPanel:ApplyShown()
    end)
    self.show = show

    local summary = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    summary:SetPoint("TOPLEFT", show, "BOTTOMLEFT", 4, -16)
    summary:SetJustifyH("LEFT")
    self.summary = summary

    local function refresh()
        show:SetChecked(ns.Config.db.statsShown)
        local s = ns.Stats:Get()
        summary:SetText(
            L["STATS_SESSION"] .. ": " .. fmtDuration(s.duration) .. "\n" ..
            L["STATS_UPTIME"] .. ": " .. math.floor(s.uptime + 0.5) .. "%\n" ..
            L["PERFECT"] .. ": " .. s.perfects .. " (" .. math.floor(s.perfectRate + 0.5) .. "%)\n" ..
            L["STATS_BEST_COMBO"] .. ": " .. s.bestCombo .. "\n" ..
            L["STATS_AVG_WASTE"] .. ": " .. string.format("%.2fs", s.avgWaste) .. "\n" ..
            L["STATS_CASTS"] .. ": " .. s.casts)
    end
    self.refresh = refresh
    refresh()

    local refreshBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    refreshBtn:SetSize(110, 26)
    refreshBtn:SetPoint("TOPLEFT", summary, "BOTTOMLEFT", 0, -16)
    refreshBtn:SetText(L["STATS_REFRESH"])
    refreshBtn:SetScript("OnClick", refresh)

    local resetBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    resetBtn:SetSize(110, 26)
    resetBtn:SetPoint("LEFT", refreshBtn, "RIGHT", 12, 0)
    resetBtn:SetText(L["STATS_RESET"])
    resetBtn:SetScript("OnClick", function()
        ns.Stats:Reset()
        refresh()
        print(ns.Constants.PRINT_PREFIX .. L["MSG_STATS_RESET"])
    end)

    f:SetScript("OnShow", refresh)
    Settings.RegisterCanvasLayoutSubcategory(parentCategory, f, f.name)
end

-- Called after a profile switch (if the page was built).
function StatsSubPanel:Refresh()
    if self.refresh then self.refresh() end
end
