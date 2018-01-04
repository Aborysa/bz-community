local function mapLayers(spawn_points, layers)
  local ret = {}
  for i, v in ipairs(layers) do
    local layer = {spawns = {}, indecies={}}
    for _, index in ipairs(v) do
      table.insert(layer.spawns,spawn_points[index])
      table.insert(layer.indecies,index)
    end
    table.insert(ret, layer)
  end
  return ret
end

local function mapSpawnpoints(layer, indecies)
  local ret = {}
  for i, v in ipairs(indecies) do
    table.insert(ret, layer.indecies[v])
  end
  return ret
end

local spawn_functions
spawn_functions = {
  roundRobin = function(start_index, spawn_points)
    local spawnIndecies = {}
    local used = {}
    local maxIndex = #spawn_points
    local minIndex = 1
    local extraOffset = 0

    for i=1, #spawn_points do
      local index = -1
      extraOffset = extraOffset - 1
      while index == -1 or used[index] do
        extraOffset = extraOffset + 1
        index = (start_index-1 + i + extraOffset)
        index = index + math.min(0, (maxIndex - index) * 2)
      end
      table.insert(spawnIndecies, index)
      used[index] = true
    end
    return spawnIndecies
  end,
  furtherAway = function(start_index, spawn_points)
    local spawnIndecies = {start_index}
    local current = start_index
    local available_indecies = {}
    for i, v in ipairs(spawn_points) do
      available_indecies[i] = i~=start_index or nil
    end
    for _ = 2, #spawn_points do
      local mostDistant = nil
      local dist = 0
      for index, _1 in pairs(available_indecies) do
        local d = Distance2D(spawn_points[index], spawn_points[current])
        if d > dist then
          dist = d
          mostDistant = index
        end
      end
      available_indecies[mostDistant] = nil
      table.insert(spawnIndecies, mostDistant)
      current = mostDistant
    end
    return spawnIndecies
  end,
  layered = function(start_index, spawn_points, layers, func)
    local mappedLayers = mapLayers(spawn_points, layers)
    local startLayer = (start_index) % #mappedLayers
    local spawnIndecies = {}
    for i=1, #mappedLayers do
      li = ((startLayer + i - 1) % #mappedLayers) + 1
      subList = mapSpawnpoints(mappedLayers[li], func(((start_index-1) % #mappedLayers[li].spawns) + 1, mappedLayers[li].spawns))
      for i, v in ipairs(subList) do
        table.insert(spawnIndecies, v)
      end
    end
    return spawnIndecies
  end,
  layeredFurtherAway = function(start_index, spawn_points, layers)
    return spawn_functions["layered"](start_index, spawn_points, layers, spawn_functions["furtherAway"])
  end,
  layeredRoundRobin = function(start_index, spawn_points, layers)
    return spawn_functions["layered"](start_index, spawn_points, layers, spawn_functions["roundRobin"])
  end
}

local function generateSpawnSequence(spawn_type, spawn_points, offset, layers)
  local func = spawn_functions[spawn_type]
  if func then
    return func(offset, spawn_points, layers)
  else
    error(("Invalid spawn type %s"):format(spawn_type))
  end
end

local function getNextSpawnPoint(occupied, indecies, ...)
  indecies = indecies == nil and generateSpawnSequence(...) or indecies
  for i, index in ipairs(indecies) do
    if not occupied[index] then
      return index
    end
  end
end


return {
  getNextSpawnPoint = getNextSpawnPoint,
  generateSpawnSequence = generateSpawnSequence
}