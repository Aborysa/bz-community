local bzutils = require("bzutils")
local rx = require("rx")
local runtimeController = bzutils.runtime.runtimeController
local easing = require("easing")

local easeOutBackV = easing.easeOutBackV

local local2Global = bzutils.utils.local2Global
local global2Local = bzutils.utils.global2Local

local interpolatedNormal = easing.interpolatedNormal

local net = bzutils.net.net

CameraController = bzutils.utils.createClass("CameraController", {
  new = function(self, terminate)
    self.terminate = terminate
    self.base = nil
    self:setBase(nil, SetVector(0,0,0))
    self.destroySubject = rx.Subject.create()
  end,
  routineWasCreated = function(self, base, offset, target, easingFunc)
    self:setBase(base, offset)
    self:setTarget(target)
    self.easingFunc = easingFunc or easeOutBackV
  end,
  setBase = function(self, base, offset)
    self.base = base
    self.offset = offset or self.offset or SetVector(0, 0, 0)
    if IsValid(self.dummy) then
      --SetPosition(self.dummy, GetPosition(self.base))
      --self.prev = GetPosition(self.dummy)
    end
  end,
  setTarget = function(self, target)
    self.target = target or self.base
  end,
  onDestroyed = function(self)
    return self.destroySubject
  end,
  postInit = function(self)
    self.dummy = BuildLocal("dummy", 0, GetPosition(self.base))
    self.prev = GetPosition(self.dummy)
    CameraReady()
  end,
  update = function(self, dtime)
    local offset = self.offset
    local cc = CameraCancelled()
    offset = global2Local(offset, GetTransform(self.base))
    local actualOffset = offset + GetPosition(self.base)
    local h, normal = GetFloorHeightAndNormal(actualOffset + SetVector(0,10,0))
    offset.y = offset.y + math.max(h - actualOffset.y, 0)
    offset = global2Local(offset, GetTransform(self.base))
    if (not IsValid(self.base)) or CameraObject(
      self.base, 
      offset.z * 100,
      offset.y * 100,
      offset.x * 100,
      self.base) or cc then
        self.terminate(cc)
    else
      local pos = GetPosition(self.dummy)
      SetTransform(self.dummy, GetTransform(self.base))
      SetPosition(self.dummy, self.easingFunc(self.prev, GetPosition(self.base), dtime*4))
      self.prev = self.easingFunc(self.prev, GetPosition(self.dummy), dtime*4)
    end
  end,
  routineWasDestroyed = function(self, cc)
    CameraFinish()
    RemoveObject(self.dummy)
    self.destroySubject:onNext(not cc)
  end
})

-- controller for spectating players
SpectateController = bzutils.utils.createClass("SpectateController", {
  new = function(self, terminate)
    self.terminate = terminate
    self.playerIdx = 1
    self.retry = 0
    self.players = {}
    self.cameraRoutineId = -1
  end,
  routineWasCreated = function(self, players, offset)
    self.playerIdx = (offset > 0 and offset <= #players and offset) or self.playerIdx
    self.players = players
  end,
  setPlayer = function(self, offset)
    self.playerIdx = (offset > 0 and offset <= #self.players and offset) or self.playerIdx
    self:updatePlayer()
  end,
  nextPlayer = function(self)
    self.playerIdx = (self.playerIdx % #self.players) + 1
    self.retry = self.retry + 1
    if self.retry <= #self.players then
      self:updatePlayer()
    else
      self.terminate()
    end
  end,
  updatePlayer = function(self)
    --self.playerIdx = (self.playerIdx % #self.players) + 1
    local ph = self.players[self.playerIdx] and net:getPlayerHandle(self.players[self.playerIdx].team) --GetPlayerHandle(self.players[self.playerIdx].team)
    if not IsValid(ph) then
      self:nextPlayer()
      return
    end
    self.retry = 0
    local r = runtimeController:getRoutine(self.cameraRoutineId)
    if r==nil then
      self.cameraRoutineId, camctrl = runtimeController:createRoutine(CameraController, ph, SetVector(-20,10,0))
      self.sub = camctrl:onDestroyed():subscribe(function(a)
        if a then
          self:updatePlayer()
        else
          self.terminate()
        end
      end)
    else
      r:setBase(ph)
    end
  end,
  postInit = function(self)
    self:updatePlayer()
  end,
  update = function(self)

  end,
  routineWasDestroyed = function(self)
    if self.sub then
      self.sub:unsubscribe()
    end
    runtimeController:clearRoutine(self.cameraRoutineId)
  end
})



return {
  CameraController = CameraController,
  SpectateController = SpectateController
}