local bzutils = require("bzutils")
local rx = require("rx")
local easing = require("easing")
local exmath = require("exmath")
local utils = require("utils")

local lvdf = require("lvdf")

local bundle = {}

if IsBzr() then
  bundle = lvdf.loadBundle()
end
local function _GetBase(...)
  return (GetBase(...) or ""):gmatch("[^%c]*")()
end


local easeOutBackV = easing.easeOutBackV

local local2Global = exmath.local2Global
local global2Local = exmath.global2Local
local isNullPos = utils.isNullPos
local interpolatedNormal = easing.interpolatedNormal
local calcPt = easing.calcPt

local mfield = {
  "right_x", "right_y", "right_z",
  "up_x", "up_y", "up_z",
  "front_x", "front_y", "front_z",
  "posit_x", "posit_y", "posit_z"
}


local function hasVdf(handle)
  local base = _GetBase(handle)
  return bundle[base] ~= nil
end

local function getVdf(handle)
  if hasVdf(handle) then
    local base = _GetBase(handle)
    return bundle[base]
  end
end


local AddMatrix = function(...)
  local m = SetMatrix()
  for i, m2 in ipairs({...}) do
    for _, k in pairs(mfield) do
      m[k] = m[k] + m2[k]
    end
  end
  return m
end

local ScaleMatrix = function(m2, v)
  local m = SetMatrix()
  for _, k in pairs(mfield) do
    m[k] = m2[k] * v
  end
  return m
end

local function InterpolateMatrix(base, target, smoothness)
  smoothness = smoothness or 1
  local f1 = SetVector(base.front_x, base.front_y, base.front_z)
  local f2 = SetVector(target.front_x, target.front_y, target.front_z)
  local fn = Normalize(calcPt(f1, f2, 1/smoothness))

  local p1 = SetVector(base.posit_x, base.posit_y, base.posit_z)
  local p2 = SetVector(target.posit_x, target.posit_y, target.posit_z)
  local pn = calcPt(p1, p2, 1/smoothness)

  return BuildDirectionalMatrix(pn, fn)
end


local fperson_parts = {
  "hed", "tur","lgt", "gc1", "gc2", "gr1", "gr2", "pov"
}

local default_parts = {
  "tur", "bda", "ty1"
}
-- parts that has greater influence on camera position
local strong_parts = {
  "nrr", "hed", "rsh", "tx1", "nfr", "gc2"
}

CameraController = bzutils.utils.createClass("CameraController", {
  new = function(self, props)
    self.terminate = props.terminate
    self.base = nil
    self:setBase(nil, SetVector(0,0,0))
    self.destroySubject = rx.Subject.create()
    self.smoothness = 0.5
    self.avoid_ground = true
  end,
  routineWasCreated = function(self, base, offset, target, targetOffset)
    self:setBase(base, offset)
    self:setTarget(target)
    self:setTargetOffset(targetOffset)
    self.easingFunc = easingFunc or easeOutBackV
    self.anchor = BuildObject("nparr", 0, GetPosition(self.base))
    self.target_anchor = BuildObject("nparr", 0, GetPosition(self.base))
    SetLocal(self.anchor)
    SetLocal(self.target_anchor)
  end,
  setBase = function(self, base, offset)
    self.base = base
    self:setOffset(offset)
    self.previous_transform = GetTransform(self.base)
  end,
  setOffset = function(self, offset)
    self.offset = offset or self.offset or SetVector(0, 0, 0)
  end,
  setTarget = function(self, target)
    self.target = target or self.base
  end,
  setTargetOffset = function(self, offset)
    self.target_offset = offset or self.target_offset or SetVector(0, 0, 0)
  end,
  onDestroyed = function(self)
    return self.destroySubject
  end,
  postInit = function(self)
    print("Creating camera")
    CameraReady()
  end,
  setSmoothnessFactor = function(self, factor)
    self.smoothness = factor
  end,
  setAvoidGround = function(self, avoid)
    self.avoid_ground = avoid
  end,
  update = function(self, dtime)
    local offset = self.offset
    local anchor_offset = SetVector(-10000, -10000, -10000)

    local cc = CameraCancelled()
    local ntransform = InterpolateMatrix(self.previous_transform, GetTransform(self.base),self.smoothness/dtime)
    --local lookatbase_transform = InterpolateMatrix(self.previous_transform, GetTransform(self.target),self.smoothness/dtime)
    local inter_pos = SetVector(ntransform.posit_x, ntransform.posit_y, ntransform.posit_z)

    local lookAt = GetPosition(self.target) + self.target_offset
    --if(self.previous_lookat) then
    --  lookAt = calcPt(self.previous_lookat, lookAt, 1/(self.smoothness/dtime) )
    --end

    --self.previous_lookat = lookAt

    self.previous_transform = ntransform
    SetTransform(self.anchor, ntransform)
    SetPosition(self.anchor, GetPosition(self.anchor) + anchor_offset)


    offset = local2Global(offset, ntransform)
    local actualOffset = offset + inter_pos
    local h, normal = GetFloorHeightAndNormal(actualOffset + SetVector(0,5,0))
    if(self.avoid_ground) then
      actualOffset.y = math.max(actualOffset.y, h + 5)
    end
    offset = actualOffset - inter_pos - anchor_offset
    offset = global2Local(offset, ntransform)

    local look_dir = Normalize(lookAt - actualOffset)
    if(self.previous_lookat) then
      look_dir = Normalize(calcPt(self.previous_lookat, look_dir, 1/( (self.smoothness*0.25) /dtime) ))
    end
    local target_anchor_pos = look_dir*10000 + actualOffset


    self.previous_lookat = look_dir

    SetPosition(self.target_anchor, target_anchor_pos)
    if (not IsValid(self.base)) or CameraObject(
      self.anchor,
      (offset.z) * 100,
      (offset.y) * 100,
      (offset.x) * 100,
      self.target_anchor) or cc then
        self.terminate(cc)
    end
  end,
  routineWasDestroyed = function(self, cc)
    CameraFinish()
    print("Removing camera")
    RemoveObject(self.anchor)
    RemoveObject(self.target_anchor)
    self.destroySubject:onNext(not cc)
  end
})

-- controller for spectating players
SpectateController = bzutils.utils.createClass("SpectateController", {
  new = function(self, props)
    self.hfunc = nil
    self.terminate = props.terminate
    self.serviceManager = props.serviceManager
    self.serviceManager:getServices("bzutils.runtime", "bzutils.net"):subscribe(function(runtimeController, net)
      self.runtimeController = runtimeController
      self.net = net
    end)
    self.playerIdx = 1
    self.retry = 0
    self.players = {}
    self.cameraRoutineId = -1
    self.cancelled = false
    self.viewModes = {"SHOULDER", "TARGET", "AHEAD", "FIRST_PERSON"}
    self.currentViewMode = 1
  end,
  routineWasCreated = function(self, players, offset, zoom, tp_player, hfunc)
    offset = offset or 0
    self.tp_player = tp_player==nil and true or tp_player
    self.playerPos = GetTransform(GetPlayerHandle())
    self:setZoom(zoom)
    self.playerIdx = (offset > 0 and offset <= #players and offset) or self.playerIdx
    self.players = players
    self.hfunc = hfunc
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
    local ph = nil
    if not self.hfunc then
      ph = self.players[self.playerIdx] and self.net:getPlayerHandle(self.players[self.playerIdx].team) --GetPlayerHandle(self.players[self.playerIdx].team)
    else
      ph = self.hfunc(self.players[self.playerIdx])
    end
    self.zoom = math.min(math.max(zoom==nil and 1 or zoom, 0), 3)
    local r = self.runtimeController:getRoutine(self.cameraRoutineId)
    if r ~= nil then
      local vm = self.viewModes[self.currentViewMode]
      if(vm == "FIRST_PERSON") then
        if hasVdf(ph) then
          -- modify our offset
          local newOffset = SetVector(0, 0, 0)
          local d = 1
          local vdf = getVdf(ph)
          for _, partname in ipairs(fperson_parts) do
            if vdf:hasPart(partname) then
              newOffset = newOffset + vdf:getPart(partname):getPosition()
              d = d + 1
            end
          end
          newOffset = newOffset/d + SetVector(0.7, 1.1, -0.1)
          r:setOffset(newOffset)
        else
          r:setOffset(self:getOffsetVec(ph))
        end
        
        r:setSmoothnessFactor(0.01)
      else
        r:setOffset(self:getOffsetVec(ph))
        r:setSmoothnessFactor(0.1 + ({0.0, 0.1, 0.35, 0.9})[(3-self.zoom + 1)] )
      end

    end
  end,
  getBaseVector = function(self, ph)
    local baseOffset = SetVector(0, 0, 0)
    if hasVdf(ph) then
      local vdf = getVdf(ph)
      local vm = self.viewModes[self.currentViewMode]
      local d = 1
      for _, partname in ipairs(default_parts) do
        if vdf:hasPart(partname) then
          baseOffset = baseOffset + vdf:getPart(partname):getPosition()
          d = d + 1
        end
      end
      for _, partname in ipairs(strong_parts) do
        if vdf:hasPart(partname) then
          baseOffset = baseOffset + (vdf:getPart(partname):getPosition()*5)
          d = d + 5
        end
      end
      baseOffset = baseOffset/d
    end
    return baseOffset
  end,
  getOffsetVec = function(self, ph)
    return self:getBaseVector(ph) + SetVector(-10 - math.pow(4-self.zoom, 2)*1.1,2 + math.pow(4-self.zoom, 2.2)/1.5,0)
  end,
  zoomIn = function(self)
    self:setZoom(self.zoom + 1)
  end,
  zoomOut = function(self)
    self:setZoom(self.zoom - 1)
  end,
  rotateMode = function(self)
    self.currentViewMode = (self.currentViewMode)%(#self.viewModes) + 1
    DisplayMessage(("Camera Mode: %s"):format(self.viewModes[self.currentViewMode]))
  end,
  _updateViewMode = function(self, ph, alttarget)
    local lookAt = SetVector(0, 0, 0)
    local vm = self.viewModes[self.currentViewMode]
    local t = GetTarget(ph)


    local offsetVec = self:getBaseVector(ph)
    offsetVec = local2Global(offsetVec + SetVector(5, 0, 0), GetTransform(ph))
    if(not IsValid(t)) then
      t = alttarget
    end
    if(vm == "SHOULDER" or vm == "TARGET") then
      lookAt = offsetVec
    end
    if(vm == "TARGET") and IsValid(t) then
      lookAt = GetPosition(t) - GetPosition(ph)
    end
    if(vm == "AHEAD" or vm == "FIRST_PERSON") then
      lookAt = GetFront(ph) * 500 + offsetVec
    end
    if(vm == "TARGET" or vm == "FIRST_PERSON") then
      SetUserTarget(t)
    else
      SetUserTarget(nil)
    end


    local r = self.runtimeController:getRoutine(self.cameraRoutineId)
    if r~= nil then
      self:setZoom(self.zoom)
      r:setTargetOffset(lookAt)
      if(vm == "FIRST_PERSON") then
        r:setAvoidGround(false)
      else
        r:setAvoidGround(true)
      end
    end
  end,
  updatePlayer = function(self)
    --self.playerIdx = (self.playerIdx % #self.players) + 1
    local ph = nil
    if not self.hfunc then
      ph = self.players[self.playerIdx] and self.net:getPlayerHandle(self.players[self.playerIdx].team) --GetPlayerHandle(self.players[self.playerIdx].team)
    else
      ph = self.hfunc(self.players[self.playerIdx])
    end
    if not IsValid(ph) then
      self:nextPlayer()
      return
    end
    self.retry = 0
    local r = self.runtimeController:getRoutine(self.cameraRoutineId)
    if r~=nil then
      r:setBase(ph)
      r:setTarget(ph)

    end
  end,
  _createCameraR = function(self)
    print("Creating new!", self.cancelled)
    self.cameraRoutineId, camctrl = self.runtimeController:createRoutine(CameraController, ph, self:getOffsetVec(ph), ph, SetVector(0, 0, 0))
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
    local r = self.runtimeController:getRoutine(self.cameraRoutineId)
    if r==nil and not self.cancelled then
      self:_createCameraR()
    end

    local ph = nil
    if not self.hfunc then
      ph = self.players[self.playerIdx] and self.net:getPlayerHandle(self.players[self.playerIdx].team)
    else
      ph = self.hfunc(self.players[self.playerIdx])
    end

    if IsValid(ph) then
      local pt = self.players[self.playerIdx] and self.net:getTarget(ph)
      local pp = GetPosition(ph)

      self:_updateViewMode(ph, pt)
      if self.tp_player then
        if not isNullPos(pp) then
          local h = GetTerrainHeightAndNormal(pp)
          SetTransform(GetPlayerHandle(), GetTransform(ph))
          pp.y = h - 35
          SetPosition(GetPlayerHandle(), pp)
          SetVelocity(GetPlayerHandle(), GetVelocity(ph))
        end
      end
    end
  end,
  enableGamekey = function(self, ed)
    self.ed_sub = ed:on("GAME_KEY"):subscribe(function(event)
      self:gameKey(event:getArgs())
    end)
  end,
  enableMovePlayer = function()
    self.movePlayer = true
  end,
  gameKey = function(self, key)
    if key == "GreyPlus" or key == "+" then
      self:zoomIn()
    elseif key == "GreyMinus" or key == "-" then
      self:zoomOut()
    elseif key == "Tab" then
      self:nextPlayer()
    elseif key == "C" then
      self:rotateMode()
    end
  end,
  routineWasDestroyed = function(self)
    if self.sub then
      self.sub:unsubscribe()
    end
    if self.ed_sub then
      self.ed_sub:unsubscribe()
    end
    self.runtimeController:clearRoutine(self.cameraRoutineId)
    if self.tp_player then
      SetTransform(GetPlayerHandle(), self.playerPos)
    end
  end
})



return {
  CameraController = CameraController,
  SpectateController = SpectateController
}
