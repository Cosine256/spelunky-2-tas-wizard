local module = {}

local POINT_SCR_W_HALF = 0.005
local POINT_SCR_H_HALF

local PATH_SAME_LAYER_ALPHA = 0.9
local PATH_OTHER_LAYER_ALPHA = 0.4
local PATH_NORMAL_COLORS = {
    same_layer = {
        primary = Color:new(0.7, 0.0, 0.0, PATH_SAME_LAYER_ALPHA):get_ucolor(),
        secondary = Color:new(0.7, 0.3, 0.0, PATH_SAME_LAYER_ALPHA):get_ucolor(),
        mark = Color:new(1.0, 0.5, 0.2, PATH_SAME_LAYER_ALPHA):get_ucolor()
    },
    other_layer = {
        primary = Color:new(0.7, 0.0, 0.0, PATH_OTHER_LAYER_ALPHA):get_ucolor(),
        secondary = Color:new(0.7, 0.3, 0.0, PATH_OTHER_LAYER_ALPHA):get_ucolor(),
        mark = Color:new(1.0, 0.5, 0.2, PATH_OTHER_LAYER_ALPHA):get_ucolor()
    }
}
local PATH_GHOST_COLORS = {
    same_layer = {
        primary = Color:new(0.8, 0.8, 0.8, PATH_SAME_LAYER_ALPHA):get_ucolor(),
        secondary = Color:new(0.6, 0.6, 0.6, PATH_SAME_LAYER_ALPHA):get_ucolor(),
        mark = Color:new(0.9, 0.9, 0.9, PATH_SAME_LAYER_ALPHA):get_ucolor()
    },
    other_layer = {
        primary = Color:new(0.8, 0.8, 0.8, PATH_OTHER_LAYER_ALPHA):get_ucolor(),
        secondary = Color:new(0.6, 0.6, 0.6, PATH_OTHER_LAYER_ALPHA):get_ucolor(),
        mark = Color:new(0.9, 0.9, 0.9, PATH_OTHER_LAYER_ALPHA):get_ucolor()
    }
}

function module.update_screen_vars()
    local window_w, window_h = get_window_size()
    POINT_SCR_H_HALF = POINT_SCR_W_HALF * (window_w / window_h)
end

local function draw_point_mark(ctx, x, y, ucolor)
    local scr_x, scr_y = screen_position(x, y)
    ctx:draw_line(scr_x - POINT_SCR_W_HALF, scr_y, scr_x + POINT_SCR_W_HALF, scr_y, 2, ucolor)
    ctx:draw_line(scr_x, scr_y - POINT_SCR_H_HALF, scr_x, scr_y + POINT_SCR_H_HALF, 2, ucolor)
end

local function draw_tas_path_mark(ctx, pos, label, ucolor)
    draw_point_mark(ctx, pos.x, pos.y, ucolor)
    if options.path_mark_labels_visible then
        local x, y = screen_position(pos.x, pos.y)
        ctx:draw_text(x, y, 0, label, ucolor)
    end
end

function module.draw_tas_path(ctx, tas_session, is_ghost)
    if state.screen == SCREEN.OPTIONS or not tas_session.current_screen_data or not tas_session.current_tasable_screen.record_frames then
        return
    end
    local screen = tas_session.current_screen_data
    local path_colors = is_ghost and PATH_GHOST_COLORS or PATH_NORMAL_COLORS
    for i, frame in ipairs(screen.frames) do
        for player_index, player in ipairs(frame.players) do
            local pos1
            if i == 1 then
                pos1 = screen.players[player_index].start_position
            else
                pos1 = screen.frames[i - 1].players[player_index].position
            end
            local pos2 = player.position
            if pos1 and pos2 then
                local x1, y1 = screen_position(pos1.x, pos1.y)
                local x2, y2 = screen_position(pos2.x, pos2.y)
                local layer_colors = pos2.l == state.camera_layer and path_colors.same_layer or path_colors.other_layer
                local ucolor = (i % 2 == 0) and layer_colors.primary or layer_colors.secondary
                ctx:draw_line(x1, y1, x2, y2, 2, ucolor)
            end
        end
    end
    if options.path_marks_visible then
        -- Draw path marks in this second iteration so that they always draw on top of the path.
        for i = options.path_mark_increment, #screen.frames, options.path_mark_increment do
            local frame = screen.frames[i]
            for _, player in ipairs(frame.players) do
                local pos = player.position
                if pos then
                    local layer_colors = pos.l == state.camera_layer and path_colors.same_layer or path_colors.other_layer
                    draw_tas_path_mark(ctx, pos, tostring(i), layer_colors.mark)
                end
            end
        end
    end
end

return module
