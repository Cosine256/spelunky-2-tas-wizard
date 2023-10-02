local common = require("common")
local common_enums = require("common_enums")
local common_gui = require("gui/common_gui")
local game_controller = require("game_controller")
local tas_persistence = require("tas_persistence")
local Tool_GUI = require("gui/tool_gui")

local module = Tool_GUI:new("options", "Options", "options_window")

function module:draw_panel(ctx, is_window)
    if not is_window then
        -- TODO: Can't distinguish between whether this is embedded in the options dropdown or the TAS Tool window.
        if ctx:win_button("Show TAS Tool window") then
            if tool_guis.root:is_window_open() then
                if game_controller.mode == common_enums.MODE.PLAYBACK and options.presentation_enabled then
                    -- This is a shortcut for the user to disable the presentation mode setting during playback.
                    options.presentation_enabled = false
                end
            else
                tool_guis.root:set_window_open(true)
            end
        end
        ctx:win_separator()
    end

    ctx:win_separator_text("Speed tweaks")
    options.transition_skip = ctx:win_check("Skip level transitions", options.transition_skip)

    ctx:win_separator_text("Automatic pausing")
    ctx:win_text("These options control automatic game engine pauses. The pauses are the same ones used by Overlunky for frame advancing. These pauses are not recommended for use in regular Playlunky, as you will not have controls to unpause or frame advance.")
    options.pause_playback_on_screen_load = ctx:win_check("Pause after screen loads during playback", options.pause_playback_on_screen_load)
    options.pause_recording_on_screen_load = ctx:win_check("Pause after screen loads during recording", options.pause_recording_on_screen_load)
    options.pause_desync = ctx:win_check("Pause when desync is detected", options.pause_desync)
    options.pause_suppress_auto_transition_exit = ctx:win_check("Suppress transition auto-exit instead of pausing", options.pause_suppress_auto_transition_exit)
    ctx:win_text("Instead of pausing in a transition screen, temporarily suppress automatically exiting the transition.")

    ctx:win_separator_text("Player paths")
    -- TODO: This only controls visibility of the active TAS path, not the ghost TAS path. Maybe have this setting apply globally to all paths, and then add a new TAS setting for showing its own path.
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

    ctx:win_separator_text("TAS file history")
    local new_tas_file_history_max_size = math.max(ctx:win_input_int("Max size", options.tas_file_history_max_size), 0)
    if options.tas_file_history_max_size ~= new_tas_file_history_max_size then
        options.tas_file_history_max_size = new_tas_file_history_max_size
        tas_persistence.trim_tas_file_history()
    end
    if ctx:win_button("Clear history") then
        options.tas_file_history = {}
    end

    ctx:win_separator_text("Default TAS settings")
    ctx:win_text("These TAS settings are used as a preset when creating a new TAS, and as default values when changing some settings in existing TASes.")
    ctx:win_section("Default TAS", function()
        ctx:win_pushid("new_tas_settings")
        ctx:win_indent(common_gui.INDENT_SECTION)
        common_gui.draw_tas_start_settings(ctx, options.new_tas, true)
        ctx:win_indent(-common_gui.INDENT_SECTION)
        ctx:win_popid()
    end)

    ctx:win_separator_text("Tools")
    -- TODO: These are shown in an arbitrary order. Give them some meaningful order, such as alphabetical, or the order they appear in the root GUI.
    ctx:win_pushid("tool_guis")
    for _, tool_gui in pairs(tool_guis) do
        ctx:win_pushid(tool_gui.id)
        ctx:win_text(tool_gui.name)
        ctx:win_indent(common_gui.INDENT_SUB_INPUT)
        if not tool_gui.is_popup then
            tool_gui:set_window_open(ctx:win_check("Windowed", tool_gui:is_window_open()))
        end
        if ctx:win_button("Reset window position") then
            tool_gui:reset_window_position()
        end
        ctx:win_indent(-common_gui.INDENT_SUB_INPUT)
        ctx:win_popid()
    end
    ctx:win_popid()

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
