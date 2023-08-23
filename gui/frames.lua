local ComboInput = require("gui/combo_input")
local common = require("common")
local common_enums = require("common_enums")
local common_gui = require("gui/common_gui")
local game_controller = require("game_controller")
local OrderedTable = require("ordered_table")
local Tool_GUI = require("gui/tool_gui")

local module = Tool_GUI:new("frames", "Frames", "frames_window")

local FRAMES_EDIT_OPERATION = OrderedTable:new({
    { id = "insert", name = "Insert", desc = "Insert new frames after the specified frame." },
    { id = "delete", name = "Delete", desc = "Delete frames, starting at the specified frame." }
})
local FRAMES_EDIT_OPERATION_COMBO = ComboInput:new(FRAMES_EDIT_OPERATION)

local frames_view_player_index
local frames_edit_operation
local frames_edit_level
local frames_edit_frame_start
local frames_edit_frame_count
local frames_edit_insert_use_start
local frames_edit_insert_inputs
local frame_edit_level
local frame_edit_frame
local frame_edit_player_index
local frame_edit_input
local frame_edit_input_orig

local function reset_frame_edit_vars()
    frame_edit_level = -1
    frame_edit_frame = -1
    frame_edit_player_index = 1
    frame_edit_input = INPUTS.NONE
    frame_edit_input_orig = INPUTS.NONE
end

function module.reset_vars()
    frames_view_player_index = 1
    frames_edit_operation = "delete"
    frames_edit_level = 0
    frames_edit_frame_start = 0
    frames_edit_frame_count = 1
    frames_edit_insert_use_start = true
    frames_edit_insert_inputs = {}
    reset_frame_edit_vars()
end

local function draw_input_editor_button_input(ctx, input, input_bit, label)
    return ctx:win_check(label, input & input_bit > 0) and (input | input_bit) or (input & ~input_bit)
end

local function draw_input_editor_inputs(ctx, input)
    input = draw_input_editor_button_input(ctx, input, INPUTS.LEFT, "Left")
    ctx:win_inline()
    input = draw_input_editor_button_input(ctx, input, INPUTS.RIGHT, "Right")
    ctx:win_inline()
    input = draw_input_editor_button_input(ctx, input, INPUTS.UP, "Up")
    ctx:win_inline()
    input = draw_input_editor_button_input(ctx, input, INPUTS.DOWN, "Down")

    input = draw_input_editor_button_input(ctx, input, INPUTS.JUMP, "Jump")
    ctx:win_inline()
    input = draw_input_editor_button_input(ctx, input, INPUTS.WHIP, "Whip")
    ctx:win_inline()
    input = draw_input_editor_button_input(ctx, input, INPUTS.BOMB, "Bomb")
    ctx:win_inline()
    input = draw_input_editor_button_input(ctx, input, INPUTS.ROPE, "Rope")

    input = draw_input_editor_button_input(ctx, input, INPUTS.DOOR, "Door")
    ctx:win_inline()
    input = draw_input_editor_button_input(ctx, input, INPUTS.RUN, "Run")
    ctx:win_inline()
    input = draw_input_editor_button_input(ctx, input, INPUTS.MENU, "Menu")
    ctx:win_inline()
    input = draw_input_editor_button_input(ctx, input, INPUTS.JOURNAL, "Journal")

    return input
end

function module:draw_panel(ctx, is_window)
    local session = game_controller.current

    ctx:win_section("Options", function()
        ctx:win_indent(common_gui.INDENT_SECTION)
        ctx:win_separator_text("Frames window")
        self:draw_window_options(ctx, is_window)
        ctx:win_separator_text("Input viewer")
        options.frames_shown_past = common.clamp(ctx:win_drag_int("Past frames shown", options.frames_shown_past, 0, 100), 0, 100)
        options.frames_shown_future = common.clamp(ctx:win_drag_int("Future frames shown", options.frames_shown_future, 0, 100), 0, 100)
        ctx:win_indent(-common_gui.INDENT_SECTION)
    end)

    ctx:win_separator()

    ctx:win_section("Editing tools", function()
        ctx:win_indent(common_gui.INDENT_SECTION)
        if not session then
            ctx:win_text("No TAS loaded.")
        elseif not session.tas:is_start_configured() then
            ctx:win_text("TAS start settings are not fully configured.")
        else
            frames_edit_operation = FRAMES_EDIT_OPERATION_COMBO:draw(ctx, "Operation", frames_edit_operation)
            ctx:win_text(FRAMES_EDIT_OPERATION:value_by_id(frames_edit_operation).desc)
            local level_choices = {
                [0] = "Current level"
            }
            for i = 1, #session.tas.levels do
                level_choices[i] = "Level "..common.level_metadata_to_string(session.tas, i)
            end
            local level_combo = ComboInput:new(OrderedTable:new(level_choices))
            frames_edit_level = level_combo:draw(ctx, "Level", frames_edit_level)
            if frames_edit_level == 0 and session.current_level_index == -1 then
                ctx:win_text("Current level is undefined.")
            else
                local level_index = frames_edit_level == 0 and session.current_level_index or frames_edit_level
                local level_data = session.tas.levels[level_index]
                ctx:win_text("Frames in level: "..#level_data.frames)
                if frames_edit_operation == "insert" then
                    frames_edit_frame_start = common.clamp(ctx:win_drag_int("Start frame", frames_edit_frame_start, 0, #level_data.frames), 0, #level_data.frames)
                    frames_edit_frame_count = math.max(1, ctx:win_drag_int("Frame count to insert", frames_edit_frame_count, 1, 60))
                    frames_edit_insert_use_start = ctx:win_check("Use inputs of start frame", frames_edit_insert_use_start)
                    for player_index = 1, session.tas:get_player_count() do
                        if frames_edit_insert_use_start and frames_edit_frame_start ~= 0 then
                            if frames_edit_frame_start == 0 then
                                frames_edit_insert_inputs[player_index] = INPUTS.NONE
                            else
                                frames_edit_insert_inputs[player_index] = level_data.frames[frames_edit_frame_start].players[player_index].input
                            end
                        elseif not frames_edit_insert_inputs[player_index] then
                            frames_edit_insert_inputs[player_index] = INPUTS.NONE
                        end
                        local input = frames_edit_insert_inputs[player_index]
                        if session.tas:get_player_count() == 1 then
                            input = draw_input_editor_inputs(ctx, input)
                        else
                            ctx:win_section("Player "..player_index.." inputs", function()
                                ctx:win_pushid(player_index)
                                input = draw_input_editor_inputs(ctx, input)
                                ctx:win_popid()
                            end)
                        end
                        if not frames_edit_insert_use_start then
                            frames_edit_insert_inputs[player_index] = input
                        end
                    end
                    if ctx:win_button("Insert") then
                        session.tas:insert_frames(level_index, frames_edit_frame_start, frames_edit_frame_count, frames_edit_insert_inputs)
                        frames_edit_frame_start = frames_edit_frame_start + frames_edit_frame_count
                        game_controller.validate_current_frame()
                        game_controller.validate_playback_target()
                    end
                elseif frames_edit_operation == "delete" then
                    if #level_data.frames == 0 then
                        ctx:win_text("Level contains no frames to delete.")
                    else
                        frames_edit_frame_start = common.clamp(ctx:win_drag_int("Start frame", frames_edit_frame_start, 1, #level_data.frames), 1, #level_data.frames)
                        local max_frame_count = #level_data.frames - frames_edit_frame_start + 1
                        frames_edit_frame_count = common.clamp(ctx:win_drag_int("Frame count to delete", frames_edit_frame_count, 1, max_frame_count), 1, max_frame_count)
                        ctx:win_text("Frames to delete (inclusive): "..frames_edit_frame_start.." to "..(frames_edit_frame_start + frames_edit_frame_count - 1))
                        if ctx:win_button("Delete") then
                            session.tas:delete_frames(level_index, frames_edit_frame_start, frames_edit_frame_count)
                            game_controller.validate_current_frame()
                            game_controller.validate_playback_target()
                        end
                    end
                end
            end
        end
        ctx:win_indent(-common_gui.INDENT_SECTION)
    end)

    ctx:win_separator()

    ctx:win_section("Input viewer", function()
        ctx:win_indent(common_gui.INDENT_SECTION)
        if not session then
            ctx:win_text("No TAS loaded.")
        elseif not session.tas:is_start_configured() then
            ctx:win_text("TAS start settings are not fully configured.")
        elseif game_controller.mode == common_enums.MODE.FREEPLAY then
            ctx:win_text("TAS in freeplay mode.")
        elseif session.current_level_index == -1 then
            ctx:win_text("No TAS data for current level.")
        elseif game_controller.current_frame_index == -1 then
            ctx:win_text("Current frame is undefined.")
        else
            if session.tas:get_player_count() == 1 then
                frames_view_player_index = 1
            else
                local player_chars = session.tas:get_player_chars()
                local player_choices = {}
                for i = 1, session.tas:get_player_count() do
                    player_choices[i] = i.." ("..common_enums.PLAYER_CHAR:value_by_id(player_chars[i]).name..")"
                end
                local player_combo = ComboInput:new(OrderedTable:new(player_choices))
                frames_view_player_index = player_combo:draw(ctx, "Player", frames_view_player_index)
                ctx:win_separator()
            end
            for i = 1 - options.frames_shown_past, options.frames_shown_future do
                ctx:win_pushid(i)
                local frame_index = game_controller.current_frame_index + i
                if session.current_level_data and session.current_level_data.frames[frame_index] then
                    local input = session.current_level_data.frames[frame_index].players[frames_view_player_index].input
                    local label = tostring(frame_index)
                    if i == 0 then
                        label = label.." (Previous)"
                    elseif i == 1 then
                        label = label.." (Next)"
                    end
                    ctx:win_input_text(label, common.input_to_string(input))
                    ctx:win_inline()
                    if ctx:win_button("Edit") then
                        frame_edit_level = session.current_level_index
                        frame_edit_frame = frame_index
                        frame_edit_player_index = frames_view_player_index
                        frame_edit_input = input
                        frame_edit_input_orig = input
                    end
                else
                    ctx:win_input_text("", "")
                end
                if i == 0 then
                    ctx:win_separator()
                end
                ctx:win_popid()
            end
        end
        ctx:win_indent(-common_gui.INDENT_SECTION)
    end)
end

-- TODO: Attach this to the frames window instead of making a separate window.
function module.draw_frame_edit_window(ctx, session)
    if frame_edit_level == -1 then
        return
    end

    local keep_open = ctx:window("Edit Frame ("..frame_edit_level.."-"..frame_edit_frame..")", -0.6, 0.8, 0.0, 0.0, true, function()
        frame_edit_input = draw_input_editor_inputs(ctx, frame_edit_input)
        ctx:win_input_text("Old input", common.input_to_string(frame_edit_input_orig))
        ctx:win_input_text("New input", common.input_to_string(frame_edit_input))

        if ctx:win_button("OK") then
            if session.tas.levels[frame_edit_level] and session.tas.levels[frame_edit_level].frames[frame_edit_frame] then
                session.tas.levels[frame_edit_level].frames[frame_edit_frame].players[frame_edit_player_index].input = frame_edit_input
                reset_frame_edit_vars()
            else
                print("Warning: Failed to edit frame "..frame_edit_level.."-"..frame_edit_frame.." for player "..frame_edit_player_index..": Frame does not exist.")
            end
        end
        ctx:win_inline()
        if ctx:win_button("Cancel") then
            reset_frame_edit_vars()
        end
    end)

    if not keep_open then
        reset_frame_edit_vars()
    end
end

return module
