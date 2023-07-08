local common = require("common")
local common_enums = require("common_enums")
local common_gui = require("gui/common_gui")
local game_controller = require("game_controller")
local Tool_GUI = require("gui/tool_gui")

local module = Tool_GUI:new("Options", "options_window")

function module:draw_panel(ctx, is_window)
    if not is_window then
        -- TODO: Can't distinguish between whether this is embedded in the options dropdown or the TAS Tool window.
        if ctx:win_button("Show TAS Tool window") then
            if options.root_window.visible then
                if game_controller.mode == common_enums.MODE.PLAYBACK and options.presentation_enabled then
                    -- This is a shortcut for the user to disable the presentation mode setting during playback.
                    options.presentation_enabled = false
                end
            else
                options.root_window.visible = true
            end
        end
        ctx:win_separator()
    end

    ctx:win_separator_text("Speed tweaks")
    options.transition_skip = ctx:win_check("Skip level transitions", options.transition_skip)

    ctx:win_separator_text("Automatic pausing")
    ctx:win_text("These options control automatic game engine pauses. The pauses are the same ones used by Overlunky for frame advancing. These pauses are not recommended for use in regular Playlunky, as you will not have controls to unpause or frame advance.")
    options.pause_recording_on_level_start = ctx:win_check("Pause recording on level start", options.pause_recording_on_level_start)
    options.pause_playback_on_level_start = ctx:win_check("Pause playback on level start", options.pause_playback_on_level_start)
    options.pause_desync = ctx:win_check("Pause when desync is detected", options.pause_desync)

    ctx:win_separator_text("Player paths")
    -- TODO: This only controls visibility of the current TAS path, not the ghost TAS path. Maybe have this setting apply globally to all paths, and then add a new TAS setting for showing its own path.
    options.paths_visible = ctx:win_check("Draw paths", options.paths_visible)
    options.path_marks_visible = ctx:win_check("Draw path marks", options.path_marks_visible)
    options.path_mark_labels_visible = ctx:win_check("Draw path mark labels", options.path_mark_labels_visible)
    options.path_mark_increment = ctx:win_input_int("Frames between path marks", options.path_mark_increment)
    if options.path_mark_increment < 1 then
        options.path_mark_increment = 1
    end

    ctx:win_separator_text("Presentation mode")
    ctx:win_text("Presentation mode hides the TAS Tool GUI and paths, and disables speed tweaks.")
    options.presentation_enabled = ctx:win_check("Activate during playback", options.presentation_enabled)

    ctx:win_separator_text("Tools")
    -- TODO: These are shown in an arbitrary order. Give them some meaningful order, such as alphabetical, or the order they appear in the root GUI.
    for _, tool_gui in pairs(tool_guis) do
        ctx:win_text(tool_gui.name)
        ctx:win_indent(common_gui.INDENT_SUB_INPUT)
        options[tool_gui.option_id].visible = ctx:win_check("Windowed##"..tool_gui.option_id.."_windowed", options[tool_gui.option_id].visible)
        if ctx:win_button("Reset position##"..tool_gui.option_id.."_reset") then
            tool_gui:reset_window_position()
        end
        ctx:win_indent(-common_gui.INDENT_SUB_INPUT)
    end

    ctx:win_separator_text("Debug")
    options.debug_print_load = ctx:win_check("Print load info", options.debug_print_load)
    options.debug_print_file = ctx:win_check("Print file info", options.debug_print_file)
    options.debug_print_frame = ctx:win_check("Print frame info", options.debug_print_frame)
    options.debug_print_input = ctx:win_check("Print input info", options.debug_print_input)
    options.debug_print_mode = ctx:win_check("Print mode info", options.debug_print_mode)
    options.debug_print_pause = ctx:win_check("Print pause info", options.debug_print_pause)
    options.debug_print_snapshot = ctx:win_check("Print snapshot info", options.debug_print_snapshot)

    ctx:win_separator_text("Option persistence")
    if ctx:win_button("Save options") then
        if not save_script() then
            print("Save occurred too recently. Wait a few seconds and try again.")
        end
    end
    ctx:win_text("Immediately save the current options. Saves also happen automatically during screen changes.")
    if ctx:win_button("Reset options") then
        options = common.deep_copy(default_options)
    end
    ctx:win_text("Reset all TAS Tool options to their default values. This does not affect any loaded TAS data.")
end

return module