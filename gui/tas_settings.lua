local common_enums = require("common_enums")
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
    tas.save_player_positions_default = ctx:win_check("Save player positions (default)", tas.save_player_positions_default)
    ctx:win_text("Save player positions in the TAS file by default for new screens.")
    if ctx:win_button("Clear player positions") then
        tas:clear_all_player_positions()
    end
    ctx:win_text("Clears all stored player position data.")
    ctx:win_popid()

    ctx:win_pushid("screen_snapshots")
    ctx:win_separator_text("Screen snapshots")
    common_gui.draw_screen_snapshot_more_info(ctx)
    ctx:win_text("Save screen snapshots in the TAS file by default for new screens:")
    ctx:win_indent(common_gui.INDENT_SUB_INPUT)
    local tasable_screen_camp = common_enums.TASABLE_SCREEN[SCREEN.CAMP]
    tas.save_screen_snapshot_defaults[tasable_screen_camp.data_id] =
        ctx:win_check(tasable_screen_camp.name, tas.save_screen_snapshot_defaults[tasable_screen_camp.data_id])
    local tasable_screen_level = common_enums.TASABLE_SCREEN[SCREEN.LEVEL]
    tas.save_screen_snapshot_defaults[tasable_screen_level.data_id] =
        ctx:win_check(tasable_screen_level.name, tas.save_screen_snapshot_defaults[tasable_screen_level.data_id])
    ctx:win_indent(-common_gui.INDENT_SUB_INPUT)
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
