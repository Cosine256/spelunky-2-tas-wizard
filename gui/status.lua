local common = require("common")
local common_enums = require("common_enums")
local common_gui = require("gui/common_gui")
local game_controller = require("game_controller")
local Tool_GUI = require("gui/tool_gui")

local module = Tool_GUI:new("status", "Status", "status_window")

function module:draw_panel(ctx, is_window)
    if active_tas_session then
        local mode_string
        if game_controller.mode == common_enums.MODE.FREEPLAY then
            mode_string = "Freeplay"
        elseif game_controller.mode == common_enums.MODE.RECORD then
            mode_string = "Record"
        elseif game_controller.mode == common_enums.MODE.PLAYBACK then
            mode_string = "Playback"
        end

        ctx:win_text("Mode")
        ctx:win_inline()
        ctx:win_width(-0.000001)
        ctx:win_input_text("##mode", mode_string)
        if game_controller.mode == common_enums.MODE.PLAYBACK then
            ctx:win_text("Playing back to frame: "..game_controller.playback_target_level.."-"..game_controller.playback_target_frame)
        end

        ctx:win_text("Level")
        local level_text = "Undefined"
        if active_tas_session.current_level_index then
            level_text = common.level_metadata_to_string(active_tas_session.tas, active_tas_session.current_level_index, true)
        end
        ctx:win_inline()
        ctx:win_width(-0.000001)
        ctx:win_input_text("##current_level", level_text)

        ctx:win_text("Frame")
        local frame_text = "Undefined"
        if active_tas_session.current_frame_index then
            frame_text = active_tas_session.current_frame_index.."/"..#active_tas_session.current_level_data.frames
        end
        ctx:win_inline()
        ctx:win_width(-0.000001)
        ctx:win_input_text("##current_frame", frame_text)

        if active_tas_session.desync then
            ctx:win_text("Warning: Desynchronization detected:")
            ctx:win_indent(common_gui.INDENT_SUB_INPUT)
            ctx:win_text(active_tas_session.desync.desc)
            ctx:win_text("Level")
            ctx:win_inline()
            ctx:win_width(-0.000001)
            ctx:win_input_text("##desync_level", common.level_metadata_to_string(active_tas_session.tas, active_tas_session.desync.level_index, true))
            ctx:win_text("Frame")
            ctx:win_inline()
            ctx:win_width(-0.000001)
            ctx:win_input_text("##desync_frame", active_tas_session.desync.frame_index.."/"..#active_tas_session.tas.levels[active_tas_session.desync.level_index].frames)
            ctx:win_indent(-common_gui.INDENT_SUB_INPUT)
        end
    else
        ctx:win_text("No TAS loaded.")
    end
end

return module
