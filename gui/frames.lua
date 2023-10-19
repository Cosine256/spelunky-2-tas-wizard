local ComboInput = require("gui/combo_input")
local common = require("common")
local common_enums = require("common_enums")
local common_gui = require("gui/common_gui")
local game_controller = require("game_controller")
local OrderedTable = require("ordered_table")
local Tool_GUI = require("gui/tool_gui")

local module = Tool_GUI:new("frames", "Frames", "frames_window")

local BULK_OPERATION = OrderedTable:new({
    { id = "none", name = "None" },
    { id = "insert", name = "Insert", desc = "Insert new frames after the specified frame." },
    { id = "delete", name = "Delete", desc = "Delete frames, starting at the specified frame." }
})
local BULK_OPERATION_COMBO = ComboInput:new(BULK_OPERATION)

local selected_level_index = 0
local edit_mode = false
local bulk_operation = "none"
local bulk_start_index
local bulk_count
local bulk_use_start_inputs = false
local bulk_inputs
local viewer_player_index = 1
local viewer_frame_index = 1
local last_current_level_index
local last_current_frame_index

function module:reset_session_vars()
    bulk_start_index = 0
    bulk_count = 1
    bulk_inputs = {}
    last_current_level_index = nil
    last_current_frame_index = nil
end

local function compute_last_page_frame_index()
    return math.max(active_tas_session.tas:get_end_frame_index(module.level_index) - options.frames_viewer_page_size + 1, 1)
end

local function draw_page_controls(ctx, id)
    ctx:win_pushid(id)
    if ctx:win_button("|<") then
        viewer_frame_index = 1
    end
    ctx:win_inline()
    if ctx:win_button("-"..options.frames_viewer_step_size) then
        viewer_frame_index = math.max(viewer_frame_index - options.frames_viewer_step_size, 1)
    end
    ctx:win_inline()
    viewer_frame_index = common_gui.draw_drag_int_clamped(ctx, "##viewer_frame_index", viewer_frame_index,
        1, active_tas_session.tas:get_end_frame_index(module.level_index))
    ctx:win_inline()
    if ctx:win_button("+"..options.frames_viewer_step_size) and viewer_frame_index < compute_last_page_frame_index() then
        viewer_frame_index = math.min(viewer_frame_index + options.frames_viewer_step_size, compute_last_page_frame_index())
    end
    ctx:win_inline()
    if ctx:win_button(">|") then
        viewer_frame_index = compute_last_page_frame_index()
    end
    ctx:win_popid()
end

function module:draw_panel(ctx, is_window)
    ctx:win_section("Options", function()
        ctx:win_indent(common_gui.INDENT_SECTION)
        self:draw_window_options(ctx, is_window)
        options.frames_viewer_page_size = common_gui.draw_drag_int_clamped(ctx, "Frame viewer page size", options.frames_viewer_page_size, 1, 3600)
        ctx:win_text("Number of frames to display at once.")
        options.frames_viewer_step_size = common_gui.draw_drag_int_clamped(ctx, "Frame viewer step size", options.frames_viewer_step_size, 1, 60, true, false)
        ctx:win_text("Number of frames to step forward or backward with the navigation buttons.")
        ctx:win_indent(-common_gui.INDENT_SECTION)
    end)

    local session = active_tas_session
    if not session then
        ctx:win_text("No TAS loaded.")
        return
    end
    if #session.tas.levels == 0 then
        ctx:win_text("TAS contains no recorded data.")
        return
    end

    -- When this tool GUI is not windowed, the parent tool GUI is expected set the level index before drawing this as a panel.
    if is_window then
        local level_choices = {
            [0] = "Current level"
        }
        for i = 1, #session.tas.levels do
            level_choices[i] = common.level_to_string(session.tas, i, false)
        end
        local level_combo = ComboInput:new(OrderedTable:new(level_choices))
        selected_level_index = level_combo:draw(ctx, "Level", selected_level_index)
        if selected_level_index == 0 and not session.current_level_index then
            ctx:win_text("Current level is undefined.")
            return
        end
        self.level_index = selected_level_index == 0 and session.current_level_index or selected_level_index
    end

    local tasable_screen = common_enums.TASABLE_SCREEN[session.tas.levels[self.level_index].metadata.screen]
    if not tasable_screen.record_frames then
        ctx:win_text(tasable_screen.name.." screen does not record frames.")
        return
    end

    local frames = session.tas.levels[self.level_index].frames

    edit_mode = ctx:win_check("Enable editing", edit_mode)

    if edit_mode then
        ctx:win_pushid("bulk_editor")
        ctx:win_separator_text("Bulk frame editor")
        bulk_operation = BULK_OPERATION_COMBO:draw(ctx, "Operation", bulk_operation)
        if bulk_operation ~= "none" then
            ctx:win_text(BULK_OPERATION:value_by_id(bulk_operation).desc)
        end
        if bulk_operation == "insert" then
            bulk_start_index = common_gui.draw_drag_int_clamped(ctx, "Start frame", bulk_start_index, 0, #frames)
            bulk_count = common_gui.draw_drag_int_clamped(ctx, "Frame count to insert", bulk_count, 1, 60, true, false)
            bulk_use_start_inputs = ctx:win_check(bulk_start_index == 0 and "Use inputs of first frame" or "Use inputs of start frame", bulk_use_start_inputs)
            for player_index = 1, session.tas:get_player_count() do
                if bulk_use_start_inputs then
                    if bulk_start_index == 0 then
                        if #frames == 0 then
                            bulk_inputs[player_index] = INPUTS.NONE
                        else
                            bulk_inputs[player_index] = frames[1].players[player_index].inputs
                        end
                    else
                        bulk_inputs[player_index] = frames[bulk_start_index].players[player_index].inputs
                    end
                elseif not bulk_inputs[player_index] then
                    bulk_inputs[player_index] = INPUTS.NONE
                end
                local player_inputs = bulk_inputs[player_index]
                if session.tas:get_player_count() == 1 then
                    player_inputs = common_gui.draw_inputs_editor(ctx, player_inputs)
                    player_inputs = common.string_to_inputs(ctx:win_input_text("Inputs", common.inputs_to_string(player_inputs)))
                else
                    ctx:win_section("Player "..player_index.." inputs", function()
                        ctx:win_pushid(player_index)
                        ctx:win_indent(common_gui.INDENT_SECTION)
                        player_inputs = common_gui.draw_inputs_editor(ctx, player_inputs)
                        player_inputs = common.string_to_inputs(ctx:win_input_text("Inputs", common.inputs_to_string(player_inputs)))
                        ctx:win_indent(-common_gui.INDENT_SECTION)
                        ctx:win_popid()
                    end)
                end
                if not bulk_use_start_inputs then
                    bulk_inputs[player_index] = player_inputs
                end
            end
            if ctx:win_button("Insert") then
                session.tas:insert_frames(self.level_index, bulk_start_index, bulk_count, bulk_inputs)
                bulk_start_index = bulk_start_index + bulk_count
                session.desync = nil
                game_controller.validate_current_frame()
                game_controller.check_playback()
            end
        elseif bulk_operation == "delete" then
            if #frames == 0 then
                ctx:win_text("Level contains no frames to delete.")
            else
                bulk_start_index = common_gui.draw_drag_int_clamped(ctx, "Start frame", bulk_start_index, 1, #frames)
                local max_frame_count = #frames - bulk_start_index + 1
                bulk_count = common_gui.draw_drag_int_clamped(ctx, "Frame count to delete", bulk_count, 1, max_frame_count)
                ctx:win_text("Frames to delete (inclusive): "..bulk_start_index.." to "..(bulk_start_index + bulk_count - 1))
                if ctx:win_button("Delete") then
                    session.tas:delete_frames(self.level_index, bulk_start_index, bulk_count)
                    session.desync = nil
                    game_controller.validate_current_frame()
                    game_controller.check_playback()
                end
            end
        end
        ctx:win_popid()
    end

    ctx:win_pushid("viewer")
    ctx:win_separator_text("Frame viewer")
    if session.tas:get_player_count() == 1 then
        viewer_player_index = 1
    else
        viewer_player_index = common_gui.draw_player_combo_input(ctx, session.tas, "Player", viewer_player_index)
        if edit_mode and bulk_operation ~= "none" then
            ctx:win_text("Note: Bulk edit operations affect all players. The player selector only controls whose inputs are shown below.")
        end
    end
    local follow_current = ctx:win_check("Follow current frame", options.frames_viewer_follow_current)
    if options.frames_viewer_follow_current ~= follow_current then
        options.frames_viewer_follow_current = follow_current
        if not follow_current then
            last_current_level_index = nil
            last_current_frame_index = nil
        end
    end
    ctx:win_text("Frames in level: "..#frames)
    if #frames == 0 then
        return
    end
    if follow_current then
        if game_controller.mode == common_enums.MODE.FREEPLAY then
            last_current_level_index = nil
            last_current_frame_index = nil
        elseif session.current_level_index == module.level_index and session.current_frame_index
            and (session.current_level_index ~= last_current_level_index or session.current_frame_index ~= last_current_frame_index)
        then
            last_current_level_index = session.current_level_index
            last_current_frame_index = session.current_frame_index
            viewer_frame_index = math.min(session.current_frame_index - math.ceil(options.frames_viewer_page_size / 2) + 1, compute_last_page_frame_index())
        end
    end
    if viewer_frame_index > #frames then
        viewer_frame_index = compute_last_page_frame_index()
    end
    draw_page_controls(ctx, "page_controls_top")
    local end_frame_index = viewer_frame_index + options.frames_viewer_page_size - 1
    for frame_index = viewer_frame_index, end_frame_index do
        ctx:win_pushid(frame_index)
        local draw_separator = false
        if frames[frame_index] then
            local inputs = frames[frame_index].players[viewer_player_index].inputs
            local label = tostring(frame_index)
            if edit_mode then
                if bulk_operation == "insert" then
                    if frame_index == bulk_start_index then
                        label = label.." (inserting after)"
                    end
                elseif bulk_operation == "delete" then
                    if frame_index >= bulk_start_index and frame_index <= bulk_start_index + bulk_count - 1 then
                        label = label.." (deleting)"
                    end
                end
            end
            if session.current_level_index == self.level_index and session.current_frame_index then
                if frame_index == session.current_frame_index then
                    label = label.." (prev)"
                    if frame_index ~= end_frame_index then
                        draw_separator = true
                    end
                elseif frame_index == session.current_frame_index + 1 then
                    label = label.." (next)"
                end
            end
            if edit_mode then
                local inputs_string = common.inputs_to_string(inputs)
                local new_inputs_string = ctx:win_input_text(label.."###inputs", inputs_string)
                if inputs_string ~= new_inputs_string then
                    inputs = common.string_to_inputs(new_inputs_string)
                    frames[frame_index].players[viewer_player_index].inputs = inputs
                end
                ctx:win_inline()
                if ctx:win_button("Edit") then
                    tool_guis.single_frame_editor:open(self.level_index, frame_index, viewer_player_index, inputs)
                end
            else
                ctx:win_input_text(label.."###inputs", common.inputs_to_string(inputs))
            end
        else
            ctx:win_input_text("##inputs", "")
        end
        if draw_separator then
            ctx:win_separator()
        end
        ctx:win_popid()
    end
    draw_page_controls(ctx, "page_controls_bottom")
    ctx:win_popid()
end

return module
