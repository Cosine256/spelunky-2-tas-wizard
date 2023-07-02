local module = {}

function module.update_format(obj, final_format, updaters)
    while obj.format ~= final_format do
        local updater = updaters[obj.format]
        if updater then
            -- TODO: Print is for testing.
            print("Updating from format "..obj.format.." to "..updater.output_format..".")
            updater.update(obj)
            obj.format = updater.output_format
        else
            error("Unknown format: "..tostring(obj.format))
        end
    end
end

function module.json_decode(str, allow_empty)
    if allow_empty and (str == nil or str == "") then
        return true, nil
    else
        local success, result = pcall(function()
            return json.decode(str)
        end)
        if success then
            return true, result
        else
            return false, "Failed to decode JSON into object: "..result
        end
    end
end

return module
