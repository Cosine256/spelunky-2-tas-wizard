local common = require("common")
local common_gui = require("gui/common_gui")
local game_controller = require("game_controller")
local Tool_GUI = require("gui/tool_gui")

-- TODO: Prevent popup visibility from persisting across sessions.
local module = Tool_GUI:new("single_frame_editor", "Edit Frame", "single_frame_editor_window")
module.is_popup = true

function module.open(level_index, frame_index, player_index, inputs)
    module.level_index = level_index
    module.frame_index = frame_index
    module.player_index = player_index
    module.old_inputs = inputs
    module.new_inputs = inputs
    options[module.option_id].visible = true
end

function module.close()
    options[module.option_id].visible = false
end

function module:draw_panel(ctx, is_window)
    local tas = game_controller.current.tas
    ctx:win_text("Editing frame "..self.level_index.."-"..self.frame_index.." for player "..self.player_index..".")
    self.new_inputs = common_gui.draw_inputs_editor(ctx, self.new_inputs)
    ctx:win_input_text("Old input", common.input_to_string(self.old_inputs))
    ctx:win_input_text("New input", common.input_to_string(self.new_inputs))
    if ctx:win_button("OK") then
        if tas.levels[self.level_index] and tas.levels[self.level_index].frames[self.frame_index]
            and tas.levels[self.level_index].frames[self.frame_index].players[self.player_index]
        then
            tas.levels[self.level_index].frames[self.frame_index].players[self.player_index].input = self.new_inputs
            module.close()
        else
            print("Warning: Failed to edit frame "..self.level_index.."-"..self.frame_index.." for player "..self.player_index..": Frame or player does not exist.")
        end
    end
    ctx:win_inline()
    if ctx:win_button("Cancel") then
        module.close()
    end
end

return module
