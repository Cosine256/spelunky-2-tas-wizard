local Tool_GUI = {}
Tool_GUI.__index = Tool_GUI

function Tool_GUI:new(name, option_id)
    local o = {
        name = name,
        option_id = option_id,
        _skip_draw = false
    }
    setmetatable(o, self)
    return o
end

function Tool_GUI:reset_window_position()
    local window_default_options = default_options[self.option_id]
    local window_options = options[self.option_id]
    window_options.x, window_options.y = window_default_options.x, window_default_options.y
    window_options.w, window_options.h = window_default_options.w, window_default_options.h
    self._skip_draw = true
end

function Tool_GUI:draw_window(ctx)
    if self._skip_draw then
        self._skip_draw = false
    else
        local tool_gui_options = options[self.option_id]
        if tool_gui_options.visible then
            -- TODO: Can't get or set the collapsed state of a window. If collapsed, then the wrong window height is written to the options.
            local keep_visible = ctx:window(self.name, tool_gui_options.x, tool_gui_options.y, tool_gui_options.w, tool_gui_options.h, true, function(_, pos, size)
                tool_gui_options.x, tool_gui_options.y = pos.x, pos.y
                tool_gui_options.w, tool_gui_options.h = size.x, size.y
                self:draw_panel(ctx, true)
            end)
            if not keep_visible then
                tool_gui_options.visible = false
            end
        end
    end
end

return Tool_GUI
