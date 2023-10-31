local common_gui = require("gui/common_gui")
local ToolGui = require("gui/tool_gui")

local module = ToolGui:new("tas_root", "Active TAS")

local ordered_tool_guis

function module:draw_panel(ctx, is_window)
    common_gui.draw_tool_gui_panels(ctx, ordered_tool_guis)
end

function module:initialize()
    ordered_tool_guis = {
        tool_guis.tas_settings,
        tool_guis.tas_data,
        tool_guis.playback_record,
        tool_guis.warp,
        tool_guis.status
    }
end

return module
