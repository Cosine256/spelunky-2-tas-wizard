local ComboInput = require("gui/combo_input")
local common = require("common")
local common_enums = require("common_enums")
local common_gui = require("gui/common_gui")
local OrderedTable = require("ordered_table")
local ToolGui = require("gui/tool_gui")

local module = ToolGui:new("playback_record", "Playback & Recording")

local PLAYBACK_TARGET_MODE_COMBO = ComboInput:new(common_enums.PLAYBACK_TARGET_MODE)

local RECORD_FRAME_CLEAR_ACTION = OrderedTable:new({
    { id = "none", name = "None", desc = "When recording starts, do not delete any frames." },
    { id = "remaining_screen", name = "Remaining screen", desc = "When recording starts, delete all future frames in the current screen." },
    { id = "remaining_tas", name = "Remaining TAS", desc = "When recording starts, delete all future frames in the entire TAS." }
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

local function draw_frame_tag(ctx, frame_tag_index, screen_choices, screen_combo)
    local tas = active_tas_session.tas
    local frame_tag = tas.frame_tags[frame_tag_index]
    local frame_tag_data = frame_tag_datas[frame_tag_index]
    ctx:win_pushid(frame_tag_data.id)

    local end_screen_index = tas:get_end_screen_index()
    local screen_index = frame_tag.screen == -1 and end_screen_index or frame_tag.screen
    -- TODO: Validate and clean up frame tags immediately when TAS data is changed, not here in the GUI.
    if screen_index > end_screen_index then
        screen_index = end_screen_index
        frame_tag.screen = end_screen_index
    end
    local end_frame_index = tas:get_end_frame_index(screen_index)
    local frame_index = frame_tag.frame == -1 and end_frame_index or frame_tag.frame
    -- TODO: Validate and clean up frame tags immediately when TAS data is changed, not here in the GUI.
    if frame_index > end_frame_index then
        frame_index = end_frame_index
        frame_tag.frame = end_frame_index
    end
    local screen_records_frames = common_enums.TASABLE_SCREEN[tas.screens[screen_index].metadata.screen].record_frames

    if ctx:win_button("Go") then
        active_tas_session:set_mode_playback(screen_index, frame_index)
    end
    ctx:win_inline()

    local section_label = frame_tag.name.." [Scr "..common.tas_screen_to_string(tas, screen_index, false)
        ..(screen_records_frames and ", Fr "..frame_index or "").."]###section"
    ctx:win_section(section_label, function()
        ctx:win_indent(common_gui.INDENT_SECTION)

        frame_tag.name = ctx:win_input_text("Name", frame_tag.name)

        local end_screen_choice = #screen_choices
        local new_screen = screen_combo:draw(ctx, "Screen", frame_tag.screen == -1 and end_screen_choice or frame_tag.screen)
        local old_screen_index = screen_index
        if new_screen == end_screen_choice then
            screen_index = #tas.screens
            frame_tag.screen = -1
        else
            screen_index = new_screen
            frame_tag.screen = new_screen
        end

        if old_screen_index ~= screen_index then
            end_frame_index = tas:get_end_frame_index(screen_index)
            frame_index = frame_tag.frame == -1 and end_frame_index or frame_tag.frame
            if frame_index > end_frame_index then
                frame_index = end_frame_index
                frame_tag.frame = end_frame_index
            end
            screen_records_frames = common_enums.TASABLE_SCREEN[tas.screens[screen_index].metadata.screen].record_frames
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

        frame_tag.show_on_path = ctx:win_check("Show on path", frame_tag.show_on_path)

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

function module:draw_pause_controls(ctx)
    if pause:paused() then
        if ctx:win_button("Unpause") then
            pause:set_paused(false)
        end
        ctx:win_inline()
        if ctx:win_button("Frame advance") then
            pause:frame_advance()
        end
    else
        if ctx:win_button("Pause") then
            pause:set_paused(true)
        end
    end
    ctx:win_text("These are basic manual controls for engine pauses. Using Overlunky's engine pause controls instead is highly recommended.")
end

function module:draw_playback_from_here_unpause_option(ctx)
    options.playback_from_here_unpause = ctx:win_check("Unpause for playback from current frame", options.playback_from_here_unpause)
end

function module:draw_playback_from_warp_unpause_option(ctx)
    options.playback_from_warp_unpause = ctx:win_check("Unpause for playback from warp", options.playback_from_warp_unpause)
end

function module:draw_playback_screen_load_pause_option(ctx)
    options.playback_screen_load_pause = ctx:win_check("Pause after screen load during playback", options.playback_screen_load_pause)
end

function module:draw_record_screen_load_pause_option(ctx)
    options.record_screen_load_pause = ctx:win_check("Pause after screen load during recording", options.record_screen_load_pause)
end

function module:draw_playback_target_pause_option(ctx)
    options.playback_target_pause = ctx:win_check("Pause at playback target", options.playback_target_pause)
end

function module:draw_playback_fast_update_option(ctx, include_desc)
    options.playback_fast_update = ctx:win_check("Fast playback", options.playback_fast_update)
    if include_desc then
        ctx:win_text("During playback, execute game updates as fast as possible and skip rendering on most frames. The game will be very laggy during fast updates.")
    end
end

function module:draw_panel(ctx, is_window)
    ctx:win_section("More Options", function()
        ctx:win_indent(common_gui.INDENT_SECTION)
        self:draw_window_options(ctx, is_window)
        self:draw_playback_from_here_unpause_option(ctx)
        self:draw_playback_from_warp_unpause_option(ctx)
        self:draw_playback_screen_load_pause_option(ctx)
        self:draw_record_screen_load_pause_option(ctx)
        self:draw_pause_controls(ctx)
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

        if #tas.screens == 0 then
            ctx:win_text("No data to playback.")
        else
            if ctx:win_button("Playback entire TAS") then
                active_tas_session:set_mode_playback(tas:get_end_screen_index(), tas:get_end_frame_index(), true, false)
            end

            ctx:win_separator()

            local screen_choices = {}
            for i = 1, #tas.screens do
                screen_choices[i] = common.tas_screen_to_string(tas, i, false)
            end
            screen_choices[#screen_choices + 1] = "End screen"
            screen_choices = OrderedTable:new(screen_choices)
            local screen_combo = ComboInput:new(screen_choices)
            local i = 1
            while i <= #tas.frame_tags do
                draw_frame_tag(ctx, i, screen_choices, screen_combo)
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
                    screen = active_tas_session.current_screen_index or 1,
                    frame = active_tas_session.current_frame_index or 0,
                    show_on_path = true
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
                if active_tas_session.current_screen_index and active_tas_session.current_frame_index
                    and ctx:win_button("Switch to playback mode")
                then
                    print_debug("mode", "draw_panel: Switching to playback mode.")
                    active_tas_session:set_mode_playback(tas:get_end_screen_index(), tas:get_end_frame_index(), false, true)
                end
            elseif active_tas_session.mode == common_enums.MODE.PLAYBACK then
                if ctx:win_button("Switch to record mode") then
                    print_debug("mode", "draw_panel: Switching to record mode.")
                    active_tas_session:set_mode_record()
                end
            end
            if active_tas_session.mode ~= common_enums.MODE.FREEPLAY then
                if ctx:win_button("Switch to freeplay mode") then
                    print_debug("mode", "draw_panel: Switching to freeplay mode.")
                    active_tas_session:set_mode_freeplay()
                end
            end
        end

        local playback_from_choices = {}
        for i, playback_from_choice in ipairs(common_enums.PLAYBACK_FROM) do
            playback_from_choices[i] = playback_from_choice
        end
        for i = 1, #tas.screens do
            playback_from_choices[#playback_from_choices + 1] = {
                id = i,
                name = "Screen "..common.tas_screen_to_string(tas, i, false)
            }
        end
        local playback_from_combo = ComboInput:new(OrderedTable:new(playback_from_choices))
        options.playback_from = playback_from_combo:draw(ctx, "Playback from", options.playback_from)
        options.playback_target_mode = PLAYBACK_TARGET_MODE_COMBO:draw(ctx, "Playback target action", options.playback_target_mode)
        self:draw_playback_target_pause_option(ctx)
        self:draw_playback_fast_update_option(ctx, false)

        ctx:win_separator_text("Recording")

        if #tas.screens == 0 then
            if ctx:win_button("Start recording") and active_tas_session:trigger_warp(1) then
                active_tas_session:set_mode_record()
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
