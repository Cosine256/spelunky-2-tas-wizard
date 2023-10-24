local common = require("common")
local ComboInput = require("gui/combo_input")
local OrderedTable = require("ordered_table")
local Tool_GUI = require("gui/tool_gui")

local module = Tool_GUI:new("warp", "Warp")

local warp_screen = 1

function module:draw_panel(ctx, is_window)
    if not active_tas_session then
        ctx:win_text("No TAS loaded.")
    elseif not active_tas_session.tas:is_start_configured() then
        ctx:win_text("TAS start settings are not fully configured.")
    else
        local tas = active_tas_session.tas
        local warp_choices = {}
        if #tas.screens == 0 then
            warp_choices[1] = "1"
        else
            for i = 1, #tas.screens do
                warp_choices[i] = common.tas_screen_to_string(tas, i, false)
            end
        end
        local warp_combo = ComboInput:new(OrderedTable:new(warp_choices))
        warp_screen = warp_combo:draw(ctx, "Warp to screen", warp_screen)
        if ctx:win_button("Warp##warp_screen_button") then
            if active_tas_session:trigger_warp(warp_screen) then
                active_tas_session:set_mode_freeplay()
            end
        end
        ctx:win_text("Warp to the specified screen in freeplay mode using a snapshot stored by the TAS. If a warp is unavailable, then the TAS must be played back to that screen first to store a snapshot.")
    end
end

return module
