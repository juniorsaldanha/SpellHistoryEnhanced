-- Stats.lua - per-combat performance statistics (model).
--
-- A UI-agnostic accumulator. The session is a single combat: BeginCombat
-- resets and starts the clock, Record adds graded GCD casts, EndCombat stops
-- the clock. The panel keeps showing the last fight's numbers until the next
-- one starts. Get() returns derived, display-ready values.
local _, ns = ...

local GetTime = GetTime

local Stats = {}
ns.Stats = Stats

function Stats:Init()
    self:Reset()
end

function Stats:Reset()
    self.casts = 0
    self.perfects = 0
    self.wasteSum = 0
    self.wasteSamples = 0
    self.bestCombo = 0
    self.activeTime = 0
    self.combatStart = nil
    self.combatEnd = nil
    self.inCombat = false
end

function Stats:BeginCombat(now)
    self:Reset()
    self.combatStart = now
    self.inCombat = true
end

function Stats:EndCombat(now)
    self.combatEnd = now
    self.inCombat = false
end

-- Record one graded GCD cast. Call only for in-combat, on-GCD casts.
--   isPerfect   - was it graded PERFECT
--   combo       - the combo count after this cast
--   isStart     - truthy if this began/restarted a combo (no waste sample)
--   wasteTime   - measured gap before this cast (seconds)
--   activeChunk - time this cast kept the GCD/cast busy (seconds)
function Stats:Record(isPerfect, combo, isStart, wasteTime, activeChunk)
    -- Start the clock lazily (e.g. after a /reload mid-combat, where
    -- BeginCombat never fired).
    if not self.combatStart then
        self.combatStart = GetTime()
        self.inCombat = true
    end
    self.casts = self.casts + 1
    if isPerfect then self.perfects = self.perfects + 1 end
    if combo and combo > self.bestCombo then self.bestCombo = combo end
    if activeChunk and activeChunk > 0 then
        self.activeTime = self.activeTime + activeChunk
    end
    -- A (re)start has no meaningful gap, so it is not a waste sample.
    if not isStart then
        self.wasteSum = self.wasteSum + (wasteTime or 0)
        self.wasteSamples = self.wasteSamples + 1
    end
end

-- Add active (busy) time on its own, for casts whose true duration is only
-- known after Record was already called (e.g. a channel finalized at its
-- CHANNEL_STOP). Keeps the cast/grade counted at the right time while letting
-- uptime reflect the real channel length.
function Stats:AddActiveTime(seconds)
    if seconds and seconds > 0 then
        self.activeTime = self.activeTime + seconds
    end
end

-- Combat duration so far (live while in combat, frozen after it ends).
function Stats:Duration()
    if not self.combatStart then return 0 end
    local endTime = self.combatEnd or GetTime()
    local d = endTime - self.combatStart
    if d < 0 then d = 0 end
    return d
end

-- Derived, display-ready statistics.
function Stats:Get()
    local dur = self:Duration()
    local uptime = 0
    if dur > 0 then
        uptime = self.activeTime / dur
        if uptime > 1 then uptime = 1 elseif uptime < 0 then uptime = 0 end
    end
    local perfectRate = self.casts > 0 and (self.perfects / self.casts) or 0
    local avgWaste = self.wasteSamples > 0 and (self.wasteSum / self.wasteSamples) or 0
    return {
        uptime = uptime * 100,
        casts = self.casts,
        perfects = self.perfects,
        perfectRate = perfectRate * 100,
        bestCombo = self.bestCombo,
        avgWaste = avgWaste,
        duration = dur,
    }
end
