local common = require("common")
local common_enums = require("common_enums")
local game_controller = require("game_controller")
local Tool_GUI = require("gui/tool_gui")

local module = Tool_GUI:new("Status", "status_window")

function module:draw_panel(ctx, is_window)
    if game_controller.current then
        local tas_session = game_controller.current

        local mode_string
        if game_controller.mode == common_enums.MODE.FREEPLAY then
            mode_string = "Freeplay"
        elseif game_controller.mode == common_enums.MODE.RECORD then
            mode_string = "Record"
        elseif game_controller.mode == common_enums.MODE.PLAYBACK then
            mode_string = "Playback"
        end

        if game_controller.desync_level ~= -1 then
            ctx:win_text("WARNING: Desynchronized on frame: "..game_controller.desync_level.."-"..game_controller.desync_frame)
        end

        ctx:win_text("Mode")
        ctx:win_inline()
        ctx:win_input_text("##mode", mode_string)
        if game_controller.mode == common_enums.MODE.PLAYBACK then
            ctx:win_text("Playing back to frame: "..game_controller.playback_target_level.."-"..game_controller.playback_target_frame)
        end

        ctx:win_text("Level")
        ctx:win_inline()
        local level_text = "Undefined"
        if tas_session.current_level_index ~= -1 then
            level_text = common.level_metadata_to_string(tas_session.tas, tas_session.current_level_index, true)
        end
        ctx:win_input_text("##level_text", level_text)

        ctx:win_text("Frame")
        ctx:win_inline()
        local frame_text = "Undefined"
        if game_controller.current_frame_index ~= -1 then
            frame_text = game_controller.current_frame_index.."/"..#tas_session.current_level_data.frames
        end
        ctx:win_input_text("##frame_text", frame_text)
    else
        ctx:win_text("No TAS loaded.")
    end
end

return module
