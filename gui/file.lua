local common_gui = require("gui/common_gui")
local tas_persistence = require("tas_persistence")
local Tool_GUI = require("gui/tool_gui")

local module = Tool_GUI:new("file", "New, Save, Load")

local file_io_status

function module:draw_panel(ctx, is_window)
    ctx:win_text("TAS file:")
    ctx:win_inline()
    ctx:win_width(0.9999)
    options.tas_file_name = ctx:win_input_text("##tas_file_name", options.tas_file_name)
    if ctx:win_button("New##new_tas") then
        set_active_tas(options.new_tas:copy())
        file_io_status = "New TAS created"
    end
    ctx:win_inline()
    if active_tas_session then
        if ctx:win_button("Save##save_tas") then
            file_io_status = tas_persistence.save_tas(active_tas_session.tas, options.tas_file_name)
            tas_persistence.add_tas_file_history(options.tas_file_name, active_tas_session.tas.name)
        end
        ctx:win_inline()
    end
    if ctx:win_button("Load##load_tas") then
        local tas
        tas, file_io_status = tas_persistence.load_tas(options.tas_file_name)
        if tas then
            tas_persistence.add_tas_file_history(options.tas_file_name, tas.name)
        end
        set_active_tas(tas)
    end
    ctx:win_inline()
    if ctx:win_button("Load as ghost##load_ghost") then
        local tas
        tas, file_io_status = tas_persistence.load_tas(options.tas_file_name)
        if tas then
            tas_persistence.add_tas_file_history(options.tas_file_name, tas.name)
        end
        set_ghost_tas(tas)
    end
    if active_tas_session then
        ctx:win_inline()
        if ctx:win_button("Unload##unload_tas") then
            set_active_tas(nil)
            file_io_status = "TAS unloaded"
        end
    end
    if file_io_status then
        ctx:win_width(0.9999)
        ctx:win_input_text("##file_io_status", file_io_status)
    end
    if #options.tas_file_history > 0 then
        ctx:win_pushid("tas_file_history")
        ctx:win_section("History", function()
            ctx:win_indent(common_gui.INDENT_SECTION)
            local remove
            for i, item in ipairs(options.tas_file_history) do
                ctx:win_pushid(i)
                local label
                if #item.name == 0 then
                    label = item.file_name
                else
                    label = item.name.." ("..item.file_name..")"
                end
                if ctx:win_button(label.."###select") then
                    options.tas_file_name = item.file_name
                end
                ctx:win_inline()
                if ctx:win_button("X") then
                    remove = i
                end
                ctx:win_popid()
            end
            if remove then
                table.remove(options.tas_file_history, remove)
            end
            ctx:win_indent(-common_gui.INDENT_SECTION)
        end)
        ctx:win_popid()
    end
    ctx:win_text("The TAS file input accepts file paths relative to this mod's data directory. When writing files, directories will be created if needed. The data directory is located in the Spelunky 2 install directory at \"Mods/Data/[mod_name]\".")
end

return module
