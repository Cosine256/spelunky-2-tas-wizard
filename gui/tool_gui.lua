local Tool_GUI = {}
Tool_GUI.__index = Tool_GUI

function Tool_GUI:new(id, name)
    local o = {
        id = id,
        name = name,
        window_label = name.."###"..id,
        is_popup = false,
        is_popup_open = false,
        _reset_window_position = false
    }
    setmetatable(o, self)
    return o
end

function Tool_GUI:reset_window_position()
    local window_settings = options.tool_guis[self.id].window_settings
    local default_window_settings = default_options.tool_guis[self.id].window_settings
    window_settings.x, window_settings.y = default_window_settings.x, default_window_settings.y
    window_settings.w, window_settings.h = default_window_settings.w, default_window_settings.h
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
        local window_settings = options.tool_guis[self.id].window_settings
        local movable = true
        if self._reset_window_position then
            self._reset_window_position = false
            movable = false
        end
        -- TODO: Can't get or set the collapsed state of a window. If collapsed, then the wrong window height is written to the options.
        local keep_open = ctx:window(self.window_label, window_settings.x, window_settings.y, window_settings.w, window_settings.h, movable, function(_, pos, size)
            window_settings.x, window_settings.y = pos.x, pos.y
            window_settings.w, window_settings.h = size.x, size.y
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
        return options.tool_guis[self.id].windowed
    end
end

function Tool_GUI:set_window_open(open)
    if self.is_popup then
        self.is_popup_open = open
    else
        options.tool_guis[self.id].windowed = open
    end
end

-- Called once when the script is loaded.
function Tool_GUI:initialize()
end

-- Called when the active TAS session is reset, replaced, or cleared, and once when the script is loaded.
function Tool_GUI:reset_session_vars()
end

return Tool_GUI
