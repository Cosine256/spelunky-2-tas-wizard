local common_gui = require("gui/common_gui")
local Tool_GUI = require("gui/tool_gui")

local module = Tool_GUI:new("root", "TAS Tool", "root_window")

local ordered_tool_guis

function module:draw_panel(ctx, is_window)
    common_gui.draw_tool_gui_panels(ctx, ordered_tool_guis)
end

function module:initialize()
    ordered_tool_guis = {
        tool_guis.file,
        tool_guis.options,
        tool_guis.tas_root,
        tool_guis.ghost
    }
end

return module
