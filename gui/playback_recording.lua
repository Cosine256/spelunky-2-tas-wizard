local ComboInput = require("gui/combo_input")
local common = require("common")
local common_enums = require("common_enums")
local common_gui = require("gui/common_gui")
local game_controller = require("game_controller")
local OrderedTable = require("ordered_table")
local Tool_GUI = require("gui/tool_gui")

local module = Tool_GUI:new("playback_recording", "Playback & Recording", "playback_recording_window")

local PLAYBACK_TARGET_MODE_COMBO = ComboInput:new(common_enums.PLAYBACK_TARGET_MODE)

local RECORD_FRAME_CLEAR_ACTION = OrderedTable:new({
    { id = "none", name = "None", desc = "When recording starts, do not delete any frames." },
    { id = "remaining_level", name = "Remaining level", desc = "When recording starts, delete all future frames in the current level." },
    { id = "remaining_run", name = "Remaining run", desc = "When recording starts, delete all future frames in the entire run." }
})
local RECORD_FRAME_CLEAR_ACTION_COMBO = ComboInput:new(RECORD_FRAME_CLEAR_ACTION)

local RECORD_FRAME_WRITE_TYPE = OrderedTable:new({
    { id = "overwrite", name = "Overwrite", desc = "Overwrite existing frames with recorded frames." },
    { id = "insert", name = "Insert", desc = "Insert recorded frames in front of existing frames." }
})
local RECORD_FRAME_WRITE_TYPE_COMBO = ComboInput:new(RECORD_FRAME_WRITE_TYPE)

local function draw_frame_tag(ctx, id, tas, frame_tag, level_choices, level_combo)
    ctx:win_pushid(id)

    frame_tag.name = ctx:win_input_text("Name", frame_tag.name)

    local level_index
    local new_level = level_combo:draw(ctx, "##level", frame_tag.level == -1 and #level_choices or frame_tag.level)
    if new_level == #level_choices then
        frame_tag.level = -1
        level_index = #tas.levels
    else
        frame_tag.level = new_level
        level_index = new_level
    end

    local end_frame_index = tas:get_end_frame_index(level_index)
    local frame_index
    local new_frame
    ctx:win_inline()
    ctx:win_width(0.25)
    if frame_tag.frame == -1 then
        ctx:win_drag_int("Frame", end_frame_index, end_frame_index, end_frame_index)
        new_frame = end_frame_index
    else
        new_frame = common_gui.draw_drag_int_clamped(ctx, "Frame", frame_tag.frame, 0, end_frame_index)
    end
    local use_end_frame = ctx:win_check("End frame", frame_tag.frame == -1)
    if use_end_frame then
        frame_tag.frame = -1
        frame_index = end_frame_index
    else
        frame_tag.frame = new_frame
        frame_index = new_frame
    end

    if ctx:win_button("Playback to here") then
        game_controller.playback_target_level = level_index
        game_controller.playback_target_frame = frame_index
        game_controller.set_mode(common_enums.MODE.PLAYBACK)
    end
    local delete = false
    ctx:win_inline()
    if ctx:win_button("Delete") then
        delete = true
    end

    ctx:win_popid()
    return delete
end

function module:draw_fast_update_playback_option(ctx, include_desc)
    options.fast_update_playback = ctx:win_check("Fast playback", options.fast_update_playback)
    if include_desc then
        ctx:win_text("During playback, execute game updates as fast as possible and skip rendering on most frames. The game will be very laggy during fast updates.")
    end
end

function module:draw_panel(ctx, is_window)
    -- TODO: This panel feels messy. How could I reorganize it to be easier to use?
    ctx:win_section("Options", function()
        ctx:win_indent(common_gui.INDENT_SECTION)
        self:draw_window_options(ctx, is_window)
        ctx:win_indent(-common_gui.INDENT_SECTION)
    end)

    ctx:win_separator()

    if not active_tas_session then
        ctx:win_text("No TAS loaded.")
    elseif not active_tas_session.tas:is_start_configured() then
        ctx:win_text("TAS start settings are not fully configured.")
    else
        local tas = active_tas_session.tas

        ctx:win_separator_text("Playback")

        if #tas.levels == 0 then
            ctx:win_text("No data to playback.")
        else
            if ctx:win_button("Playback entire run") then
                game_controller.playback_target_level, game_controller.playback_target_frame = tas:get_end_indices()
                game_controller.playback_force_full_run = true
                game_controller.set_mode(common_enums.MODE.PLAYBACK)
            end

            ctx:win_separator()

            local level_choices = {}
            for i = 1, #tas.levels do
                level_choices[i] = common.level_to_string(tas, i, false)
            end
            level_choices[#level_choices + 1] = "End level"
            level_choices = OrderedTable:new(level_choices)
            local level_combo = ComboInput:new(level_choices)
            local i = 1
            while i <= #tas.frame_tags do
                local frame_tag = tas.frame_tags[i]
                if draw_frame_tag(ctx, i, tas, frame_tag, level_choices, level_combo) then
                    table.remove(tas.frame_tags, i)
                else
                    i = i + 1
                end
                ctx:win_separator()
            end
            if ctx:win_button("Create frame tag") then
                table.insert(tas.frame_tags, {
                    name = "New",
                    level = active_tas_session.current_level_index or 1,
                    frame = active_tas_session.current_frame_index or 0
                })
            end
            ctx:win_separator()
            if game_controller.mode == common_enums.MODE.FREEPLAY then
                ctx:win_text("TAS is in freeplay mode. To start recording, playback to the desired frame first.")
            elseif game_controller.mode == common_enums.MODE.RECORD then
                if active_tas_session.current_level_index and active_tas_session.current_frame_index
                    and ctx:win_button("Switch to playback mode")
                then
                    if options.debug_print_mode then
                        print("Switching to playback mode.")
                    end
                    game_controller.playback_target_level, game_controller.playback_target_frame = tas:get_end_indices()
                    game_controller.playback_force_current_frame = true
                    game_controller.set_mode(common_enums.MODE.PLAYBACK)
                end
            elseif game_controller.mode == common_enums.MODE.PLAYBACK then
                if ctx:win_button("Switch to record mode") then
                    if options.debug_print_mode then
                        print("Switching to record mode.")
                    end
                    game_controller.set_mode(common_enums.MODE.RECORD)
                end
            end
            if game_controller.mode ~= common_enums.MODE.FREEPLAY then
                if ctx:win_button("Switch to freeplay mode") then
                    if options.debug_print_mode then
                        print("Switching to freeplay mode.")
                    end
                    game_controller.set_mode(common_enums.MODE.FREEPLAY)
                end
            end
        end

        local playback_from_choices = {
            "Here or nearest level",
            "Here, else nearest level",
            "Nearest level"
        }
        for i = 1, #tas.levels do
            playback_from_choices[i + 3] = "Level "..common.level_to_string(tas, i, false)
        end
        local playback_from_combo = ComboInput:new(OrderedTable:new(playback_from_choices))
        options.playback_from = playback_from_combo:draw(ctx, "Playback from", options.playback_from)
        options.playback_target_mode = PLAYBACK_TARGET_MODE_COMBO:draw(ctx, "Playback target action", options.playback_target_mode)
        options.playback_target_pause = ctx:win_check("Pause at playback target", options.playback_target_pause)
        self:draw_fast_update_playback_option(ctx, false)

        ctx:win_separator_text("Recording")

        if #tas.levels == 0 then
            if ctx:win_button("Start recording") and game_controller.apply_start_state() then
                game_controller.set_mode(common_enums.MODE.RECORD)
            end
        else
            options.record_frame_clear_action = RECORD_FRAME_CLEAR_ACTION_COMBO:draw(ctx, "Clear frames on record", options.record_frame_clear_action)
            local clear_action = RECORD_FRAME_CLEAR_ACTION:value_by_id(options.record_frame_clear_action)
            ctx:win_text(clear_action.name..": "..clear_action.desc)
            options.record_frame_write_type = RECORD_FRAME_WRITE_TYPE_COMBO:draw(ctx, "Frame write behavior", options.record_frame_write_type)
            local write_type = RECORD_FRAME_WRITE_TYPE:value_by_id(options.record_frame_write_type)
            ctx:win_text(write_type.name..": "..write_type.desc)
        end
    end
end

return module
