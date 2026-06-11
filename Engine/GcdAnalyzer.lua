-- Engine/GcdAnalyzer.lua - GCD ownership detection + waste/combo grading.
-- Publishes one CAST_GRADED event per analyzed spell; has no UI knowledge.
local _, ns = ...
local L = ns.L

local GetTime              = GetTime
local GetSpellBaseCooldown = GetSpellBaseCooldown
local InCombatLockdown     = InCombatLockdown
local UnitAffectingCombat  = UnitAffectingCombat
local GetNetStats          = GetNetStats
local GetSpellCooldown     = GetSpellCooldown or function(id) return C_Spell.GetSpellCooldown(id) end

local GCD_SPELL_ID = ns.Constants.GCD_SPELL_ID

-- Safely return just a spell's cooldown duration.
local function GetSpellCooldownDuration(spellID)
    if C_Spell and C_Spell.GetSpellCooldown then
        local cd = C_Spell.GetSpellCooldown(spellID)
        return cd and cd.duration or 0
    end
    local _, dur = GetSpellCooldown(spellID)
    return dur or 0
end

local GcdAnalyzer = {}
ns.GcdAnalyzer = GcdAnalyzer

-- Analyze one frame's batch of spells: find which spell owns the GCD, grade
-- waste/combo, and publish a CAST_GRADED event for each.
function GcdAnalyzer:Process(spells)
    local st = ns.Config.state
    local db = ns.Config.db

    -- Current state of the shared GCD bar.
    local currentStart = 0
    local currentDuration = 0
    if C_Spell and C_Spell.GetSpellCooldown then
        local cooldownInfo = C_Spell.GetSpellCooldown(GCD_SPELL_ID)
        if cooldownInfo then
            currentStart = cooldownInfo.startTime
            currentDuration = cooldownInfo.duration
        end
    else
        local start, duration = GetSpellCooldown(GCD_SPELL_ID)
        currentStart = start or 0
        currentDuration = duration or 0
    end

    -- Detect whether a new GCD cycle began (0.1s threshold).
    local gcdTriggered = false
    if currentStart > 0 and math.abs(currentStart - st.lastGcdStartTime) >= 0.1 then
        gcdTriggered = true
    end

    -- Which spell in this frame actually "owns" the GCD.
    local gcdSpellIndex = -1
    if gcdTriggered then
        for i = 1, #spells do
            local sp = spells[i]
            if sp.castStartTime then
                gcdSpellIndex = i
                break
            end

            local d = GetSpellCooldownDuration(sp.spellID)
            if pcall(function() return d + 0 end) then
                if d > 0 and currentDuration > 0 and math.abs(d - currentDuration) < 0.01 then
                    gcdSpellIndex = i
                    break
                end
            end
        end

        if gcdSpellIndex == -1 then
            for i = 1, #spells do
                local sp = spells[i]
                local d = GetSpellCooldownDuration(sp.spellID)
                if pcall(function() return d + 0 end) then
                    if d >= currentDuration - 0.01 then
                        gcdSpellIndex = i
                        break
                    end
                end
            end
        end

        if gcdSpellIndex == -1 then
            gcdSpellIndex = 1
        end
    end

    -- Use world ping to set the PERFECT threshold (ms -> s).
    local _, _, _, lagWorld = GetNetStats()
    local threshold = lagWorld / 1000

    -- Final grading and publish for each spell in the batch.
    for i, sp in ipairs(spells) do
        local _, gcdMS = GetSpellBaseCooldown(sp.spellID)
        local isOffGCD = (gcdMS == 0)
        if sp.castStartTime then
            isOffGCD = false
        end

        local wasteTime = 0
        local now = GetTime()
        local actionStartTime = sp.castStartTime or now
        local isStart = false
        local isPerfect = false
        local channelWaste = 999

        local inCombat = InCombatLockdown() or UnitAffectingCombat("player")

        if inCombat then
            if st.pendingStart then
                isStart = L["START"]
                st.pendingStart = false
                st.perfectCombo = 1
                st.lastChannelEndTime = 0
                isPerfect = true
            elseif not isOffGCD and actionStartTime > 0 then
                local timeout = (db and db.restartTimeout) or 10

                if st.lastGcdEndTime == 0 or actionStartTime > st.lastGcdEndTime + timeout then
                    isStart = (st.lastGcdEndTime == 0) and L["START"] or L["RESTART"]
                    st.perfectCombo = 1
                    isPerfect = true
                else
                    if actionStartTime > st.lastGcdEndTime then
                        wasteTime = actionStartTime - st.lastGcdEndTime
                    end

                    isPerfect = (wasteTime <= threshold)

                    if not isPerfect and st.lastChannelEndTime > 0 then
                        channelWaste = math.abs(actionStartTime - st.lastChannelEndTime)
                        if channelWaste <= threshold then
                            isPerfect = true
                        end
                    end

                    st.perfectCombo = isPerfect and (st.perfectCombo + 1) or 0
                end
            end

            -- If this spell was a GCD spell, update timers for the next one.
            if not isOffGCD and actionStartTime > 0 then
                st.lastGcdStartTime = now
                if sp.castStartTime then
                    st.lastGcdEndTime = now
                else
                    st.lastGcdEndTime = now + currentDuration
                end
            end
        else
            st.perfectCombo = 0
            wasteTime = 0
            isPerfect = false
        end

        -- Compute the busy/active time for in-combat on-GCD casts only (channels
        -- defer until CHANNEL_STOP), matching the stats model's own guard.
        local activeChunk = 0
        if inCombat and not isOffGCD then
            if sp.isChannel then
                st.pendingChannelActiveStart = sp.castStartTime or now
                activeChunk = 0
            else
                activeChunk = sp.castStartTime and (now - sp.castStartTime) or currentDuration
            end
        end

        ns.EventBus:Publish("CAST_GRADED", {
            spellID    = sp.spellID,
            wasteTime  = wasteTime,
            isOffGCD   = isOffGCD,
            isStart    = isStart,
            isPerfect  = isPerfect,
            comboCount = st.perfectCombo,
            isChannel  = sp.isChannel,
            inCombat   = inCombat,
            activeChunk = activeChunk,
        })
    end
end
