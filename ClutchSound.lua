-- ============================================================
-- FS25_ClutchSound.lua
-- by Marcus (Cobra Modding)
-- 
--
-- Version 1.0.0.0
--
--
-- Keine Änderung am Skript ohne meine Erlaubnis
-- ============================================================

ClutchSound = {directory=g_currentModDirectory}

function ClutchSound.onCreaking(vehicle)
    local self = ClutchSound
    if self.sample == nil or not vehicle.isClient
        or not vehicle:getIsActiveForInput(true)
        or not RealisticClutch.isApplicable(vehicle.spec_motorized.motor) then return end
    if not isSamplePlaying(self.sample) then
        playSample(self.sample, 1, 1.0, 0, 0, 0)
    end
end

function ClutchSound:loadMap()
    if g_dedicatedServer ~= nil then return end
    local sample = createSample("RealisticClutchGearGrind")
    if sample == nil or sample == 0 then return end
    if not loadSample(sample, self.directory .. "sounds/gear_grind.ogg", false) then
        delete(sample)
        Logging.warning("[RealisticClutch] Cannot load sounds/gear_grind.ogg")
        return
    end
    setSampleGroup(sample, AudioGroup.VEHICLE)
    self.sample = sample
end

function ClutchSound:deleteMap()
    if self.sample ~= nil then
        stopSample(self.sample, 0, 0)
        delete(self.sample)
        self.sample = nil
    end
end

Motorized.onClutchCreaking = Utils.appendedFunction(Motorized.onClutchCreaking, ClutchSound.onCreaking)
addModEventListener(ClutchSound)
