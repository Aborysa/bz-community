local helpers = require("helpers")

local utils = require("bzutils").utils

local rx = require("rx")


local choose = helpers.choose
local chooseA = helpers.chooseA

local createClass = utils.createClass

local function spawnWave(wave_table,faction,location)
  local units = utils.spawnInFormation2(wave_table,location,faction,15)
  return units, units[1]
end



local WaveController = createClass("hp.WaveController", {
  new = function(self, faction, locations, frequency, variance, wave_types, wave_count)
    self.faction = faction
    self.locations = locations
    self.variance = variance
    self.frequency = frequency
    self.wave_types = wave_types
    self.waves_left = wave_count
    self.waveSpawnSubject = rx.Subject.create()
    self.timer = 0
    self.c_variance = 0
  end,
  onWaveSpawn = function(self)
    return self.waveSpawnSubject
  end,
  update = function(self, dtime)
    if self.waves_left > 0 then
      self.timer = self.timer + dtime
      local freq = self.frequency + self.c_variance
      if(self.timer * freq >= 1) then
        self.timer = self.timer - 1/freq
        local f = self.frequency*self.variance
        self.c_variance =  f + 2*f*math.random()
        self.waves_left = self.waves_left - 1

        local location = choose(unpack(self.locations))
        local w_type = chooseA(unpack(self.wave_types))
        self.waveSpawnSubject:onNext(spawnWave(w_type,self.faction,location))
      end
    elseif self.waveSpawnSubject then
      self.waveSpawnSubject:onCompleted()
      self.waveSpawnSubject = nil
    end
  end
})

return WaveController