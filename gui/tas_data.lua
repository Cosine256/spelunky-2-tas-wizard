local common = require("common")
local common_enums = require("common_enums")
local common_gui = require("gui/common_gui")
local game_controller = require("game_controller")
local ComboInput = require("gui/combo_input")
local OrderedTable = require("ordered_table")
local Tool_GUI = require("gui/tool_gui")

local module = Tool_GUI:new("tas_data", "TAS Data", "tas_data_window")

local SKIP_INPUT_COMBO = ComboInput:new(common_enums.SKIP_INPUT)

local selected_level_index = 0
local level_index

local function draw_cutscene_skip_settings(ctx, level, name, last_frame_index)
    local cutscene_skip = ctx:win_check("Skip "..name.." cutscene", level.cutscene_skip_frame_index ~= -1)
    if cutscene_skip then
        if level.cutscene_skip_frame_index == -1 then
            level.cutscene_skip_frame_index = game_controller.CUTSCENE_SKIP_FIRST_FRAME
        end
        level.cutscene_skip_frame_index = common_gui.draw_drag_int_clamped(ctx, "Cutscene skip frame",
            level.cutscene_skip_frame_index, game_controller.CUTSCENE_SKIP_FIRST_FRAME, last_frame_index)
        level.cutscene_skip_input = SKIP_INPUT_COMBO:draw(ctx, "Cutscene skip input", level.cutscene_skip_input)
    else
        level.cutscene_skip_frame_index = -1
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
                        ctx:win_separator_text("Cutscene settings")
                        if level.metadata.theme == THEME.OLMEC then
                            draw_cutscene_skip_settings(ctx, level, "Olmec", game_controller.OLMEC_CUTSCENE_LAST_FRAME)
                        elseif level.metadata.theme == THEME.TIAMAT then
                            draw_cutscene_skip_settings(ctx, level, "Tiamat", game_controller.TIAMAT_CUTSCENE_LAST_FRAME)
                        end
                    end
                elseif level.metadata.screen == SCREEN.TRANSITION then
                    ctx:win_separator_text("Transition settings")
                    local transition_exit = ctx:win_check("Automatically exit transition", level.transition_exit_frame_index ~= -1)
                    if transition_exit then
                        if level.transition_exit_frame_index == -1 then
                            level.transition_exit_frame_index = game_controller.TRANSITION_EXIT_FIRST_FRAME
                        end
                        level.transition_exit_frame_index = common_gui.draw_drag_int_clamped(ctx, "Transition exit frame",
                            level.transition_exit_frame_index, game_controller.TRANSITION_EXIT_FIRST_FRAME, 300, true, false)
                    else
                        level.transition_exit_frame_index = -1
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
