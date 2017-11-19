local bzutils = require("bzutils")
local core = bzutils.core

local shared = require("shared")
local runtimeController = bzutils.runtime.runtimeController

local CameraController = shared.CameraController

local target = nil
local rid = nil
function Start()
  core:start()
  target = GetPlayerHandle()
  rid = runtimeController:createRoutine(CameraController, target, SetVector(-30,20,0))
end

function Update(dtime)
  core:update(dtime)
end

function AddObject(h)
  core:addObject(h)
end

function CreateObject(h)
  core:createObject(h)
end

function DeleteObject(h)
  core:deleteObject(h)
end

function GameKey(key)
  print("key", key)
  if key == "Tab" and rid ~= nil then
    local controller = runtimeController:getRoutine(rid)
    local base = ({[GetRecyclerHandle()] = GetPlayerHandle(), [GetPlayerHandle()] = GetRecyclerHandle()})[target]
    target = base
    controller:setBase(base)
    controller:setTarget(base)
  end
  core:gameKey(key)
end