-- ============================================================
-- FS25_RealisticClutch.lua
-- by Marcus (Cobra Modding)
-- 
--
-- Version 1.0.0.0
--
--
-- Keine Änderung am Skript ohne meine Erlaubnis
-- ============================================================

RealisticClutch = {}

function RealisticClutch.setGearShiftMode(motor, superFunc, mode)
    superFunc(motor, mode)
    if mode == VehicleMotor.SHIFT_MODE_MANUAL_CLUTCH
        and (motor.forwardGears ~= nil or motor.backwardGears ~= nil) then
        motor.gearShiftMode = mode
    end
end

function RealisticClutch.isApplicable(motor)
    local vehicle = motor.vehicle
    return vehicle ~= nil
        and motor.gearShiftMode == VehicleMotor.SHIFT_MODE_MANUAL_CLUTCH
        and (motor.forwardGears ~= nil or motor.backwardGears ~= nil)
        and not (vehicle.getIsAIActive ~= nil and vehicle:getIsAIActive())
end

function RealisticClutch.clutchInput(vehicle, superFunc, actionName, value, callbackState, isAnalog)
    local motor = vehicle.spec_motorized.motor
    if RealisticClutch.isApplicable(motor) and not isAnalog then
        return 
    end
    motor.rcAnalogSeen = isAnalog == true or motor.rcAnalogSeen
    motor.rcLocalPedal = ClutchModel.clamp(value, 0, 1)
    return superFunc(vehicle, actionName, ClutchModel.clamp(value, 0, 1), callbackState, isAnalog)
end

function RealisticClutch.torqueFactor(motor)
    if not RealisticClutch.isApplicable(motor) then return 1 end
    return math.max(ClutchModel.getOpenTorqueFloor(), ClutchModel.engagement(motor.manualClutchValue or 0))
end

function RealisticClutch.torqueValues(motor, superFunc)
    local torques, speeds = superFunc(motor)
    local factor = RealisticClutch.torqueFactor(motor)
    if factor == 1 then return torques, speeds end
    local scaled = {}
    for i, torque in ipairs(torques) do scaled[i] = torque * factor end
    return scaled, speeds
end

function RealisticClutch.refreshPhysics(motor)
    local vehicle = motor.vehicle
    if not vehicle.isServer then return end
    local factor = RealisticClutch.torqueFactor(motor)
    if factor ~= (motor.rcPhysicsFactor or 1) and vehicle.isAddedToPhysics
        and vehicle.spec_motorized.motorizedNode ~= nil then
        vehicle:updateMotorProperties()
        motor.rcPhysicsFactor = factor
    end
end

function RealisticClutch.gearAllowed(motor, superFunc)
    if RealisticClutch.isApplicable(motor) then
        return (motor.manualClutchValue or 0) >= 0.90
    end
    return superFunc(motor)
end

function RealisticClutch.groupAllowed(motor, superFunc)
    if RealisticClutch.isApplicable(motor) and motor.gearGroups ~= nil then
        return (motor.manualClutchValue or 0) >= 0.90
    end
    return superFunc(motor)
end

function RealisticClutch.updateGear(motor, superFunc, accelerator, brake, dt)
    RealisticClutch.refreshPhysics(motor)
    if not RealisticClutch.isApplicable(motor) or not motor.vehicle.isServer then
        motor.rcStallTimer = 0
        motor.rcStoppedTimer = 0
        return superFunc(motor, accelerator, brake, dt)
    end

    motor.stallTimer = -math.huge
    local adjustedAccelerator, adjustedBrake = superFunc(motor, accelerator, brake, dt)
    motor.stallTimer = 0

    local gear = motor.currentGears ~= nil and motor.currentGears[motor.gear] or nil
    if gear == nil or not motor.vehicle:getIsMotorStarted()
        or (motor.gearChangeTimer or -1) >= 0
        or (motor.groupChangeTimer or 0) > 0
        or (motor.directionChangeTimer or 0) > 0 then
        motor.rcStallTimer = 0
        motor.rcStoppedTimer = 0
        return adjustedAccelerator, adjustedBrake
    end

    local ratio = gear.ratio * motor:getGearRatioMultiplier()
    motor.minGearRatio, motor.maxGearRatio = ratio, ratio
    motor.clutchSlippingTimer = 0
    if ratio == 0 then
        motor.rcStallTimer = 0
        motor.rcStoppedTimer = 0
        return adjustedAccelerator, adjustedBrake
    end
    local shaftRpm = math.abs((motor.differentialRotSpeed or 0) * ratio) * 30 / math.pi
    local rpm = math.max(motor:getNonClampedMotorRpm(), motor.minRpm)
    local protected = ClutchModel.isProtectedGear(motor.gear)
    local stalled = false
    if protected then
        motor.rcStallTimer = 0
        if math.abs(motor.vehicle:getLastSpeed()) < 0.15
            and (motor.manualClutchValue or 0) <= 0.05 then
            motor.rcStoppedTimer = (motor.rcStoppedTimer or 0)
                + ClutchModel.clamp(dt / 1000, 0, 0.1)
            stalled = motor.rcStoppedTimer >= 0.8
        else
            motor.rcStoppedTimer = 0
        end
    else
        motor.rcStoppedTimer = 0
        motor.rcStallTimer, stalled = ClutchModel.step(motor.rcStallTimer or 0,
            dt / 1000, motor.manualClutchValue or 0, rpm, shaftRpm, motor.minRpm)
    end
    if stalled then
        motor.rcStallTimer = 0
        motor.vehicle:stopMotor() 
    else
        local idle = ClutchModel.idleThrottle(motor.manualClutchValue or 0,
            shaftRpm, motor.minRpm, math.max(brake or 0, adjustedBrake or 0), protected)
        local direction = ratio < 0 and -1 or 1
        if adjustedAccelerator * direction >= 0 then
            adjustedAccelerator = direction * math.max(math.abs(adjustedAccelerator), idle)
        end
    end
    return adjustedAccelerator, adjustedBrake
end

function RealisticClutch.canMotorRun(motor, superFunc)
    if RealisticClutch.isApplicable(motor) and not motor.vehicle:getIsMotorStarted()
        and not motor:getIsInNeutral() and motor:getGearRatioMultiplier() ~= 0
        and (motor.manualClutchValue or 0) < 0.90 then
        return false, VehicleMotor.REASON_CLUTCH_NOT_ENGAGED
    end
    return superFunc(motor)
end

function RealisticClutch.motorLoadPercentage(vehicle, superFunc)
    local load = superFunc(vehicle)
    local motor = vehicle.spec_motorized ~= nil and vehicle.spec_motorized.motor or nil
    if motor == nil or not RealisticClutch.isApplicable(motor) then
        return load
    end

    local factor = RealisticClutch.torqueFactor(motor)
    return ClutchModel.clamp((load or 0) * factor, 0, 1)
end

VehicleMotor.setGearShiftMode = Utils.overwrittenFunction(VehicleMotor.setGearShiftMode, RealisticClutch.setGearShiftMode)
VehicleMotor.getTorqueAndSpeedValues = Utils.overwrittenFunction(VehicleMotor.getTorqueAndSpeedValues, RealisticClutch.torqueValues)
VehicleMotor.getIsGearChangeAllowed = Utils.overwrittenFunction(VehicleMotor.getIsGearChangeAllowed, RealisticClutch.gearAllowed)
VehicleMotor.getIsGearGroupChangeAllowed = Utils.overwrittenFunction(VehicleMotor.getIsGearGroupChangeAllowed, RealisticClutch.groupAllowed)
VehicleMotor.updateGear = Utils.overwrittenFunction(VehicleMotor.updateGear, RealisticClutch.updateGear)
VehicleMotor.getCanMotorRun = Utils.overwrittenFunction(VehicleMotor.getCanMotorRun, RealisticClutch.canMotorRun)
Motorized.actionEventClutch = Utils.overwrittenFunction(Motorized.actionEventClutch, RealisticClutch.clutchInput)
Motorized.getMotorLoadPercentage = Utils.overwrittenFunction(Motorized.getMotorLoadPercentage, RealisticClutch.motorLoadPercentage)
Logging.info("[RealisticClutch] Release 1.1.0.0 realistic bite-point model + ADS load fix loaded")
