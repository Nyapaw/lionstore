# Tips

On `HandleLocked` you can steal a lock if you return true. A good use is wait n seconds for another server to save your data, polling the callback. If after n seconds nothing changes, return true.

By default studio doesn't save data. You can change this by putting `lionstoreSave` in ServerStorage.
