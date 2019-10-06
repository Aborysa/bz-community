-- script to help with posting stats to the statserver
-- requires that bzext to be enabled when setting up bzutils
local bzext = require("bzext_m")
local base64 = require("base64")
local json = require("json")
local uuid = require("uuid")

local utils = require("utils")
local assignObject = utils.assignObject

local BASE_ADDR = "https://bzext.dock1.spaceway.network/"
--local BASE_ADDR = "http://localhost:5000/"
-- for creating a user session:
local SESSIONS = BASE_ADDR .. "sessions"
-- for creating a game, joining a game and for listing all played games
-- "games/<id>" for getting stats and posting stats to a game
local GAMES = BASE_ADDR .. "games"
local STATS = GAMES .. "/%s"

-- after posting, server will return a session token for further use
local session_template = {
  name = "Player name",
  client_id = "Client's id",
  user_id = "Leave blank to create a user",
  secret = "not used",
  session_data = { -- custom metadata for the session
    map = "map name",
    client_id = "client_id",
    name = "player name"
  }

}

local game_template = {
  action = "join/create",
  token = "token returned when creating a session",
  game_id = "only required when joining a game, host should share this with other players"
}

local stat_template = {
  game_id = "game id",
  token = "session token",
  scrap = "player's scrap count",
  pilots = "player's pilot count",
  kills = "player's kill count",
  deaths = "player's death count",
  offensive_count = "number of offensive units",
  defensive_count = "number of defensive units",
  scavs = "how many scavs does the player have",
  player_lives = "how many lives does the player have left",
  has_recycler = "does the player have a recycler",
  has_armory = "does the player have an armory",
  has_constructor = "does the player have a constructor",
  silo_count = "number of silos",
  player_ammo = "how many units of ammo does the player have",
  player_health = "how much health does the player have",
  player_unit = "what unit is the player?"
}

local function checkServer()
  return bzext.httpGet(BASE_ADDR .. "index"):map(function(data)
    if data:len() > 0 then
      return json.decode(data).server_up
    end
    return false
  end)
end

local function extractTokenData(token)
  local match = token:gmatch("[^%.]+")
  local data, hash = match(), match()
  return json.decode(base64.decode(data))
end

local function createSession(player_name)
  local steam_id = bzext.getUserId()
  local local_data = bzext.readString("bzt_data")
  local client_id = uuid()
  local secret = nil
  local user_id = nil
  print(client_id)
  if local_data:len() > 0 then
    data = json.decode(local_data)
    client_id = data.client_id
    secret = data.secret
    user_id = data.user_id
  end

  local session = {
    client_id = client_id,
    secret = secret,
    user_id = user_id,
    map = GetMapTRNFilename(),
    name = player_name
  }
  return bzext.httpPost(SESSIONS, json.encode(session)):map(function(token)
    local token_data = extractTokenData(token)
    bzext.writeString("bzt_data", json.encode({
      user_id = token_data["user_id"],
      client_id = client_id,
      steam_id = steam_id,
      secret = token_data["secret"]
    }))
    
    return token
  end)
end

local function createGame(token)
  local game_data = {
    action = "create",
    token = token
  }
  return bzext.httpPost(GAMES, json.encode(game_data)):map(function(data)
    print(data)
    return json.decode(data)
  end)
end

local function joinGame(token, game_id)
  local game_data = {
    action = "join",
    token = token,
    game_id = game_id
  }

  return bzext.httpPost(GAMES, json.encode(game_data)):map(function(data)
    print(data)
    return json.decode(data)
  end)
end


local default_stats = {
  scrap = 0,
  pilots = 0,
  kills = 0,
  deaths = 0,
  offensive_count = 0,
  defensive_count = 0,
  scavs = 0,
  player_lives = 0,
  has_recycler = false,
  has_armory = false,
  has_constructor = false,
  has_factory = false,
  silo_count = 0,
  player_ammo = 0,
  player_health = 0,
  player_unit = "player"
}

local function countTeamSlot(start, _end, team, cls)
  local count = 0
  for i=start, _end do 
    local h = GetTeamSlot(i, team)
    if IsValid(h) and (cls == nil or GetClassLabel(h) == cls) then
      count = count + 1
    end
  end
  

  return count
end

local function postStats(team, token, game_id, stats)
  
  local scavs = countTeamSlot(TeamSlot.MIN_UTILITY, TeamSlot.MAX_UTILITY, team, "scavenger")
  local silos = countTeamSlot(TeamSlot.MIN_SILO, TeamSlot.MAX_SILO, team)
  local offensive_count = countTeamSlot(TeamSlot.MIN_OFFENSE, TeamSlot.MAX_OFFENSE, team)
  local defensive_count = countTeamSlot(TeamSlot.MIN_DEFENSE, TeamSlot.MAX_DEFENSE, team)
  
  local ph = GetPlayerHandle()
  local _stats = {
    token = token,
    scrap = GetScrap(team),
    pilots = GetPilot(team),
    scavs = scavs,
    silo_count = silos,
    offensive_count = offensive_count,
    defensive_count = defensive_count,
    has_recycler = IsAlive(GetRecyclerHandle(team)),
    has_armory = IsAlive(GetArmoryHandle(team)),
    has_constructor = IsAlive(GetConstructorHandle(team)),
    has_factory = IsAlive(GetFactoryHandle(team)),
    player_unit = GetOdf(ph),
    player_ammo = GetCurAmmo(ph),
    player_health = GetCurHealth(ph)
  }

  bzext.httpPost(STATS:format(game_id), json.encode(assignObject(default_stats, _stats, stats))):subscribe(function()
    print("Statistics posted")
  end)
end


return {
  createGame = createGame,
  createSession = createSession,
  joinGame = joinGame,
  postStats = postStats,
  checkServer = checkServer
}