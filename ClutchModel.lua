-- ============================================================
-- FS25_ClutchModel.lua
-- by Marcus (Cobra Modding)
-- 
--
-- Version 1.0.0.0
--
--
-- Keine Änderung am Skript ohne meine Erlaubnis
-- ============================================================

ClutchModel = {}

function ClutchModel.clamp(value, low, high)
    return math.max(low, math.min(high, value))
end

local PEDAL_CONTACT = 0.82
local PEDAL_BITE_END = 0.66
local PEDAL_CLAMP_START = 0.38
local PEDAL_LOCKED = 0.18
local OPEN_TORQUE_FLOOR = 0.01

local function smoothstep(x)
    x = ClutchModel.clamp(x, 0, 1)
    return x * x * (3 - 2 * x)
end

function ClutchModel.engagement(pedal)
    pedal = ClutchModel.clamp(pedal or 0, 0, 1)

    if pedal >= PEDAL_CONTACT then
        return OPEN_TORQUE_FLOOR
    end

    if pedal >= PEDAL_BITE_END then
        local x = (PEDAL_CONTACT - pedal) / (PEDAL_CONTACT - PEDAL_BITE_END)
        return OPEN_TORQUE_FLOOR + (0.12 - OPEN_TORQUE_FLOOR) * smoothstep(x)
    end

    if pedal >= PEDAL_CLAMP_START then
        local x = (PEDAL_BITE_END - pedal) / (PEDAL_BITE_END - PEDAL_CLAMP_START)
        local shaped = smoothstep(x) ^ 1.15
        return 0.12 + (0.72 - 0.12) * shaped
    end

    if pedal > PEDAL_LOCKED then
        local x = (PEDAL_CLAMP_START - pedal) / (PEDAL_CLAMP_START - PEDAL_LOCKED)
        return 0.72 + (1.00 - 0.72) * smoothstep(x)
    end

    return 1.0
end

function ClutchModel.getOpenTorqueFloor()
    return OPEN_TORQUE_FLOOR
end

function ClutchModel.isInBiteZone(pedal)
    pedal = ClutchModel.clamp(pedal or 0, 0, 1)
    return pedal < PEDAL_CONTACT and pedal > PEDAL_LOCKED
end

function ClutchModel.isProtectedGear(gear)
    local index = math.abs(gear or 0)
    return index == 1
end

function ClutchModel.idleThrottle(pedal, shaftRpm, idleRpm, brake, protected)
    if pedal >= PEDAL_CONTACT or brake > 0.01 or idleRpm <= 0 then return 0 end

    local engagement = ClutchModel.engagement(pedal)
    local rpmRatio = math.abs(shaftRpm) / idleRpm
    local deficit = ClutchModel.clamp((1.05 - rpmRatio) / 0.55, 0, 1)
    local authority = protected and 0.24 or 0.16
    local biteAuthority = ClutchModel.clamp((engagement - 0.08) / 0.62, 0, 1)
    return authority * deficit * biteAuthority
end

function ClutchModel.step(timer, dt, pedal, motorRpm, shaftRpm, idleRpm)
    local engagement = ClutchModel.engagement(pedal)
    local coupling = engagement ^ 1.65
    local effectiveRpm = motorRpm * (1 - coupling) + math.abs(shaftRpm) * coupling
    local stallThreshold = idleRpm * 0.58
    local deficit = ClutchModel.clamp((stallThreshold - effectiveRpm)
        / math.max(stallThreshold, 1), 0, 1)

    dt = ClutchModel.clamp(dt, 0, 0.1) 

    if deficit > 0 and engagement > 0.42 then
        local clampSeverity = ClutchModel.clamp((engagement - 0.42) / 0.58, 0, 1)
        timer = timer + dt * (0.35 + 2.35 * deficit + 0.75 * clampSeverity)
    else
        timer = math.max(0, timer - dt * 4.5)
    end

    return timer, timer >= 0.85
end
