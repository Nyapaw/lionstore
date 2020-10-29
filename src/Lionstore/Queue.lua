local Queue = {};
Queue.__index = Queue;

Queue.new = function(MAX)
    local Self = {};

    Self.list = {}; 
    Self.MAX = MAX;

    return setmetatable(Self, Queue);
end

function Queue:push(obj)
    local MAX = self.MAX;
    table.insert(self.list, 1, obj);
    if (#self.list > MAX) then
        table.remove(self.list, MAX)
    end;
end;

function Queue:get(index)
    return self.list[index];
end;

function Queue:peek()
    return self:get(1)
end

return Queue;