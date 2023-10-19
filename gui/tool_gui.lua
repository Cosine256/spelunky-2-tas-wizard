local Tool_GUI = {}
Tool_GUI.__index = Tool_GUI

function Tool_GUI:new(id, name, option_id)
    local o = {
        id = id,
        name = name,
        option_id = option_id,
        window_label = name.."###"..id,
        is_popup = false,
        is_popup_open = false,
        _reset_window_position = false
    }
    setmetatable(o, self)
    return o
end

function Tool_GUI:reset_window_position()
    local window_default_options = default_options[self.option_id]
    local window_options = options[self.option_id]
    window_options.x, window_options.y = window_default_options.x, window_default_options.y
    window_options.w, window_options.h = window_default_options.w, window_default_options.h
    if self:is_window_open() then
        self._reset_window_position = true
    end
end

function Tool_GUI:draw_window_options(ctx, is_window)
    if is_window then
        if ctx:win_button("Reset window position") then
            self:reset_window_position()
        end
    else
        if ctx:win_button("Detach into window") then
            self:set_window_open(true)
        end
    end
end

function Tool_GUI:draw_window(ctx)
    if self:is_window_open() then
        local tool_gui_options = options[self.option_id]
        local movable = true
        if self._reset_window_position then
            self._reset_window_position = false
            movable = false
        end
        -- TODO: Can't get or set the collapsed state of a window. If collapsed, then the wrong window height is written to the options.
        local keep_open = ctx:window(self.window_label, tool_gui_options.x, tool_gui_options.y, tool_gui_options.w, tool_gui_options.h, movable, function(_, pos, size)
            tool_gui_options.x, tool_gui_options.y = pos.x, pos.y
            tool_gui_options.w, tool_gui_options.h = size.x, size.y
            self:draw_panel(ctx, true)
        end)
        if not keep_open then
            self:set_window_open(false)
        end
    end
end

function Tool_GUI:is_window_open()
    if self.is_popup then
        return self.is_popup_open
    else
        return options[self.option_id].visible
    end
end

function Tool_GUI:set_window_open(open)
    if self.is_popup then
        self.is_popup_open = open
    else
        options[self.option_id].visible = open
    end
end

-- Called once when the script is loaded.
function Tool_GUI:initialize()
end

-- Called when the active TAS session is reset, replaced, or cleared, and once when the script is loaded.
function Tool_GUI:reset_session_vars()
end

return Tool_GUI
