local common = require("common")
local common_gui = require("gui/common_gui")
local game_controller = require("game_controller")
local Tool_GUI = require("gui/tool_gui")

local module = Tool_GUI:new("tas_settings", "TAS Settings")

local function draw_tas_settings(ctx, tas)
    tas.name = ctx:win_input_text("Name", tas.name)
    -- TODO: Use a multi-line text input.
    tas.description = ctx:win_input_text("Description", tas.description)

    ctx:win_pushid("start_settings")
    ctx:win_separator_text("Start settings")
    if #tas.screens > 0 then
        ctx:win_text("Warning: This TAS has recorded data. Modifying the start settings can change level generation and RNG, which may cause it to desynchronize.")
    end
    common_gui.draw_tas_start_settings(ctx, tas, false)
    ctx:win_popid()

    ctx:win_pushid("player_positions")
    ctx:win_separator_text("Player positions")
    common_gui.draw_player_positions_more_info(ctx)
    tas.save_player_positions = ctx:win_check("Save player positions", tas.save_player_positions)
    ctx:win_text("Save player positions in the TAS file. This will greatly increase its file size.")
    if ctx:win_button("Clear player positions") then
        tas:clear_all_player_positions()
    end
    ctx:win_text("Clears all stored player position data.")
    ctx:win_popid()

    ctx:win_pushid("screen_snapshots")
    ctx:win_separator_text("Screen snapshots")
    common_gui.draw_screen_snapshot_more_info(ctx)
    tas.save_screen_snapshots = ctx:win_check("Save screen snapshots", tas.save_screen_snapshots)
    ctx:win_text("Save screen snapshots in the TAS file. This will greatly increase its file size.")
    if ctx:win_button("Clear screen snapshots") then
        tas:clear_all_screen_snapshots()
    end
    ctx:win_text("Clears all stored screen snapshot data.")
    ctx:win_popid()

    ctx:win_pushid("reset")
    ctx:win_separator_text("Reset")
    if ctx:win_button("Reset TAS") then
        game_controller.cancel_requested_pause()
        active_tas_session:set_mode_freeplay()
        active_tas_session:unset_current_screen()
        active_tas_session.desync = nil
        tas.screens = {}
        tas.frame_tags = common.deep_copy(options.new_tas.frame_tags)
        for _, tool_gui in pairs(tool_guis) do
            tool_gui:reset_session_vars()
        end
    end
    ctx:win_text("Resets the TAS to an empty state, clearing all recorded inputs, generated data, and frame tags. This does not reset the start settings.")
    ctx:win_popid()
end

function module:draw_panel(ctx, is_window)
    if active_tas_session then
        draw_tas_settings(ctx, active_tas_session.tas)
    else
        ctx:win_text("No TAS loaded.")
    end
end

return module
