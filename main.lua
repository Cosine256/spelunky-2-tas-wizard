meta.name = "TAS Wizard"
meta.version = "1.0.0"
meta.description = "A mod for creating tool-assisted speedruns."
meta.author = "Cosine"

local common = require("common")
local common_enums = require("common_enums")
local drawing = require("gui/drawing")
local game_controller = require("game_controller")
local persistence = require("persistence")
local Tas = require("tas")
local TasSession = require("tas_session")

tool_guis = {
    file = require("gui/file"),
    frames = require("gui/frames"),
    ghost = require("gui/ghost"),
    options = require("gui/options"),
    playback_record = require("gui/playback_record"),
    root = require("gui/root"),
    single_frame_editor = require("gui/single_frame_editor"),
    status = require("gui/status"),
    tas_data = require("gui/tas_data"),
    tas_root = require("gui/tas_root"),
    tas_settings = require("gui/tas_settings"),
    warp = require("gui/warp")
}

local CURRENT_SCRIPT_DATA_FORMAT = 1

default_options = {
    tas_file_name = "tas.json",
    tas_file_history = {},
    tas_file_history_max_size = 10,
    playback_from = "here_or_nearest_screen",
    playback_target_mode = "playback",
    playback_target_pause = true,
    record_frame_clear_action = "remaining_tas",
    record_frame_write_type = "overwrite",
    playback_screen_load_pause = false,
    record_screen_load_pause = true,
    desync_pause = true,
    pause_suppress_transition_tas_inputs = true,
    playback_fast_update = false,
    fast_update_flash_prevention = true,
    transition_skip = false,
    presentation_start_on_playback = false,
    presentation_stop_after_playback = false,
    presentation_mode_watermark_visible = false,
    frames_viewer_follow_current = true,
    frames_viewer_page_size = 10,
    frames_viewer_step_size = 10,
    active_path_visible = true,
    ghost_path_visible = true,
    path_frame_mark_visible = true,
    path_frame_mark_label_visible = true,
    path_frame_mark_label_size = 20.0,
    path_frame_mark_interval = 30,
    path_frame_tag_visible = true,
    path_frame_tag_label_visible = true,
    path_frame_tag_label_size = 20.0,
    mode_watermark_visible = true,
    mode_watermark_x = 0.0,
    mode_watermark_y = -0.95,
    mode_watermark_size = 32.0,
    new_tas = {
        name = "Unnamed TAS",
        description = "",
        start_type = "simple",
        start_simple = {
            seed_type = "seeded",
            seeded_seed = 0x00000000,
            -- Adventure seed 0,0 generates runs with unusual similarity between levels. This default adventure seed has better behavior.
            adventure_seed = { 0x0000000000000001, 0x0000000000000000 },
            is_custom_preset = false,
            screen = SCREEN.LEVEL,
            world = 1,
            level = 1,
            theme = THEME.DWELLING,
            shortcut = false,
            tutorial_race = false,
            tutorial_race_referee = "margaret",
            player_count = 1,
            players = { "ana", "margaret", "colin", "roffy" },
        },
        start_snapshot = {},
        screens = {},
        frame_tags = {
            {
                name = "Start",
                screen = 1,
                frame = 0,
                show_on_path = false
            },
            {
                name = "End",
                screen = -1,
                frame = -1,
                show_on_path = false
            }
        },
        save_player_positions_default = true,
        save_screen_snapshot_defaults = {
            [common_enums.TASABLE_SCREEN[SCREEN.CAMP].data_id] = true,
            [common_enums.TASABLE_SCREEN[SCREEN.LEVEL].data_id] = true
        }
    },
    tool_guis = {
        file = {
            windowed = false,
            window_settings = { x = -0.3, y = 0.5, w = 0.4, h = 0.6 }
        },
        frames = {
            windowed = false,
            window_settings = { x = -0.59, y = 0.8, w = 0.4, h = 1.2 }
        },
        ghost = {
            windowed = false,
            window_settings = { x = -0.25, y = 0.45, w = 0.4, h = 0.3 }
        },
        options = {
            windowed = false,
            window_settings = { x = -0.2, y = 0.4, w = 0.4, h = 1.0 }
        },
        playback_record = {
            windowed = false,
            window_settings = { x = 0.6, y = 0.8, w = 0.4, h = 1.0 }
        },
        root = {
            windowed = true,
            window_settings = { x = 0.6, y = -0.21, w = 0.4, h = 0.74 }
        },
        single_frame_editor = {
            window_settings = { x = -0.2, y = 0.25, w = 0.4, h = 0.5 }
        },
        status = {
            windowed = false,
            window_settings = { x = -0.15, y = 0.35, w = 0.4, h = 0.6 }
        },
        tas_data = {
            windowed = false,
            window_settings = { x = -0.1, y = 0.3, w = 0.4, h = 1.2 }
        },
        tas_root = {
            windowed = true,
            window_settings = { x = -1.0, y = 0.8, w = 0.4, h = 1.2 }
        },
        tas_settings = {
            windowed = false,
            window_settings = { x = -0.05, y = 0.25, w = 0.4, h = 0.8 }
        },
        warp = {
            windowed = false,
            window_settings = { x = 0.0, y = 0.2, w = 0.4, h = 0.4 }
        }
    },
    debug_prints = {
        fast_update = false,
        file = false,
        input = false,
        misc = false,
        mode = false,
        pause = false,
        screen_load = false,
        snapshot = false
    }
}

---@type TasSession?
active_tas_session = nil
---@type TasSession?
ghost_tas_session = nil
presentation_active = false

function print_debug(category, format_string, ...)
    if not presentation_active and options.debug_prints[category] then
        print("[Debug] "..string.format(format_string, ...))
    end
end

function print_info(format_string, ...)
    print("[Info] "..string.format(format_string, ...))
end

function print_warn(format_string, ...)
    print("[Warning] "..string.format(format_string, ...))
end

local function save_script_data(save_ctx)
    local save_data = {
        format = CURRENT_SCRIPT_DATA_FORMAT,
        options = common.deep_copy(options)
    }
    save_data.options.new_tas = options.new_tas:to_raw(Tas.SERIAL_MODS.OPTIONS)
    local save_json = json.encode(save_data)
    local success, err = pcall(function()
        save_ctx:save(save_json)
    end)
    if not success then
        print_warn("Failed to save script data: %s", err)
    end
end

local function load_script_data(load_ctx)
    local load_json
    local load_data
    local success, err = pcall(function()
        load_json = load_ctx:load()
    end)
    if not success then
        print_warn("Failed to load script data: %s", err)
    else
        local result
        success, result = persistence.json_decode(load_json, true)
        if not success then
            print_warn("Failed to load script data: %s", result)
        elseif result then
            load_data = result
        end
    end
    if load_data then
        persistence.update_format(load_data, CURRENT_SCRIPT_DATA_FORMAT, {})
        options = load_data.options
        options.new_tas = Tas:from_raw(options.new_tas, Tas.SERIAL_MODS.OPTIONS)
    else
        options = common.deep_copy(default_options)
        options.new_tas = Tas:from_raw(options.new_tas, Tas.SERIAL_MODS.NONE)
    end
end

local function on_active_tas_mode_set(old_mode, new_mode)
    if presentation_active then
        if options.presentation_stop_after_playback and old_mode == common_enums.MODE.PLAYBACK and new_mode ~= common_enums.MODE.PLAYBACK then
            presentation_active = false
        end
    else
        if options.presentation_start_on_playback and new_mode == common_enums.MODE.PLAYBACK then
            presentation_active = true
        end
    end
end

-- Set the TAS for a new active TAS session.
function set_active_tas(tas)
    game_controller.cancel_requested_pause()
    if active_tas_session then
        if active_tas_session.tas.screen_snapshot_request_id then
            game_controller.clear_screen_snapshot_request(active_tas_session.tas.screen_snapshot_request_id)
            active_tas_session.tas.screen_snapshot_request_id = nil
        end
        on_active_tas_mode_set(active_tas_session.mode, nil)
    end
    if tas then
        active_tas_session = TasSession:new(tas)
        active_tas_session.set_mode_callback = on_active_tas_mode_set
        active_tas_session:find_current_screen()
        on_active_tas_mode_set(nil, active_tas_session.mode)
    else
        active_tas_session = nil
    end
    for _, tool_gui in pairs(tool_guis) do
        tool_gui:reset_session_vars()
    end
end

-- Set the TAS for a new ghost TAS session.
function set_ghost_tas(tas)
    if tas then
        ghost_tas_session = TasSession:new(tas)
        ghost_tas_session:find_current_screen()
    else
        ghost_tas_session = nil
    end
end

local function on_gui_frame(ctx)
    -- Draw the windows before the background elements. The background elements should not throw any errors, but if they do, then the user will still be able to interact with the windows and save their TAS or disable whatever is causing the errors.
    if not presentation_active then
        ctx:draw_layer(DRAW_LAYER.WINDOW)
        for _, tool_gui in pairs(tool_guis) do
            tool_gui:draw_window(ctx)
        end
    end

    ctx:draw_layer(DRAW_LAYER.BACKGROUND)
    drawing.update_screen_vars()
    if not presentation_active then
        if ghost_tas_session and options.ghost_path_visible then
            drawing.draw_tas_path(ctx, ghost_tas_session, true)
        end
        if active_tas_session and options.active_path_visible then
            drawing.draw_tas_path(ctx, active_tas_session, false)
        end
    end
    if options.fast_update_flash_prevention and game_controller.pre_update_executed_fast_update_batch then
        drawing.draw_black_overlay(ctx)
    end
    if active_tas_session then
        drawing.draw_mode_watermark(ctx)
    end
end

set_callback(function(ctx)
    load_script_data(ctx)
    set_callback(save_script_data, ON.SAVE)
    register_option_callback("", options, function(ctx) tool_guis.options:draw_panel(ctx, false) end)
    set_callback(on_gui_frame, ON.GUIFRAME)
    game_controller.initialize()
    for _, tool_gui in pairs(tool_guis) do
        tool_gui:initialize()
        tool_gui:reset_session_vars()
    end
end, ON.LOAD)
