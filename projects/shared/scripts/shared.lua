local namespace = require("bzutils").utils.namespace
local CameraController = require("cam_ctrl").CameraController
local SpectateController = require("cam_ctrl").SpectateController
local PatrolController = require("patrol_ctrl")
local WaveController = require("wave_ctrl")
local SpectatorCraft = require("tvspec")

namespace("shared", CameraController, SpectateController, PatrolController, WaveController, SpectatorCraft)


local function setup(serviceManager)
  serviceManager:getService("bzutils.runtime"):subscribe(function(runtimeController)
    runtimeController:useClass(CameraController)
    runtimeController:useClass(SpectateController)
    runtimeController:useClass(PatrolController)
    runtimeController:useClass(WaveController)
  end)
end



return {
  CameraController = CameraController,
  PatrolController = PatrolController,
  WaveController = WaveController,
  SpectateController = SpectateController,
  SpectatorCraft = SpectatorCraft,
  setup = setup
}