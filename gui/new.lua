local common_gui = require("gui/common_gui")
local Tool_GUI = require("gui/tool_gui")

local module = Tool_GUI:new("new", "New", "new_window")

function module:draw_panel(ctx, is_window)
    common_gui.draw_tas_start_settings(ctx, options.new_tas)
    if ctx:win_button("Create") then
        set_current_tas(options.new_tas:copy())
    end
    ctx:win_text("Create a new TAS with these settings.")
end

return module
