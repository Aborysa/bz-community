local bzutils = require("bzutils")
local core = bzutils.core
local utils = bzutils.utils
local rx = require("rx")
local runtimeController = bzutils.runtime.runtimeController

local shared = require("shared")
local SpectateController = shared.SpectateController

local net = bzutils.net.net
local Store = utils.Store
local SharedStore = bzutils.net.SharedStore
local Observable = rx.Observable

local BroadcastSocket = bzutils.net.BroadcastSocket
local ServerSocket = bzutils.net.ServerSocket


local compareTables = utils.compareTables
local namespace = utils.namespace

local SpectatorCraft = shared.SpectatorCraft

bzutils.component.componentManager:useClass(SpectatorCraft)

local removeOnDead = {}

local assignObject = utils.assignObject

local event = bzutils.event.bzApi

local _DisplayMessage = DisplayMessage
function DisplayMessage(...)
  print("Display: ", ...)
  _DisplayMessage(...)
end



SetCloaked = SetCloaked or function()
end

local function forceSpectatorCraft(handle)
  SetPilotClass(handle, "tvspec")
  HopOut(handle)
  removeOnDead[handle] = true
end

local GameController = utils.createClass("GameController", {
  new = function(self, terminate)
    self.displayText = ""
    self.showInfo = true
    self.ready = false
    self.spectating = false
    
    -- has player spawned
    self.spawned = false

    self.spectate_r = -1
    self.spawn_point = nil
    self.maxPlayers = 0
    self.renderTimer = utils.Timer(0.1,-1)
    self.renderTimer:onAlarm():subscribe(function()
      self:_rerender()
    end)
    self.renderTimer:start()
    self.terminate = terminate
    self.ph = GetPlayerHandle()
    self.pp = GetPosition(self.ph)
    self.gameStore = Store({
      startTimer = 10,
      playerCount = 0,
      spectatorCount = 0,
      gameStarted = false,
      spawnOffset = 0,
      players = {}
    })
    self.playerStore = Store({})
    AddObjective("stats.obj", "white", 8, self.displayText)
  end,
  routineWasCreated = function(sef)
    print("routineWasCreated")
  end,
  postInit = function(self)
    print("postInit")
    -- check local players craft to determin if they're spectating or not
    RemoveObject(GetRecyclerHandle())
    event:on("GAME_KEY"):subscribe(function(event)
      self:gameKey(event:getArgs())
    end)
    self.maxPlayers = GetPathPointCount("p_spawns")
    self.gameStore:set("spawnOffset", math.random(1, self.maxPlayers))
    local ph = GetPlayerHandle()
    print(GetLabel(ph))
    if IsOdf(ph, "tvspec") then
      self.spectating = true
    end
    self.displayText = "Waiting for network...\n"
    DisplayMessage("Waiting for network...")
    net:onNetworkReady():subscribe(function()
      DisplayMessage("Network is read!")
      self.displayText = self.displayText .. "Network is ready!\n"
      self:_setUpSockets()
    end)
    net:onHostMigration():subscribe(function()
      DisplayMessage("Host migrated")
      self.displayText = "Host migrated\n"
      self:_setUpSockets()
    end)
  end,
  _rerender = function(self)
    if self.showInfo or (not self.ready) then
      UpdateObjective("stats.obj", "yellow", 0.2, self.displayText)
      self.showInfo = true
    end
  end,
  _setUpSockets = function(self)
    self.displayText = self.displayText .. "Setting up sockets...\n"
    DisplayMessage("Setting up sockets...")
    self.stateSocket = nil
    self.eventSocket = nil
    self.playerSocket = nil
    self.ready = false
    self.acc = 0
    local socketsub1 = nil
    local socketsub2 = nil
    local socketsub3 = nil
    local socketsLeft = 3
    if IsHosting() then
      socketsub2 = Observable.of(net:openSocket(0, ServerSocket, "bzt", "event", "sock"))
      socketsub1 = Observable.of(net:openSocket(0, BroadcastSocket, "bzt", "state", "sock"))
      socketsub3 = Observable.of(net:openSocket(0, BroadcastSocket, "bzt", "player", "sock"))
    else
      socketsub2 = net:getRemoteSocket("bzt", "event", "sock")
      socketsub1 = net:getRemoteSocket("bzt","state","sock")
      socketsub3 = net:getRemoteSocket("bzt", "player", "sock")
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
      if not self.gameStore:getState().gameStarted then
        if IsHosting() then
          if self.spectating then
            self.spawn_point = self:_addSpectator()
          else
            local succ, spawn = self:_addPlayer(net:getLocalPlayer().id)
            self.spawn_point = spawn
            if not succ then
              self.spectating = true
              forceSpectatorCraft(GetPlayerHandle())
            end
          end
        else
          socket:send(self.spectating and "SPECTATE" or "JOIN", net:getLocalPlayer().id)
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
      return true, (pc + offset) % (self.maxPlayers) + 1
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
      local p = net:getPlayer(i)
      table.insert(sorted, {
        order = i,
        player = net:getPlayer(i) or {team = 0, name = "Unknown", id = i},
        state = v
      })
    end
    table.sort(sorted, function(a, b)
      return a.order < b.order
    end)
    for i, v in ipairs(sorted) do
      self.displayText = self.displayText .. ("%s (%d, %d):\n"):format(v.player.name, v.player.team, v.player.id)
      self.displayText = self.displayText .. ("  scrap: %d/%d\n"):format(v.state.scrap, v.state.mscrap)
      self.displayText = self.displayText .. ("  pilot: %d/%d\n\n"):format(v.state.pilot, v.state.mpilot)
    end
    print(self.displayText)
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
      self.gameStore:set("startTimer", 10)
      local succ, spawn = self:_addPlayer(...)
      socket:send("JOIN_M", succ, spawn)
    elseif what == "SPECTATE" then
      local spawn = self:_addSpectator()
      socket:send("SPEC_SPAWN", spawn)
    end
  end,
  _spawnInRecycler = function(self)
    if (not self.spectating) and (self.spawn_point ~= nil) then
      local n = GetNation(GetPlayerHandle())
      local rtable = {"%svremp", "%svrecy", "avremp", "avrecy"}
      for i, v in ipairs(rtable) do
        local recy = BuildObject(v:format(n), net:getLocalPlayer().team, GetPathPoints(self.spectating and "spectator_spawns" or "p_spawns")[self.spawn_point])
        if IsValid(recy) then
          break
        end
      end
      SetScrap(net:getLocalPlayer().team, 20)
    else
      for i=1,15 do
        Ally(net:getLocalPlayer().team, i)
      end
    end
  end,
  update = function(self, dtime)
    local ph = GetPlayerHandle()
    local pp = GetPosition(ph)
    local vel = Length(GetVelocity(ph))
    if (not IsValid(ph)) or (IsPerson(ph) and vel < 1 and self.ph ~= ph and Distance3D(self.pp, pp) > (vel*dtime+10) ) then
      self.spawned = false
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
        local spawn =  GetPathPoints(self.spectating and "spectator_spawns" or "p_spawns")[self.spawn_point]
        SetPosition(ph,GetPositionNear(spawn, 50, 60))
        self.spawned = true
      end
      if gameState.gameStarted and not self.spectating then
        local player = net:getLocalPlayer()
        local pstate = self.playerStore:getState()[player.id] or {scrap = 0, pilot = 0, mscrap = 0, mpilot = 0}
        local nstate = {
          scrap = GetScrap(player.team),
          pilot = GetPilot(player.team),
          mscrap = GetMaxScrap(player.team),
          mpilot = GetMaxPilot(player.team)
        }
        -- for loop to just check if the table isn't empty
        for i, v in pairs(compareTables(pstate, nstate)) do
          self.playerStore:set(player.id, nstate)
          break
        end
      end
    end
    if self.spectating then
      SetCloaked(ph)
    end
    self.renderTimer:update(dtime)
  end,
  gameKey = function(self, key)
    local r = runtimeController:getRoutine(self.spectate_r)
    if key == "O" then
      self.showInfo = not self.showInfo
    elseif key == "Tab" and r~=nil then
      r:nextPlayer()
    end
    local w = key:gmatch("[^F](%d)")();
    if(w and self.ready and self.spectating) then
      w = tonumber(w)
      if r ~= nil then
        r:setPlayer(w)
      else
        local players = {}
        for i,v in ipairs(self.gameStore:getState().players) do
          table.insert(players, net:getPlayer(v))
        end
        local id, r = runtimeController:createRoutine(SpectateController, players, w)
        self.spectate_r = id
      end
    end
  end
})


namespace("bzt", GameController)

runtimeController:useClass(GameController)

function Start()
  runtimeController:createRoutine(GameController)
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