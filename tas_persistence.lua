local persistence = require("persistence")
local Tas = require("tas")

local module = {}

function module.save_tas(tas, file_name)
    local status = nil
    local save_data = tas:to_raw(true)
    local save_json = json.encode(save_data)
    local file, err = io.open(file_name, "w+")
    if not file then
        status = "Failed to open TAS file for writing: "..err
    else
        _, err = file:write(save_json)
        if err then
            status = "Failed to write to TAS file: "..err
        else
            status = "TAS saved successfully"
        end
        file:close()
    end
    return status
end

function module.load_tas(file_name)
    local file, err = io.open(file_name, "r")
    if not file then
        return nil, "Failed to open TAS file for reading: "..err
    else
        local load_json = file:read("*all")
        file:close()
        local success, result = persistence.json_decode(load_json, false)
        if not success then
            return nil, "Failed to decode TAS data from JSON: "..err
        else
            local tas = Tas:from_raw(result, true)
            return tas, "TAS loaded successfully"
        end
    end
end

return module
