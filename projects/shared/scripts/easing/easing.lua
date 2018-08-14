



local function calcPt(n1, n2, perc)
  return n1 + (n2 - n1)*math.max(math.min(perc, 1), 0)
end

local function quadBezier(x1, x2, x3, perc)
  -- points
  xa = calcPt( x1 , x2 , perc )
  xb = calcPt( x2 , x3 , perc )
  
  -- value
  x = calcPt( xa , xb , perc )

  return x
end

local function cubicBezier(x1, x2, x3, x4, perc)
  -- points
  xa = calcPt( x1 , x2 , perc )
  xb = calcPt( x2 , x3 , perc )
  xc = calcPt( x3 , x4 , perc )
  
  -- tangent
  xm = calcPt( xa , xb , perc )
  xn = calcPt( xb , xc , perc )

  -- value
  x = calcPt( xm , xn , perc )
  return x
end

local function superBezier(x1, x2, x3, x4, x5, perc)
  -- points
  xa = calcPt( x1 , x2 , perc )
  xb = calcPt( x2 , x3 , perc )
  xc = calcPt( x3 , x4 , perc )
  xd = calcPt( x4 , x5 , perc )
  -- tangent
  xm1 = calcPt( xa , xb , perc )
  xn1 = calcPt( xb , xc , perc )
  xy1 = calcPt( xc , xd , perc )

  xm = calcPt(xm1 , xn1 , perc )
  xn = calcPt(xn1 , xy1 , perc)
  -- value
  x = calcPt( xm , xn , perc )
  return x
end

local function interpolatedNormal(pos)
  npos = SetVector(math.floor(pos.x) + 5, pos.y + 1000, math.floor(pos.z) + 5)
  local h1, n1 = GetTerrainHeightAndNormal(npos)
  local h2, n2 = GetTerrainHeightAndNormal(npos + SetVector(0, 0, 10))
  local h3, n3 = GetTerrainHeightAndNormal(npos + SetVector(10, 0, 0))
  local h4, n4 = GetTerrainHeightAndNormal(npos + SetVector(0, 0, -10))
  local h5, n5 = GetTerrainHeightAndNormal(npos + SetVector(-10, 0, 0))

  local percent = Normalize(SetVector(0.5, 0.5, 0.5) + (npos-pos)/20)

  local x1 = superBezier(n3.x, n2.x, n1.x, n4.x, n5.x, percent.x)
  local z1 = superBezier(n2.z, n3.z, n5.z, n1.z, n4.z, percent.z)
  local y1 = superBezier(n1.y, n2.y, n3.y, n4.z, n5.z, percent.y)


  return Normalize(SetVector(x1,y1,z1))

end


local function easeOutBack(time)
  return cubicBezier(0, 0.885, 0.9, 1, time)
end

local function easeOutBackV(startV, endV, time)
  --[[if time == 0 then
    return startV
  elseif time == 1 then
    return endV
  end]]
  return easeOutBack(time) * (endV-startV) + startV
end

  

return {
  calcPt = calcPt,
  easeOutBack = easeOutBack,
  easeOutBackV = easeOutBackV,
  quadBezier = quadBezier,
  cubicBezier = cubicBezier,
  interpolatedNormal = interpolatedNormal
}