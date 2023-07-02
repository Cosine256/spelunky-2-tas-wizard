local ComboInput = {}
ComboInput.__index = ComboInput

function ComboInput:new(choices)
    local o = {}
    setmetatable(o, self)
    o:set_choices(choices)
    return o
end

function ComboInput:set_choices(choices)
    self._choices = choices
    local choice_name_array = {}
    for i = 1, choices:count() do
        local choice_id = choices:id_by_index(i)
        local choice_value = choices:value_by_index(i)
        local name
        if type(choice_value) == "table" then
            name = tostring(choice_value.name or choice_id)
        elseif type(choice_value) == "string" then
            name = choice_value
        elseif type(choice_value) == "number" or type(choice_value) == "boolean" then
            name = tostring(choice_value)
        else
            name = tostring(choice_id)
        end
        if #name == 0 then
            -- Empty strings break the way the combo parses the choice string. Replace them with spaces.
            name = " "
        end
        choice_name_array[i] = name
    end
    self._choice_string = table.concat(choice_name_array, "\0").."\0\0"
end

-- Draws a combo input. If the current choice ID does not match an existing choice, then it is set to the first choice. Returns the ID of the new choice, or `nil` if there are no choices. If the `on_change` function is specified, then it will be called only if the current choice and new choice are different. Its signature is: `function(current_choice_id, new_choice_id)`
function ComboInput:draw(ctx, name, current_choice_id, on_change)
    local current_choice_index = self._choices:index_by_id(current_choice_id) or 1
    local new_choice_index = ctx:win_combo(name, current_choice_index, self._choice_string)
    local new_choice_id = self._choices:id_by_index(new_choice_index)
    if on_change and current_choice_id ~= new_choice_id then
        on_change(current_choice_id, new_choice_id)
    end
    return new_choice_id
end

return ComboInput
