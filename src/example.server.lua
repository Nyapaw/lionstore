local Lionstore = require(script.Parent.Lionstore)

Lionstore.SetInfo({
    Partitions = 9,
    Default = {Log = 0},
    HandleLocked = function(Player)
        print(Player.Name .. " has data loaded elsewhere")
        local Profile = Lionstore.GetProfile(Player)
        Profile.Release.Event:Wait()
        print("other servers done")
        return true
    end,
    HandleCorruption = function(Player, Data)
        print(Player.Name .. " has bad  data")
        local File2 = Data.Data[2]
        if File2 then
            print('revert')
            Data.Data[1] = File2
            Data.Corrupted = false
            return true
        end
    end,
    BeforeSave = function(Player, Data) 
        print(Player.Name .. " is about to save") 
        return Data
    end,
    BeforeInitialGet = function(Player, Data)
        print(Player.Name .. " has data")
        return Data
    end,
    
})

game.Players.PlayerAdded:Connect(function(Player)
    local Profile = Lionstore.new("key2825122", Player)

    Profile:habitat(function(Data)
        Profile:update(function()
            Data.Log += 1
            return Data
        end)
        print("person logged in; " .. Data.Log)
    end)
end)
