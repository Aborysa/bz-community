local mGUI = require "mGUI";
local mFlow = require "mFlow";
local mMP = require "mMP";
local mTimer  = require "mTimer";
local mHandle = require "mHandle";
local mUnit = require "mUnit";
local mTask = require "mTask";


local spectating = false;
local mteam = nil;
local init = false;
local ran_path = nil;
local requested_path = IsHosting();
local requestTimer = 0.1;
local paths = 1;

if not _G["Hide"] then
    _G["Hide"] = function() return end;
end

if not(GetPathPointCount) then
    GetPathPointCount = function(path)
        local count = 0;
        local p = SetVector(0,0,0);
        local n = GetPosition(path,0);
        while p ~= n do
            p = n;
            count = count + 1;
            n = GetPosition(path,count);
        end
        print("Checked " .. path,"found " .. tostring(count) .. " pathpoints");
        return count;
    end
end

local dead = false;

local nationCmap = {
    a = "green",
    c = "yellow",
    b = "blue",
    s = "red"
}

local builtUnits = {
    constructionrig = 0,
    factory = 0,
    armory = 0
}
 
local unitMap = {
    wingman = "totalOffensive",
    scavenger = "totalUtility",
    tug = "totalUtility",
    turrettank = "totalDefencive",
    turret = "totalDefencive", 
};

local receiveMap = {
    req_stats = function(from,h)
        Send(from,"F","up_stats",
        {
            scrap = GetScrap(mteam),
            mscrap = GetMaxScrap(mteam),
            pilots = GetPilot(mteam),
            mpilots = GetMaxPilot(mteam),
            h = GetPlayerHandle(),
            t = GetTarget(GetPlayerHandle()),
            recy = GetRecyclerHandle(mteam),
            muf = GetFactoryHandle(mteam),
            slf = GetArmoryHandle(mteam),
            cnst = GetConstructorHandle(mteam),
            tmuf = builtUnits["factory"],
            tslf = builtUnits["armory"],
            tcnst = builtUnits["constructionrig"]
        });
        Hide(h);
    end,
    up_stats = function(from,info)
        local p = mMP.players[from]
        local s = p.stats;
        p.h = info.h;
        p.t = info.t;
        s.recy = info.recy;
        s.muf = info.muf;
        s.slf = info.slf;
        s.cnst = info.cnst;
        s.scrap = info.scrap;
        s.mscrap = info.mscrap;
        s.pilots = info.pilots;
        s.mpilots = info.mpilots;
        s.tmuf = info.tmuf;
        s.tslf = info.tslf;
        s.tcnst = info.tcnst;
        
    end,
    req_spawn = function(from)
        if(IsHosting()) then
            print("Sending spawnpoint to:",from,"path:",ran_path);
            Send(from,"F","set_spawn",ran_path);
        end
    end,
    set_spawn = function(from,path)
        print("Got spawnpoint from host:",path);
        ran_path = path;
    end
};
local commandMap = {
    watch = function(args)
        if(spectating) then
            local t = tonumber(args);
            if(t and (t == 2) or (t == 1)) then
                local cam_task = mTask:getTask("cam_task");
                cam_task.team = t;
                cam_task:start();
                DisplayMessage(("Watching %s, press [space] to exit"):format(mMP:getPlayer(t).name));
            elseif(not t) then
                DisplayMessage("No team specified!\n/watch [team#]");
            end
            return true;
        end
        return false;
    end
}


mFlow.callback("watch_ship_start_resume",function(task)
    if(task.camready) then
        CameraFinish();
    end
    task.camready = CameraReady();
    task.team = task.team or 1;
    task.prev = {
        pos = nil,
        dir = nil
    };
    
end);

mFlow.callback("watch_ship_update",function(task,dtime)
    if(task.team~=0 and task.camready) then
        local p = mMP:getPlayer(task.team);
        local dfac = 0.98;
        if(p) then
            --Code to make sure camera dosen't clip terrain
            local b = p.h or GetPlayerHandle(task.team);
            local t = b;--p.t or b;
            local intp = GetPosition(b);
            local intd = GetFront(b) * 30;
            if(task.prev.pos) then
                intp = intp + (GetPosition(b)-task.prev.pos)*dfac;
            end
            task.prev.pos = intp;
            if(task.prev.dir) then
                intd = intd + ( (GetFront(b)*30) - task.prev.dir)*dfac;
            end
            task.prev.dir = intd;
            local check = intp - intd;
            
            check.y = 1000000;
            local fh = GetFloorHeightAndNormal(check);
            local height = math.max(8,8+(fh-GetPosition(b).y));
            local up = height * 1-GetFront(b).y;
            local forward = height * GetFront(b).y;
            --Place camera
            CameraObject(b,forward*100 ,up*100,-3000,t);
            if(CameraCancelled()) then
                task:stop();
            end
        else
            task:stop();
        end
    end
end);

mFlow.callback("watch_ship_stop",function(task)
    task.team = 1;
    task.camready = not CameraFinish();
end);

mFlow.callback("slander_start",function(c,lander)
    lander:setTeamNum(0);
end);

mFlow.callback("slander_update",function(lander,dtime)
    --StopSound("amb_wind.wav",lander.h);
    lander:setHealth(1);
    lander:setTeamNum(0);
    if(lander:isAliveAndPilot()) then
        lander:setPilotClass("");
    end
    if(lander:isAlive()) then
        for v in ObjectsInRange(40,lander:getPosition()) do
            if((v~=lander.h) and (GetTeamNum(v) ~= 0) and (GetTeamNum(v) <= 2)) then
                local diff = lander:getPosition() - GetPosition(v);
                --print(Length(diff),lander:getPosition(),GetPosition(v),v);
                if(Length(diff) < 30) then
                    local p = GetPosition(v) + Normalize(diff)*30;
                    local h = GetTerrainHeightAndNormal(p);
                    p.y = math.max(h,p.y);
                    lander:setPosition(p);
                end
            end
        end
    end
end);


mFlow.callback("spec_update",function(obj)
    --Remove old vehicle
    local p = GetPlayerHandle();
    SetVelocity(p,SetVector(0,0,0));
    obj:removeObject();
end);

mFlow.callback("statsDraw",function(frame)
    frame:clear();
    local w,h = frame:getSize();
    local p = mMP:getPlayer(frame.team);
    if(p) then
        local s = p.stats;
        
        frame:writeln(("%s"):format(p.name));
        frame:writeln(("  Scrap: %d/%d"):format(s.scrap,s.mscrap));
        frame:writeln(("  Pilots: %d/%d"):format(s.pilots,s.mpilots));
        frame:writeln(("  Recycler: %s"):format( (IsAlive(s.recy) and "Yes") or "No"));
        frame:write(("  Factory: %s"):format( (IsAlive(s.muf) and "Yes") or "No"));
        --local x,y = frame:getCursorPos();
       -- frame:setCursorPos(19,y);
        frame:writeln((" (%d)"):format(s.tmuf));
        
        frame:write(("  Armory: %s"):format( (IsAlive(s.slf) and "Yes") or "No"));
        --local x,y = frame:getCursorPos();
        --frame:setCursorPos(19,y);
        frame:writeln((" (%d)"):format(s.tslf));
        
        frame:write(("  Constructor: %s"):format( (IsAlive(s.cnst) and "Yes") or "No"));
        --local x,y = frame:getCursorPos();
        --frame:setCursorPos(19,y);
        frame:writeln((" (%d)"):format(s.tcnst));
    end
end);

mFlow.callback("request_stats_timer",function(timer)
    mMP:SendT(1,"F","req_stats",GetPlayerHandle());
    mMP:SendT(2,"F","req_stats",GetPlayerHandle());
end);

bzUtils:init();

function spectateInit()
    spectating = true;
    local cam_task = mTask.task("cam_task");
    cam_task:addListener("start","watch_ship_start_resume");
    cam_task:addListener("resume","watch_ship_start_resume");
    cam_task:addListener("update","watch_ship_update");
    cam_task:addListener("stop","watch_ship_stop");
    local h = GetPlayerHandle();
    RemoveObject(GetRecyclerHandle(mteam));
    --stats timer
    local stimer = mTimer.timer(1,true);
    stimer:addListener("timeout","request_stats_timer");
    stimer:start();
    SetPilotClass(h,"tvspec");
    HopOut(h);
    mHandle.gameObject(h):addListener("update","spec_update");
    for i=0,10 do
        Ally(mteam,i);
    end
    DisplayMessage("use /watch [team#] or ctrl/shift+1,ctrl/shift+2 to watch one of the players");
    AddObjective("stats_objective1","yellow",0,"Stats screen init");
    AddObjective("stats_objective2","yellow",0,"Stats screen init");
    local interface1 = mGUI.component(0,0,25,8,"stats_objective1");
    local statsFrame1 = mGUI.component(1,1,25-2,8-1);
    local interface2 = mGUI.component(0,0,25,9,"stats_objective2");
    local statsFrame2 = mGUI.component(1,1,25-2,9-2);
    
    interface1:setColor(nationCmap[GetNation(GetPlayerHandle(1)) or "a"] or "green");
    interface2:setColor(nationCmap[GetNation(GetPlayerHandle(2)) or "s"] or "red");
    local p1 = mMP:getPlayer(1);
    local p2 = mMP:getPlayer(2);
    
    if(p1 and (p1.name == "HyperFighter")) then
        interface1:setColor("dkyellow");
    end
    if(p2 and (p2.name == "HyperFighter")) then
        interface2:setColor("dkyellow");
    end
    
    statsFrame1:addListener("draw","statsDraw");
    statsFrame2:addListener("draw","statsDraw");
    
    statsFrame1.team = 1;
    statsFrame2.team = 2;
    
    interface1:add(statsFrame1);
    interface1:setFocus(statsFrame1);

    interface2:add(statsFrame2);
    interface2:setFocus(statsFrame2);
    
end

function playerInit()
    for i=1,10 do
        if mteam ~= i then
            UnAlly(mteam,i);
        end
    end
end

function Start()
    LockAllies(true);
    local landerC = mUnit.controller();
    landerC:applyToODF("tvspec");
    landerC:addUnitListener("update","slander_update");
    bzUtils:Start();
    local cpath = "spawn2";
    while (GetPathPointCount and GetPathPointCount(cpath) > 0)  do
        paths = paths + 1;
        cpath = string.format("spawn%d",paths+1);
    end
    if(IsHosting()) then
        ran_path = math.random(1,paths);
    end
    print("Valid spawn paths:");
    for i=1,paths do
        print("  spawn" .. tostring(i));
    end
    
end


function Update(dtime)
    for i,v in pairs(mMP.players) do
        v.h = GetPlayerHandle(v.team) or v.h;
    end
    local h = GetPlayerHandle();
    if((not h) and init) then
        dead = 0;
    end
    if(h and dead) then
        --respawn
        dead = dead + 1;
        if(dead > 2) then
            local pp = GetPosition("spawn" .. tostring(ran_path),mteam-1);
            pp.y = pp.y + 40;
            SetPosition(h,pp);
            dead = false;
        end
    end
    bzUtils:Update(dtime);
    if((not init) and h and ran_path) then
        mteam = GetTeamNum(h);
        --Move to spawnpoint
        local pp = GetPosition("spawn" .. tostring(ran_path),mteam-1);
        print("spawn",pp,ran_path);
        SetPosition(GetRecyclerHandle(mteam),pp);
        SetPosition(h,GetPositionNear(pp,50,60));
        if(GetTeamNum(GetPlayerHandle()) > 2) then
            spectateInit();
        else
            playerInit();
        end
        init = true;
    end
    if((not ran_path) and (not init) and (requestTimer <= 0) and (not IsHosting())) then
        print("Requesting spawn");
        Send(0,"F","req_spawn");
        requestTimer = 0.5;
    end
    requestTimer = requestTimer - dtime;
end


function GameKey(key)
    local w = key:gmatch("[^F](%d)")();
    if(w) then
        commandMap.watch(w);
    end
    bzUtils:GameKey(key);
end

function AddObject(handle)
    local t = GetTeamNum(handle);
    local c = GetClassLabel(handle);
    --print(t,c,builtUnits[c],builtUnits["factory"]);
    if((t == mteam) and (builtUnits[c] ~= nil)) then
        builtUnits[c] = builtUnits[c] + 1;
    end
    --bzUtils:AddObject(handle);
end

function CreateObject(handle)
    --
    bzUtils:AddObject(handle);
end

function DeleteObject(handle)
    bzUtils:DeleteObject(handle);
end

function Load(data)
    bzUtils:Load(data);
end

function Save()
    return bzUtils:Save();
end

function CreatePlayer(id,name,team)
    bzUtils:CreatePlayer(id,name,team);
end

function AddPlayer(id,name,team)
    bzUtils:AddPlayer(id,name,team);
    mMP.players[id].stats = {
        scrap = 0,
        mscrap = 0,
        pilots = 0,
        mpilots = 0,
        tmuf = 0,
        tslf = 0,
        tcnst = 0
    };
end

function DeletePlayer(id,name,team)
    if(spectating) then
        RemoveObject(mMP.players[id].cam);
    end
    bzUtils:DeletePlayer(id,name,team);
end

function Receive(from,type,func,...)
    print("Receive!",from,type,func,...);
    if(mMP.players[from]) then
        print("Accepted receive");
    --if((not mMP.me) or (mMP.me and mMP.me.id ~= from)) then  
        bzUtils:Receive(from,mType,func,...);
        if(type == "F" and receiveMap[func]) then
            receiveMap[func](from,...);
        end
    end
end

function Command(command,arguments)
    return (commandMap[command] and commandMap[command](arguments)) or bzUtils:Command(command,arguments);
end
