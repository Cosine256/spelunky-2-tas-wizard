local common_gui = require("gui/common_gui")
local Tool_GUI = require("gui/tool_gui")

local module = Tool_GUI:new("New", "new_window")

function module:draw_panel(ctx, is_window)
    ctx:win_pushid("new_tas_start_settings")
    common_gui.draw_tas_start_settings(ctx, options.new_tas)
    ctx:win_popid()
    if ctx:win_button("Create") then
        set_current_tas(options.new_tas:copy())
    end
    ctx:win_text("Create a new TAS with these settings.")
end

return module
