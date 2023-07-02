local game_controller = require("game_controller")
local tas_persistence = require("tas_persistence")
local Tool_GUI = require("gui/tool_gui")

local module = Tool_GUI:new("Save & Load", "save_load_window")

local file_io_status

function module:draw_panel(ctx, is_window)
    ctx:win_text("TAS file:")
    ctx:win_inline()
    ctx:win_width(0.9999)
    options.file_name = ctx:win_input_text("##file_name", options.file_name)
    if file_io_status then
        ctx:win_width(0.9999)
        ctx:win_input_text("##file_io_status", file_io_status)
    end
    if game_controller.current then
        if ctx:win_button("Save##save_tas") then
            file_io_status = tas_persistence.save_tas(game_controller.current.tas, options.file_name)
        end
        ctx:win_inline()
    end
    if ctx:win_button("Load##load_tas") then
        local tas
        tas, file_io_status = tas_persistence.load_tas(options.file_name)
        set_current_tas(tas)
    end
    ctx:win_inline()
    if ctx:win_button("Load as ghost##load_ghost") then
        local tas
        tas, file_io_status = tas_persistence.load_tas(options.file_name)
        game_controller.set_ghost_tas(tas)
    end
    if game_controller.current then
        ctx:win_inline()
        if ctx:win_button("Unload current##unload_tas") then
            set_current_tas(nil)
            file_io_status = "TAS unloaded"
        end
    end
    if options.file_name:find("[/\\]") then
        ctx:win_text("Note: This script cannot create directories. If this directory does not exist, then you'll need to create it yourself.")
    end
    ctx:win_text("The TAS file input accepts any valid file path. By default, relative paths are relative to the directory containing the Spelunky 2 executable file.")
end

return module
