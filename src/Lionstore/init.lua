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
local MessagingService = game:GetService("MessagingService")
local RunService = game:GetService("RunService")

local IsStudio = RunService:IsStudio()

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

local function wait(n)
    Promise.delay(n):await()
end;

local Shutdown = false

Lionstore.Info = {
    Partitions = 1;
    Default = {},
    HandleLocked = function(Player)
        Player:Kick()
    end,
    --BeforeSave
    --BeforeInitialGet
    --Retries
}
Lionstore.Modifiers = {}

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
    
    Profile.DatastoreKey = Key
    Profile.Key = tostring(Player.UserId)

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
                if (Profile:isLocked()) then
                    Profile:Lock()
                end;
            end
        end;
    end)

    Profile.Release = Instance.new("BindableEvent")

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
            Profile:SaveAsync()
        end;
    end
end)

Players.PlayerRemoving:Connect(function(Player)
    local Profile = Profiles[Player]
    if Profile then
        if Profile.Success then 
            Profile.Saving = Profile:Save()

            if (Profile.Saving) then
                Profile.Saving:await() 
            end;
        end;
        
        Profile.Release:Destroy()
        if (Profile.OnUpdate) then
            Profile.OnUpdate:Disconnect()
        end;
        Profiles[Player] = nil
    end
end)

function Lionstore:isLocked()
    return self.MainData.Locked > os.time()
end

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
    if (not Lionstore.Info.DisregardLimitCheck) then
        local Len = #HttpService:JSONEncode(Data)
        assert(Len <= Lionstore.Info.Chunk, ("data exceed %d char"):format(Len))
    end;
    self.CurrentData.list[1] = Data
end

function Lionstore:habitat(Callback, ErrHandle, ...)
    local Success, Result = pcall(Callback, self:get())

    if (not Success) then
        self.MainData.Corrupted = true
        warn("habitat err;", debug.traceback())
        if (ErrHandle) then
            ErrHandle(Result, ...)
        end;
    end
end

function Lionstore:GetChannel()
    return Promise.defer(function(resolve)
        resolve(MessagingService:SubscribeAsync(self.Key, function(data)
            data = HttpService:JSONDecode(data.Data)
            if data.code == 'release' then
                self.Release:Fire()
            else
                self.MainData.list[1] = Lionstore.Modifiers[data.code](self.Key, self:get(), data.args)
            end
        end))
    end):andThen(function(Con)
        self.OnUpdate = Con
    end):catch(function(err)
    
        warn(err)
        wait(5)
        return self:GetChannel()
    end)
end

function Lionstore:SendRelease()
    return Promise.new(function(resolve)
        resolve(MessagingService:PublishAsync(self.Key, HttpService:JSONEncode{code = 'release'}))
    end):catch(function(err)
    
        warn(err)
        wait(5)
        return self:SendRelease()
    end)
end

function Lionstore.read(Key, PlayerId, i)
    local Retries = Lionstore.Info.Retries or 5
    if not i then
        i = 0
    end
    i += 1

    local Datastore = DataStoreService:GetDataStore(Key)
    PlayerId = tostring(PlayerId)

    local this = Promise.defer(function(resolve, reject)
        local Success, Result = pcall(Datastore.GetAsync, Datastore, PlayerId)

        if Success then 
            if not Result then
                reject({error = ("Player with id %s doesn't exist"):format(PlayerId)})
            end
            resolve(Result)
        else
            reject(Result)
        end
    end):andThen(function(Result)
        Result = HttpService:JSONDecode(Result)
        local Info = {
            Locked = Result.Locked,
            Data = Result.Data[1]
        }
        return true, Info

    end):catch(function(Result)
        warn(Result)
        if i >= Retries then 
            return false, Result.error
        end
        print("read fail", PlayerId, "retry", i)
        wait(5)
        
        return Lionstore.read(Key, PlayerId, i)
    end)

    return this:await()
end

function Lionstore.modify(Key, PlayerId, Id, Args, i)
    assert(Lionstore.Modifiers[Id], ('Modifier %s doesn\'t exist'):format(Id))

    local Retries = Lionstore.Info.Retries or 5
    if not i then
        i = 0
    end
    i += 1

    local Datastore = DataStoreService:GetDataStore(Key)
    PlayerId = tostring(PlayerId)

    local this = Promise.defer(function(resolve, reject)
        local Success, Result = Lionstore.read(Key, PlayerId)

        if Success then 
            resolve(Result)
        else
            reject(Result)
        end
    end):andThen(function(Result)
        
        return Promise.defer(function(resolve)
            if Result.Locked then
                resolve(MessagingService:PublishAsync(PlayerId, HttpService:JSONEncode{code = Id, args = Args}))
            else
                resolve(Datastore:UpdateAsync(PlayerId, function(Data)
                    Data = HttpService:JSONDecode(Data)
                    Data.Data[1] = Lionstore.Modifiers[Id](PlayerId, Data.Data[1], Args)
                    return HttpService:JSONEncode(Data)
                end))
            end
        end)
    end)
    :andThenReturn(true)
    :catch(function(Result)
        warn(Result)
        if i >= Retries then 
            return false, Result
        end
        print("modify fail", PlayerId, "retry", i)
        wait(5)
        
        return Lionstore.modify(Key, PlayerId, Id, Args, i)
    end)

    return this:await()
end

function Lionstore.SetModifier(Id, Callback)
    Lionstore.Modifiers[Id] = Callback
end

function Lionstore:getDS()
    local Player = self.Player
    local Info = Lionstore.Info

    local this = Promise.defer(function(resolve, reject)
        local Success, Result = pcall(self.Datastore.GetAsync, self.Datastore, self.Key)
        if not Player.Parent then
            return
        end
        if Success then 
            resolve(Result)
        else
            reject(Result)
        end
        
    end):andThen(function(Result)
        
        
        if (Result) then
            Result = HttpService:JSONDecode(Result)
            if (Result.Corrupted) then
                local Type

                if (Info.HandleCorruption) then
                    Type = Info.HandleCorruption(Player, Result)
                end;
                if (not Type) then
                    return
                end;
            end
            if (Result.Locked > os.time()) then
                local Type

                if (Info.HandleLocked) then
                    self:GetChannel()
                    Type = Info.HandleLocked(Player, Result)
                end;
                if (not Type) then
                    return
                end;
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
    local P = self:setDS(function(Data)
        Data = self:applyBS(Data)
        Data.Locked = os.time() + 600
        return Data
    end, true)
    
    if not P then
        return
    end
    P:await()
end

function Lionstore:applyBS(DataTable)
    DataTable.Data = self.CurrentData.list

    local Info = Lionstore.Info

    if Info.BeforeSave then
        DataTable.Data[1] = Info.BeforeSave(self.Player, DataTable.Data[1])
    end

    return DataTable
end

function Lionstore:Save()
    
    return self:setDS(function(DataTable)
        DataTable.Locked = 0
        DataTable.VERSION += 1
        DataTable = self:applyBS(DataTable)
 
        return DataTable
    end)
end

function Lionstore:SaveAsync()
    local P = self:Save()
    if not P then
        return
    end
    P:await()
end

function Lionstore:setDS(Callback, isLock)
    local Player = self.Player
    if not self.MainData then
        return
    end
    if not game:GetService("ServerStorage"):FindFirstChild("lionstoreSave") and IsStudio then
        warn("data won't save due to no 'lionstoreSave' object in ServerStorage")
        return
    end
    print("saving", self.Player.Name, isLock and "lock")
    local Data = Callback(self.MainData)
    local this = Promise.defer(function(resolve)
        resolve(self.Datastore:SetAsync(self.Key, HttpService:JSONEncode(Data)))
    end):andThen(function()
        if (not isLock) then
            self:SendRelease():await()
        end;
        print("saved", Player.Name, isLock and "lock")
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