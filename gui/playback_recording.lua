local ComboInput = require("gui/combo_input")
local common = require("common")
local common_enums = require("common_enums")
local common_gui = require("gui/common_gui")
local game_controller = require("game_controller")
local OrderedTable = require("ordered_table")
local Tool_GUI = require("gui/tool_gui")

local module = Tool_GUI:new("Playback & Recording", "playback_recording_window")

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

local START_TAGGED_FRAME = {
    immutable = true,
    name = "Start",
    level = 1,
    frame = 0
}
local END_TAGGED_FRAME = {
    immutable = true,
    name = "End",
    level = -1,
    frame = -1
}

local function draw_tagged_frame(ctx, id, tas, tagged_frame, level_choices, level_combo)
    ctx:win_pushid(id)
    local delete = false
    local level = tagged_frame.level == -1 and #tas.levels or tagged_frame.level
    local frame = tagged_frame.frame == -1 and #tas.levels[level].frames or tagged_frame.frame
    if tagged_frame.immutable then
        ctx:win_text(tagged_frame.name)
        ctx:win_input_text("##level", level_choices:value_by_id(level))
        ctx:win_inline()
        ctx:win_width(0.25)
        ctx:win_input_text("Frame", tostring(frame))
    else
        tagged_frame.name = ctx:win_input_text("Name", tagged_frame.name)
        level = level_combo:draw(ctx, "##level", level)
        ctx:win_inline()
        ctx:win_width(0.25)
        frame = common.clamp(ctx:win_drag_int("Frame", frame, 0, #tas.levels[level].frames), 0, #tas.levels[level].frames)
        tagged_frame.level = level
        tagged_frame.frame = frame
    end
    if ctx:win_button("Playback to here") then
        game_controller.playback_target_level = level
        game_controller.playback_target_frame = frame
        game_controller.set_mode(common_enums.MODE.PLAYBACK)
    end
    if not tagged_frame.immutable then
        ctx:win_inline()
        if ctx:win_button("Delete") then
            delete = true
        end
    end
    ctx:win_popid()
    return delete
end

function module:draw_panel(ctx, is_window)
    -- TODO: This panel feels messy. How could I reorganize it to be easier to use?
    ctx:win_section("Options##playback_recording_panel_options", function()
        ctx:win_indent(common_gui.INDENT_SECTION)
        -- TODO: Share code for all tool GUIs that have this option.
        if is_window then
            if ctx:win_button("Reset window position") then
                self:reset_window_position()
            end
        else
            if ctx:win_button("Detach into window") then
                options[self.option_id].visible = true
            end
        end
        ctx:win_indent(-common_gui.INDENT_SECTION)
    end)

    ctx:win_separator()

    if game_controller.current then
        local tas_session = game_controller.current
        local tas = tas_session.tas

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
                level_choices[i] = common.level_metadata_to_string(tas, i)
            end
            level_choices = OrderedTable:new(level_choices)
            local level_combo = ComboInput:new(level_choices)
            draw_tagged_frame(ctx, -1, tas, START_TAGGED_FRAME, level_choices, level_combo)
            ctx:win_separator()
            draw_tagged_frame(ctx, 0, tas, END_TAGGED_FRAME, level_choices, level_combo)
            local i = 1
            while i <= #tas.tagged_frames do
                local tagged_frame = tas.tagged_frames[i]
                ctx:win_separator()
                if draw_tagged_frame(ctx, i, tas, tagged_frame, level_choices, level_combo) then
                    table.remove(tas.tagged_frames, i)
                else
                    i = i + 1
                end
            end
            ctx:win_separator()
            if ctx:win_button("Create tagged frame") then
                table.insert(tas.tagged_frames, {
                    name = "New",
                    level = tas_session.current_level_index == -1 and 1 or tas_session.current_level_index,
                    frame = game_controller.current_frame_index == -1 and 0 or game_controller.current_frame_index
                })
            end
            ctx:win_separator()
            if game_controller.mode == common_enums.MODE.FREEPLAY then
                ctx:win_text("TAS is in freeplay mode. To start recording, playback to the desired frame first.")
            elseif game_controller.mode == common_enums.MODE.RECORD then
                if (tas_session.current_level_index < #tas.levels or game_controller.current_frame_index < #tas_session.current_level_data.frames) and ctx:win_button("Switch to playback mode") then
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
            "Current frame or nearest level",
            "Current frame",
            "Nearest level"
        }
        for i = 1, #tas.levels do
            playback_from_choices[i + 3] = "Level "..common.level_metadata_to_string(tas, i)
        end
        local playback_from_combo = ComboInput:new(OrderedTable:new(playback_from_choices))
        options.playback_from = playback_from_combo:draw(ctx, "Playback from", options.playback_from)
        options.playback_target_mode = PLAYBACK_TARGET_MODE_COMBO:draw(ctx, "Playback target action", options.playback_target_mode)
        options.playback_target_pause = ctx:win_check("Pause at playback target", options.playback_target_pause)

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
    else
        ctx:win_text("No TAS loaded.")
    end
end

return module
