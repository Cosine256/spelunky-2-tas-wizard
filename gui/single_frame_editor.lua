local common = require("common")
local common_gui = require("gui/common_gui")
local Tool_GUI = require("gui/tool_gui")

local module = Tool_GUI:new("single_frame_editor", "Edit Frame", "single_frame_editor_window")
module.is_popup = true

function module:reset_session_vars()
    self:close()
end

function module:open(level_index, frame_index, player_index, inputs)
    self.level_index = level_index
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
    ctx:win_text("Editing frame "..self.level_index.."-"..self.frame_index.." for player "..self.player_index..".")
    self.new_inputs = common_gui.draw_inputs_editor(ctx, self.new_inputs)
    ctx:win_input_text("Old inputs", common.inputs_to_string(self.old_inputs))
    self.new_inputs = common.string_to_inputs(ctx:win_input_text("New inputs", common.inputs_to_string(self.new_inputs)))
    if ctx:win_button("OK") then
        -- TODO: This popup doesn't elegantly handle situations where the underlying TAS data changes after the popup is spawned. The popup should be closed automatically when this happens.
        if tas.levels[self.level_index] and tas.levels[self.level_index].frames[self.frame_index]
            and tas.levels[self.level_index].frames[self.frame_index].players[self.player_index]
        then
            tas.levels[self.level_index].frames[self.frame_index].players[self.player_index].inputs = self.new_inputs
            self:close()
        else
            print("Warning: Failed to edit frame "..self.level_index.."-"..self.frame_index.." for player "..self.player_index..": Frame or player does not exist.")
        end
    end
    ctx:win_inline()
    if ctx:win_button("Cancel") then
        self:close()
    end
end

return module
