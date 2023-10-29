local common = require("common")
local common_gui = require("gui/common_gui")
local tas_persistence = require("tas_persistence")
local Tool_GUI = require("gui/tool_gui")

local module = Tool_GUI:new("options", "Options")

function module:draw_panel(ctx, is_window)
    if not is_window then
        -- TODO: Can't distinguish between whether this is embedded in the options dropdown or the TAS Tool window.
        if ctx:win_button("Show TAS Tool window") then
            if presentation_active then
                presentation_active = false
            end
            tool_guis.root:set_window_open(true)
        end
        if presentation_active then
            if ctx:win_button("Deactivate presentation mode") then
                presentation_active = false
            end
        else
            if ctx:win_button("Activate presentation mode") then
                presentation_active = true
            end
        end
        ctx:win_separator()
    end

    ctx:win_separator_text("Speed tweaks")
    tool_guis.playback_record:draw_playback_fast_update_option(ctx, true)
    options.transition_skip = ctx:win_check("Skip transition screens", options.transition_skip)
    ctx:win_text("Instantly skip transition screens instead of allowing them to fade in and out. This also skips the spaceship cutscene screen after exiting 6-4 via the spaceship.")

    ctx:win_separator_text("Automatic pausing")
    ctx:win_text("These options control automatic game engine pauses. The pauses are the same ones used by Overlunky for frame advancing. These pauses are not recommended for use in regular Playlunky, as you will not have hotkeys to unpause or frame advance.")
    tool_guis.playback_record:draw_unpause_button(ctx)
    tool_guis.playback_record:draw_playback_target_pause_option(ctx)
    tool_guis.playback_record:draw_playback_screen_load_pause_option(ctx)
    tool_guis.playback_record:draw_record_screen_load_pause_option(ctx)
    options.desync_pause = ctx:win_check("Pause when desync is detected", options.desync_pause)
    options.pause_suppress_transition_tas_inputs = ctx:win_check("Suppress transition TAS inputs instead of pausing", options.pause_suppress_transition_tas_inputs)
    ctx:win_text("Instead of engine pausing in a transition screen, temporarily suppress TAS inputs and wait for the user to exit the transition manually.")

    ctx:win_separator_text("Player paths")
    ctx:win_text("Player paths show the recorded positions of each player.")
    options.active_path_visible = ctx:win_check("Show active TAS paths", options.active_path_visible)
    tool_guis.ghost:draw_ghost_path_visible_option(ctx)
    options.path_mark_visible = ctx:win_check("Draw path marks", options.path_mark_visible)
    options.path_mark_label_visible = ctx:win_check("Draw path mark labels", options.path_mark_label_visible)
    options.path_mark_increment = ctx:win_input_int("Frames between path marks", options.path_mark_increment)
    if options.path_mark_increment < 1 then
        options.path_mark_increment = 1
    end

    ctx:win_separator_text("Mode watermark")
    ctx:win_text("A mode watermark can be shown on the screen to indicate that the TAS is in recording or playback mode.")
    options.mode_watermark_visible = ctx:win_check("Show mode watermark###mode_watermark_visible", options.mode_watermark_visible)
    options.mode_watermark_x = common_gui.draw_drag_float_clamped(ctx, "Watermark X", options.mode_watermark_x, -1.0, 1.0)
    options.mode_watermark_y = common_gui.draw_drag_float_clamped(ctx, "Watermark Y", options.mode_watermark_y, -1.0, 1.0)
    options.mode_watermark_size = common_gui.draw_drag_float_clamped(ctx, "Watermark size", options.mode_watermark_size, 1.0, 200.0)

    ctx:win_separator_text("Presentation mode")
    ctx:win_text("Presentation mode hides the TAS Tool GUI and paths, and disables speed tweaks.")
    options.presentation_start_on_playback = ctx:win_check("Activate on playback", options.presentation_start_on_playback)
    options.presentation_stop_after_playback = ctx:win_check("Deactivate after playback", options.presentation_stop_after_playback)
    options.presentation_mode_watermark_visible = ctx:win_check("Show mode watermark###presentation_mode_watermark_visible",
        options.presentation_mode_watermark_visible)
    ctx:win_text("Show the mode watermark in presentation mode.")

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

    ctx:win_separator_text("Tool GUIs")
    -- TODO: These are shown in an arbitrary order. Give them some meaningful order, such as alphabetical, or the order they appear in the root GUI.
    ctx:win_pushid("tool_guis")
    ctx:win_section("Tool GUIs", function()
        ctx:win_indent(common_gui.INDENT_SECTION)
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
        ctx:win_indent(-common_gui.INDENT_SECTION)
    end)
    ctx:win_popid()

    ctx:win_separator_text("Debug")
    ctx:win_pushid("debug_prints")
    ctx:win_section("Debug Prints", function()
        ctx:win_indent(common_gui.INDENT_SECTION)
        options.debug_print_load = ctx:win_check("Load info", options.debug_print_load)
        options.debug_print_fast_update = ctx:win_check("Fast update info", options.debug_print_fast_update)
        options.debug_print_file = ctx:win_check("File info", options.debug_print_file)
        options.debug_print_frame = ctx:win_check("Frame info", options.debug_print_frame)
        options.debug_print_input = ctx:win_check("Input info", options.debug_print_input)
        options.debug_print_mode = ctx:win_check("Mode info", options.debug_print_mode)
        options.debug_print_pause = ctx:win_check("Pause info", options.debug_print_pause)
        options.debug_print_snapshot = ctx:win_check("Snapshot info", options.debug_print_snapshot)
        ctx:win_indent(-common_gui.INDENT_SECTION)
    end)
    ctx:win_popid()

    ctx:win_separator_text("Option persistence")
    if ctx:win_button("Save options") then
        if not save_script() then
            print("Save occurred too recently. Wait a few seconds and try again.")
        end
    end
    ctx:win_text("Immediately save the current TAS Tool options. Saves also happen automatically during screen changes.")
    if ctx:win_button("Reset options") then
        options = common.deep_copy(default_options)
    end
    ctx:win_text("Reset all TAS Tool options to their default values. This does not affect any loaded TAS data or saved TAS files.")
end

return module
