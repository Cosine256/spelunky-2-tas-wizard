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

local function draw_tas_path_mark(ctx, pos, label, size, top_label, ucolor)
    draw_point_mark(ctx, pos.x, pos.y, ucolor)
    if label then
        local x, y = screen_position(pos.x, pos.y)
        if top_label then
            local _, h = draw_text_size(size, "")
            y = y - h
        end
        ctx:draw_text(x, y, size, label, ucolor)
    end
end

function module.draw_tas_path(ctx, tas_session, is_ghost)
    if state.screen == SCREEN.OPTIONS or not tas_session.current_screen_data or not tas_session.current_tasable_screen.record_frames then
        return
    end
    local screen = tas_session.current_screen_data
    local color_type = is_ghost and "ghost" or "normal"
    local prev_frame_positions = screen.start_positions
    for i, frame in ipairs(screen.frames) do
        if prev_frame_positions and frame.positions then
            for player_index, this_pos in ipairs(frame.positions) do
                local prev_pos = prev_frame_positions[player_index]
                if prev_pos.x and this_pos.x then
                    local x1, y1 = screen_position(prev_pos.x, prev_pos.y)
                    local x2, y2 = screen_position(this_pos.x, this_pos.y)
                    ctx:draw_line(x1, y1, x2, y2, 2,
                        PATH_COLORS[player_index][color_type][this_pos.l == state.camera_layer and "same_layer" or "other_layer"][(i % 2) + 1])
                end
            end
        end
        prev_frame_positions = frame.positions
    end
    if options.path_frame_mark_visible then
        -- Draw frame marks in this second iteration so that they always draw on top of the path.
        for i = options.path_frame_mark_interval, #screen.frames, options.path_frame_mark_interval do
            local frame = screen.frames[i]
            if frame.positions then
                for player_index, pos in ipairs(frame.positions) do
                    if pos.x then
                        draw_tas_path_mark(ctx, pos, options.path_frame_mark_label_visible and tostring(i) or nil, options.path_frame_mark_label_size, false,
                            PATH_COLORS[player_index][color_type][pos.l == state.camera_layer and "same_layer" or "other_layer"][1])
                    end
                end
            end
        end
    end
    if options.path_frame_tag_visible then
        for _, frame_tag in ipairs(tas_session.tas.frame_tags) do
            if frame_tag.show_on_path and (frame_tag.screen == -1 and tas_session.tas:get_end_screen_index()
                or frame_tag.screen) == tas_session.current_screen_index
            then
                local positions
                if frame_tag.frame == 0 then
                    positions = screen.start_positions
                else
                    local frame = screen.frames[frame_tag.frame == -1 and tas_session.tas:get_end_frame_index(tas_session.current_screen_index) or frame_tag.frame]
                    if frame then
                        positions = frame.positions
                    end
                end
                if positions then
                    for player_index, pos in ipairs(positions) do
                        if pos.x then
                            draw_tas_path_mark(ctx, pos, options.path_frame_tag_label_visible and frame_tag.name or nil, options.path_frame_tag_label_size, true,
                                PATH_COLORS[player_index][color_type][pos.l == state.camera_layer and "same_layer" or "other_layer"][1])
                        end
                    end
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
