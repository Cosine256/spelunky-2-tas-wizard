local common_gui = require("gui/common_gui")
local ToolGui = require("gui/tool_gui")

local module = ToolGui:new("tas_settings", "TAS Settings")

local function draw_tas_settings(ctx)
    local tas = active_tas_session.tas

    tas.name = ctx:win_input_text("Name", tas.name)
    -- TODO: Use a multi-line text input.
    tas.description = ctx:win_input_text("Description", tas.description)

    ctx:win_pushid("start_settings")
    ctx:win_separator_text("Start settings")
    if #tas.screens > 0 then
        ctx:win_text("Warning: This TAS has recorded data. Changing the player count or start type will immediately delete recorded data for removed players. Modifying the start settings can change level generation and RNG, which may cause the TAS to desynchronize.")
    end
    common_gui.draw_tas_start_settings(ctx, active_tas_session, tas, false)
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
    if ctx:win_button("Reset TAS data") then
        active_tas_session:reset_tas(true)
    end
    ctx:win_text("Resets the TAS to an empty state, clearing all recorded inputs and generated data. This does not reset TAS settings and frame tags.")
    ctx:win_popid()
end

function module:draw_panel(ctx, is_window)
    if active_tas_session then
        draw_tas_settings(ctx)
    else
        ctx:win_text("No TAS loaded.")
    end
end

return module
