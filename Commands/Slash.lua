-- Commands/Slash.lua - the /she slash command (print or reset stats).
local _, ns = ...
local L = ns.L

local function fmtDuration(sec)
    sec = math.floor(sec)
    return string.format("%d:%02d", math.floor(sec / 60), sec % 60)
end

SLASH_SPELLHISTORYENHANCED1 = "/she"
SLASH_SPELLHISTORYENHANCED2 = "/spellhistory"
SlashCmdList["SPELLHISTORYENHANCED"] = function(msg)
    msg = (msg or ""):lower():gsub("%s+", "")
    if msg == "reset" then
        ns.Stats:Reset()
        print(ns.Constants.PRINT_PREFIX .. L["MSG_STATS_RESET"])
        return
    end
    if msg == "debug" then
        ns.debug = not ns.debug
        print(ns.Constants.PRINT_PREFIX .. "debug = " .. tostring(ns.debug))
        return
    end
    -- Print the current/last fight's statistics.
    local s = ns.Stats:Get()
    print(ns.Constants.PRINT_PREFIX .. L["STATS_HEADER"] .. " (" .. fmtDuration(s.duration) .. ")")
    print("  " .. L["STATS_UPTIME"] .. ": " .. math.floor(s.uptime + 0.5) .. "%")
    print("  " .. L["PERFECT"] .. ": " .. s.perfects .. " (" .. math.floor(s.perfectRate + 0.5) .. "%)")
    print("  " .. L["STATS_BEST_COMBO"] .. ": " .. s.bestCombo)
    print("  " .. L["STATS_AVG_WASTE"] .. ": " .. string.format("%.2fs", s.avgWaste))
    print("  " .. L["STATS_CASTS"] .. ": " .. s.casts)
end
