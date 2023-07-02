local game_controller = require("game_controller")
local Tool_GUI = require("gui/tool_gui")

local module = Tool_GUI:new("Ghost", "ghost_window")

function module:draw_panel(ctx, is_window)
    if game_controller.current and ctx:win_button("Create ghost from current") then
        game_controller.set_ghost_tas(game_controller.current.tas:copy())
    end
    if game_controller.ghost_tas_session then
        if ctx:win_button("Clear ghost") then
            game_controller.set_ghost_tas(nil)
        end
    else
        ctx:win_text("No ghost TAS loaded.")
    end
    options.ghost_path_visible = ctx:win_check("Draw ghost paths", options.ghost_path_visible)
end

return module
