local bzindex = require("bzindex")
local bzutils = require("bzutils")
local runtime = require("runtime")

local setup = bzutils.defaultSetup()

local core = setup.core
local serviceManager = setup.serviceManager

local utils = bzutils.utils
local rx = require("rx")

local shared = require("shared")

shared.setup(serviceManager)
local SpectateController = shared.SpectateController

local Store = utils.Store
local SharedStore = bzutils.net.SharedStore
local Observable = rx.Observable

local BroadcastSocket = bzutils.net.BroadcastSocket
local ServerSocket = bzutils.net.ServerSocket


local compareTables = utils.compareTables
local namespace = utils.namespace
local getFullName = utils.getFullName
local SpectatorCraft = shared.SpectatorCraft

local removeOnDead = {}
local removeOnNext = {}
local assignObject = utils.assignObject

--local event = bzutils.event.bzApi

local spawnlib = require("spawnlib")

local _DisplayMessage = DisplayMessage
function DisplayMessage(...)
  print("Display: ", ...)
  _DisplayMessage(...)
end

local config = Store({
  playerSpawns = "p_spawns",
  spectatorSpawns = "spectator_spawns",
  spawnLayers = {},
  spawnType = "roundRobin" --roundRobin, --layered, --furtherAway
})




SetCloaked = SetCloaked or function()end
Hide = Hide or function()end



local function forceSpectatorCraft(handle)
  for i=1,15 do
    Ally(GetTeamNum(handle), i)
  end
  SetPilotClass(handle, "tvspec")
  HopOut(handle)
  removeOnDead[handle] = true
end

local GameController = utils.createClass("GameController", {
  new = function(self, props)
    self.serviceManager = props.serviceManager
    
    self.displayText = ""
    self.showInfo = true
    self.ready = false
    self.spectating = false

    -- has player spawned
    self.spawned = false

    self.spectate_r = -1
    self.spawn_point = nil
    self.maxPlayers = 0
    self.renderTimer = runtime.Timer(0.19,-1, self.serviceManager)
    self.renderTimer:onAlarm():subscribe(function()
      self:_rerender()
    end)
    self.renderTimer:start()

    self.statsUpdateTimer = runtime.Timer(1, -1, self.serviceManager)
    self.statsUpdateTimer:onAlarm():subscribe(function()
      self:_updateStats()
    end)
    self.statsUpdateTimer:start()
    self.terminate = props.terminate

    self.ph = GetPlayerHandle()
    self.pp = GetPosition(self.ph)
    self.gameStore = Store({
      startTimer = 20,
      playerCount = 0,
      spectatorCount = 0,
      gameStarted = false,
      spawnOffset = 0,
      players = {},
      usedSpawnpoints = {},
      spawnSequence = {}
    })
    self.playerStore = Store({})
    self.extraStatsStore = Store({
      --factoryCount = 0,
      --armoryCount = 0,
      destroyedVehicles = 0,
      destroyedBuildings = 0,
      --builtVehicleTotal = 0,
      --builtBuildingsTotal = 0,
      --vehicleCount = 0,
      --buildingCount = 0
    })



    self.trackedObjects = {}
    self.removeObjectCache = {}
    AddObjective("stats.obj", "white", 8, self.displayText)
  end,
  routineWasCreated = function(self, config)
    self.mapConfig = config
  end,
  postInit = function(self)
    local conf = self.mapConfig:getState()
    -- check local players craft to determin if they're spectating or not
    RemoveObject(GetRecyclerHandle())
    self.serviceManager:getService("bzutils.bzapi"):subscribe(function(bzapi)
      local dp = bzapi:getDispatcher()
      dp:on("GAME_KEY"):subscribe(function(event)
        self:gameKey(event:getArgs())
      end)
  
      dp:on("CREATE_OBJECT"):subscribe(function(event)
        self:createObject(event:getArgs())
      end)

      dp:on("ADD_OBJECT"):subscribe(function(event)
        self:addObject(event:getArgs())
      end)
      
      dp:on("DELETE_OBJECT"):subscribe(function(event)
        self:deleteObject(event:getArgs())
      end)
    end)
    local playerPoints = GetPathPoints(conf.playerSpawns)
    self.maxPlayers = #playerPoints
    local spawnOffset = 1
    if self.maxPlayers > 1 then
      spawnOffset = math.random(1, self.maxPlayers)
    end
    self.gameStore:set("spawnOffset", spawnOffset)
    self.gameStore:set("spawnSequence", spawnlib.generateSpawnSequence(conf.spawnType, playerPoints, spawnOffset, conf.spawnLayers))
    local ph = GetPlayerHandle()
    if IsOdf(ph, "tvspec") then
      self.spectating = true
    else
      self.playerPilot = GetPilotClass(ph)
      SetPilotClass(ph, "")
    end
    self.displayText = "Waiting for network...\n"
    DisplayMessage("Waiting for network...")
    
    self.serviceManager:getService("bzutils.net"):subscribe(function(net)
      self.net = net
      self.net:onNetworkReady():subscribe(function()
        DisplayMessage("Network is ready!")
        self.displayText = self.displayText .. "Network is ready!\n"
        self:_setUpSockets()
      end)
      self.net:onHostMigration():subscribe(function()
        DisplayMessage("Host migrated")
        self.displayText = "Host migrated\n"
        self:_setUpSockets()
      end)
    end)

  end,
  _rerender = function(self)
    if self.showInfo or (not self.ready) then
      UpdateObjective("stats.obj", "yellow", 0.2, self.displayText)
      self.showInfo = true
    end
  end,
  _updateStats = function(self)
    if not (gameState.gameStarted and not self.spectating) then
      return
    end
    local player = self.net:getLocalPlayer()
    local ph = GetPlayerHandle()
    local pstate = self.playerStore:getState()[player.id] or assignObject({scrap = 0, pilot = 0, mscrap = 0, mpilot = 0, hasRecycler = true, hasFactory = false, hasArmory = false, hasConstructor = false}, self.extraStatsStore:getState())
    local nstate = {
      scrap = GetScrap(player.team),
      pilot = GetPilot(player.team),
      mscrap = GetMaxScrap(player.team),
      mpilot = GetMaxPilot(player.team),
      --ammo = GetAmmo(ph),
      --health = GetHealth(ph),
      hasRecycler = IsAlive(GetRecyclerHandle()),
      hasFactory = IsAlive(GetFactoryHandle()),
      hasArmory = IsAlive(GetArmoryHandle()),
      hasConstructor = IsAlive(GetConstructorHandle())
    }

    for k, v in pairs(self.extraStatsStore:getState()) do
      nstate[k] = v
    end

    -- for loop to just check if the table isn't empty
    for i, v in pairs(compareTables(pstate, nstate)) do
      self.playerStore:set(player.id, nstate)
      break
    end

    local destroyList = {}

    for i, h in pairs(self.removeObjectCache) do
      local v = self.trackedObjects[h]
      if(v ~= nil) then
        if v.lastEnemyShot < 10+GetTime() and v.lastEnemyShot > v.lastFriendShot then
          if(IsValid(v.whoShotMeLast)) then
            local team = GetTeamNum(v.whoShotMeLast)
            destroyList[team] = destroyList[team] or {vcount=0, bcount=0}
            local list = destroyList[team]
            if(v.isVehicle) then
              list.vcount = list.vcount + 1
            else
              list.bcount = list.bcount + 1 
            end
          end
        end
      end

      self.trackedObjects[h] = nil
    end
    self.removeObjectCache = {}

    for h, v in pairs(self.trackedObjects) do
      if(IsAlive(h)) then
        v.whoShotMeLast = GetWhoShotMe(h)
        v.lastEnemyShot = GetLastEnemyShot(h)
        v.lastFriendShot = GetLastFriendShot(h)
      else
        table.insert(self.removeObjectCache, v)
      end
    end

    for team, dstats in pairs(destroyList) do
      self.gameEventSocket:send("DESTROYED", team, dstats.vcount, dstats.bcount)
    end

  end,
  _setUpSockets = function(self)
    self.displayText = self.displayText .. "Setting up sockets...\n"
    DisplayMessage("Setting up sockets...")
    self.stateSocket = nil
    self.eventSocket = nil
    self.playerSocket = nil
    self.gameEventSocket = nil
    self.ready = false
    self.acc = 0
    local socketsub1 = nil
    local socketsub2 = nil
    local socketsub3 = nil
    local socketsub4 = nil
    local socketsLeft = 4
    if IsHosting() then
      socketsub2 = Observable.of(self.net:openSocket(0, ServerSocket, "bzt", "event", "sock"))
      socketsub1 = Observable.of(self.net:openSocket(0, BroadcastSocket, "bzt", "state", "sock"))
      socketsub3 = Observable.of(self.net:openSocket(0, BroadcastSocket, "bzt", "player", "sock"))
      socketsub4 = Observable.of(self.net:openSocket(0, BroadcastSocket, "bzt", "game_event", "sock"))
    else
      socketsub2 = self.net:getRemoteSocket("bzt", "event", "sock")
      socketsub1 = self.net:getRemoteSocket("bzt","state","sock")
      socketsub3 = self.net:getRemoteSocket("bzt", "player", "sock")
      socketsub4 = self.net:getRemoteSocket("bzt", "game_event", "sock")
    end

    socketsub1:subscribe(function(socket)
      socketsLeft = socketsLeft - 1
      self.ready = socketsLeft <= 0
      self.displayText = self.displayText .. "State socket set up!\n"
      DisplayMessage("State socket set up!")
      self.stateSocket = socket
      self.gameStore = SharedStore(self.gameStore:getState(), socket)
      self.gameStore:onKeyUpdate():subscribe(function(...)
        self:_storeKeyUpdate(...)
      end)
    end)
    socketsub2:subscribe(function(socket)
      socketsLeft = socketsLeft - 1
      self.ready = socketsLeft <= 0
      self.displayText = self.displayText .. "Event socket set up!\n"
      DisplayMessage("Event socket set up!")
      self.eventSocket = socket
      socket:onReceive():subscribe(IsHosting() and function(...)
        print("Host rec", ...)
        self:_onHostReceive(...)
      end or function(...)
        print("Client rec", ...)
        self:_onReceive(...)
      end)
      if self.spawn_point==nil then
        if IsHosting() then
          if self.spectating then
            self.spawn_point = self:_addSpectator()
          else
            local succ, spawn = self:_addPlayer(self.net:getLocalPlayer().id)
            self.spawn_point = spawn
            if not succ then
              self.spectating = true
              forceSpectatorCraft(GetPlayerHandle())
            end
          end
        else
          socket:send(self.spectating and "SPECTATE" or "JOIN", self.net:getLocalPlayer().id)
        end
      end
    end)
    socketsub3:subscribe(function(socket)
      socketsLeft = socketsLeft - 1
      self.ready = socketsLeft <= 0
      self.displayText = self.displayText .. "Player stat socket set up!\n"
      DisplayMessage("Player stat socket set up!")
      self.playerSocket = socket
      self.playerStore = SharedStore(self.playerStore:getState(), socket)
      self.playerStore:onStateUpdate():subscribe(function(...)
        if self.spectating then
          self:_playerStoreUpdate(...)
        end
      end)
    end)
    socketsub4:subscribe(function(socket)
      socketsLeft = socketsLeft - 1
      self.ready = socketsLeft <= 0
      self.displayText = self.displayText .. "Game event socket set up!\n"
      DisplayMessage("Game event socket set up!")
      self.gameEventSocket = socket
      socket:onReceive():subscribe(function(...)
        self:_onGameEventReceive(...)
      end)
    end)

  end,
  _addPlayer = function(self, id)
    local state = self.gameStore:getState()
    local offset = state.spawnOffset
    local pc = state.playerCount
    if (not state.gameStarted) and pc < self.maxPlayers then
      self.gameStore:set("playerCount", pc + 1)
      local players = assignObject({}, state.players)
      table.insert(players, id)
      self.gameStore:set("players", players)
      local usedSpawnpoints = assignObject({},state.usedSpawnpoints)
      local spawnPoint = spawnlib.getNextSpawnPoint(usedSpawnpoints, state.spawnSequence)
      if spawnPoint == nil then
        return false, self:_addSpectator()
      end
      usedSpawnpoints[spawnPoint] = true
      self.gameStore:set("usedSpawnpoints", usedSpawnpoints)
      return true, spawnPoint  --% (self.maxPlayers) + 1
    else
      return false, self:_addSpectator()
    end
  end,
  _addSpectator = function(self)
    local sc = self.gameStore:getState().spectatorCount
    sc = sc + 1
    self.gameStore:set("playerCount", sc)
    return sc
  end,
  _storeKeyUpdate = function(self, key, value)
    if key == "startTimer" then
      self.displayText = ("Starting in %d seconds\n"):format(value)
      if value > 0 and value <= 3 then
        DisplayMessage(("Starting in %d"):format(value))
      end
    end
  end,
  _playerStoreUpdate = function(self, nstate)
    self.displayText = ""
    local sorted = {}
    for i, v in pairs(nstate) do
      local p = self.net:getPlayer(i)
      table.insert(sorted, {
        order = i,
        player = self.net:getPlayer(i) or {team = 0, name = "Unknown", id = i},
        state = v
      })
    end
    table.sort(sorted, function(a, b)
      return a.order < b.order
    end)
    for i, v in ipairs(sorted) do
      self.displayText = self.displayText .. ("%s (%d, %d):\n"):format(v.player.name, v.player.team, v.player.id)
      self.displayText = self.displayText .. ("  has factory, armory, const?: %s, %s, %s\n"):format(v.state.hasFactory and "yes" or "no", v.state.hasArmory and "yes" or "no", v.state.hasConstructor and "yes" or "no")
      self.displayText = self.displayText .. ("  scrap: %d/%d\n"):format(v.state.scrap, v.state.mscrap)
      self.displayText = self.displayText .. ("  pilot: %d/%d\n"):format(v.state.pilot, v.state.mpilot)
      self.displayText = self.displayText .. ("  destroyed buildings: %d\n"):format(v.state.destroyedBuildings)
      self.displayText = self.displayText .. ("  destroyed vehicles: %d\n"):format(v.state.destroyedVehicles)
    end
  end,
  _onReceive = function(self, what, ...)
    if what == "JOIN_M" then
      local ack, spawn = ...
      self.spectating = not ack
      self.spawn_point = spawn
      if not ack then
        forceSpectatorCraft(GetPlayerHandle())
      end
    elseif what == "SPEC_SPAWN" then
      self.spawn_point = ...
      self.spectating = true
    elseif what == "START" then
      self:_spawnInRecycler()
    end
  end,
  _onHostReceive = function(self, socket, what, ...)
    self:_onReceive(what, ...)
    if what == "JOIN" then
      self.gameStore:set("startTimer", 20)
      local succ, spawn = self:_addPlayer(...)
      socket:send("JOIN_M", succ, spawn)
    elseif what == "SPECTATE" then
      local spawn = self:_addSpectator()
      socket:send("SPEC_SPAWN", spawn)
    end
  end,
  _onGameEventReceive = function(self, what, ...)
    -- object(s) were destroyed
    if(what == "DESTROYED") then
      local team, vcount, bcount = ...
      if(self.net:getLocalPlayer().team == team) then
        local state = self.extraStatsStore:getState()
        self.extraStatsStore:set("destroyedVehicles", state.destroyedVehicles + vcount)
        self.extraStatsStore:set("destroyedBuildings", state.destroyedBuildings + bcount)
      end
    end
  end,
  _spawnInRecycler = function(self)
    if (not self.spectating) and (self.spawn_point ~= nil) then
      SetPilotClass(GetPlayerHandle(), self.playerPilot)
      local n = GetNation(GetPlayerHandle())
      local rtable = {"%svremp", "%svrecy", "avremp", "avrecy"}
      local conf = self.mapConfig:getState()
      for i, v in ipairs(rtable) do
        local recy = BuildObject(v:format(n), self.net:getLocalPlayer().team, GetPathPoints(self.spectating and conf.spectatorSpawns or conf.playerSpawns)[self.spawn_point])
        if IsValid(recy) then
          self:_trackObject(recy)
          break
        end
      end
      self:_trackObject(GetPlayerHandle())
      
      SetScrap(self.net:getLocalPlayer().team, 20)
    end
  end,
  update = function(self, dtime)
    local ph = GetPlayerHandle()
    local pp = GetPosition(ph)
    local vel = Length(GetVelocity(ph))
    if self.spawned and IsPerson(ph) then
      self.spawned = not ((not IsAlive(ph)) or vel < 1 and self.ph ~= ph and Distance3D(self.pp, pp) > (vel*dtime+10))
    end
    self.pp = pp
    self.ph = ph
    local gameState = self.gameStore:getState()
    if not (gameState.gameStarted or self.spectating) then
      SetVelocity(GetPlayerHandle(), SetVector(0, 0, 0))
      SetOmega(GetPlayerHandle(), SetVector(0, 0, 0))
    end
    if self.ready then
      if IsHosting() then
        if not gameState.gameStarted then
          if gameState.startTimer <= 0 then
            self.gameStore:set("gameStarted", true)
            self.eventSocket:send("START")
            self:_spawnInRecycler()
          end
          self.acc = self.acc + dtime
          if self.acc >= 1 then
            self.gameStore:set("startTimer", gameState.startTimer - 1)
            self.acc = self.acc - 1
          end
        end
      end
      if IsAlive(ph) and (not self.spawned) and (self.spawn_point ~= nil) and IsValid(GetPlayerHandle()) then
        local conf = self.mapConfig:getState()
        local spawn =  GetPathPoints(self.spectating and conf.spectatorSpawns or conf.playerSpawns)[self.spawn_point]
        SetPosition(ph,GetPositionNear(spawn, 50, 60))
        self.spawned = true
      end
    end
    if self.spectating then
      --Hide(ph)
      SetCloaked(ph)
    end
  end,
  createObject = function(self, handle)
    if (not self.gameStore:getState().gameStarted or self.spectating) then
      if GetClassLabel(handle) == "camerapod" then
        removeOnNext[handle] = true
        --RemoveObject(handle)
      end
    end
  end,
  deleteObject = function(self, handle)
    if(self.trackedObjects[handle] ~= nil) then
      table.insert(self.removeObjectCache, handle)
    end
  end,
  _trackObject = function(self, handle)
    print("Tracking object", handle)
    self.trackedObjects[handle] = {
      isVehicle = IsCraft(handle),
      whoShotMeLast = nil,
      lastEnemyShot = 0,
      lastFriendShot = 0
    }
  end,
  addObject = function(self, handle)
    if(self.gameStore:getState().gameStarted and not self.spectating) then
      self:_trackObject(handle)
    end
  end,
  gameKey = function(self, key)
    self.serviceManager:getService("bzutils.runtime"):subscribe(function(runtimeController)
      local r = runtimeController:getRoutine(self.spectate_r)
      if key == "O" then
        self.showInfo = not self.showInfo
      end
      local w = key:gmatch("[^F](%d)")();
      if(w and self.ready and self.spectating) then
        w = tonumber(w)
        if r ~= nil then
          r:setPlayer(w)
        else
          local players = {}
          for i,v in ipairs(self.gameStore:getState().players) do
            table.insert(players, self.net:getPlayer(v))
          end
          local id, r = runtimeController:createRoutine(SpectateController, players, w, 1, true)
          self.spectate_r = id
          r:enableGamekey(self.serviceManager:getServiceSync("bzutils.bzapi"):getDispatcher())
        end
      end
    end)
  end
})


namespace("bzt", GameController)



serviceManager:getServices("bzutils.component","bzutils.runtime"):subscribe(function(componentManager, runtimeController)
  componentManager:useClass(SpectatorCraft)
  runtimeController:useClass(GameController)
end)

function Start()
  serviceManager:getService("bzutils.runtime"):subscribe(function(runtimeController)
    runtimeController:createRoutine(GameController, config)
  end)
  core:start()
end


function Update(dtime)
  core:update(dtime)
  for i, v in pairs(removeOnDead) do
    HopOut(i)
    if not IsAliveAndPilot(i) then
      RemoveObject(i)
      removeOnDead[i] = nil
    end
  end
  for i, v in pairs(removeOnNext) do
    RemoveObject(i)
  end
  removeOnNext = {}
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

function AddPlayer(...)
  core:addPlayer(...)
end

function DeletePlayer(...)
  core:deletePlayer(...)
end

function CreatePlayer(...)
  core:createPlayer(...)
end

function Receive(...)
  core:receive(...)
end

function GameKey(...)
  core:gameKey(...)
end

return {
  setSpawns = function(player_spawns, spectator_spawns)
    config:assign({
      playerSpawns = player_spawns,
      spectatorSpawns = spectator_spawns,
    })
  end,
  furtherAwaySpawnConfig = function()
    config:assign({
      spawnType = 'furtherAway'
    })
  end,
  layerSpawnConfig = function(layers, roundRobin)
    config:assign({
      spawnLayers = layers,
      spawnType = roundRobin and 'layeredRoundRobin' or 'layeredFurtherAway'
    })
  end
}
