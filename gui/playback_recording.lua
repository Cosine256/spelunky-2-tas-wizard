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

-- The next unique ID for a frame tag in the GUI. The array index of the frame tag can't be used because it will confuse ImGui if they are reordered.
local next_frame_tag_data_id = 1
local frame_tag_datas
local frame_tag_move_index
local frame_tag_move_dir

function module:reset_session_vars()
    frame_tag_datas = {}
    frame_tag_move_index = nil
    frame_tag_move_dir = nil
    if active_tas_session then
        for i = 1, #active_tas_session.tas.frame_tags do
            frame_tag_datas[i] = {
                id = next_frame_tag_data_id
            }
            next_frame_tag_data_id = next_frame_tag_data_id + 1
        end
    end
end

local function draw_frame_tag(ctx, frame_tag_index, level_choices, level_combo)
    local tas = active_tas_session.tas
    local frame_tag = tas.frame_tags[frame_tag_index]
    local frame_tag_data = frame_tag_datas[frame_tag_index]
    ctx:win_pushid(frame_tag_data.id)

    local end_level_index = tas:get_end_level_index()
    local level_index = frame_tag.level == -1 and end_level_index or frame_tag.level
    -- TODO: Validate and clean up frame tags immediately when TAS data is changed, not here in the GUI.
    if level_index > end_level_index then
        level_index = end_level_index
        frame_tag.level = end_level_index
    end
    local end_frame_index = tas:get_end_frame_index(level_index)
    local frame_index = frame_tag.frame == -1 and end_frame_index or frame_tag.frame
    -- TODO: Validate and clean up frame tags immediately when TAS data is changed, not here in the GUI.
    if frame_index > end_frame_index then
        frame_index = end_frame_index
        frame_tag.frame = end_frame_index
    end
    local screen_records_frames = common_enums.TASABLE_SCREEN[tas.levels[level_index].metadata.screen].record_frames

    if ctx:win_button("Go") then
        active_tas_session.playback_target_level = level_index
        active_tas_session.playback_target_frame = frame_index
        game_controller.set_mode(common_enums.MODE.PLAYBACK)
    end
    ctx:win_inline()

    local section_label = frame_tag.name.." [Lv "..common.level_to_string(tas, level_index, false)
        ..(screen_records_frames and ", Fr "..frame_index or "").."]###section"
    ctx:win_section(section_label, function()
        ctx:win_indent(common_gui.INDENT_SECTION)

        frame_tag.name = ctx:win_input_text("Name", frame_tag.name)

        local end_level_choice = #level_choices
        local new_level = level_combo:draw(ctx, "Level", frame_tag.level == -1 and end_level_choice or frame_tag.level)
        local old_level_index = level_index
        if new_level == end_level_choice then
            level_index = #tas.levels
            frame_tag.level = -1
        else
            level_index = new_level
            frame_tag.level = new_level
        end

        if old_level_index ~= level_index then
            end_frame_index = tas:get_end_frame_index(level_index)
            frame_index = frame_tag.frame == -1 and end_frame_index or frame_tag.frame
            if frame_index > end_frame_index then
                frame_index = end_frame_index
                frame_tag.frame = end_frame_index
            end
            screen_records_frames = common_enums.TASABLE_SCREEN[tas.levels[level_index].metadata.screen].record_frames
        end

        if screen_records_frames then
            local new_frame_index
            ctx:win_width(0.25)
            if frame_tag.frame == -1 then
                ctx:win_drag_int("Frame", end_frame_index, end_frame_index, end_frame_index)
                new_frame_index = end_frame_index
            else
                new_frame_index = common_gui.draw_drag_int_clamped(ctx, "Frame", frame_tag.frame, 0, end_frame_index)
            end
            ctx:win_inline()
            local use_end_frame = ctx:win_check("End frame", frame_tag.frame == -1)
            frame_tag.frame = use_end_frame and -1 or new_frame_index
        end

        if ctx:win_button("Move up") then
            frame_tag_move_index = frame_tag_index
            frame_tag_move_dir = -1
        end
        ctx:win_inline()
        if ctx:win_button("Move down") then
            frame_tag_move_index = frame_tag_index
            frame_tag_move_dir = 1
        end
        ctx:win_inline()
        if ctx:win_button("Delete") then
            frame_tag_data.delete = true
        end

        ctx:win_indent(-common_gui.INDENT_SECTION)
    end)
    ctx:win_popid()
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
                active_tas_session.playback_target_level, active_tas_session.playback_target_frame = tas:get_end_indices()
                active_tas_session.playback_force_full_run = true
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
                draw_frame_tag(ctx, i, level_choices, level_combo)
                local frame_tag_data = frame_tag_datas[i]
                if frame_tag_data.delete then
                    table.remove(tas.frame_tags, i)
                    table.remove(frame_tag_datas, i)
                else
                    i = i + 1
                end
            end
            if frame_tag_move_index then
                local other_move_index = frame_tag_move_index + frame_tag_move_dir
                if frame_tag_datas[other_move_index] then
                    tas.frame_tags[frame_tag_move_index], tas.frame_tags[other_move_index] = tas.frame_tags[other_move_index], tas.frame_tags[frame_tag_move_index]
                    frame_tag_datas[frame_tag_move_index], frame_tag_datas[other_move_index] = frame_tag_datas[other_move_index], frame_tag_datas[frame_tag_move_index]
                end
                frame_tag_move_index = nil
                frame_tag_move_dir = nil
            end
            if ctx:win_button("Add frame tag") then
                table.insert(tas.frame_tags, {
                    name = "New",
                    level = active_tas_session.current_level_index or 1,
                    frame = active_tas_session.current_frame_index or 0
                })
                table.insert(frame_tag_datas, {
                    id = next_frame_tag_data_id
                })
                next_frame_tag_data_id = next_frame_tag_data_id + 1
            end

            ctx:win_separator()

            if active_tas_session.mode == common_enums.MODE.FREEPLAY then
                ctx:win_text("TAS is in freeplay mode. To start recording, playback to the desired frame first.")
            elseif active_tas_session.mode == common_enums.MODE.RECORD then
                if active_tas_session.current_level_index and active_tas_session.current_frame_index
                    and ctx:win_button("Switch to playback mode")
                then
                    if options.debug_print_mode then
                        print("Switching to playback mode.")
                    end
                    active_tas_session.playback_target_level, active_tas_session.playback_target_frame = tas:get_end_indices()
                    active_tas_session.playback_force_current_frame = true
                    game_controller.set_mode(common_enums.MODE.PLAYBACK)
                end
            elseif active_tas_session.mode == common_enums.MODE.PLAYBACK then
                if ctx:win_button("Switch to record mode") then
                    if options.debug_print_mode then
                        print("Switching to record mode.")
                    end
                    game_controller.set_mode(common_enums.MODE.RECORD)
                end
            end
            if active_tas_session.mode ~= common_enums.MODE.FREEPLAY then
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
