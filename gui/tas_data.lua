local common = require("common")
local common_enums = require("common_enums")
local common_gui = require("gui/common_gui")
local ComboInput = require("gui/combo_input")
local OrderedTable = require("ordered_table")
local ToolGui = require("gui/tool_gui")

local module = ToolGui:new("tas_data", "TAS Data")

local selected_screen_index = 0
local screen_index

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
                if screen.metadata.skippable_intro_cutscene ~= nil then
                    ctx:win_text("Skippable intro cutscene: "..(screen.metadata.skippable_intro_cutscene and "Yes" or "No"))
                end
                if screen.metadata.screen == SCREEN.TRANSITION then
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
                    screen.save_player_positions = ctx:win_check("Save player positions", screen.save_player_positions)
                    ctx:win_text("Save this screen's player positions in the TAS file.")
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
                        ctx:win_text("Status: Screen snapshot captured.")
                    else
                        ctx:win_text("Status: No screen snapshot captured.")
                    end
                    screen.save_screen_snapshot = ctx:win_check("Save screen snapshot", screen.save_screen_snapshot)
                    ctx:win_text("Save this screen's snapshot in the TAS file.")
                    if screen.snapshot and ctx:win_button("Clear screen snapshot") then
                        tas:clear_screen_snapshot(screen_index)
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
