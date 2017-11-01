-- Game mode for VS AI

local bzutils = require("bzutils")
local rx = require("rx")
local helper = require("helpers")



helper.setup(bzutils.event.bzApi)

local core = bzutils.core
local net = bzutils.net.net
local SharedStore = bzutils.net.SharedStore
local Store = bzutils.utils.Store
local BroadcastSocket = bzutils.net.BroadcastSocket

local Timer = bzutils.utils.Timer

local createClass = bzutils.utils.createClass


local WaveController = require("wave_c") 

local locations = {}
local scoutLocationPath = nil

Formation = function(me,him,priority)
  if(priority == nil) then
    priority = 1;
  end
  SetCommand(me,AiCommand["FORMATION"],priority,him);
end


local function ScoutTask(handle, s)
  if IsAlive(handle) then
    -- look for enemies
    local enemy = GetNearestEnemy(handle)
    SetObjectiveOn(handle)
    if IsValid(enemy) then
      s:queue2("Attack", enemy)
    else
      local loc = {}
      for i, v in pairs(GetPathPoints(scoutLocationPath)) do
        local d = GetDistance(handle, v)
        table.insert(loc, {item=v, chance=(math.log(d)*25 - math.log(25)*25) })
      end
      local goal = helper.chooseA(unpack(loc))
      s:queue2("Goto", goal)
    end
    s:queue3("ScoutTask")
  end
end


helper.createTask("ScoutTask", ScoutTask)


local furyFaction = {
  "hvsat", "hvsav", "zvtank", "zvfigh", "zvwalk", "zvhraz"
}

local furyWaves = {
  {item = {"1"}, chance = 10},
  {item = {"2"}, chance = 9},
  {item = {"3"}, chance = 11},
  {item = {"4"}, chance = 12},
  {item = {"5"}, chance = 8},
  {item = {"6"}, chance = 10},
  {item = {"1", "1"}, chance = 6},
  {item = {" 3 ", "4 4"}, chance = 7},
  {item = {"444"}, chance = 8},
  {item = {" 5 ", "3 4"}, chance = 5},
  {item = {" 1 ", "4 3"}, chance = 4},
  {item = {"6 4"}, chance = 5}
}




local GameManager = createClass("game.vsai", {
  new = function(self)
    self:super("__init")
    self.initialized = false
    net:onNetworkReady():subscribe(function()
      self.displayText = ("Network initilized!\n")
      self:_initState()
    end) 
    net:onHostMigration():subscribe(function(host)
      self.initialized = false
      self.displayText = ("Host migrated, %s\n is now hosting\n"):format(host.name)
      self:_initState()
    end)
    self.renderTimer = Timer(0.1, -1)
    self.renderTimer:onAlarm():subscribe(function()
      self:_rerender()
    end)
    self.renderTimer:start()
    self.displayText = "Waiting for network ...\n"
    self.showDisplay = true
    self.units = {}
    AddObjective("stats.obj", "white", 8, self.displayText)

    self.acc = 0
    self.waveController = nil



    self.store = Store({
      currentWave = 0,
      unitsLeft = 0,
      totalUnits = 0,
      grace = 15,
      allSpawned = false,
      waveRunning = false,
      score = 0
    })
  end,
  _rerender = function(self)
    if self.showDisplay or (not self.initialized) then
      UpdateObjective("stats.obj", "yellow", 0.2, self.displayText)
      self.showDisplay = true
    end
  end,
  _initState = function(self)
    self.displayText = self.displayText .. "Waiting for socket connection ...\n" 
    -- set up sockets
    local socketSub 
    if IsHosting() then
      socketSub = rx.Observable.of(net:openSocket(0, BroadcastSocket, "vsai.sock" ,"state"))
    else
      socketSub = net:getRemoteSocket("vsai.sock","state")
    end
    socketSub:subscribe(function(socket)
      self.initialized = true
      self.displayText = self.displayText .. "Socket set up!"
      self.socket = socket
      self.store = SharedStore(self.store:getState(), socket)
      -- update display
      self.store:onStateUpdate():subscribe(function(state, pstate)
        if state.currentWave ~= pstate.currentWave then
          DisplayMessage(("Wave %d started!"):format(state.currentWave))
        elseif not state.waveRunning and pstate.waveRunning then
          DisplayMessage(("Wave %d ended!"):format(state.currentWave))
        end
        self.displayText = ("Current wave: %d\n"):format(state.currentWave)
        self.displayText = self.displayText .. ("Total score: %d\n"):format(state.score)
        if not state.waveRunning then
          self.displayText = self.displayText .. ("Grace periode: %d\n"):format(state.grace)
        else
          self.displayText = self.displayText .. ("Units left: %d/%d\n"):format(state.unitsLeft, state.totalUnits)
        end

        
        if state.waveRunning and state.unitsLeft <= 0 and state.allSpawned then
          --self:_endWave()
        elseif (not state.waveRunning) and state.grace <= 0 then
          --self:_startWave()
        end
  
      end)

      self.store:onKeyUpdate():subscribe(function(key, value)
        print("Set key", key,value)
      end)
      if IsHosting() then
        self:_postInit()
      end
    end)
  end,
  _postInit = function(self)
    -- if there are units on the field remove them and restart the wave
    local s = self.store:getState()
    if s.waveRunning then
      self:_restartWave()
    end
  end,
  _startWave = function(self)
    local s = self.store:getState()
    self.units = {}
    print("starting", s.currentWave, s.waveRunning)
    self.store:assign({
      waveRunning = true,
      currentWave = s.currentWave + 1,
      unitsLeft = 0,
      totalUnits = 0,
      grace = 20,
      allSpawned = false
    })
    self.waveController = WaveController( furyFaction, locations, 1/20, 0.05, furyWaves, math.exp(s.currentWave) )
    self.waveController:onWaveSpawn():subscribe(function(handles, leader)
  
      local state = self.store:getState()
      self.store:assign({
        totalUnits = state.totalUnits + #handles,
        unitsLeft = state.unitsLeft + #handles
      })
      SetObjectiveOn(leader)
      for i, v in pairs(handles) do
        self.units[v] = true

        local s = helper.sequencer(v)
        if v ~= leader then
          s:queue2("Formation", leader)
        end
        s:queue3("ScoutTask")
      end
    end,nil,function()
      self.waveController = nil
      self.store:set("allSpawned", true)
    end)

  end,
  _restartWave = function(self)
    self:_endWave()
    for v in AllObjects() do
      if GetTeamNum(v) == 15 then
        RemoveObject(v)
      end
    end
    local s = self.store:getState()
    self.store:set("currentWave", s.currentWave - 1)
  end,
  _endWave = function(self)
    self.acc = 0
    self.units = {}
    self.store:assign({
      waveRunning = false,
      grace = 20,
      allSpawned = false
    })
  end,
  update = function(self, dtime)
    if self.initialized then
      if IsHosting() then
        local s = self.store:getState()
        if s.waveRunning then
          if self.waveController then
            self.waveController:update(dtime)
          end
          if s.waveRunning and s.unitsLeft <= 0 and s.allSpawned then
            self:_endWave()
          end
        else
          self.acc = self.acc + dtime
          if self.acc >= 1 then
            self.acc = self.acc - 1
            self.store:set("grace", s.grace - 1)
            if (not s.waveRunning) and s.grace - 1 <= 0 then
              self:_startWave()
            end
          end
        end
      end
      self.renderTimer:update(dtime)
    end
  end,
  gameKey = function(self, key)
    if key == "O" then
      self.showDisplay = not self.showDisplay
    end
  end,
  deleteObject = function(self, handle)
    if IsHosting() then
      local s = self.store:getState()
      if s.waveRunning and self.units[handle] then
        self.store:assign({
          unitsLeft = s.unitsLeft - 1,
          score = s.score + math.floor(math.exp(s.currentWave - 1))
        })
      end
    end
    self.units[handle] = nil
  end
}, bzutils.utils.Module)

bzutils.utils.namespace("vsai", GameManager)
core:useModule(GameManager)

local ambientTimer = math.random(5,20)


function Start()
  core:start()
end

  local function logTrace(...)
    local trace = debug.traceback();
    print(...);
    print(trace);
  end


function Update(dtime)
  xpcall(function()
    ambientTimer = ambientTimer - dtime
    if ambientTimer <= 0 then
      ambientTimer = math.random()*35 + 7
    end
    core:update(dtime)

  end, logTrace)
end

function AddPlayer(id, name, team)
  core:addPlayer(id, name, team)
end

function CreatePlayer(id, name, team)
  core:createPlayer(id, name, team)
end

function DeletePlayer(id, name, team)
  core:deletePlayer(id, name, team)
end

function CreateObject(handle)
  core:createObject(handle)
end

function AddObject(handle)
  core:addObject(handle)
end

function DeleteObject(handle)
  core:deleteObject(handle)
end

function Receive(...)
  core:receive(...)
end

function GameKey(...)
  core:gameKey(...)
end







-- setup function
return function(spawns, loc_of_interest)
  locations = spawns
  scoutLocationPath = loc_of_interest
end