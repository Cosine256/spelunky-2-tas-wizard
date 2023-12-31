local common = require("common")
local common_enums = require("common_enums")
local common_gui = require("gui/common_gui")
local ToolGui = require("gui/tool_gui")

local module = ToolGui:new("status", "Status")

function module:draw_panel(ctx, is_window)
    if active_tas_session then
        local mode_string
        if active_tas_session.mode == common_enums.MODE.FREEPLAY then
            mode_string = "Freeplay"
        elseif active_tas_session.mode == common_enums.MODE.RECORD then
            mode_string = "Record"
        elseif active_tas_session.mode == common_enums.MODE.PLAYBACK then
            mode_string = "Playback"
        end

        ctx:win_text("Mode")
        ctx:win_inline()
        ctx:win_width(-0.000001)
        ctx:win_input_text("##mode", mode_string)
        if active_tas_session.mode == common_enums.MODE.PLAYBACK then
            ctx:win_text("Playing back to frame: "..active_tas_session:get_playback_target_string())
        end

        ctx:win_text("Screen")
        local screen_text = "Undefined"
        if active_tas_session.current_screen_index then
            screen_text = common.tas_screen_to_string(active_tas_session.tas, active_tas_session.current_screen_index, true)
        end
        ctx:win_inline()
        ctx:win_width(-0.000001)
        ctx:win_input_text("##current_screen", screen_text)

        ctx:win_text("Frame")
        local frame_text = "Undefined"
        if active_tas_session.current_frame_index then
            if active_tas_session.current_tasable_screen.record_frames then
                frame_text = active_tas_session.current_frame_index.."/"..active_tas_session.tas:get_end_frame_index(active_tas_session.current_screen_index)
            else
                frame_text = tostring(active_tas_session.current_frame_index)
            end
        end
        ctx:win_inline()
        ctx:win_width(-0.000001)
        ctx:win_input_text("##current_frame", frame_text)

        if active_tas_session.desync then
            ctx:win_text("Warning: Desynchronization detected:")
            ctx:win_indent(common_gui.INDENT_SUB_INPUT)
            ctx:win_text(active_tas_session.desync.desc)
            ctx:win_text("Screen")
            ctx:win_inline()
            ctx:win_width(-0.000001)
            ctx:win_input_text("##desync_screen", common.tas_screen_to_string(active_tas_session.tas, active_tas_session.desync.screen_index, true))
            ctx:win_text("Frame")
            ctx:win_inline()
            ctx:win_width(-0.000001)
            ctx:win_input_text("##desync_frame", active_tas_session.desync.frame_index.."/"..active_tas_session.tas:get_end_frame_index(active_tas_session.desync.screen_index))
            ctx:win_indent(-common_gui.INDENT_SUB_INPUT)
        end
    else
        ctx:win_text("No TAS loaded.")
    end
end

return module
