-- Animations.lua - tween engine + pluggable icon animation strategies.
--
-- Three independent pieces live here:
--   * ns.Easing     - easing functions (pure math).
--   * ns.Tween      - a generic numeric interpolation engine. It only knows
--                     how to lerp the fields of an object's `state` table and
--                     call its Apply() method; it has no knowledge of frames.
--   * ns.Animations - a registry of animation strategies. Each strategy shares
--                     the same interface (PlayIn / PlayMove / PlayOut), so new
--                     styles can be added without touching the display code.
local _, ns = ...

local GetTime = GetTime

-- ---------------------------------------------------------------------------
-- Easing: map progress t in [0,1] to an eased value (may overshoot 1).
-- ---------------------------------------------------------------------------
local Easing = {}
ns.Easing = Easing

function Easing.linear(t) return t end
function Easing.outQuad(t) return 1 - (1 - t) * (1 - t) end
function Easing.outCubic(t) local f = 1 - t; return 1 - f * f * f end
-- Overshoots past 1 then settles back, giving a springy "back" feel.
function Easing.outBack(t)
    local c1 = 1.70158
    local c3 = c1 + 1
    local f = t - 1
    return 1 + c3 * f * f * f + c1 * f * f
end

-- ---------------------------------------------------------------------------
-- Tween engine.
--
-- A target object must expose:
--   * obj.state  - a table of numeric fields (e.g. x, y, alpha, scale)
--   * obj:Apply() - reads obj.state and pushes it onto the real frame
-- The engine interpolates only the fields named in the `target` table.
-- ---------------------------------------------------------------------------
local Tween = {}
ns.Tween = Tween

-- Map of object -> active tween record. Driven by a single OnUpdate handler.
local running = {}
local driver = CreateFrame("Frame")

local function onUpdate()
    local now = GetTime()
    for obj, tw in pairs(running) do
        local t = (now - tw.startTime) / tw.duration
        if t > 1 then t = 1 end
        local e = tw.easing(t)
        local state = obj.state
        for field, fromValue in pairs(tw.from) do
            local toValue = tw.to[field]
            state[field] = fromValue + (toValue - fromValue) * e
        end
        obj:Apply()
        if t >= 1 then
            -- Snap exactly onto the targets and finish.
            for field, toValue in pairs(tw.to) do state[field] = toValue end
            obj:Apply()
            running[obj] = nil
            if tw.onComplete then tw.onComplete() end
        end
    end
    -- Stop the driver when there is nothing left to animate.
    if not next(running) then driver:SetScript("OnUpdate", nil) end
end

-- Start (or replace) a tween on `obj` toward `target` over `duration` seconds.
-- A duration of 0 (or nil) applies the target instantly.
function Tween:Start(obj, duration, target, easing, onComplete)
    if not duration or duration <= 0 then
        for field, value in pairs(target) do obj.state[field] = value end
        obj:Apply()
        running[obj] = nil
        if onComplete then onComplete() end
        return
    end
    -- Carry over any fields still being animated by a previous tween that the
    -- new target does not set, so an interrupting tween (e.g. a move) keeps them
    -- going instead of freezing them mid-flight. Without this, a slide-in icon
    -- that gets moved before its fade finishes stays stuck at partial alpha and
    -- looks like an empty slot.
    local existing = running[obj]
    if existing then
        for field, toValue in pairs(existing.to) do
            if target[field] == nil then
                target[field] = toValue
            end
        end
    end

    -- Capture the current values as the animation's starting point.
    local from = {}
    for field in pairs(target) do from[field] = obj.state[field] end
    running[obj] = {
        from = from,
        to = target,
        duration = duration,
        easing = easing or Easing.outQuad,
        startTime = GetTime(),
        onComplete = onComplete,
    }
    driver:SetScript("OnUpdate", onUpdate)
end

-- Cancel any tween on `obj` without firing its completion callback.
function Tween:Stop(obj)
    running[obj] = nil
end

-- ---------------------------------------------------------------------------
-- Animation strategy registry.
--
-- A strategy is a table:
--   { key, labelKey, PlayIn, PlayMove, PlayOut }
-- where the three Play* methods receive (bar, icon, targetX, targetY, duration)
-- and PlayOut also receives an onComplete callback. `bar` is the HistoryBar,
-- exposed so strategies can read geometry such as bar.step.
-- ---------------------------------------------------------------------------
local Animations = { _byKey = {}, _order = {} }
ns.Animations = Animations

function Animations:Register(strategy)
    if not self._byKey[strategy.key] then
        table.insert(self._order, strategy)
    end
    self._byKey[strategy.key] = strategy
end

function Animations:Get(key)
    return self._byKey[key] or self._byKey["none"]
end

function Animations:List()
    return self._order
end

-- none: instant, no animation. Reproduces the original behavior.
Animations:Register({
    key = "none",
    labelKey = "ANIM_NONE",
    PlayIn = function(_, icon, tx, ty)
        local s = icon.state
        s.x, s.y, s.alpha, s.scale = tx, ty, 1, 1
        icon:Apply()
    end,
    PlayMove = function(_, icon, tx, ty)
        Tween:Stop(icon)
        icon.state.x, icon.state.y = tx, ty
        icon:Apply()
    end,
    PlayOut = function(_, icon, _duration, onComplete)
        Tween:Stop(icon)
        if onComplete then onComplete() end
    end,
})

-- fade: new icons fade in, leaving icons fade out, moves are smooth.
Animations:Register({
    key = "fade",
    labelKey = "ANIM_FADE",
    PlayIn = function(_, icon, tx, ty, duration)
        local s = icon.state
        s.x, s.y, s.scale = tx, ty, 1
        s.alpha = 0
        icon:Apply()
        Tween:Start(icon, duration, { alpha = 1 }, Easing.outQuad)
    end,
    PlayMove = function(_, icon, tx, ty, duration)
        Tween:Start(icon, duration, { x = tx, y = ty }, Easing.outQuad)
    end,
    PlayOut = function(_, icon, duration, onComplete)
        Tween:Start(icon, duration, { alpha = 0 }, Easing.outQuad, onComplete)
    end,
})

-- slide: new icons slide in from the right; leaving icons slide further left.
Animations:Register({
    key = "slide",
    labelKey = "ANIM_SLIDE",
    PlayIn = function(bar, icon, tx, ty, duration)
        local s = icon.state
        s.x, s.y, s.scale = tx + bar.step, ty, 1
        s.alpha = 0
        icon:Apply()
        Tween:Start(icon, duration, { x = tx, alpha = 1 }, Easing.outCubic)
    end,
    PlayMove = function(_, icon, tx, ty, duration)
        Tween:Start(icon, duration, { x = tx, y = ty }, Easing.outCubic)
    end,
    PlayOut = function(bar, icon, duration, onComplete)
        Tween:Start(icon, duration, { x = icon.state.x - bar.step, alpha = 0 }, Easing.outCubic, onComplete)
    end,
})

-- bounce: new icons pop in with a springy scale; moves overshoot slightly.
Animations:Register({
    key = "bounce",
    labelKey = "ANIM_BOUNCE",
    PlayIn = function(_, icon, tx, ty, duration)
        local s = icon.state
        s.x, s.y, s.alpha = tx, ty, 1
        s.scale = 0.4
        icon:Apply()
        Tween:Start(icon, duration, { scale = 1 }, Easing.outBack)
    end,
    PlayMove = function(_, icon, tx, ty, duration)
        Tween:Start(icon, duration, { x = tx, y = ty }, Easing.outBack)
    end,
    PlayOut = function(_, icon, duration, onComplete)
        Tween:Start(icon, duration, { alpha = 0, scale = 0.4 }, Easing.outQuad, onComplete)
    end,
})
