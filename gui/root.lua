local common_gui = require("gui/common_gui")
local common_enums = require("common_enums")
local game_controller = require("game_controller")
local Tool_GUI = require("gui/tool_gui")

local module = Tool_GUI:new("TAS Tool", "root_window")

-- This can't be initialized until later after all of the tool GUI modules are loaded.
local ordered_tool_guis

function module:draw_panel(ctx, is_window)
    if not ordered_tool_guis then
        ordered_tool_guis = {
            tool_guis.new,
            tool_guis.save_load,
            tool_guis.options,
            tool_guis.tas_settings,
            tool_guis.playback_recording,
            tool_guis.frames,
            tool_guis.status,
            tool_guis.warp,
            tool_guis.ghost
        }
    end
    local panel_drawn = false
    for _, tool_gui in ipairs(ordered_tool_guis) do
        if not options[tool_gui.option_id].visible then
            if panel_drawn then
                ctx:win_separator()
            else
                panel_drawn = true
            end
            -- TODO: Give tool GUIs a second name field where only the first word is capitalized for sections.
            ctx:win_section(tool_gui.name, function()
                ctx:win_indent(common_gui.INDENT_SECTION)
                tool_gui:draw_panel(ctx, false)
                ctx:win_indent(-common_gui.INDENT_SECTION)
            end)
        end
    end
    if not panel_drawn then
        ctx:win_text("All tools detached into separate windows.")
    end
end

function module.draw_windows(ctx)
    if game_controller.mode == common_enums.MODE.PLAYBACK and options.presentation_enabled then
        return
    end
    for _, tool_gui in pairs(tool_guis) do
        tool_gui:draw_window(ctx)
    end
    -- TODO: Combine this window with the frames GUI.
    tool_guis.frames.draw_frame_edit_window(ctx, game_controller.current)
end

return module
