meta.name = "TAS Tool"
meta.version = "0.0.0"
meta.description = ""
meta.author = "Cosine"
meta.unsafe = true

local common = require("common")
local common_enums = require("common_enums")
local drawing = require("drawing")
local game_controller = require("game_controller")
local persistence = require("persistence")
local Tas = require("tas")
tool_guis = {
    frames = require("gui/frames"),
    ghost = require("gui/ghost"),
    new = require("gui/new"),
    options = require("gui/options"),
    playback_recording = require("gui/playback_recording"),
    root = require("gui/root"),
    save_load = require("gui/save_load"),
    status = require("gui/status"),
    tas_settings = require("gui/tas_settings"),
    warp = require("gui/warp")
}

local CURRENT_SCRIPT_DATA_FORMAT = 1

default_options = {
    tas_file_name = "tas.json",
    tas_file_history = {},
    tas_file_history_max_size = 10,
    playback_from = game_controller.PLAYBACK_FROM.NOW_OR_LEVEL,
    playback_target_pause = true,
    playback_target_mode = "playback",
    record_frame_clear_action = "remaining_run",
    record_frame_write_type = "overwrite",
    presentation_enabled = false,
    -- TODO: Order of tool GUIs is arbitrary. Alphabetize and put them in a sub-table with their IDs as keys?
    root_window = { visible = true, x = 0.6, y = 0.95, w = 0.4, h = 1.6 },
    frames_window = { visible = false, x = -1.0, y = 0.95, w = 0.4, h = 1.2 },
    playback_recording_window = { visible = false, x = 0.6, y = 0.25, w = 0.4, h = 1.2 },
    save_load_window = { visible = false, x = -1.0, y = -0.35, w = 0.4, h = 0.6 },
    new_window = { visible = false, x = -1.0, y = -0.15, w = 0.4, h = 0.8 },
    ghost_window = { visible = false, x = -1.0, y = -0.55, w = 0.4, h = 0.4 },
    warp_window = { visible = false, x = -1.0, y = -0.55, w = 0.4, h = 0.4 },
    tas_settings_window = { visible = false, x = -1.0, y = -0.15, w = 0.4, h = 0.8 },
    options_window = { visible = false, x = -1.0, y = -0.15, w = 0.4, h = 0.8 },
    status_window = { visible = false, x = -1.0, y = -0.55, w = 0.4, h = 0.4 },
    frames_shown_past = 8,
    frames_shown_future = 8,
    pause_recording_on_level_start = true,
    pause_playback_on_level_start = false,
    pause_desync = true,
    transition_skip = false,
    paths_visible = true,
    path_marks_visible = true,
    path_mark_labels_visible = true,
    path_mark_increment = 30,
    ghost_path_visible = true,
    new_tas = {
        name = "Unnamed TAS",
        description = "",
        start = {
            type = "simple",
            seed_type = "seeded",
            seeded_seed = 0x00000000,
            -- Adventure seed 0,0 generates runs with unusual similarity between levels. This default adventure seed has better behavior.
            adventure_seed = { 0x0000000000000001, 0x0000000000000000 },
            is_custom_area_choice = false,
            world = 1,
            level = 1,
            theme = THEME.DWELLING,
            shortcut = false,
            tutorial_race = false,
            tutorial_race_referee = "margaret",
            player_count = 1,
            players = { "ana", "margaret", "colin", "roffy" },
        },
        levels = {},
        olmec_cutscene_skip_frame = game_controller.CUTSCENE_SKIP_FIRST_FRAME,
        olmec_cutscene_skip_input = "jump",
        tiamat_cutscene_skip_frame = game_controller.CUTSCENE_SKIP_FIRST_FRAME,
        tiamat_cutscene_skip_input = "jump",
        transition_exit_frame = game_controller.TRANSITION_EXIT_FIRST_FRAME,
        tagged_frames = {},
        save_player_positions = true,
        save_level_snapshots = true
    },
    debug_print_load = false,
    debug_print_file = false,
    debug_print_frame = false,
    debug_print_input = false,
    debug_print_mode = false,
    debug_print_pause = false,
    debug_print_snapshot = false
}

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
        print("Warning: Failed to save script data: "..err)
    end
end

local function load_script_data(load_ctx)
    local load_json
    local load_data
    local success, err = pcall(function()
        load_json = load_ctx:load()
    end)
    if not success then
        print("Warning: Failed to load script data: "..err)
    else
        local result
        success, result = persistence.json_decode(load_json, true)
        if not success then
            print("Warning: Failed to load script data: "..result)
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

-- Reset the TAS session and set the current TAS.
-- TODO: Could move this into game_controller and give the frames GUI a way to listen for the change.
function set_current_tas(tas)
    game_controller.set_tas(tas)
    tool_guis.frames.reset_vars()
end

local function on_gui_frame(ctx)
    if game_controller.mode ~= common_enums.MODE.PLAYBACK or not options.presentation_enabled then
        ctx:draw_layer(DRAW_LAYER.BACKGROUND)
        drawing.update_screen_vars()
        if game_controller.ghost_tas_session and options.ghost_path_visible then
            drawing.draw_tas_path(ctx, game_controller.ghost_tas_session, true)
        end
        if game_controller.current and options.paths_visible then
            drawing.draw_tas_path(ctx, game_controller.current, false)
        end
    end

    ctx:draw_layer(DRAW_LAYER.WINDOW)
    tool_guis.root.draw_windows(ctx)
end

set_callback(function(ctx)
    load_script_data(ctx)
    set_callback(save_script_data, ON.SAVE)
    register_option_callback("", options, function(ctx) tool_guis.options:draw_panel(ctx, false) end)
    set_callback(on_gui_frame, ON.GUIFRAME)
    game_controller.initialize()
    tool_guis.frames.reset_vars()
end, ON.LOAD)
