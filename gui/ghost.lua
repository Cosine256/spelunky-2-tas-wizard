local Tool_GUI = require("gui/tool_gui")

local module = Tool_GUI:new("ghost", "Ghost")

function module:draw_ghost_path_visible_option(ctx)
    options.ghost_path_visible = ctx:win_check("Show ghost TAS paths", options.ghost_path_visible)
end

function module:draw_panel(ctx, is_window)
    if active_tas_session and ctx:win_button("Create ghost from active TAS") then
        set_ghost_tas(active_tas_session.tas:copy())
    end
    if ghost_tas_session then
        if ctx:win_button("Clear ghost") then
            set_ghost_tas(nil)
        end
    else
        ctx:win_text("No ghost TAS loaded.")
    end
    self:draw_ghost_path_visible_option(ctx)
end

return module
