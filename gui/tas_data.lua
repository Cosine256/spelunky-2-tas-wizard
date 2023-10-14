local common = require("common")
local common_enums = require("common_enums")
local common_gui = require("gui/common_gui")
local game_controller = require("game_controller")
local ComboInput = require("gui/combo_input")
local OrderedTable = require("ordered_table")
local Tool_GUI = require("gui/tool_gui")

local module = Tool_GUI:new("tas_data", "TAS Data", "tas_data_window")

local CUTSCENE_SKIP_INPUT = OrderedTable:new({
    { id = "jump", name = "Jump", input = INPUTS.JUMP },
    { id = "bomb", name = "Bomb", input = INPUTS.BOMB },
    { id = "both", name = "Jump & Bomb", input = INPUTS.JUMP | INPUTS.BOMB }
})
local CUTSCENE_SKIP_INPUT_COMBO = ComboInput:new(CUTSCENE_SKIP_INPUT)

local selected_level_index = 0
local level_index
local leader_player_index = 1
local new_cutscene_skip_active = true
local new_cutscene_skip_frame_index = common.CUTSCENE_SKIP_FIRST_FRAME
local new_cutscene_skip_input_id = "jump"

local function draw_cutscene_skip_editor(ctx, level)
    ctx:win_section("More info", function()
        ctx:win_indent(common_gui.INDENT_SECTION)
        ctx:win_text("This editor allows easy modification of a level's Olmec and Tiamat cutscene skip behavior. It's a workaround for the inability to properly pause and frame advance during cutscenes. Recording a cutscene skip with precise timing is difficult without pauses, and directly modifying the inputs can be tedious and complicated.")
        ctx:win_text("The editor operates directly on the level's frame data. The changes it makes can also be done manually in the Frames panel.")
        ctx:win_text("A cutscene's \"skip frame\" is the first frame where a jump or bomb input is released.")
        if active_tas_session.tas:get_player_count() > 1 then
            ctx:win_text("Only the leader player is able to skip a cutscene. The editor doesn't know who the leader is, so this information must be provided via the \"Leader player\" input. Be careful, as applying a cutscene skip with the wrong leader player can make undesirable changes to the frame data.")
        end
        ctx:win_indent(-common_gui.INDENT_SECTION)
    end)

    if active_tas_session.tas:get_player_count() == 1 then
        leader_player_index = 1
    else
        -- It can be complicated to determine who the leader is based on TAS data, and it may be impossible if this is not the current level. Keep it simple by always asking the user for this information.
        leader_player_index = common_gui.draw_player_combo_input(ctx, active_tas_session.tas, "Leader player", leader_player_index)
    end

    -- Determine the current cutscene skip input and its release frame. The game skips the cutscene and processes inputs normally during the first update where a previously held skip input is released.
    local cutscene_skip_frame_index
    local cutscene_skip_input_id
    local cutscene_last_frame_index = level.metadata.theme == THEME.OLMEC
        and common.OLMEC_CUTSCENE_LAST_FRAME or common.TIAMAT_CUTSCENE_LAST_FRAME
    for frame_index = common.CUTSCENE_SKIP_FIRST_FRAME, math.min(#level.frames, cutscene_last_frame_index) do
        local prev_input = level.frames[frame_index - 1].players[leader_player_index].input
        local this_input = level.frames[frame_index].players[leader_player_index].input
        local skip_jump = prev_input & INPUTS.JUMP > 0 and this_input & INPUTS.JUMP == 0
        local skip_bomb = prev_input & INPUTS.BOMB > 0 and this_input & INPUTS.BOMB == 0
        if skip_jump or skip_bomb then
            cutscene_skip_frame_index = frame_index
            cutscene_skip_input_id = skip_jump and (skip_bomb and "both" or "jump") or "bomb"
            break
        end
    end

    ctx:win_separator_text("Current skip behavior")
    if cutscene_skip_frame_index then
        ctx:win_text("Skip frame: "..cutscene_skip_frame_index)
        ctx:win_text("Skip input: "..CUTSCENE_SKIP_INPUT:value_by_id(cutscene_skip_input_id).name)
    else
        ctx:win_text("Not skipping cutscene.")
    end

    ctx:win_separator_text("New skip behavior")
    local new_cutscene_skip_input
    new_cutscene_skip_active = ctx:win_check("Skip cutscene", new_cutscene_skip_active)
    if new_cutscene_skip_active then
        new_cutscene_skip_frame_index = common_gui.draw_drag_int_clamped(ctx, "New skip frame",
            new_cutscene_skip_frame_index, common.CUTSCENE_SKIP_FIRST_FRAME, cutscene_last_frame_index)
        new_cutscene_skip_input_id = CUTSCENE_SKIP_INPUT_COMBO:draw(ctx, "New skip input", new_cutscene_skip_input_id)
        new_cutscene_skip_input = CUTSCENE_SKIP_INPUT:value_by_id(new_cutscene_skip_input_id).input
    end

    local post_cutscene_frame_index = cutscene_skip_frame_index or cutscene_last_frame_index + 1
    if new_cutscene_skip_active and level.frames[post_cutscene_frame_index]
        and level.frames[post_cutscene_frame_index].players[leader_player_index].input & new_cutscene_skip_input == new_cutscene_skip_input
    then
        ctx:win_text("Invalid: New cutscene skip input will merge with existing player input on the skip frame. The skip input needs to be released for at least one frame for the skip to occur.")
    elseif ctx:win_button("Apply") then
        local new_frames = {}
        -- Generate new cutscene inputs to skip the cutscene at the chosen frame, or to let the cutscene finish.
        for frame_index = 1, new_cutscene_skip_active and new_cutscene_skip_frame_index - 1 or cutscene_last_frame_index do
            local frame = active_tas_session.tas:create_frame_data()
            new_frames[frame_index] = frame
            for player_index, player in ipairs(frame.players) do
                if new_cutscene_skip_active and frame_index == new_cutscene_skip_frame_index - 1 and player_index == leader_player_index then
                    player.input = new_cutscene_skip_input
                else
                    player.input = INPUTS.NONE
                end
            end
        end
        -- Append the existing post-cutscene inputs.
        for frame_index = post_cutscene_frame_index, #level.frames do
            new_frames[#new_frames + 1] = level.frames[frame_index]
        end
        -- Use the new input sequence. Any previous cutscene inputs are discarded.
        level.frames = new_frames
        active_tas_session.desync = nil
        game_controller.validate_current_frame()
        game_controller.check_playback()
    end
end

function module:draw_panel(ctx, is_window)
    if not active_tas_session then
        ctx:win_text("No TAS loaded.")
    elseif #active_tas_session.tas.levels == 0 then
        ctx:win_text("TAS contains no recorded or generated data.")
    else
        local tas = active_tas_session.tas
        local level_choices = {
            [0] = "Current level"
        }
        for i = 1, #tas.levels do
            level_choices[i] = common.level_to_string(tas, i, false)
        end
        local level_combo = ComboInput:new(OrderedTable:new(level_choices))
        selected_level_index = level_combo:draw(ctx, "Level", selected_level_index)
        if selected_level_index == 0 and not active_tas_session.current_level_index then
            ctx:win_text("Current level is undefined.")
        else
            level_index = selected_level_index == 0 and active_tas_session.current_level_index or selected_level_index
            ctx:win_pushid("frames")
            ctx:win_section("Frames", function()
                ctx:win_indent(common_gui.INDENT_SECTION)
                if tool_guis.frames:is_window_open() then
                    ctx:win_text("Panel detached into separate window.")
                else
                    tool_guis.frames.level_index = level_index
                    tool_guis.frames:draw_panel(ctx, false)
                end
                ctx:win_indent(-common_gui.INDENT_SECTION)
            end)
            ctx:win_popid()
            ctx:win_pushid("level_data")
            ctx:win_section("Level Data", function()
                ctx:win_indent(common_gui.INDENT_SECTION)
                local level = tas.levels[level_index]
                local tasable_screen = common_enums.TASABLE_SCREEN[level.metadata.screen]
                ctx:win_separator_text("Metadata")
                ctx:win_text("Screen: "..tasable_screen.name)
                if level.metadata.world then
                    ctx:win_text("World: "..level.metadata.world)
                end
                if level.metadata.level then
                    ctx:win_text("Level: "..level.metadata.level)
                end
                if level.metadata.theme then
                    ctx:win_text("Theme: "..common.THEME_NAME[level.metadata.theme])
                end
                if level.metadata.cutscene ~= nil then
                    ctx:win_text("Cutscene: "..(level.metadata.cutscene and "Yes" or "No"))
                end
                if level.metadata.screen == SCREEN.LEVEL then
                    if level.metadata.cutscene then
                        ctx:win_separator_text("Cutscene")
                        ctx:win_section("Cutscene Skip Editor", function()
                            ctx:win_indent(common_gui.INDENT_SECTION)
                            draw_cutscene_skip_editor(ctx, level)
                            ctx:win_indent(-common_gui.INDENT_SECTION)
                        end)
                    end
                elseif level.metadata.screen == SCREEN.TRANSITION then
                    ctx:win_separator_text("Transition settings")
                    local transition_exit = ctx:win_check("Automatically exit transition", level.transition_exit_frame_index ~= nil)
                    if transition_exit then
                        if not level.transition_exit_frame_index then
                            level.transition_exit_frame_index = common.TRANSITION_EXIT_FIRST_FRAME
                        end
                        level.transition_exit_frame_index = common_gui.draw_drag_int_clamped(ctx, "Transition exit frame",
                            level.transition_exit_frame_index, common.TRANSITION_EXIT_FIRST_FRAME, 300, true, false)
                    else
                        level.transition_exit_frame_index = nil
                    end
                end
                if tasable_screen.record_frames then
                    ctx:win_separator_text("Player positions")
                    if ctx:win_button("Clear player positions") then
                        tas:clear_player_positions(level_index)
                    end
                end
                if tasable_screen.can_snapshot and level_index > 1 then
                    ctx:win_separator_text("Level snapshot")
                    if level.snapshot then
                        ctx:win_text("Level snapshot captured.")
                        if ctx:win_button("Clear level snapshot") then
                            tas:clear_level_snapshot(level_index)
                        end
                    else
                        ctx:win_text("No level snapshot captured.")
                    end
                end
                ctx:win_indent(-common_gui.INDENT_SECTION)
            end)
            ctx:win_popid()
        end
    end
end

return module
