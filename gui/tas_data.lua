local common = require("common")
local common_enums = require("common_enums")
local common_gui = require("gui/common_gui")
local ComboInput = require("gui/combo_input")
local OrderedTable = require("ordered_table")
local Tool_GUI = require("gui/tool_gui")

local module = Tool_GUI:new("tas_data", "TAS Data")

local CUTSCENE_SKIP_INPUT = OrderedTable:new({
    { id = "jump", name = "Jump", inputs = INPUTS.JUMP },
    { id = "bomb", name = "Bomb", inputs = INPUTS.BOMB },
    { id = "both", name = "Jump & Bomb", inputs = INPUTS.JUMP | INPUTS.BOMB }
})
local CUTSCENE_SKIP_INPUT_COMBO = ComboInput:new(CUTSCENE_SKIP_INPUT)

local selected_screen_index = 0
local screen_index
local leader_player_index = 1
local new_cutscene_skip_active = true
local new_cutscene_skip_frame_index = common.CUTSCENE_SKIP_FIRST_FRAME
local new_cutscene_skip_input_id = "jump"

local function draw_cutscene_skip_editor(ctx, screen)
    ctx:win_section("More info", function()
        ctx:win_indent(common_gui.INDENT_SECTION)
        ctx:win_text("This editor allows easy modification of a screen's Olmec and Tiamat cutscene skip behavior. It's a workaround for the inability to properly pause and frame advance during cutscenes. Recording a cutscene skip with precise timing is difficult without pauses, and directly modifying the inputs can be tedious and complicated.")
        ctx:win_text("The editor operates directly on the screen's frame data. The changes it makes can also be done manually in the Frames panel.")
        ctx:win_text("A cutscene's \"skip frame\" is the first frame where a jump or bomb input is released.")
        if active_tas_session.tas:get_player_count() > 1 then
            ctx:win_text("Only the leader player is able to skip a cutscene. The editor doesn't know who the leader is, so this information must be provided via the \"Leader player\" input. Be careful, as applying a cutscene skip with the wrong leader player can make undesirable changes to the frame data.")
        end
        ctx:win_indent(-common_gui.INDENT_SECTION)
    end)

    if active_tas_session.tas:get_player_count() == 1 then
        leader_player_index = 1
    else
        -- It can be complicated to determine who the leader is based on TAS data, and it may be impossible if this is not the current screen. Keep it simple by always asking the user for this information.
        leader_player_index = common_gui.draw_player_combo_input(ctx, active_tas_session.tas, "Leader player", leader_player_index)
    end

    -- Determine the current cutscene skip input and its release frame. The game skips the cutscene and processes inputs normally during the first update where a previously held skip input is released.
    local cutscene_skip_frame_index
    local cutscene_skip_input_id
    local cutscene_last_frame_index = screen.metadata.theme == THEME.OLMEC
        and common.OLMEC_CUTSCENE_LAST_FRAME or common.TIAMAT_CUTSCENE_LAST_FRAME
    for frame_index = common.CUTSCENE_SKIP_FIRST_FRAME, math.min(#screen.frames, cutscene_last_frame_index) do
        local prev_inputs = screen.frames[frame_index - 1].inputs[leader_player_index]
        local this_inputs = screen.frames[frame_index].inputs[leader_player_index]
        local skip_jump = prev_inputs & INPUTS.JUMP > 0 and this_inputs & INPUTS.JUMP == 0
        local skip_bomb = prev_inputs & INPUTS.BOMB > 0 and this_inputs & INPUTS.BOMB == 0
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
    local new_cutscene_skip_inputs
    new_cutscene_skip_active = ctx:win_check("Skip cutscene", new_cutscene_skip_active)
    if new_cutscene_skip_active then
        new_cutscene_skip_frame_index = common_gui.draw_drag_int_clamped(ctx, "New skip frame",
            new_cutscene_skip_frame_index, common.CUTSCENE_SKIP_FIRST_FRAME, cutscene_last_frame_index)
        new_cutscene_skip_input_id = CUTSCENE_SKIP_INPUT_COMBO:draw(ctx, "New skip input", new_cutscene_skip_input_id)
        new_cutscene_skip_inputs = CUTSCENE_SKIP_INPUT:value_by_id(new_cutscene_skip_input_id).inputs
    end

    local post_cutscene_frame_index = cutscene_skip_frame_index or cutscene_last_frame_index + 1
    if new_cutscene_skip_active and screen.frames[post_cutscene_frame_index]
        and screen.frames[post_cutscene_frame_index].inputs[leader_player_index] & new_cutscene_skip_inputs == new_cutscene_skip_inputs
    then
        ctx:win_text("Invalid: New cutscene skip input will merge with existing player inputs on the skip frame. The skip input needs to be released for at least one frame for the skip to occur.")
    elseif ctx:win_button("Apply") then
        local new_frames = {}
        -- Generate new cutscene frames to skip the cutscene at the chosen frame, or to let the cutscene finish.
        for frame_index = 1, new_cutscene_skip_active and new_cutscene_skip_frame_index - 1 or cutscene_last_frame_index do
            local frame_inputs = {}
            for player_index = 1, active_tas_session.tas:get_player_count() do
                if new_cutscene_skip_active and frame_index == new_cutscene_skip_frame_index - 1 and player_index == leader_player_index then
                    frame_inputs[player_index] = new_cutscene_skip_inputs
                else
                    frame_inputs[player_index] = INPUTS.NONE
                end
            end
            new_frames[frame_index] = {
                inputs = frame_inputs
            }
        end
        -- Append the existing post-cutscene frames.
        for frame_index = post_cutscene_frame_index, #screen.frames do
            new_frames[#new_frames + 1] = screen.frames[frame_index]
        end
        -- Use the new frames. Any previous cutscene frames are discarded.
        screen.frames = new_frames
        active_tas_session.desync = nil
        active_tas_session:validate_current_frame()
        active_tas_session:check_playback()
    end
end

function module:draw_panel(ctx, is_window)
    if not active_tas_session then
        ctx:win_text("No TAS loaded.")
    elseif #active_tas_session.tas.screens == 0 then
        ctx:win_text("TAS contains no recorded or generated data.")
    else
        local tas = active_tas_session.tas
        local screen_choices = {
            [0] = "Current screen"
        }
        for i = 1, #tas.screens do
            screen_choices[i] = common.tas_screen_to_string(tas, i, false)
        end
        local screen_combo = ComboInput:new(OrderedTable:new(screen_choices))
        selected_screen_index = screen_combo:draw(ctx, "Screen", selected_screen_index)
        if selected_screen_index == 0 and not active_tas_session.current_screen_index then
            ctx:win_text("Current screen is undefined.")
        else
            screen_index = selected_screen_index == 0 and active_tas_session.current_screen_index or selected_screen_index
            ctx:win_pushid("frames")
            ctx:win_section("Frames", function()
                ctx:win_indent(common_gui.INDENT_SECTION)
                if tool_guis.frames:is_window_open() then
                    ctx:win_text("Panel detached into separate window.")
                else
                    tool_guis.frames.screen_index = screen_index
                    tool_guis.frames:draw_panel(ctx, false)
                end
                ctx:win_indent(-common_gui.INDENT_SECTION)
            end)
            ctx:win_popid()
            ctx:win_pushid("screen_data")
            ctx:win_section("Screen Data", function()
                ctx:win_indent(common_gui.INDENT_SECTION)
                local screen = tas.screens[screen_index]
                local tasable_screen = common_enums.TASABLE_SCREEN[screen.metadata.screen]
                ctx:win_separator_text("Metadata")
                ctx:win_text("Screen: "..tasable_screen.name)
                if screen.metadata.world then
                    ctx:win_text("World: "..screen.metadata.world)
                end
                if screen.metadata.level then
                    ctx:win_text("Level: "..screen.metadata.level)
                end
                if screen.metadata.theme then
                    ctx:win_text("Theme: "..common.THEME_NAME[screen.metadata.theme])
                end
                if screen.metadata.cutscene ~= nil then
                    ctx:win_text("Cutscene: "..(screen.metadata.cutscene and "Yes" or "No"))
                end
                if screen.metadata.screen == SCREEN.LEVEL then
                    if screen.metadata.cutscene then
                        ctx:win_pushid("cutscene")
                        ctx:win_separator_text("Cutscene")
                        ctx:win_section("Cutscene Skip Editor", function()
                            ctx:win_indent(common_gui.INDENT_SECTION)
                            draw_cutscene_skip_editor(ctx, screen)
                            ctx:win_indent(-common_gui.INDENT_SECTION)
                        end)
                        ctx:win_popid()
                    end
                elseif screen.metadata.screen == SCREEN.TRANSITION then
                    ctx:win_pushid("transition_settings")
                    ctx:win_separator_text("Transition settings")
                    screen.transition_exit_frame = common_gui.draw_drag_int_clamped(ctx, "Transition exit frame",
                        screen.transition_exit_frame, common.TRANSITION_EXIT_FIRST_FRAME, 300, true, false)
                    ctx:win_popid()
                end
                if tasable_screen.record_frames then
                    ctx:win_pushid("player_positions")
                    ctx:win_separator_text("Player positions")
                    common_gui.draw_player_positions_more_info(ctx)
                    if ctx:win_button("Clear player positions") then
                        tas:clear_player_positions(screen_index)
                    end
                    ctx:win_popid()
                end
                if tasable_screen.can_snapshot and screen_index > 1 then
                    ctx:win_pushid("screen_snapshot")
                    ctx:win_separator_text("Screen snapshot")
                    common_gui.draw_screen_snapshot_more_info(ctx)
                    if screen.snapshot then
                        ctx:win_text("Screen snapshot captured.")
                        if ctx:win_button("Clear screen snapshot") then
                            tas:clear_screen_snapshot(screen_index)
                        end
                    else
                        ctx:win_text("No screen snapshot captured.")
                    end
                    ctx:win_popid()
                end
                ctx:win_pushid("screen_deletion")
                ctx:win_separator_text("Screen deletion")
                if ctx:win_button("Delete screen") then
                    tas:remove_screens_after(screen_index - 1)
                    active_tas_session:validate_current_frame()
                    active_tas_session:check_playback()
                    selected_screen_index = selected_screen_index - 1
                end
                ctx:win_text("Deletes this entire screen and all later screen data in the TAS.")
                ctx:win_popid()
                ctx:win_indent(-common_gui.INDENT_SECTION)
            end)
            ctx:win_popid()
        end
    end
end

return module
