local common = require("common")
local common_enums = require("common_enums")
local game_controller = require("game_controller")
local ComboInput = require("gui/combo_input")
local OrderedTable = require("ordered_table")
local Tool_GUI = require("gui/tool_gui")

local module = Tool_GUI:new("warp", "Warp", "warp_window")

local warp_level = 1

function module:draw_panel(ctx, is_window)
    if not game_controller.current then
        ctx:win_text("No TAS loaded.")
    elseif not game_controller.current.tas:is_start_configured() then
        ctx:win_text("TAS start settings are not fully configured.")
    else
        local tas = game_controller.current.tas
        local warp_choices = {}
        if #tas.levels == 0 then
            warp_choices[1] = "1"
        else
            for i = 1, #tas.levels do
                warp_choices[i] = common.level_metadata_to_string(tas, i)
            end
        end
        local warp_combo = ComboInput:new(OrderedTable:new(warp_choices))
        warp_level = warp_combo:draw(ctx, "Warp to level", warp_level)
        if ctx:win_button("Warp##warp_level_button") then
            if warp_level == 1 then
                if game_controller.apply_start_state() then
                    game_controller.set_mode(common_enums.MODE.FREEPLAY)
                end
            elseif tas.levels[warp_level].snapshot then
                if game_controller.apply_level_snapshot(warp_level) then
                    game_controller.set_mode(common_enums.MODE.FREEPLAY)
                end
            else
                print("Cannot warp to level: No level snapshot stored.")
            end
        end
        ctx:win_text("Warp to the specified level in freeplay mode using a snapshot stored by the TAS. If a warp is unavailable, then the TAS must be played back to that level first to store a snapshot.")
    end
end

return module
