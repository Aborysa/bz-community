local gmvsai = require("gmvsai")


local spawns = {}
for i=1, 8 do
  table.insert(spawns, ("spawn_%d"):format(i))
end


local game = gmvsai(spawns, "points_of_interest")