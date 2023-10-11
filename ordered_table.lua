local OrderedTable = {}
OrderedTable.__index = OrderedTable

OrderedTable.SORT_BY_KEY = function(entry_1, entry_2)
    return entry_1.key < entry_2.key
end

OrderedTable.SORT_BY_ID = function(entry_1, entry_2)
    return entry_1.id < entry_2.id
end

function OrderedTable:new(new_table, sort)
    local o = {}
    setmetatable(o, self)
    o._sort = sort or self.SORT_BY_KEY
    o:update(new_table)
    return o
end

function OrderedTable:update(new_table)
    self._entries_by_index = {}
    self._entries_by_id = {}
    if new_table == nil then
        return
    end
    for k, v in pairs(new_table) do
        local id
        if type(v) == "table" then
            if type(v.id) == "string" or type(v.id) == "number" then
                id = v.id
            elseif v.id ~= nil then
                id = tostring(v.id)
            else
                id = k
            end
        else
            id = k
        end
        table.insert(self._entries_by_index, {
            key = k,
            id = id,
            value = v
        })
    end
    table.sort(self._entries_by_index, self._sort)
    for i, entry in ipairs(self._entries_by_index) do
        entry.index = i
        entry.key = nil -- The key was only needed for sorting.
        self._entries_by_id[entry.id] = entry
    end
end

function OrderedTable:values_by_index()
    local values = {}
    for i, entry in ipairs(self._entries_by_index) do
        values[i] = entry.value
    end
    return values
end

function OrderedTable:values_by_id()
    local values = {}
    for id, entry in pairs(self._entries_by_id) do
        values[id] = entry.value
    end
    return values
end

function OrderedTable:value_by_index(index)
    local entry = self._entries_by_index[index]
    return entry and entry.value or nil
end

function OrderedTable:value_by_id(id)
    local entry = self._entries_by_id[id]
    return entry and entry.value or nil
end

function OrderedTable:id_by_index(index)
    local entry = self._entries_by_index[index]
    return entry and entry.id or nil
end

function OrderedTable:index_by_id(id)
    local entry = self._entries_by_id[id]
    return entry and entry.index or nil
end

function OrderedTable:count()
    return #self._entries_by_index
end

return OrderedTable
