local common_enums = require("common_enums")
local common_gui = require("gui/common_gui")
local game_controller = require("game_controller")
local ComboInput = require("gui/combo_input")
local Tool_GUI = require("gui/tool_gui")

local module = Tool_GUI:new("tas_settings", "TAS Settings", "tas_settings_window")

local SKIP_INPUT_COMBO = ComboInput:new(common_enums.SKIP_INPUT)

local function draw_tas_settings(ctx, tas)
    tas.name = ctx:win_input_text("Name", tas.name)
    -- TODO: Use a multi-line text input.
    tas.description = ctx:win_input_text("Description", tas.description)

    ctx:win_separator_text("Start settings")
    if #tas.levels > 0 then
        ctx:win_text("Warning: This TAS has recorded inputs. Modifying the start settings can change level generation and RNG, which may cause it to desynchronize.")
    end
    common_gui.draw_tas_start_settings(ctx, tas, false)

    ctx:win_separator_text("Cutscenes and transitions")
    local olmec_cutscene_skip = ctx:win_check("Skip Olmec cutscene", tas.olmec_cutscene_skip_frame ~= -1)
    if olmec_cutscene_skip then
        if tas.olmec_cutscene_skip_frame == -1 then
            tas.olmec_cutscene_skip_frame = game_controller.CUTSCENE_SKIP_FIRST_FRAME
        end
        tas.olmec_cutscene_skip_frame = ctx:win_drag_int("Olmec cutscene skip frame", tas.olmec_cutscene_skip_frame,
        game_controller.CUTSCENE_SKIP_FIRST_FRAME, game_controller.OLMEC_CUTSCENE_LAST_FRAME)
        if tas.olmec_cutscene_skip_frame < game_controller.CUTSCENE_SKIP_FIRST_FRAME then
            tas.olmec_cutscene_skip_frame = game_controller.CUTSCENE_SKIP_FIRST_FRAME
        elseif tas.olmec_cutscene_skip_frame > game_controller.OLMEC_CUTSCENE_LAST_FRAME then
            tas.olmec_cutscene_skip_frame = game_controller.OLMEC_CUTSCENE_LAST_FRAME
        end
        tas.olmec_cutscene_skip_input = SKIP_INPUT_COMBO:draw(ctx, "Olmec cutscene skip input", tas.olmec_cutscene_skip_input)
    else
        tas.olmec_cutscene_skip_frame = -1
    end
    local tiamat_cutscene_skip = ctx:win_check("Skip Tiamat cutscene", tas.tiamat_cutscene_skip_frame ~= -1)
    if tiamat_cutscene_skip then
        if tas.tiamat_cutscene_skip_frame == -1 then
            tas.tiamat_cutscene_skip_frame = game_controller.CUTSCENE_SKIP_FIRST_FRAME
        end
        tas.tiamat_cutscene_skip_frame = ctx:win_drag_int("Tiamat cutscene skip frame", tas.tiamat_cutscene_skip_frame,
        game_controller.CUTSCENE_SKIP_FIRST_FRAME, game_controller.TIAMAT_CUTSCENE_LAST_FRAME)
        if tas.tiamat_cutscene_skip_frame < game_controller.CUTSCENE_SKIP_FIRST_FRAME then
            tas.tiamat_cutscene_skip_frame = game_controller.CUTSCENE_SKIP_FIRST_FRAME
        elseif tas.tiamat_cutscene_skip_frame > game_controller.TIAMAT_CUTSCENE_LAST_FRAME then
            tas.tiamat_cutscene_skip_frame = game_controller.TIAMAT_CUTSCENE_LAST_FRAME
        end
        tas.tiamat_cutscene_skip_input = SKIP_INPUT_COMBO:draw(ctx, "Tiamat cutscene skip input", tas.tiamat_cutscene_skip_input)
    else
        tas.tiamat_cutscene_skip_frame = -1
    end
    local transition_continue = ctx:win_check("Automatically exit transitions", tas.transition_exit_frame ~= -1)
    if transition_continue then
        if tas.transition_exit_frame == -1 then
            tas.transition_exit_frame = game_controller.TRANSITION_EXIT_FIRST_FRAME
        end
        -- Maximum value is a soft limit. User can manually set it to be higher.
        tas.transition_exit_frame = ctx:win_drag_int("Transition exit frame", tas.transition_exit_frame,
            game_controller.TRANSITION_EXIT_FIRST_FRAME, 300)
        if tas.transition_exit_frame < game_controller.TRANSITION_EXIT_FIRST_FRAME then
            tas.transition_exit_frame = game_controller.TRANSITION_EXIT_FIRST_FRAME
        end
    else
        tas.transition_exit_frame = -1
    end

    ctx:win_separator_text("Generated data")
    tas.save_player_positions = ctx:win_check("Save player positions", tas.save_player_positions)
    ctx:win_text("Player positions are used to show the player paths through each level and to detect desyncs. If this setting is enabled, then player positions are saved as part of the TAS file, but this will greatly increase its file size. If disabled, then the TAS will always need to be played back once when loaded to store these positions in memory.")
    if ctx:win_button("Clear player positions") then
        tas:clear_all_player_positions()
    end
    ctx:win_text("Clears stored player position data. Use this if you believe the stored data is out of sync with the inputs. This data can be regenerated by playing back the TAS.")
    tas.save_level_snapshots = ctx:win_check("Save level snapshots", tas.save_level_snapshots)
    ctx:win_text("Level snapshots allow the TAS to be played back from the start of the nearest level instead of the start of the run. If this setting is enabled, then level snapshots are saved as part of the TAS file, but this will greatly increase its file size. If disabled, then the TAS will always need to be played back once when loaded to store these snapshots in memory.")
    if ctx:win_button("Clear level snapshots") then
        tas:clear_all_level_snapshots()
    end
    ctx:win_text("Clears stored level snapshot data. Use this if you believe the stored data is out of sync with the inputs. This data can be regenerated by playing back the TAS.")

    ctx:win_separator_text("Reset")
    if ctx:win_button("Reset TAS") then
        active_tas_session.desync = nil
        game_controller.reset_session_vars()
        tool_guis.frames.reset_vars()
        tool_guis.single_frame_editor:close()
        tas.levels = {}
        tas.tagged_frames = {}
    end
    ctx:win_text("Resets the TAS to an empty state, clearing all recorded inputs and generated data. This does not reset the start settings.")
end

function module:draw_panel(ctx, is_window)
    if active_tas_session then
        draw_tas_settings(ctx, active_tas_session.tas)
    else
        ctx:win_text("No TAS loaded.")
    end
end

return module
