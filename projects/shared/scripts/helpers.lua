

local bzutils = require("bzutils")

local createClass = bzutils.utils.createClass



TaskSequencer = createClass("hp.TaskSequencer", {
  new = function(self, handle, ex_table)
    self.handle = handle
    self.tasks = {}
    self.ex_table = ex_table or {}
  end,
  update = function(self,dtime)
    if((#self.tasks > 0) and (GetCurrentCommand(self.handle) == AiCommand["NONE"])) then
      local next = table.remove(self.tasks, 1);
      print(next.fname,next.type,GetLabel(self.handle),unpack(next.args));
      if(next.type == 1) then
        SetCommand(self.handle,unpack(next.args));
      elseif(next.type == 2) then
        _G[next.fname](self.handle,unpack(next.args));
      elseif(next.type == 3) then
        table.insert(next.args,self);
        self.ex_table[next.fname](self.handle,unpack(next.args));
      end
    end
  end,
  save = function(self)
    return self.tasks;
  end,
  load = function(self,...)
    self.tasks = ...;
  end,
  clear = function(self)
    self.tasks = {};
  end,
  push = function(self,...)
    table.insert(self.tasks,1,{type=1,args=table.pack(...)});
  end,
  push2 = function(self,fname,...)
    table.insert(self.tasks,1,{type=2,fname=fname,table.pack(...)});
  end,
  push3 = function(self,fname,...)
    table.insert(self.tasks,1,{type=3,fname=fname,args={...}});
  end,
  queue = function(self,...)
    table.insert(self.tasks,{type=1,args=table.pack(...)});
  end,
  queue2 = function(self,fname,...)
    table.insert(self.tasks,{type=2,fname=fname,args=table.pack(...)});
  end,
  queue3 = function(self,fname,...)
    table.insert(self.tasks,{type=3,fname=fname,args={...}});
  end
})


TaskManager = {
  sequencers = {},
  tasks = {},
  createTask = function(self, name, func)
    self.tasks[name] = func
  end,
  Update = function(self,...)
    for i,v in pairs(self.sequencers) do
      if(IsValid(i)) then
        v:update(...);
      else
        self.sequencers[i] = nil;
      end
    end
  end,
  Save = function(self,...)
    local sdata = {};
    for i,v in pairs(self.sequencers) do
      sdata[i] = table.pack(v:save());
    end
    return sdata;
  end,
  sequencer = function(self,handle)
    if(not self.sequencers[handle]) then
      self.sequencers[handle] = TaskSequencer(handle,self.tasks);
    end
    return self.sequencers[handle];
  end,
  Load = function(self,data)
    for i,v in pairs(data) do
      local s = self:sequencer(i);
      s:load(unpack(v));
    end
  end
}



local function choose(...)
  local t = {...};
  local rn = math.random(#t);
  return t[rn];
end

local function chooseA(...)
  local t = {...};
  local m = 0;
  for i, v in pairs(t) do
    m = m + v.chance; 
  end
  local rn = math.random()*m;
  local n = 0;
  for i, v in ipairs(t) do
    if (v.chance+n) > rn then
    return v.item;
    end
    n = n + v.chance;
  end
end

return {
  choose = choose,
  chooseA = chooseA,
  createTask = function(...)
    TaskManager:createTask(...)
  end,
  sequencer = function(...)
    return TaskManager:sequencer(...)
  end,
  setup = function(dp)
    dp:on("UPDATE"):subscribe(function(event)
      TaskManager:Update(event:getArgs())
    end)
  end
}