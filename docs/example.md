# Usage

```lua
local Lionstore = require(script.Parent.Lionstore)

Lionstore.SetInfo({
    Partitions = 9,
    Default = {Log = 0},
    HandleLocked = function(Player)
        print(Player.Name .. " has data loaded elsewhere")
    end,
    HandleCorruption = function(Player)
        print(Player.Name .. " has bad  data")
    end,
    BeforeSave = function(Player, Data) 
        print(Player.Name .. " is about to save") 
        return Data
    end,
    BeforeInitialGet = function(Player, Data)
        print(Player.Name .. " is getting  data")
        return Data
    end,
    
})

game.Players.PlayerAdded:Connect(function(Player)
    local Profile = Lionstore.new("key28285122", Player)

    Profile:habitat(function(Data)
        Profile:update(function()
            Data.Log += 1
            return Data
        end)
        print("person logged in; " .. Data.Log)
    end)
end)

```