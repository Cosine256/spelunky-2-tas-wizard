local common = require("common")
local common_enums = require("common_enums")
local common_gui = require("gui/common_gui")
local ComboInput = require("gui/combo_input")
local OrderedTable = require("ordered_table")
local Tool_GUI = require("gui/tool_gui")

local module = Tool_GUI:new("tas_data", "TAS Data", "tas_data_window")

local selected_level_index = 0
local level_index

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
            ctx:win_pushid("generated_data")
            ctx:win_section("Generated", function()
                ctx:win_indent(common_gui.INDENT_SECTION)
                local level = tas.levels[level_index]
                local tasable_screen = common_enums.TASABLE_SCREEN[level.metadata.screen]
                ctx:win_separator_text("Metadata")
                ctx:win_text("Screen: "..tasable_screen.name)
                if level.metadata.world then
                    ctx:win_text("World: "..level.metadata.world)
                end
                if level.metadata.level then
                    ctx:win_text("Level: "..level.metadata.world)
                end
                if level.metadata.theme then
                    ctx:win_text("Theme: "..common.THEME_NAME[level.metadata.theme])
                end
                ctx:win_separator_text("Player positions")
                if tasable_screen.record_frames then
                    if ctx:win_button("Clear player positions") then
                        tas:clear_player_positions(level_index)
                    end
                else
                    ctx:win_text(tasable_screen.name.." screen does not store player positions.")
                end
                ctx:win_separator_text("Level snapshot")
                if tasable_screen.can_snapshot then
                    if level.snapshot then
                        ctx:win_text("Level snapshot captured.")
                        if ctx:win_button("Clear level snapshot") then
                            tas:clear_level_snapshot(level_index)
                        end
                    else
                        if level_index == 1 then
                            ctx:win_text("Level snapshot is not applicable for the first level.")
                        else
                            ctx:win_text("No level snapshot captured.")
                        end
                    end
                else
                    ctx:win_text(tasable_screen.name.." screen does not support snapshots.")
                end
                ctx:win_indent(-common_gui.INDENT_SECTION)
            end)
            ctx:win_popid()
        end
    end
end

return module
