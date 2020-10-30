--https://github.com/Nyapaw/lionstore

local Lionstore = {}
Lionstore.__index = Lionstore

local DATA_BUDGET = 3999000;

local Promise = require(script.Promise)
local Queue = require(script.Queue)
local spawn = require(script.spawn)
local inspect = require(script.inspect)
local TableUtil = require(script.TableUtil)
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

Lionstore.Profiles = {}
local Profiles = Lionstore.Profiles

local concat = function(...)
    local str = ""
    for _, item in pairs({...}) do
        str = str .. (type(item) == 'table' and inspect(item) or item) .. " "
    end
    return str
end

local print = function(...)
    print("Lionstore; " .. concat(...))
end;

local warn = function(...)
    warn("Lionstore; " .. concat(...))
end;

local Shutdown = false

Lionstore.Info = {
    Partitions = 1;
    Default = {},
    HandleError = function(Player)
        Player:Kick()
    end,
    --BeforeSave
    --BeforeInitialGet
}

function Lionstore.SetInfo(Info)
    Lionstore.Info = Info;

    local Partitions = Info.Partitions
    Info.Chunk = math.floor(DATA_BUDGET/Partitions)
end

function Lionstore.GetProfile(Player)
    return Lionstore.Profiles[Player]
end

function Lionstore.new(Key, Player)
    if Shutdown then
        return
    end;
    print("init", Player.Name)

    local Profile = setmetatable({}, Lionstore)
    Profiles[Player] = Profile

    Profile.Player = Player
    Profile.Datastore = DataStoreService:GetDataStore(Key)
    
    Profile.Key = Player.UserId

    Profile.Loaded = Profile:getDS()
    Profile.CurrentData = Queue.new(Lionstore.Info.Partitions)
    --Profile.MainData 

    spawn(function()
        Profile.Loaded:await()
        if Player.Parent then
            while true do
                wait(240)
                if Shutdown or not Player.Parent then
                    break
                end
                Profile:Lock()
            end
        end;
    end)

    return Profile
end 

game:BindToClose(function()
    Shutdown = true
    for _, Profile in pairs(Profiles) do
        if not Profile.Success then 
            continue 
        end;
        if (Profile.Saving) then
            Profile.Saving:await()
        else
            Profile:Save():await()
        end;
    end
end)

Players.PlayerRemoving:Connect(function(Player)
    local Profile = Profiles[Player]
    if Profile then
        if Profile.Success then 
            Profiles[Player].Saving = Profile:Save()
            Profiles[Player].Saving:await() 
        end;
        
        Profiles[Player] = nil
    end
end)

function Lionstore:loaded()
    return self.Loaded:getStatus() ~= "Started"
end

function Lionstore:check()
    if not self:loaded() then
        self.Loaded:await()
    end
    assert(self.Success, "corrupt " .. self.Player.Name)
end

function Lionstore:get()
    self:check()
    
    return self.CurrentData:peek()
end

function Lionstore:update(Callback)
    self:check()
    
    local Data = Callback(self:get())
    assert(Data, "no return")
    local Len = #HttpService:JSONEncode(Data)
    assert(Len <= Lionstore.Info.Chunk, ("data exceed %d char"):format(Len))
    self.CurrentData.list[1] = Data
end

function Lionstore:habitat(Callback, ErrHandle)
    local Success, Result = pcall(Callback, self:get())

    if (not Success) then
        self.MainData.Corrupted = true
        warn("habitat err;", debug.traceback())
        if (ErrHandle) then
            ErrHandle(Result)
        end;
    end
end

function Lionstore:getDS()
    local Player = self.Player
    local Info = Lionstore.Info

    local this = Promise.async(function(resolve, reject)
        local Success, Result = pcall(self.Datastore.GetAsync, self.Datastore, self.Key)
        if Success then 
            resolve(Result)
        else
            reject(Result)
        end
        
    end):andThen(function(Result)
        if not Player.Parent then
            return
        end
        
        if (Result) then
            Result = HttpService:JSONDecode(Result)
            if (Result.Corrupted) then
                Info.HandleCorruption(Player, Result)
                return
            end
            if (Result.Locked > os.time()) then
                Info.HandleLocked(Player, Result)
                return
            end
            self.MainData = Result
            self.CurrentData.list = Result.Data
            self.CurrentData:push(TableUtil.clone(self.CurrentData:peek()))

            local File1 = self.CurrentData:peek()
            for field, value in pairs(Info.Default) do
                if File1[field] == nil then --falsible
                    local isTable = type(value) == 'table'

                    if (isTable) then
                        File1[field] = TableUtil.clone(value)
                    else
                        File1[field] = value
                    end;
                end
            end
            if Info.BeforeInitialGet then
                self.CurrentData.list[1] = Info.BeforeInitialGet(Player, File1)
            end
        else
            self.MainData = {
                VERSION = 0;
                Locked = 0;
                Data = {};
                Corrupted = false,
            }
            self.CurrentData:push( TableUtil.clone(Info.Default))
            print("new", Player.Name)
        end;

        print("load", Player.Name)
        self.Success = true
        self:Lock()
    end):catch(function(Result)
        warn(Result)
        print("get fail", Player.Name, "retrying")
        wait(5)
        if not Player.Parent then 
            return
        end
        return self:getDS()
    end)

    return this
end

function Lionstore:Lock()
    print("Lock", self.Player.Name)
    self:setDS(function(Data)
        Data.Locked = os.time() + 600
        return Data
    end, "lock"):await()
end

function Lionstore:Save()
    
    return self:setDS(function(DataTable)
        DataTable.Locked = 0
        DataTable.VERSION += 1
        DataTable.Data = self.CurrentData.list

        local Info = Lionstore.Info

        if Info.BeforeSave then
            DataTable.Data[1] = Info.BeforeSave(self.Player, DataTable.Data[1])
        end    
 
        return DataTable
    end)
end

function Lionstore:setDS(Callback, Message)
    local Player = self.Player
    if not self.MainData then
        return
    end
    print("saving", self.Player.Name, Message or "")
    local Data = Callback(self.MainData)

    local this = Promise.async(function(resolve, reject)
        local Success, Result = pcall(self.Datastore.SetAsync, self.Datastore, self.Key, HttpService:JSONEncode(Data))
        if Success then 
            resolve()
        else
            reject(Result)
        end
        
    end):andThen(function()
        print("saved".. (Message and " " .. Message or ""), Player.Name)
    end):catch(function(Result)
        warn(Result)
        print("set fail", Player.Name, "retrying")
        wait(5)
        if not Player.Parent then 
            return
        end
        return self:setDS()
    end)

    return this
end

return Lionstore