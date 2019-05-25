local bzindex = require("bzindex")
local bzt = require('bzst17')
local bzutils = require("bzutils")
local setup = bzutils.defaultSetup()
local core = setup.core
local serviceManager = setup.serviceManager
local cam_ctrl = require("cam_ctrl")

local runtime = require("runtime")

local shared = require("shared")
local utils = require("utils")
shared.setup(serviceManager)
local SpectateController = shared.SpectateController

-- disable gamekey for bzst17
function GameKey(...)
end

-- run seperate bzutils on top of bzst17
local msetup = require("msetup")
msetup.fullSetup(core)

-- demo runtime

-- alternate between nsdf, cca, bdog and cra
--[[
  ships to spectate
  vtank, vscav, vartl, vfigh, vltnk



]]

local specUnits = {
  "vwalk", "vtank", "vfigh"
}

local current_nation = 1

local factions = {
  a = "American",
  s =  "Soviet",
  b =  "Black dogs",
  c = "Chinese"
}
local nations = {"a", "s", "b", "c"}

local nextId = 1

local function createFakePlayer(handle)
  local team = GetTeamNum(handle)
  local id = nextId
  local nation = GetNation(handle) or "a"
  local faction = factions[nation] or "Unknown"
  local name = ("%s - %s"):format(faction, GetOdf(handle))
  nextId = nextId + 1
  local player = {
    name = name,
    id = id,
    team = team,
    handle = handle
  }
  return id, player 
end

-- camera routine assumes you're spectating a player
local function createFakePlayerHandleFunction(players)
  return function(player)
    --if player then
      local id = player.id
      if players[id] ~= nil then
        return players[id].handle
      end
    --end
  end
end

-- custom demo functionality
local startNewRound
startNewRound = function(runtime_m)
  print("Start new round")
  -- delete old object, spawn new ones
  -- set up timers
  local units = {}
  local camera_units = {}
  
  local respawn_interval = -1
  local spectate_r = -1


  current_nation = ((current_nation - 1) % #nations) + 1
  local target_nation = nations[ (current_nation % #nations) + 1]
  local nation = nations[current_nation]
  local roundTimeout = runtime_m:setTimeout(function()
    if respawn_interval ~= -1 then
      runtime_m:clearInterval(respawn_interval)
    end
    if spectate_r ~= -1 then
      runtime_m:clearRoutine(spectate_r)
    end
    for i, unit in ipairs(units) do
      RemoveObject(unit)
    end
    current_nation = current_nation + 1
    runtime_m:setTimeout(function() 
      startNewRound(runtime_m)
    end, 1)
  end, 60)

  local unitList = {target_nation .. "vscav"}
  
  local targets = utils.spawnInFormation2({" 1 1 1 1 ", " 1 1 1 1 ", " 1 1 1 1 "},"scavs", unitList, 6, 20)
  for _, unit in ipairs(targets) do
    table.insert(units, unit)
    Goto(unit, "attack")
  end



  local unitList = {}
  for _, name in ipairs(specUnits) do
    table.insert(unitList, nation .. name)
  end
  local players = {}
  local playerMap = {}
  print("Spawning units")


  local spawned = utils.spawnInFormation2({" 1 2 3 "},"attack", unitList, 5, 20)
  for _, unit in ipairs(spawned) do
    Attack(unit, targets[math.random(1, #targets)])
    local id, player = createFakePlayer(unit)
    playerMap[id] = player
    table.insert(units, unit)
    table.insert(players, player)
  end



  runtime_m:setTimeout(function()
    print("Starting camera routine")
    local id, r = runtime_m:createRoutine(SpectateController, players, 1, 1, false, createFakePlayerHandleFunction(playerMap))
    spectate_r = id
    r:enableGamekey(serviceManager:getServiceSync("bzutils.bzapi"):getDispatcher())
  end, 2)

end




serviceManager:getService("bzutils.runtime"):subscribe(function(runtimeController)
  print("Got runtime")
  runtimeController:setTimeout(function()
    startNewRound(runtimeController)
  end, 5)
end)