-- Engine/CastTracker.lua - capture player cast events, batch them per frame,
-- track channels, and hand each batch to the GcdAnalyzer. Also owns combat
-- enter/leave (which resets grading state and drives the stats session).
local _, ns = ...

local GetTime = GetTime
local GCD_SPELL_ID = ns.Constants.GCD_SPELL_ID
local GetSpellCooldown = GetSpellCooldown or function(id) return C_Spell.GetSpellCooldown(id) end

local frame = CreateFrame("Frame", "SpellHistoryEnhancedCastFrame", UIParent)
ns.CastTracker = { frame = frame }

-- Cast start times keyed by cast ID (compared at SUCCEEDED).
local pendingCasts = {}
-- Cast IDs that belong to a channel (set at CHANNEL_START), so SUCCEEDED can
-- tell a channel apart from a hard-cast (both carry a cast start time).
local channelCasts = {}
-- Spells collected within one frame, plus the batch timer.
local frameSpells = {}
local processingTimer = nil

frame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
frame:RegisterEvent("UNIT_SPELLCAST_START")
frame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")
frame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:RegisterEvent("PLAYER_REGEN_DISABLED")

frame:SetScript("OnEvent", function(self, event, unit, castID, spellID)
    local st = ns.Config.state

    -- When the player leaves combat.
    if event == "PLAYER_REGEN_ENABLED" then
        ns.Stats:EndCombat(GetTime())
        st.pendingStart = false
        st.lastGcdEndTime = 0
        st.lastGcdStartTime = 0
        st.perfectCombo = 0
        st.lastChannelEndTime = 0
        st.pendingChannelActiveStart = nil
        return
    end
    -- When the player enters combat.
    if event == "PLAYER_REGEN_DISABLED" then
        ns.Stats:BeginCombat(GetTime())
        st.pendingStart = true
        st.lastChannelEndTime = 0
        st.pendingChannelActiveStart = nil
        return
    end

    -- Everything below is about the player's own casts.
    if unit ~= "player" then return end

    -- A cast or channel started.
    if event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START" then
        if castID then
            pendingCasts[castID] = GetTime()
            if event == "UNIT_SPELLCAST_CHANNEL_START" then
                channelCasts[castID] = true
            end
        end
        return
    end

    -- A channel ended (naturally, clipped, or interrupted).
    if event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        local channelEnd = GetTime()
        st.lastChannelEndTime = channelEnd
        -- SUCCEEDED fired at the channel's START, so lastGcdEndTime points at
        -- the start; correct it to the true end so the next cast's wasted time
        -- is measured from here.
        if st.lastGcdEndTime ~= 0 then
            st.lastGcdEndTime = channelEnd
        end
        -- Finalize the channel's active (uptime) time (full channels + clips).
        if st.pendingChannelActiveStart then
            ns.Stats:AddActiveTime(channelEnd - st.pendingChannelActiveStart)
            st.pendingChannelActiveStart = nil
        end
        return
    end

    -- A spell cast finally succeeded.
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        local isPlayerSpell = (C_SpellBook and C_SpellBook.IsSpellInSpellBook and C_SpellBook.IsSpellInSpellBook(spellID))
                           or (IsPlayerSpell and IsPlayerSpell(spellID))

        if ns.debug then
            local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)
            print(ns.Constants.PRINT_PREFIX .. "cast " .. tostring(spellID)
                .. " |cffffff00" .. (info and info.name or "?") .. "|r"
                .. " player=" .. tostring(isPlayerSpell and true or false)
                .. " channel=" .. tostring((castID and channelCasts[castID]) and true or false)
                .. " ignored=" .. tostring(ns.IgnoreList:IsIgnored(spellID)))
        end

        if not isPlayerSpell or ns.IgnoreList:IsIgnored(spellID) then
            if castID then
                pendingCasts[castID] = nil
                channelCasts[castID] = nil
            end
            return
        end

        local castStartTime = castID and pendingCasts[castID]
        local isChannel = (castID and channelCasts[castID]) or nil
        if castID then
            pendingCasts[castID] = nil
            channelCasts[castID] = nil
        end

        -- Capture the GCD bar's start time at success (sync helper data).
        local syncStart = 0
        if C_Spell and C_Spell.GetSpellCooldown then
            local cd = C_Spell.GetSpellCooldown(GCD_SPELL_ID)
            if cd then syncStart = cd.startTime end
        else
            local s = GetSpellCooldown(GCD_SPELL_ID)
            syncStart = s or 0
        end

        table.insert(frameSpells, {spellID = spellID, castStartTime = castStartTime, syncStart = syncStart, isChannel = isChannel})

        -- Batch spells fired on the same frame, then analyze after 0.01s.
        if not processingTimer then
            processingTimer = C_Timer.After(0.01, function()
                processingTimer = nil
                local batch = frameSpells
                frameSpells = {}
                ns.GcdAnalyzer:Process(batch)
            end)
        end
    end
end)
