local common_enums = require("common_enums")

local module = {}

local POINT_SCR_W_HALF = 0.005
local POINT_SCR_H_HALF

local PATH_SAME_LAYER_ALPHA = 0.85
local PATH_OTHER_LAYER_ALPHA = 0.3

local function to_ghost_ucolor(color)
    return Color:new((0.3 * color.r) + 0.6, (0.3 * color.g) + 0.6, (0.3 * color.b) + 0.6, color.a):get_ucolor()
end

local function generate_path_colors(primary, secondary)
    local colors = {
        same_layer = {
            Color:new(primary.r, primary.g, primary.b, PATH_SAME_LAYER_ALPHA),
            Color:new(secondary.r, secondary.g, secondary.b, PATH_SAME_LAYER_ALPHA)
        },
        other_layer = {
            Color:new(primary.r, primary.g, primary.b, PATH_OTHER_LAYER_ALPHA),
            Color:new(secondary.r, secondary.g, secondary.b, PATH_OTHER_LAYER_ALPHA)
        }
    }
    return {
        normal = {
            same_layer = {
                colors.same_layer[1]:get_ucolor(),
                colors.same_layer[2]:get_ucolor()
            },
            other_layer = {
                colors.other_layer[1]:get_ucolor(),
                colors.other_layer[2]:get_ucolor()
            }
        },
        ghost = {
            same_layer = {
                to_ghost_ucolor(colors.same_layer[1]),
                to_ghost_ucolor(colors.same_layer[2])
            },
            other_layer = {
                to_ghost_ucolor(colors.other_layer[1]),
                to_ghost_ucolor(colors.other_layer[2])
            }
        }
    }
end

local PATH_COLORS = {
    generate_path_colors( -- Player 1: red
        Color:new(0.8, 0.2, 0.2, 1.0),
        Color:new(0.7, 0.0, 0.0, 1.0)),
    generate_path_colors( -- Player 2: blue
        Color:new(0.3, 0.3, 1.0, 1.0),
        Color:new(0.1, 0.1, 1.0, 1.0)),
    generate_path_colors( -- Player 3: green
        Color:new(0.2, 0.7, 0.2, 1.0),
        Color:new(0.0, 0.4, 0.0, 1.0)),
    generate_path_colors( -- Player 4: yellow
        Color:new(0.8, 0.8, 0.2, 1.0),
        Color:new(0.4, 0.4, 0.0, 1.0))
}

local MODE_WATERMARK_UCOLOR = Color:new(1.0, 1.0, 1.0, 0.25):get_ucolor()

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
    if options.path_mark_label_visible then
        local x, y = screen_position(pos.x, pos.y)
        ctx:draw_text(x, y, 0, label, ucolor)
    end
end

function module.draw_tas_path(ctx, tas_session, is_ghost)
    if state.screen == SCREEN.OPTIONS or not tas_session.current_screen_data or not tas_session.current_tasable_screen.record_frames then
        return
    end
    local screen = tas_session.current_screen_data
    local color_type = is_ghost and "ghost" or "normal"
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
                ctx:draw_line(x1, y1, x2, y2, 2,
                    PATH_COLORS[player_index][color_type][pos2.l == state.camera_layer and "same_layer" or "other_layer"][(i % 2) + 1])
            end
        end
    end
    if options.path_mark_visible then
        -- Draw path marks in this second iteration so that they always draw on top of the path.
        for i = options.path_mark_increment, #screen.frames, options.path_mark_increment do
            local frame = screen.frames[i]
            for player_index, player in ipairs(frame.players) do
                local pos = player.position
                if pos then
                    draw_tas_path_mark(ctx, pos, tostring(i),
                        PATH_COLORS[player_index][color_type][pos.l == state.camera_layer and "same_layer" or "other_layer"][1])
                end
            end
        end
    end
end

function module.draw_mode_watermark(ctx)
    if active_tas_session.mode == common_enums.MODE.FREEPLAY or state.screen == SCREEN.OPTIONS
        or not ((not presentation_active and options.mode_watermark_visible) or (presentation_active and options.presentation_mode_watermark_visible))
    then
        return
    end
    local text = active_tas_session.mode == common_enums.MODE.PLAYBACK and "TAS Playback" or "TAS Recording"
    local w, h = draw_text_size(options.mode_watermark_size, text)
    ctx:draw_text(options.mode_watermark_x - (0.5 * w * (1.0 + options.mode_watermark_x)),
        options.mode_watermark_y - (0.5 * h * (1.0 - options.mode_watermark_y)),
        options.mode_watermark_size, text, MODE_WATERMARK_UCOLOR)
end

return module
