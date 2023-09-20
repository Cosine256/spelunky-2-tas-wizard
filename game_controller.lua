local module = {}

local common = require("common")
local common_enums = require("common_enums")
local introspection = require("introspection")
local GAME_TYPES = introspection.register_types({}, require("raw_game_types"))

local POSITION_DESYNC_EPSILON = 0.0000000001
-- Vanilla frames used to fade into and out of the transition screen.
local TRANSITION_FADE_FRAMES = 18
local WARP_FADE_OUT_FRAMES = 5
-- Menu and journal inputs are not supported. They do not work correctly during recording and playback.
local SUPPORTED_INPUT_MASK = INPUTS.JUMP | INPUTS.WHIP | INPUTS.BOMB | INPUTS.ROPE | INPUTS.RUN | INPUTS.DOOR | INPUTS.LEFT | INPUTS.RIGHT | INPUTS.UP | INPUTS.DOWN

local SCREEN_WARP_HANDLER
do
    local function menu_warp()
        -- This OL warp function stops the main menu music, which can't currently be done with Lua. The caller is going to override everything else that the warp does to the state memory, so the destination level doesn't matter.
        warp(1, 1, THEME.DWELLING)
        return true
    end
    SCREEN_WARP_HANDLER = {
        [SCREEN.LOGO] = false, -- Controls don't bind properly.
        [SCREEN.INTRO] = true,
        [SCREEN.PROLOGUE] = false, -- Controls don't bind properly.
        [SCREEN.TITLE] = false, -- Controls don't bind properly.
        [SCREEN.MENU] = function()
            menu_warp()
            if game_manager.screen_menu.cthulhu_sound then
                -- Stop the stone door sound effects that play the first time the main menu is loaded.
                game_manager.screen_menu.cthulhu_sound.playing = false
            end
            return true
        end,
        [SCREEN.OPTIONS] = false,
        [SCREEN.PLAYER_PROFILE] = menu_warp,
        [SCREEN.LEADERBOARD] = menu_warp,
        [SCREEN.SEED_INPUT] = menu_warp,
        [SCREEN.CHARACTER_SELECT] = false, -- Controls don't bind properly.
        [SCREEN.TEAM_SELECT] = false,
        [SCREEN.CAMP] = true,
        [SCREEN.LEVEL] = true,
        [SCREEN.TRANSITION] = true,
        [SCREEN.DEATH] = true,
        [SCREEN.SPACESHIP] = true,
        [SCREEN.WIN] = true,
        [SCREEN.CREDITS] = true,
        [SCREEN.SCORES] = true,
        [SCREEN.CONSTELLATION] = true,
        [SCREEN.RECAP] = true,
        [SCREEN.ARENA_MENU] = false,
        [SCREEN.ARENA_STAGES] = false,
        [SCREEN.ARENA_ITEMS] = false,
        [SCREEN.ARENA_SELECT] = false,
        [SCREEN.ARENA_INTRO] = false,
        [SCREEN.ARENA_LEVEL] = false,
        [SCREEN.ARENA_SCORE] = false,
        [SCREEN.ONLINE_LOADING] = false,
        [SCREEN.ONLINE_LOBBY] = false
    }
end

module.PLAYBACK_FROM = {
    NOW_OR_LEVEL = 1,
    NOW = 2,
    LEVEL = 3
}

module.CUTSCENE_SKIP_FIRST_FRAME = 2
module.OLMEC_CUTSCENE_LAST_FRAME = 809
module.TIAMAT_CUTSCENE_LAST_FRAME = 379
module.TRANSITION_EXIT_FIRST_FRAME = 1

local desync_callbacks = {}
local next_callback_id = 0

-- Determines how the game controller and the active TAS session interact with the game engine. If this is set to anything other than freeplay, then it is assumed that there is an active TAS session in a valid state for a non-freeplay mode.
module.mode = common_enums.MODE.FREEPLAY
module.playback_target_level = nil
module.playback_target_frame = nil
module.playback_force_full_run = nil
module.playback_force_current_frame = nil
local need_pause
local force_level_snapshot

-- The number of frames that have executed on the transition screen, based on `get_frame()`.
local transition_frame
local transition_last_get_frame_seen

local pre_update_loading
local pre_update_time_level
local pre_update_cutscene_active

local level_snapshot_requests = {}
local level_snapshot_request_count = 0
local level_snapshot_request_next_id = 1
local captured_level_snapshot = nil

-- Reset variables with the scope of a single frame.
local function reset_frame_vars()
    pre_update_loading = -1
    pre_update_time_level = -1
    pre_update_cutscene_active = false
end

-- Reset variables with the scope of a single level, camp, or transition.
local function reset_level_vars()
    if active_tas_session then
        active_tas_session:clear_current_level_index()
    end
    if ghost_tas_session then
        ghost_tas_session:clear_current_level_index()
    end
    transition_frame = nil
    transition_last_get_frame_seen = nil
    reset_frame_vars()
end

-- Reset the entire TAS session by resetting all session and level variables. Does not unload the active TAS.
-- TODO: "session" is a confusing name since there are also TasSession objects.
function module.reset_session_vars()
    module.mode = common_enums.MODE.FREEPLAY
    module.playback_target_level = nil
    module.playback_target_frame = nil
    module.playback_force_full_run = false
    module.playback_force_current_frame = false
    need_pause = false
    force_level_snapshot = nil
    reset_level_vars()
end

function module.register_level_snapshot_request(callback)
    local request_id = level_snapshot_request_next_id
    level_snapshot_request_next_id = level_snapshot_request_next_id + 1
    level_snapshot_requests[request_id] = callback
    level_snapshot_request_count = level_snapshot_request_count + 1
    if options.debug_print_snapshot then
        print("register_level_snapshot_request: Registered level snapshot request "..request_id..".")
    end
    return request_id
end

function module.clear_level_snapshot_request(request_id)
    if level_snapshot_requests[request_id] then
        level_snapshot_requests[request_id] = nil
        level_snapshot_request_count = level_snapshot_request_count - 1
        if options.debug_print_snapshot then
            print("clear_level_snapshot_request: Cleared level snapshot request "..request_id..".")
        end
    end
end

-- Apply a game engine pause if one is needed and it's safe to do so. If a pause is needed but cannot be safely performed, then nothing will happen and this function can be called on the next update to try again.
local function try_pause()
    if not need_pause then
        return
    elseif state.screen ~= SCREEN.LEVEL and state.screen ~= SCREEN.CAMP then
        -- Don't pause during this non-gameplay screen.
        if state.screen ~= SCREEN.TRANSITION and state.screen ~= SCREEN.SPACESHIP and state.screen ~= SCREEN.OPTIONS then
            -- This screen doesn't lead back to a playable screen. Cancel the pause entirely.
            need_pause = false
        end
        return
    end
    if state.loading == 0 then
        -- It's safe to pause here.
        -- TODO: OL added an option to change which pause flag it uses. Need to handle the other ones, or instruct the user to only use the FADE flag.
        state.pause = PAUSE.FADE
        need_pause = false
        if options.debug_print_pause then
            print("try_pause: Paused")
        end
    end
end

local function set_desync_callback(callback)
    local callback_id = next_callback_id
    next_callback_id = next_callback_id + 1
    desync_callbacks[callback_id] = callback
    return callback_id
end

local function clear_desync_callback(callback_id)
    desync_callbacks[callback_id] = nil
end

local function run_desync_callbacks()
    for _, callback in pairs(desync_callbacks) do
        callback()
    end
end

local function check_position_desync(player_index, expected_pos, actual_pos)
    if active_tas_session.desync then
        return
    end
    if not actual_pos or math.abs(expected_pos.x - actual_pos.x) > POSITION_DESYNC_EPSILON
        or math.abs(expected_pos.y - actual_pos.y) > POSITION_DESYNC_EPSILON
    then
        local desync = {
            level_index = active_tas_session.current_level_index,
            frame_index = active_tas_session.current_frame_index,
            desc = "Actual player "..player_index.." position differs from expected position."
        }
        active_tas_session.desync = desync
        print("Desynchronized on frame "..desync.level_index.."-"..desync.frame_index..": "..desync.desc)
        print("    Expected: x="..expected_pos.x.." y="..expected_pos.y)
        if actual_pos then
            print("    Actual: x="..actual_pos.x.." y="..actual_pos.y)
            print("    Diff: dx="..(actual_pos.x - expected_pos.x).." dy="..(actual_pos.y - expected_pos.y))
        else
            print("    Actual: nil")
        end
        if options.pause_desync then
            if options.debug_print_pause then
                prinspect("position_desync: pause", get_frame())
            end
            need_pause = true
        end
        run_desync_callbacks()
    end
end

local function set_level_end_desync()
    if active_tas_session.desync then
        return
    end
    local desync = {
        level_index = active_tas_session.current_level_index,
        frame_index = active_tas_session.current_frame_index,
        desc = "Expected end of level."
    }
    active_tas_session.desync = desync
    print("Desynchronized on frame "..desync.level_index.."-"..desync.frame_index..": "..desync.desc)
    if options.pause_desync then
        if options.debug_print_pause then
            prinspect("level_end_desync: pause", get_frame())
        end
        need_pause = true
    end
    run_desync_callbacks()
end

-- Prepare for screen-specific warp behavior. Returns false if it isn't safe to warp to a level from this screen.
local function prepare_warp_from_screen()
    local screen_can_warp = SCREEN_WARP_HANDLER[state.screen]
    local can_warp = type(screen_can_warp) == "function" and screen_can_warp() or screen_can_warp == true
    if not can_warp then
        print("Cannot warp to level from current screen.")
    end
    return can_warp
end

-- Forces the game to start unloading the current screen. If nothing else is done, then this will just reload the current screen, but it can be combined with game state changes in order to perform sophisticated warps.
local function trigger_warp_unload()
    state.loading = 1
    state.pause = PAUSE.FADE
    state.fadeout = WARP_FADE_OUT_FRAMES
    state.fadein = WARP_FADE_OUT_FRAMES
end

-- Forces the game to warp to a level initialized with the simple start settings of the given TAS. This sets the run reset flag, prepares the game state, and then triggers the game to start unloading the current screen. The reset flag handles the most of the process on its own.
local function trigger_start_simple_warp(tas)
    if options.debug_print_load then
        print("trigger_start_simple_warp")
    end

    local start = tas.start_simple

    state.quest_flags = common.flag_to_value(QUEST_FLAG.RESET)
    if start.seed_type == "seeded" then
        state.seed = start.seeded_seed
        state.quest_flags = state.quest_flags | common.flag_to_value(QUEST_FLAG.SEEDED)
        -- The adventure seed will be generated by the game based on the seeded seed.
    else
        -- The adventure seed needs to be set later in the loading process.
        force_level_snapshot = {
            adventure_seed = start.adventure_seed
        }
        -- The seeded seed does not affect adventure runs.
    end
    if start.shortcut then
        state.quest_flags = state.quest_flags | common.flag_to_value(QUEST_FLAG.SHORTCUT_USED)
    end
    state.world_next = start.world
    state.level_next = start.level
    state.theme_next = start.theme
    if start.tutorial_race then
        state.screen_next = SCREEN.CAMP
        state.world_start = 1
        state.level_start = 1
        state.theme_start = THEME.DWELLING
        state.speedrun_activation_trigger = true
        state.speedrun_character = common_enums.PLAYER_CHAR:value_by_id(start.tutorial_race_referee).ent_type_id
        if not force_level_snapshot then
            force_level_snapshot = {}
        end
        -- Ensure that the player spawns in the tutorial area, instead of the rope or large door.
        force_level_snapshot.pre_level_gen_screen_last = SCREEN.CAMP
    else
        state.screen_next = SCREEN.LEVEL
        state.world_start = start.world
        state.level_start = start.level
        state.theme_start = start.theme
        state.speedrun_activation_trigger = false
    end
    state.items.player_count = start.player_count
    for player_index = 1, CONST.MAX_PLAYERS do
        local player_char = common_enums.PLAYER_CHAR:value_by_id(start.players[player_index])
        state.items.player_select[player_index].activated = player_index <= start.player_count
        state.items.player_select[player_index].character = player_char.ent_type_id
        state.items.player_select[player_index].texture = player_char.texture_id
    end

    trigger_warp_unload()

    active_tas_session.desync = nil

    return true
end

-- Forces the game to warp to a level initialized with the given level snapshot. This triggers the game to start unloading the current screen, and then it hooks into the loading process at specific points to apply the snapshot. Only level snapshots are supported, not any other screens such as the camp.
local function trigger_level_snapshot_warp(level_snapshot)
    trigger_warp_unload()
    active_tas_session.desync = nil
    force_level_snapshot = level_snapshot
end

-- Prepares the game state and triggers the loading sequence for loading from the TAS's starting state.
-- TODO: This fades in really fast if warping from another level. I use a fast fade-out for these warps, but I'm not sure how the game decides how many fade-in frames to use after that.
function module.apply_start_state()
    if not prepare_warp_from_screen() then
        return false
    end
    local tas = active_tas_session.tas
    if tas:is_start_configured() then
        if tas.start_type == "simple" then
            trigger_start_simple_warp(tas)
            return true
        elseif tas.start_type == "full" then
            if tas:is_start_configured() then
                trigger_level_snapshot_warp(tas.start_full)
                return true
            end
        end
    end
    return false
end

-- Prepares the game state and triggers the loading sequence for loading a level snapshot.
function module.apply_level_snapshot(level_index)
    if not prepare_warp_from_screen() then
        return false
    end
    local level_snapshot = active_tas_session.tas.levels[level_index].snapshot
    if not level_snapshot then
        print("Warning: Missing snapshot for level index "..level_index..".")
        return false
    end
    trigger_level_snapshot_warp(level_snapshot)
    return true
end

function module.set_mode(new_mode)
    if new_mode == common_enums.MODE.FREEPLAY then
        module.playback_target_level = nil
        module.playback_target_frame = nil
        module.playback_force_full_run = false
        module.playback_force_current_frame = false
        active_tas_session.current_frame_index = nil

    elseif new_mode == common_enums.MODE.RECORD then
        if module.mode == common_enums.MODE.PLAYBACK then
            module.playback_target_level = nil
            module.playback_target_frame = nil
            if active_tas_session.current_frame_index then
                if options.record_frame_clear_action == "remaining_level" then
                    active_tas_session.tas:remove_frames_after(active_tas_session.current_level_index, active_tas_session.current_frame_index, true)
                elseif options.record_frame_clear_action == "remaining_run" then
                    active_tas_session.tas:remove_frames_after(active_tas_session.current_level_index, active_tas_session.current_frame_index, false)
                end
            end
        end

    elseif new_mode == common_enums.MODE.PLAYBACK then
        local need_load = false
        local load_level_index = -1

        local can_use_current_frame = not module.playback_force_full_run and module.mode ~= common_enums.MODE.FREEPLAY
            and (module.playback_force_current_frame or options.playback_from == module.PLAYBACK_FROM.NOW_OR_LEVEL or options.playback_from == module.PLAYBACK_FROM.NOW)
            and (active_tas_session.current_level_index and ((module.playback_target_level == active_tas_session.current_level_index and module.playback_target_frame >= active_tas_session.current_frame_index) or module.playback_target_level > active_tas_session.current_level_index))

        local best_load_level_index = -1
        if module.playback_force_full_run then
            best_load_level_index = 1
        elseif not module.playback_force_current_frame then
            if module.mode == common_enums.MODE.FREEPLAY or options.playback_from == module.PLAYBACK_FROM.NOW_OR_LEVEL or options.playback_from == module.PLAYBACK_FROM.LEVEL then
                best_load_level_index = active_tas_session.tas:find_closest_level_with_snapshot(module.playback_target_level)
                if best_load_level_index == -1 then
                    best_load_level_index = 1
                end
            elseif options.playback_from == 4 then
                best_load_level_index = 1
            elseif options.playback_from > 4 and active_tas_session.tas.levels[options.playback_from - 3].snapshot then
                best_load_level_index = options.playback_from - 3
            end
        end

        module.playback_force_full_run = false
        module.playback_force_current_frame = false

        if options.debug_print_mode then
            print("Evaluating playback method: can_use_current_frame="..tostring(can_use_current_frame).." best_load_level_index="..best_load_level_index)
        end
        if can_use_current_frame then
            -- Default behavior is to use current frame.
            if best_load_level_index ~= -1 then
                -- Can use current frame or load a level state. Choose the closer one.
                if active_tas_session.current_level_index < best_load_level_index then
                    need_load = true
                    if best_load_level_index > 1 then
                        load_level_index = best_load_level_index
                    end
                end
            end
        elseif best_load_level_index ~= -1 then
            need_load = true
            if best_load_level_index > 1 then
                load_level_index = best_load_level_index
            end
        else
            -- Can neither use current frame nor load a level state.
            print("Warning: Cannot reach playback target with current options.")
            return
        end

        if need_load then
            -- Load a level to reach the playback target.
            if options.debug_print_mode then
                print("Loading level for playback: target_level="..module.playback_target_level.." target_frame="..module.playback_target_frame.." load_level_index="..load_level_index)
            end
            if load_level_index == -1 then
                if not module.apply_start_state() then
                    return
                end
            else
                if not module.apply_level_snapshot(load_level_index) then
                    return
                end
            end
        else
            -- Playback to the target from the current frame.
            if active_tas_session.current_level_index == module.playback_target_level and active_tas_session.current_frame_index == module.playback_target_frame then
                if options.debug_print_mode then
                    print("Already at playback target: target_level="..module.playback_target_level.." target_frame="..module.playback_target_frame.." load_level_index="..load_level_index)
                end
                -- TODO: Switch to record mode if required, or otherwise set the playback target to the end of the run. Also check whether a pause is needed. Alternately, reload and playback to get back to this frame. I often want a reload to occur when I'm trying to playback to the current frame.
            end
            if options.debug_print_mode then
                print("Playing back from current frame: target_level="..module.playback_target_level.." target_frame="..module.playback_target_frame.." load_level_index="..load_level_index)
            end
        end
    end
    module.mode = new_mode
end

-- Validates whether the current level and frame indices are within the TAS. Prints a warning, switches to freeplay mode, and pauses if the current frame is invalid.
-- Returns whether the current frame valid. Returns true if the current frame is already undefined.
function module.validate_current_frame()
    local clear_current_level_index = false
    local message
    if active_tas_session.current_level_index then
        if active_tas_session.current_level_index > active_tas_session.tas:get_end_level_index() then
            message = "Current level is later than end of TAS ("..active_tas_session.tas:get_end_level_index().."-"..active_tas_session.tas:get_end_frame_index()..")."
            clear_current_level_index = true
        elseif active_tas_session.current_frame_index and active_tas_session.current_frame_index > active_tas_session.tas:get_end_frame_index(active_tas_session.current_level_index) then
            message = "Current frame is later than end of level ("..active_tas_session.current_level_index.."-"..active_tas_session.tas:get_end_frame_index(active_tas_session.current_level_index)..")."
        end
    end
    if message then
        print("Warning: Invalid current frame ("..active_tas_session.current_level_index.."-"..tostring(active_tas_session.current_frame_index).."): "..message.." Switching to freeplay mode.")
        if options.debug_print_pause then
            prinspect("validate_current_frame: Invalid current frame pause", get_frame())
        end
        module.set_mode(common_enums.MODE.FREEPLAY)
        need_pause = true
        if clear_current_level_index then
            active_tas_session:clear_current_level_index()
        end
        return false
    else
        return true
    end
end

-- Validates the current playback target. Prints a warning, switches to freeplay mode, and pauses if the target is invalid.
-- Returns whether the playback target was valid. Returns true if current mode is not playback.
function module.validate_playback_target()
    if module.mode ~= common_enums.MODE.PLAYBACK then
        return true
    end
    local message
    if module.playback_target_level > #active_tas_session.tas.levels then
        message = "Target is later than end of TAS ("..#active_tas_session.tas.levels.."-"..#active_tas_session.tas.levels[module.playback_target_level].frames..")."
    elseif module.playback_target_frame > #active_tas_session.tas.levels[module.playback_target_level].frames then
        message = "Target is later than end of level ("..module.playback_target_level.."-"..#active_tas_session.tas.levels[module.playback_target_level].frames..")."
    elseif (state.loading == 0 or state.loading == 3) and (active_tas_session.current_level_index > module.playback_target_level
            or (active_tas_session.current_level_index == module.playback_target_level and active_tas_session.current_frame_index > module.playback_target_frame)) then
        message = "Current frame ("..active_tas_session.current_level_index.."-"..active_tas_session.current_frame_index..") is later than playback target."
    end
    if message then
        print("Warning: Invalid playback target ("..module.playback_target_level.."-"..module.playback_target_frame.."): "..message.." Switching to freeplay mode.")
        if options.debug_print_pause then
            prinspect("validate_playback_target: Invalid playback target pause", get_frame())
        end
        module.set_mode(common_enums.MODE.FREEPLAY)
        need_pause = true
        return false
    else
        return true
    end
end

-- Called right before an update that will generate a playable level or the camp. Not to be confused with `on_pre_level_gen`, which is called within the update right before level generation occurs. Between this function and `on_pre_level_gen`, the game will unload the current screen and increment the adventure seed to generate PRNG for the upcoming level.
local function on_pre_update_level_load()
    if options.debug_print_load then
        print("on_pre_update_level_load")
    end

    if ghost_tas_session then
        ghost_tas_session:update_current_level_index(false)
    end

    if active_tas_session then
        active_tas_session:update_current_level_index(module.mode == common_enums.MODE.RECORD)
        if options.debug_print_load then
            print("on_pre_update_level_load: current_level_index="..tostring(active_tas_session.current_level_index))
        end
        if module.mode == common_enums.MODE.PLAYBACK and not active_tas_session.current_level_index then
            print("Warning: Loading level with no level data during playback. Switching to freeplay mode.")
            module.set_mode(common_enums.MODE.FREEPLAY)
        end
        if not force_level_snapshot and module.mode ~= common_enums.MODE.FREEPLAY and active_tas_session.current_level_index > 1
            and (not active_tas_session.current_level_data.snapshot or module.mode == common_enums.MODE.RECORD)
            and state.screen_next == SCREEN.LEVEL
        then
            -- Request a mid-run level snapshot of the upcoming level for the active TAS.
            local level_data = active_tas_session.current_level_data
            module.register_level_snapshot_request(function(level_snapshot)
                level_data.snapshot = level_snapshot
            end)
        end
    end

    if level_snapshot_request_count > 0 then
        -- Begin capturing a level snapshot for the upcoming level.
        if options.debug_print_load or options.debug_print_snapshot then
            print("on_pre_update_level_load: Starting capture of level snapshot for "..level_snapshot_request_count.." requests.")
        end
        -- Capture a state memory snapshot.
        captured_level_snapshot = {
            state_memory = introspection.create_snapshot(state, GAME_TYPES.StateMemory_LevelSnapshot)
        }
        if not (test_flag(state.quest_flags, QUEST_FLAG.RESET) and test_flag(state.quest_flags, QUEST_FLAG.SEEDED)) then
            -- Capture the adventure seed, unless the upcoming level is a reset for a seeded run. The current adventure seed is irrelevant for that scenario.
            local part_1, part_2 = get_adventure_seed()
            captured_level_snapshot.adventure_seed = { part_1, part_2 }
        end
    end
end

-- Called right before an update which is going to load a screen. The screen value itself might not change, since the game may be loading the same type of screen.
local function on_pre_screen_change()
    if force_level_snapshot then
        -- Apply a level snapshot instead of loading the original destination for this screen change.
        if force_level_snapshot.state_memory then
            -- Apply the state memory snapshot.
            if options.debug_print_load or options.debug_print_snapshot then
                print("on_pre_screen_change: Applying state memory from level snapshot.")
            end
            introspection.apply_snapshot(state, force_level_snapshot.state_memory, GAME_TYPES.StateMemory_LevelSnapshot)
        end
        if force_level_snapshot.adventure_seed then
            -- Apply the adventure seed.
            if options.debug_print_load or options.debug_print_snapshot then
                print("on_pre_screen_change: Applying adventure seed from level snapshot: "
                    ..common.adventure_seed_part_to_string(force_level_snapshot.adventure_seed[1]).."-"
                    ..common.adventure_seed_part_to_string(force_level_snapshot.adventure_seed[2]))
            end
            set_adventure_seed(table.unpack(force_level_snapshot.adventure_seed))
        end
    end
    if ((state.screen == SCREEN.LEVEL or state.screen == SCREEN.CAMP or state.screen == SCREEN.TRANSITION)
        and state.screen_next ~= SCREEN.OPTIONS and state.screen_next ~= SCREEN.DEATH)
        or state.screen == SCREEN.DEATH
    then
        -- This update is going to unload the current level, camp, or transition screen.
        reset_level_vars()
    end
    if state.screen ~= SCREEN.OPTIONS and (state.screen_next == SCREEN.LEVEL or state.screen_next == SCREEN.CAMP) then
        on_pre_update_level_load()
    end
    if module.mode ~= common_enums.MODE.FREEPLAY and state.screen_next ~= SCREEN.OPTIONS and state.screen_next ~= ON.LEVEL and state.screen_next ~= ON.CAMP
        and state.screen_next ~= SCREEN.TRANSITION and state.screen_next ~= SCREEN.SPACESHIP
    then
        -- TODO: This feels messy. Am I sure that I covered every case? This has some overlap with the screens I check in try_pause. I'm basically trying to determine whether I'm changing to a screen that will eventually lead back into a playable level. The check should be slightly different for camp and level TASes.
        print("Loading non-run screen. Switching to freeplay mode.")
        module.set_mode(common_enums.MODE.FREEPLAY)
    end
end

-- Called before level generation for any playable level or the camp. This callback occurs within a game update, and is the last place to manipulate the state memory before the level is generated. Notably, the state memory's player inventory data will be fully set and can be read or written here.
local function on_pre_level_gen()
    if options.debug_print_load then
        print("on_pre_level_gen")
    end

    if force_level_snapshot then
        if force_level_snapshot.state_memory then
            -- The `player_inventory` array is applied pre-update, but it may be modified by the game when the previous screen is unloaded. Reapply it here.
            if options.debug_print_load or options.debug_print_snapshot then
                print("on_pre_level_gen: Reapplying player inventory array snapshot.")
            end
            introspection.apply_snapshot(state.items.player_inventory, force_level_snapshot.state_memory.items.player_inventory,
                GAME_TYPES.Items.fields_by_name["player_inventory"].type)
        end
        if force_level_snapshot.pre_level_gen_screen_last then
            state.screen_last = force_level_snapshot.pre_level_gen_screen_last
        end
        if options.debug_print_load or options.debug_print_snapshot then
            print("on_pre_level_gen: Finished applying level snapshot.")
        end
        force_level_snapshot = nil
    end

    if captured_level_snapshot then
        -- Recapture the `player_inventory` array in the state memory. Earlier in this update, the game may have modified the player inventories based on the player entities that were unloaded in the previous screen. Assuming that updates are not affected by the contents of the `player_inventory` array before level generation, it should be safe to overwrite the `player_inventory` array that was captured pre-update.
        if options.debug_print_load or options.debug_print_snapshot then
            print("on_pre_level_gen: Recapturing player inventory array snapshot.")
        end
        captured_level_snapshot.state_memory.items.player_inventory =
            introspection.create_snapshot(state.items.player_inventory, GAME_TYPES.Items.fields_by_name["player_inventory"].type)
        if state.screen == SCREEN.CAMP then
            -- Capture the previous screen value. It affects how the player spawns into the camp.
            captured_level_snapshot.pre_level_gen_screen_last = state.screen_last
        end
        -- The level snapshot capture is finished. Fulfill all of the requests.
        for request_id, callback in pairs(level_snapshot_requests) do
            if level_snapshot_request_count > 1 then
                callback(common.deep_copy(captured_level_snapshot))
            else
                callback(captured_level_snapshot)
            end
            if options.debug_print_load or options.debug_print_snapshot then
                print("on_pre_level_gen: Fulfilled level snapshot request "..request_id..".")
            end
            level_snapshot_requests[request_id] = nil
            level_snapshot_request_count = level_snapshot_request_count - 1
        end
        captured_level_snapshot = nil
    end
end

-- Called after level generation for any playable level or the camp. This callback occurs within a game update, right before the game advances `state.loading` from 2 to 3.
local function on_post_level_gen()
    if module.mode == common_enums.MODE.FREEPLAY or not active_tas_session or not active_tas_session.current_level_index then
        return
    end

    if options.debug_print_load then
        print("on_post_level_gen: current_level_index="..active_tas_session.current_level_index)
    end

    active_tas_session.current_frame_index = 0
    if (module.mode == common_enums.MODE.PLAYBACK and options.pause_playback_on_level_start) or (module.mode == common_enums.MODE.RECORD and options.pause_recording_on_level_start) then
        need_pause = true
    end

    active_tas_session.current_level_data.metadata = {
        world = state.world,
        level = state.level,
        theme = state.theme
    }

    for player_index, player in ipairs(active_tas_session.current_level_data.players) do
        local player_ent = get_player(player_index, true)
        local actual_pos
        if player_ent then
            local x, y, l = get_position(player_ent.uid)
            actual_pos = { x = x, y = y, l = l }
        end
        if module.mode == common_enums.MODE.RECORD then
            player.start_position = actual_pos
        elseif module.mode == common_enums.MODE.PLAYBACK then
            if player.start_position then
                check_position_desync(player_index, player.start_position, actual_pos)
            else
                player.start_position = actual_pos
            end
        end
    end
end

local function on_transition()
    if options.transition_skip and not (module.mode == common_enums.MODE.PLAYBACK and options.presentation_enabled) then
        -- The transition screen can't be skipped entirely. It needs to be loaded in order for pet health to be applied to players.
        if options.debug_print_load then
            print("on_transition: Skipping transition screen.")
        end
        state.screen_next = SCREEN.LEVEL
        state.fadeout = 1 -- The fade-out will finish on the next update and the transition screen will unload.
        state.fadein = TRANSITION_FADE_FRAMES
        state.loading = 1
    else
        transition_frame = 0
        transition_last_get_frame_seen = get_frame()
    end
end

local function get_cutscene_input(player_index, logic_cutscene, last_frame, skip_frame, skip_input_id)
    if player_index ~= state.items.leader then
        -- Only the leader player can skip the cutscene.
        return INPUTS.NONE
    elseif logic_cutscene.timer == last_frame then
        -- The cutscene will end naturally during this update. Defer to normal input handling.
        return nil
    elseif logic_cutscene.timer == skip_frame - 1 then
        -- The skip button needs to be pressed one frame early. The cutscene is skipped when the button is released on the next frame.
        if options.debug_print_input then
            print("get_cutscene_input: Sending cutscene skip input: frame="..active_tas_session.current_level_index.."-"..active_tas_session.current_frame_index.." timer="..logic_cutscene.timer)
        end
        return common_enums.SKIP_INPUT:value_by_id(skip_input_id).input
    elseif logic_cutscene.timer == skip_frame then
        if options.debug_print_input then
            print("get_cutscene_input: Deferring to recorded input: frame="..active_tas_session.current_level_index.."-"..active_tas_session.current_frame_index.." timer="..logic_cutscene.timer)
        end
        return nil
    else
        -- Prevent the player from pressing any buttons and interfering with the cutscene.
        return INPUTS.NONE
    end
end

-- Called before every game update in a playable level that is part of the active TAS.
local function on_pre_update_level()
    reset_frame_vars()
    pre_update_loading = state.loading
    pre_update_time_level = state.time_level
    pre_update_cutscene_active = state.logic.olmec_cutscene ~= nil or state.logic.tiamat_cutscene ~= nil

    module.validate_current_frame()
    module.validate_playback_target()

    if module.mode ~= common_enums.MODE.FREEPLAY and (state.loading == 0 or state.loading == 3) then
        -- Submit the desired inputs for the upcoming update. The script doesn't know whether this update will actually execute player inputs. If it does execute them, then it will execute the submitted inputs. If it doesn't execute them, such as due to the game being paused, then nothing will happen and the script can try again on the next update.
        for player_index = 1, active_tas_session.tas:get_player_count() do
            local input
            -- Record and playback modes should both automatically skip cutscenes.
            if state.logic.olmec_cutscene then
                input = get_cutscene_input(player_index, state.logic.olmec_cutscene, module.OLMEC_CUTSCENE_LAST_FRAME, active_tas_session.tas.olmec_cutscene_skip_frame, active_tas_session.tas.olmec_cutscene_skip_input)
            elseif state.logic.tiamat_cutscene then
                input = get_cutscene_input(player_index, state.logic.tiamat_cutscene, module.TIAMAT_CUTSCENE_LAST_FRAME, active_tas_session.tas.tiamat_cutscene_skip_frame, active_tas_session.tas.tiamat_cutscene_skip_input)
            end
            if not input and module.mode == common_enums.MODE.PLAYBACK then
                -- Only playback mode should submit normal gameplay inputs.
                if active_tas_session.current_level_data.frames[active_tas_session.current_frame_index + 1] then
                    -- Submit the input from the upcoming frame.
                    input = active_tas_session.current_level_data.frames[active_tas_session.current_frame_index + 1].players[player_index].input
                else
                    -- There is no upcoming frame stored for the current level. The level should have ended during the previous update.
                    set_level_end_desync()
                    module.set_mode(common_enums.MODE.FREEPLAY)
                end
            end
            if input then
                input = input & SUPPORTED_INPUT_MASK
                state.player_inputs.player_slots[player_index].buttons = input
                state.player_inputs.player_slots[player_index].buttons_gameplay = input
                if options.debug_print_frame or options.debug_print_input then
                    -- TODO: This is super spammy when paused.
                    --print("on_pre_update_level: Sending input for upcoming frame: frame="..active_tas_session.current_level_index.."-"..(active_tas_session.current_frame_index + 1).." input="..common.input_to_string(input))
                end
            end
        end
    end
end

-- Called before every game update in a transition while an active TAS exists.
local function on_pre_update_transition()
    if state.loading == 1 or state.loading == 2 or module.mode == common_enums.MODE.FREEPLAY then
        return
    end
    -- Transitions have no dedicated frame counter, so `get_frame()` has to be used. `get_frame()` increments at some point between updates, not during updates like most state memory variables. Based on this counting system, the frame increments to 1 after the first fade-in update, and then doesn't change for the entire remainder of the fade-in. Inputs are processed during the final update of the fade-in, which is still frame 1. If an exit input is seen during this final update, then the fade-out is started in that same update. The frame increments one more time after the update that starts the fade-out, and the character can be seen stepping forward for that one frame. This is the same behavior that occurs in normal gameplay by holding an exit input as the transition screen loads. Providing the exit input on later frames has a delay before the fade-out starts because the transition UI panel has to scroll off screen first.
    -- TODO: Test for entering sunken city, entering/exiting duat, and CO transitions.
    local this_frame = get_frame()
    if transition_last_get_frame_seen ~= this_frame then
        transition_last_get_frame_seen = this_frame
        transition_frame = transition_frame + 1
        if options.debug_print_frame then
            print("on_pre_update_transition: transition_frame="..transition_frame)
        end
    end
    if active_tas_session.tas.transition_exit_frame ~= -1 then
        for player_index = 1, active_tas_session.tas:get_player_count() do
            -- By default, suppress inputs from every player.
            state.player_inputs.player_slots[player_index].buttons = INPUTS.NONE
            state.player_inputs.player_slots[player_index].buttons_gameplay = INPUTS.NONE
        end
        if transition_frame >= active_tas_session.tas.transition_exit_frame then
            -- Have player 1 provide the transition exit input. The exit is triggered during the first update where the input is seen, not when it's released.
            if options.debug_print_input then
                print("on_pre_update_transition: Submitting transition exit input.")
            end
            state.player_inputs.player_slots[1].buttons = INPUTS.JUMP
            state.player_inputs.player_slots[1].buttons_gameplay = INPUTS.JUMP
        end
    end
end

-- TODO: Review and clean up the various "active_tas_session", "current_level_index", "current_frame_index", "state.loading", and "MODE.FREEPLAY" checks in these pre-update functions. Some of them are probably redundant.
local function on_pre_update()
    if state.loading == 2 then
        on_pre_screen_change()
    else
        if not active_tas_session then
            return
        end
        -- TODO: I would like to unify some behavior for levels and transitions. I could do this if I get them to both use the current_frame_index variable.
        if state.screen == SCREEN.LEVEL or state.screen == SCREEN.CAMP then
            -- TODO: current_level_index won't be set if I'm not on one of these screens. Do I even need to check the screens?
            if active_tas_session.current_level_index then
                on_pre_update_level()
            end
        elseif state.screen == SCREEN.TRANSITION then
            on_pre_update_transition()
        end
    end
end

local function handle_playback_target()
    if module.validate_playback_target() and active_tas_session.current_level_index == module.playback_target_level and active_tas_session.current_frame_index == module.playback_target_frame then
        -- Current frame is the playback target.
        if options.playback_target_pause then
            if options.debug_print_pause then
                prinspect("handle_playback_target: Reached playback target pause", get_frame())
            end
            need_pause = true
        end
        local new_mode = common_enums.PLAYBACK_TARGET_MODE:value_by_id(options.playback_target_mode).mode
        if new_mode == common_enums.MODE.RECORD then
            if options.debug_print_mode then
                print("Playback target ("..module.playback_target_level.."-"..module.playback_target_frame..") reached. Switching to record mode.")
            end
            module.set_mode(common_enums.MODE.RECORD)
        elseif new_mode == common_enums.MODE.FREEPLAY or (active_tas_session.current_level_index == #active_tas_session.tas.levels and active_tas_session.current_frame_index == #active_tas_session.current_level_data.frames) then
            if options.debug_print_mode then
                print("Playback target ("..module.playback_target_level.."-"..module.playback_target_frame..") reached. Switching to freeplay mode.")
            end
            module.set_mode(common_enums.MODE.FREEPLAY)
        else
            if options.debug_print_mode then
                print("Playback target ("..module.playback_target_level.."-"..module.playback_target_frame..") reached. Staying in playback mode.")
            end
            module.playback_target_level, module.playback_target_frame = active_tas_session.tas:get_end_indices()
        end
    end
end

-- Called after every game update where the current frame index was incremented.
local function on_post_update_frame_advanced()
    if options.debug_print_frame or options.debug_print_input then
        print("on_post_update_frame_advanced: frame="..active_tas_session.current_level_index.."-"..active_tas_session.current_frame_index.." input="..common.input_to_string(state.player_inputs.player_slots[1].buttons_gameplay))
    end

    local current_frame_data = active_tas_session.current_level_data.frames[active_tas_session.current_frame_index]
    if module.mode == common_enums.MODE.RECORD then
        -- Only record mode can create new frames. Playback mode should only be active during frames that already exist.
        if options.record_frame_write_type == "overwrite" then
            if not current_frame_data then
                current_frame_data = active_tas_session.tas:create_frame_data()
                active_tas_session.current_level_data.frames[active_tas_session.current_frame_index] = current_frame_data
            end
        elseif options.record_frame_write_type == "insert" then
            current_frame_data = active_tas_session.tas:create_frame_data()
            table.insert(active_tas_session.current_level_data.frames, active_tas_session.current_frame_index, current_frame_data)
        end
    end

    for player_index, player in ipairs(current_frame_data.players) do
        local player_ent = get_player(player_index, true)
        local actual_pos
        if player_ent then
            local x, y, l = get_position(player_ent.uid)
            actual_pos = { x = x, y = y, l = l }
        end
        if module.mode == common_enums.MODE.RECORD then
            -- Record the current player inputs for the frame that just executed.
            local input = state.player_inputs.player_slots[player_index].buttons_gameplay & SUPPORTED_INPUT_MASK
            if options.debug_print_frame or options.debug_print_input then
                print("on_post_update: Recording input: frame="..active_tas_session.current_level_index.."-"..active_tas_session.current_frame_index
                    .." player="..player_index.." input="..common.input_to_string(input))
            end
            player.input = input
            player.position = actual_pos
        elseif module.mode == common_enums.MODE.PLAYBACK then
            local expected_pos = player.position
            if expected_pos then
                check_position_desync(player_index, expected_pos, actual_pos)
            else
                -- No player positions are stored for this frame. Store the current positions.
                player.position = actual_pos
            end
        end
    end

    if module.mode == common_enums.MODE.PLAYBACK then
        handle_playback_target()
    end
end

-- TODO: Review and clean up the various "active_tas_session", "current_level_index", "current_frame_index", "state.loading", and "MODE.FREEPLAY" checks in these post-update functions. Some of them are probably redundant.
local function on_post_update()
    if module.mode ~= common_enums.MODE.FREEPLAY and active_tas_session and active_tas_session.current_level_index and active_tas_session.current_frame_index then
        -- Check whether this update advanced the TAS by one frame.
        -- TODO: This check feels messy. Is there a more concise way that I can check whether the previous update should advance the TAS by one frame?
        -- TODO: What does time_level do for loading 0->1? Should the TAS actually advance one frame? Can non-exiting players perform an action on this frame?
        if ((pre_update_loading == 3 and state.loading == 0) or (pre_update_loading == 0 and (state.loading == 0 or state.loading == 1)))
            and (pre_update_time_level ~= state.time_level or (pre_update_cutscene_active and not state.logic.olmec_cutscene and not state.logic.tiamat_cutscene))
        then
            active_tas_session.current_frame_index = active_tas_session.current_frame_index + 1
            on_post_update_frame_advanced()
        elseif active_tas_session.current_frame_index == 0 and module.mode == common_enums.MODE.PLAYBACK then
            -- Handle a possible frame 0 playback target.
            handle_playback_target()
        end
    end

    -- TODO: Should I call this at the start of on_pre_update instead?
    try_pause()
end

function module.initialize()
    module.reset_session_vars()
    set_callback(on_pre_update, ON.PRE_UPDATE)
    set_callback(on_post_update, ON.POST_UPDATE)
    set_callback(on_pre_level_gen, ON.PRE_LEVEL_GENERATION)
    set_callback(on_post_level_gen, ON.POST_LEVEL_GENERATION)
    set_callback(on_transition, ON.TRANSITION)
    register_console_command("set_desync_callback", set_desync_callback)
    register_console_command("clear_desync_callback", clear_desync_callback)
end

return module
