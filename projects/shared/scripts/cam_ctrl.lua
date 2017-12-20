local bzutils = require("bzutils")
local rx = require("rx")
local runtimeController = bzutils.runtime.runtimeController
local easing = require("easing")

local easeOutBackV = easing.easeOutBackV

local local2Global = bzutils.utils.local2Global
local global2Local = bzutils.utils.global2Local
local isNullPos = bzutils.utils.isNullPos
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
    self:setOffset(offset)
  end,
  setOffset = function(self, offset)
    self.offset = offset or self.offset or SetVector(0, 0, 0)
  end,
  setTarget = function(self, target)
    self.target = target or self.base
  end,
  onDestroyed = function(self)
    return self.destroySubject
  end,
  postInit = function(self)
    print("Creating camera")
    CameraReady()
  end,
  update = function(self, dtime)
    local offset = self.offset
    local cc = CameraCancelled()
    offset = local2Global(offset, GetTransform(self.base))
    local actualOffset = offset + GetPosition(self.base)
    local h, normal = GetFloorHeightAndNormal(actualOffset + SetVector(0,5,0))
    actualOffset.y = math.max(actualOffset.y, h + 5)
    offset = actualOffset - GetPosition(self.base) 
    offset = global2Local(offset, GetTransform(self.base))
    if (not IsValid(self.base)) or CameraObject(
      self.base, 
      offset.z * 100,
      offset.y * 100,
      offset.x * 100,
      self.base) or cc then
        self.terminate(cc)
    end
  end,
  routineWasDestroyed = function(self, cc)
    CameraFinish()
    print("Removing camera")
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
    self.cancelled = false
  end,
  routineWasCreated = function(self, players, offset, zoom, tp_player)
    offset = offset or 0
    self.tp_player = tp_player==nil and true or tp_player
    self.playerPos = GetTransform(GetPlayerHandle())
    self:setZoom(zoom)
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
  setZoom = function(self, zoom)
    self.zoom = math.min(math.max(zoom==nil and 1 or zoom, 0), 3)
    local r = runtimeController:getRoutine(self.cameraRoutineId)
    if r ~= nil then
      r:setOffset(self:getOffsetVec())
    end
  end,
  getOffsetVec = function(self)
    return SetVector(-10 - math.pow(4-self.zoom, 2)*1.1,2 + math.pow(4-self.zoom, 2.2)/1.5,0)
  end,
  zoomIn = function(self)
    self:setZoom(self.zoom + 1)
  end,
  zoomOut = function(self)
    self:setZoom(self.zoom - 1)
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
    if r~=nil then
      r:setBase(ph)
    end
  end,
  _createCameraR = function(self)
    print("Creating new!", self.cancelled)
    self.cameraRoutineId, camctrl = runtimeController:createRoutine(CameraController, ph, self:getOffsetVec())
    self.sub = camctrl:onDestroyed():subscribe(function(a)
      if not a then
        self.cancelled = true
        self.terminate()
      else
        self.cameraRoutineId = -1
      end
    end)
    self:updatePlayer()
  end,
  postInit = function(self)
    self:_createCameraR()
  end,
  update = function(self)
    local r = runtimeController:getRoutine(self.cameraRoutineId)
    if r==nil and not self.cancelled then
      self:_createCameraR()
    end
    if self.tp_player then
      local ph = self.players[self.playerIdx] and net:getPlayerHandle(self.players[self.playerIdx].team)
      if IsValid(ph) then
        local pp = GetPosition(ph)
        if not isNullPos(pp) then
          local h = GetTerrainHeightAndNormal(pp)
          pp.y = h - 35
          SetPosition(GetPlayerHandle(), pp)
          SetVelocity(GetPlayerHandle(), SetVector(0,0,0))
        end
      end
    end
  end,
  enableGamekey = function(self, ed)
    self.ed_sub = ed:on("GAME_KEY"):subscribe(function(event)
      self:gameKey(event:getArgs())
    end)
  end,
  enableMovelayer = function()
    self.movePlayer = true
  end,
  gameKey = function(self, key)
    if key == "GreyPlus" or key == "+" then
      self:zoomIn()
    elseif key == "GreyMinus" or key == "-" then
      self:zoomOut()
    elseif key == "Tab" then
      self:nextPlayer()
    end
  end,
  routineWasDestroyed = function(self)
    if self.sub then
      self.sub:unsubscribe()
    end
    runtimeController:clearRoutine(self.cameraRoutineId)
    if self.tp_player then
      SetTransform(GetPlayerHandle(), self.playerPos)
    end
  end
})



return {
  CameraController = CameraController,
  SpectateController = SpectateController
}