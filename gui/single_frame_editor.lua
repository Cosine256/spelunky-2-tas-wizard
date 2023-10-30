local common = require("common")
local common_gui = require("gui/common_gui")
local Tool_GUI = require("gui/tool_gui")

local module = Tool_GUI:new("single_frame_editor", "Edit Frame")
module.is_popup = true

function module:reset_session_vars()
    self:close()
end

function module:open(screen_index, frame_index, player_index, inputs)
    self.screen_index = screen_index
    self.frame_index = frame_index
    self.player_index = player_index
    self.old_inputs = inputs
    self.new_inputs = inputs
    self:set_window_open(true)
end

function module:close()
    self:set_window_open(false)
end

function module:draw_panel(ctx, is_window)
    local tas = active_tas_session.tas
    ctx:win_text("Editing frame "..self.screen_index.."-"..self.frame_index.." for player "..self.player_index..".")
    self.new_inputs = common_gui.draw_inputs_editor(ctx, self.new_inputs)
    ctx:win_input_text("Old inputs", common.inputs_to_string(self.old_inputs))
    self.new_inputs = common.string_to_inputs(ctx:win_input_text("New inputs", common.inputs_to_string(self.new_inputs)))
    if ctx:win_button("OK") then
        -- TODO: This popup doesn't elegantly handle situations where the underlying TAS data changes after the popup is spawned. The popup should be closed automatically when this happens.
        if tas.screens[self.screen_index] and tas.screens[self.screen_index].frames[self.frame_index] and self.player_index <= tas:get_player_count() then
            tas.screens[self.screen_index].frames[self.frame_index].inputs[self.player_index] = self.new_inputs
            self:close()
        else
            print_warn("Failed to edit frame %s-%s for player %s: Screen, frame, or player does not exist.", self.screen_index, self.frame_index, self.player_index)
        end
    end
    ctx:win_inline()
    if ctx:win_button("Cancel") then
        self:close()
    end
end

return module
