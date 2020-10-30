# API

## InfoSettings
Passed into `Lionstore.SetInfo`
### Partitions 
`number` **Required**

Must be 1+, allocates a DataStore into smaller partitions with limit `DataSize/Partitions` chars; DataSize is the char [limit](https://developer.roblox.com/en-us/articles/Datastore-Errors). More partitions gives you more leeway on restoring past backups but reduces the size of your partitions.

!!! warning
    Once set, you **can't** change this unless you use a new key

### Default 
`table` **Required**

The default data loaded into a new player. If missing entries of a preloaded profile exists, the data will be [reconciled](https://madstudioroblox.github.io/ProfileService/api/#profilereconcile).

### HandleLocked
`callback(Player: instance, Data: table)`

Calls when the profile is locked and does not load.

### HandleCorruption
`callback(Player: instance, Data: table)`


Calls when the profile is corrupted and does not load.

### BeforeSave
`modifier(Player: instance, Data: table) -> table`

Calls when the profile is about to be saved. **Must return profile data**.

### BeforeInitialGet
`modifier(Player: instance, Data: table) -> table`

Calls when after a value is received from Roblox data stores. **Must return profile data**.

## Lionstore
### .SetInfo
```
SetInfo(InfoSettings)
```

Set lionstore settings.

### .GetProfile
```
GetProfile(Player: instance) -> Profile?
```

Get a profile from the player if it exists.

### .new
```
new(key: string, Player: instance) -> Profile
```

Makes a new profile.

## Profile
### :loaded
```
loaded() -> boolean
```

Returns whether the data is loaded.

### :get
```
get() -> table
```

Returns the data.

### :update
```
update(modifier(data: table))
```

Update the data. **Must return profile data**.

### :habitat
```
habitat(run: callback(data: table), onCorrupt?: callback(error: string))
```

Create a habitat where the `run` callback is passed data. Acts as a pcall. Whenever an error arises, sets profile status to corrupt and calls `onCorrupt`.

!!! info
    This is the recommended way to run code in which you are dealing with profile data, no matter if you are getting or setting!

### :Lock
```
Lock()
```
Yields until the profile is locked. The library automatically locks the profile every 4 minutes so you can forget about this. Adds 10 minutes to the lock timer.

### :Save
```
Save() -> Promise
```
Saves the profile. Returns a [promise](https://eryn.io/roblox-lua-promise/). Sets lock timer to 0 and increments the version number. The library automatically saves the profile when the player leaves.

### .MainData

!!! warning
    NILABLE if profile is not loaded. Use :loaded to check!
    
```
{
    Corrupted: boolean,
    Data: array
    VERSION: number,
    Locked: number
}
```

A table describing the player's data. 

`VERSION` is the number of times the player has :Save called,

`Data` is the array where indices are 1 to `Partitions` where 1 is the latest data. 

`Locked` is the number signifying if the profile is locked- `unix time < Locked`.

`Corrupted` signifies that the profile is corrupted.