-- code for spectator craft


local bzutils = require("bzutils")

local utils = bzutils.utils
local component = bzutils.component

local namespace = utils.namespace

local ComponentConfig = component.ComponentConfig
local UnitComponent = component.UnitComponent

local createClass = utils.createClass

local SpectatorCraft = createClass("Spectator", {
  new = function(self, ...)
    self:super("__init", ...)
  end,
  postInit = function(self)
    self:getHandle():setTeamNum(0)
  end,
  update = function(self, dtime)
    local h = self:getHandle()
    for v in ObjectsInRange(40,h:getPosition()) do
      if v~=h.h and (GetTeamNum(v) ~= 0) then
        local diff = h:getPosition() - GetPosition(v);
        --print(Length(diff),lander:getPosition(),GetPosition(v),v);
        if(Length(diff) < 30) then
          local p = GetPosition(v) + Normalize(diff)*30
          --local height = GetTerrainHeightAndNormal(p)
          --p.y = math.max(height,p.y)
          h:setPosition(p)
        end
      end
    end
  end
}, UnitComponent)


ComponentConfig(SpectatorCraft,{
  componentName = "Spectator"
})

return SpectatorCraft

