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
-- Target level index for playback. When in playback mode, this field should not be `nil`.
module.playback_target_level = nil
-- Target frame index for playback. When in playback mode, this field should not be `nil`. A value of 0 means that the playback target is reached as soon at the target level is loaded.
module.playback_target_frame = nil
module.playback_force_full_run = nil
module.playback_force_current_frame = nil
local need_pause
local force_level_snapshot
-- The active TAS level index currently being warped to. This is cleared at the end of screen change updates.
local warp_level_index

-- The value of `get_frame()` at the end of the most recent update. The game increments `get_frame()` at some point between updates, not during updates.
local prev_get_frame
local pre_update_loading
local pre_update_time_level
local pre_update_cutscene_active

local level_snapshot_requests = {}
local level_snapshot_request_count = 0
local level_snapshot_request_next_id = 1
local captured_level_snapshot = nil

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
    if active_tas_session then
        active_tas_session:unset_current_level()
    end
    if ghost_tas_session then
        ghost_tas_session:unset_current_level()
    end
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
    end
    if state.screen == SCREEN.OPTIONS and common_enums.TASABLE_SCREEN[state.screen_last] then
        -- Don't pause in the options screen.
        return
    end
    if not common_enums.TASABLE_SCREEN[state.screen] then
        -- Cancel the pause entirely.
        need_pause = false
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
    warp_level_index = 1

    return true
end

-- Forces the game to warp to a level initialized with the given level snapshot. This triggers the game to start unloading the current screen, and then it hooks into the loading process at specific points to apply the snapshot.
local function trigger_level_snapshot_warp(level_snapshot, level_index)
    trigger_warp_unload()
    active_tas_session.desync = nil
    force_level_snapshot = level_snapshot
    warp_level_index = level_index
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
                trigger_level_snapshot_warp(tas.start_full, 1)
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
    trigger_level_snapshot_warp(level_snapshot, level_index)
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
                    active_tas_session.tas:remove_frames_after(active_tas_session.current_level_index, active_tas_session.current_frame_index)
                elseif options.record_frame_clear_action == "remaining_run" then
                    active_tas_session.tas:remove_frames_after(active_tas_session.current_level_index, active_tas_session.current_frame_index)
                    active_tas_session.tas:remove_levels_after(active_tas_session.current_level_index)
                end
            end
        end

    elseif new_mode == common_enums.MODE.PLAYBACK then
        local need_load = false
        local load_level_index = -1

        local can_use_current_frame = not module.playback_force_full_run and module.mode ~= common_enums.MODE.FREEPLAY
            and (module.playback_force_current_frame or options.playback_from == module.PLAYBACK_FROM.NOW_OR_LEVEL or options.playback_from == module.PLAYBACK_FROM.NOW)
            and (active_tas_session.current_level_index and ((module.playback_target_level == active_tas_session.current_level_index and (not active_tas_session.current_frame_index or module.playback_target_frame >= active_tas_session.current_frame_index)) or module.playback_target_level > active_tas_session.current_level_index))

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
    local unset_current_level = false
    local message
    if active_tas_session.current_level_index then
        if active_tas_session.current_level_index > active_tas_session.tas:get_end_level_index() then
            message = "Current level is later than end of TAS ("..active_tas_session.tas:get_end_level_index().."-"..active_tas_session.tas:get_end_frame_index()..")."
            unset_current_level = true
        elseif active_tas_session.current_tasable_screen.record_frames and active_tas_session.current_frame_index
            and active_tas_session.current_frame_index > active_tas_session.tas:get_end_frame_index(active_tas_session.current_level_index)
        then
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
        if unset_current_level then
            active_tas_session:unset_current_level()
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
        message = "Target is later than end of TAS ("..#active_tas_session.tas:get_end_level_index().."-"..active_tas_session.tas:get_end_frame_index()..")."
    elseif module.playback_target_frame > active_tas_session.tas:get_end_frame_index(module.playback_target_level) then
        message = "Target is later than end of level ("..module.playback_target_level.."-"..active_tas_session.tas:get_end_frame_index(module.playback_target_level)..")."
    elseif (state.loading == 0 or state.loading == 3) and (active_tas_session.current_level_index > module.playback_target_level
        or (active_tas_session.current_level_index == module.playback_target_level and active_tas_session.current_frame_index > module.playback_target_frame))
    then
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

-- Called right before an update which is going to load a TASable screen.
local function on_pre_update_load_tasable_screen()
    if options.debug_print_load then
        print("on_pre_update_load_tasable_screen: "..state.screen_next)
    end

    if common_enums.TASABLE_SCREEN[state.screen_next].can_snapshot then
        if not force_level_snapshot and not warp_level_index and (module.mode == common_enums.MODE.RECORD
            or (module.mode == common_enums.MODE.PLAYBACK and not active_tas_session.tas.levels[active_tas_session.current_level_index + 1].snapshot))
        then
            -- Request a level snapshot of the upcoming level for the active TAS.
            module.register_level_snapshot_request(function(level_snapshot)
                -- The snapshot request will be fulfilled before the TAS session knows which level it belongs to. Temporarily store it until a TAS level is ready for it.
                active_tas_session.stored_level_snapshot = level_snapshot
            end)
        end

        if level_snapshot_request_count > 0 then
            -- Begin capturing a level snapshot for the upcoming level.
            if options.debug_print_load or options.debug_print_snapshot then
                print("on_pre_update_load_tasable_screen: Starting capture of level snapshot for "..level_snapshot_request_count.." requests.")
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
end

-- Called right before an update which is going to load a screen. The screen value itself might not change since the game may be loading the same type of screen. For screens that include level generation, this is the last place to read or write the adventure seed. Between this function and `on_pre_level_gen`, the game will unload the current screen and increment the adventure seed to generate PRNG for the upcoming level generation.
local function on_pre_update_load_screen()
    if force_level_snapshot then
        -- Apply a level snapshot instead of loading the original destination for this screen change.
        if force_level_snapshot.state_memory then
            -- Apply the state memory snapshot.
            if options.debug_print_load or options.debug_print_snapshot then
                print("on_pre_update_load_screen: Applying state memory from level snapshot.")
            end
            introspection.apply_snapshot(state, force_level_snapshot.state_memory, GAME_TYPES.StateMemory_LevelSnapshot)
        end
        if force_level_snapshot.adventure_seed then
            -- Apply the adventure seed.
            if options.debug_print_load or options.debug_print_snapshot then
                print("on_pre_update_load_screen: Applying adventure seed from level snapshot: "
                    ..common.adventure_seed_part_to_string(force_level_snapshot.adventure_seed[1]).."-"
                    ..common.adventure_seed_part_to_string(force_level_snapshot.adventure_seed[2]))
            end
            set_adventure_seed(table.unpack(force_level_snapshot.adventure_seed))
        end
    end
    if state.screen_next == SCREEN.OPTIONS or state.screen == SCREEN.OPTIONS then
        -- This update is either entering or exiting the options screen. This does not change the underlying screen and is not a relevant event for this script.
        return
    end
    if common_enums.TASABLE_SCREEN[state.screen_next] then
        on_pre_update_load_tasable_screen()
    end
end

-- Called before level generation for the `CAMP` and `LEVEL` screens. This callback occurs within a game update where `state.loading` is initially 2. The previous screen has been unloaded at this point. This is the last place to manipulate the state memory before the level is generated. The state memory's player inventory data is fully set and can be read or written here. Shortly after level generation, the game will advance `state.loading` from 2 to 3.
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

local function get_cutscene_input(player_index, logic_cutscene, last_frame)
    if active_tas_session.current_level_data.cutscene_skip_frame_index == -1 then
        -- The cutscene should not be skipped.
        return INPUTS.NONE
    elseif player_index ~= state.items.leader then
        -- Only the leader player can skip the cutscene.
        return INPUTS.NONE
    elseif logic_cutscene.timer == last_frame then
        -- The cutscene will end naturally during this update. Defer to normal input handling.
        return nil
    elseif logic_cutscene.timer == active_tas_session.current_level_data.cutscene_skip_frame_index - 1 then
        -- The skip button needs to be pressed one frame early. The cutscene is skipped when the button is released on the next frame.
        if options.debug_print_input then
            print("get_cutscene_input: Sending cutscene skip input: frame="..active_tas_session.current_level_index.."-"..active_tas_session.current_frame_index.." timer="..logic_cutscene.timer)
        end
        return common_enums.SKIP_INPUT:value_by_id(active_tas_session.current_level_data.cutscene_skip_input).input
    elseif logic_cutscene.timer == active_tas_session.current_level_data.cutscene_skip_frame_index then
        if options.debug_print_input then
            print("get_cutscene_input: Deferring to recorded input: frame="..active_tas_session.current_level_index.."-"..active_tas_session.current_frame_index.." timer="..logic_cutscene.timer)
        end
        return nil
    else
        -- Prevent the player from pressing any buttons and interfering with the cutscene.
        return INPUTS.NONE
    end
end

-- Called before every game update in a TASable screen, excluding the update which loads the screen.
local function on_pre_update_tasable_screen()
    if (state.loading ~= 0 and state.loading ~= 3) or module.mode == common_enums.MODE.FREEPLAY
        or not active_tas_session or not active_tas_session.current_level_index
    then
        return
    end

    module.validate_current_frame()
    module.validate_playback_target()

    if module.mode == common_enums.MODE.FREEPLAY then
        return
    end

    -- Gather player inputs from the TAS to submit for the upcoming update.
    local inputs
    if active_tas_session.current_tasable_screen.record_frames then
        inputs = {}
        for player_index = 1, active_tas_session.tas:get_player_count() do
            local input
            -- Record and playback modes should both automatically skip cutscenes.
            if state.logic.olmec_cutscene then
                input = get_cutscene_input(player_index, state.logic.olmec_cutscene, module.OLMEC_CUTSCENE_LAST_FRAME)
            elseif state.logic.tiamat_cutscene then
                input = get_cutscene_input(player_index, state.logic.tiamat_cutscene, module.TIAMAT_CUTSCENE_LAST_FRAME)
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
            inputs[player_index] = input
        end
    elseif active_tas_session.current_level_data.metadata.screen == SCREEN.TRANSITION then
        inputs = {}
        if active_tas_session.current_level_data.transition_exit_frame_index ~= -1 then
            for player_index = 1, active_tas_session.tas:get_player_count() do
                -- By default, suppress inputs from every player.
                inputs[player_index] = INPUTS.NONE
            end
            if active_tas_session.current_frame_index + 1 >= active_tas_session.current_level_data.transition_exit_frame_index then
                -- Have player 1 provide the transition exit input. The exit is triggered during the first update where the input is seen, not when it's released.
                if options.debug_print_input then
                    print("on_pre_update_tasable_screen: Submitting transition exit input.")
                end
                inputs[1] = INPUTS.JUMP
            end
        end
    end
    -- Note: There is nothing to do on the SPACESHIP screen except wait for it to end.

    if inputs then
        -- Submit the desired inputs for the upcoming update. The script doesn't know whether this update will actually process player inputs. If it does process them, then it will use the submitted inputs. If it doesn't process them, such as due to the game being paused, then nothing will happen and the script can try again on the next update.
        for player_index = 1, active_tas_session.tas:get_player_count() do
            local input = inputs[player_index]
            if input then
                input = input & SUPPORTED_INPUT_MASK
                state.player_inputs.player_slots[player_index].buttons = input
                state.player_inputs.player_slots[player_index].buttons_gameplay = input
            end
        end
    end
end


local function on_pre_update()
    pre_update_loading = state.loading
    pre_update_time_level = state.time_level
    pre_update_cutscene_active = state.logic.olmec_cutscene ~= nil or state.logic.tiamat_cutscene ~= nil

    if state.loading == 2 then
        on_pre_update_load_screen()
    elseif common_enums.TASABLE_SCREEN[state.screen] then
        on_pre_update_tasable_screen()
    end
end

local function handle_playback_target()
    if not module.validate_playback_target() or active_tas_session.current_level_index ~= module.playback_target_level
        or (active_tas_session.current_tasable_screen.record_frames and active_tas_session.current_frame_index ~= module.playback_target_frame)
    then
        return
    end

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
    elseif new_mode == common_enums.MODE.FREEPLAY or active_tas_session.tas:is_end_or_later(active_tas_session.current_level_index, active_tas_session.current_frame_index) then
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

-- Called right after an update which loaded a screen.
local function on_post_update_load_screen()
    if state.screen == SCREEN.OPTIONS or state.screen_last == SCREEN.OPTIONS then
        -- This update either entered or exited the options screen. This did not change the underlying screen and is not a relevant event for this script.
        return
    end
    if options.debug_print_load then
        print("on_post_update_load_screen: "..state.screen_last.." -> "..state.screen)
    end

    if active_tas_session then
        if not common_enums.TASABLE_SCREEN[state.screen] then
            -- The new screen is not TASable.
            active_tas_session:unset_current_level()
            if module.mode ~= common_enums.MODE.FREEPLAY then
                print("Loaded non-TASable screen. Switching to freeplay mode.")
                module.set_mode(common_enums.MODE.FREEPLAY)
            end
        elseif warp_level_index then
            -- This screen change was a warp.
            if not active_tas_session:set_current_level(warp_level_index) then
                if module.mode == common_enums.MODE.FREEPLAY then
                    print("Warning: Loaded unexpected screen when warping to level index "..warp_level_index..".")
                else
                    if module.mode == common_enums.MODE.RECORD and warp_level_index == #active_tas_session.tas.levels + 1 then
                        active_tas_session:create_end_level()
                    else
                        print("Warning: Loaded unexpected screen when warping to level index "..warp_level_index..". Switching to freeplay mode.")
                        module.set_mode(common_enums.MODE.FREEPLAY)
                    end
                end
            end
        elseif active_tas_session.current_level_index then
            -- This screen change was not a warp and the previous level index is known.
            local prev_level_index = active_tas_session.current_level_index
            if not active_tas_session:set_current_level(prev_level_index + 1) then
                if module.mode == common_enums.MODE.FREEPLAY then
                    active_tas_session:find_current_level()
                else
                    if module.mode == common_enums.MODE.RECORD and prev_level_index == #active_tas_session.tas.levels then
                        active_tas_session:create_end_level()
                    else
                        print("Warning: Loaded unexpected screen after screen change from level index "..prev_level_index..". Switching to freeplay mode.")
                        module.set_mode(common_enums.MODE.FREEPLAY)
                    end
                end
            end
        else
            -- This screen change was not a warp and the previous level index is not known.
            if module.mode == common_enums.MODE.FREEPLAY then
                active_tas_session:find_current_level()
            else
                -- Note: This case should not be possible. Playback and recording should always know either the previous level index or the new level index.
                print("Warning: Loaded new screen during playback or recording with unknown previous level index and unknown new level index. Switching to freeplay mode.")
                module.set_mode(common_enums.MODE.FREEPLAY)
            end
        end
        if options.debug_print_load then
            print("on_post_update_load_screen: Current TAS level updated to "..tostring(active_tas_session.current_level_index)..".")
        end
        if module.mode ~= common_enums.MODE.FREEPLAY then
            if active_tas_session.current_tasable_screen.count_frames then
                active_tas_session.current_frame_index = 0
            end
            if active_tas_session.current_tasable_screen.record_frames then
                for player_index, player in ipairs(active_tas_session.current_level_data.players) do
                    local player_ent = get_player(player_index, true)
                    local actual_pos
                    if player_ent then
                        local x, y, l = get_position(player_ent.uid)
                        actual_pos = { x = x, y = y, l = l }
                    end
                    if module.mode == common_enums.MODE.RECORD or not player.start_position then
                        player.start_position = actual_pos
                    else
                        check_position_desync(player_index, player.start_position, actual_pos)
                    end
                end
            end
            if active_tas_session.current_tasable_screen.can_snapshot and active_tas_session.stored_level_snapshot then
                active_tas_session.current_level_data.snapshot = active_tas_session.stored_level_snapshot
                if options.debug_print_load or options.debug_print_snapshot then
                    print("on_post_update_load_screen: Transferred stored level snapshot into TAS level "..active_tas_session.current_level_index..".")
                end
            end
            if active_tas_session.current_tasable_screen.record_frames
                and ((module.mode == common_enums.MODE.PLAYBACK and options.pause_playback_on_level_start)
                or (module.mode == common_enums.MODE.RECORD and options.pause_recording_on_level_start))
            then
                need_pause = true
            end
        end
        if active_tas_session.stored_level_snapshot then
            active_tas_session.stored_level_snapshot = nil
        end
    end

    if ghost_tas_session then
        ghost_tas_session:unset_current_level()
        if common_enums.TASABLE_SCREEN[state.screen] then
            -- Check whether the active TAS's level is also the ghost TAS's level. If not, then search for any valid ghost TAS level.
            if not active_tas_session or not active_tas_session.current_level_index
                or not ghost_tas_session:set_current_level(active_tas_session.current_level_index)
            then
                ghost_tas_session:find_current_level()
            end
        end
    end

    if warp_level_index then
        warp_level_index = nil
    end

    if state.screen == SCREEN.TRANSITION and options.transition_skip and not (module.mode == common_enums.MODE.PLAYBACK and options.presentation_enabled) then
        -- The transition screen couldn't be skipped entirely. It needed to be loaded in order for pet health to be applied to players. Now it can be immediately unloaded.
        if options.debug_print_load then
            print("on_post_update_load_screen: Skipping transition screen.")
        end
        state.screen_next = SCREEN.LEVEL
        state.fadeout = 1 -- The fade-out will finish on the next update and the transition screen will unload.
        state.fadein = TRANSITION_FADE_FRAMES
        state.loading = 1
    end
end

-- Called after every game update where the current frame index was incremented.
local function on_post_update_frame_advanced()
    if options.debug_print_frame or options.debug_print_input then
        print("on_post_update_frame_advanced: frame="..active_tas_session.current_level_index.."-"..active_tas_session.current_frame_index.." input="..common.input_to_string(state.player_inputs.player_slots[1].buttons_gameplay))
    end

    if active_tas_session.current_tasable_screen.record_frames then
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
    end

    if module.mode == common_enums.MODE.PLAYBACK then
        handle_playback_target()
    end
end

local function on_post_update()
    if pre_update_loading == 2 then
        on_post_update_load_screen()
    elseif module.mode ~= common_enums.MODE.FREEPLAY and active_tas_session and active_tas_session.current_level_index then
        -- Check whether this update executed a TASable frame.
        local advanced = false
        if active_tas_session.current_tasable_screen.record_frames then
            advanced = ((pre_update_loading == 3 and state.loading == 0) or (pre_update_loading == 0 and (state.loading == 0 or state.loading == 1)))
                and (pre_update_time_level ~= state.time_level or (pre_update_cutscene_active and not state.logic.olmec_cutscene and not state.logic.tiamat_cutscene))
        elseif active_tas_session.current_level_data.metadata.screen == SCREEN.TRANSITION then
            -- Transitions have no dedicated frame counter, so `get_frame()` has to be used. `get_frame()` increments at some point between updates, not during updates like most state memory variables. Based on this counting system, the frame increments to 1 after the first fade-in update, and then doesn't change for the entire remainder of the fade-in. Inputs are processed during the final update of the fade-in, which is still frame 1. If an exit input is seen during this final update, then the fade-out is started in that same update. The frame increments one more time after the update that starts the fade-out, and the character can be seen stepping forward for that one frame. This is the same behavior that occurs in normal gameplay by holding the exit input while the transition screen fades in. Providing the exit input on later frames has a delay before the fade-out starts because the transition UI panel has to scroll off screen first.
            advanced = (state.loading == 0 or state.loading == 3) and prev_get_frame ~= get_frame()
        end
        if advanced then
            active_tas_session.current_frame_index = active_tas_session.current_frame_index + 1
            on_post_update_frame_advanced()
        elseif module.mode == common_enums.MODE.PLAYBACK
            and (not active_tas_session.current_tasable_screen.record_frames or active_tas_session.current_frame_index == 0)
        then
            -- Handle a possible frame 0 playback target, or a playback target on a screen that can't target a specific frame.
            handle_playback_target()
        end
    end

    try_pause()

    prev_get_frame = get_frame()
end

function module.initialize()
    module.reset_session_vars()
    set_callback(on_pre_update, ON.PRE_UPDATE)
    set_callback(on_post_update, ON.POST_UPDATE)
    set_callback(on_pre_level_gen, ON.PRE_LEVEL_GENERATION)
    register_console_command("set_desync_callback", set_desync_callback)
    register_console_command("clear_desync_callback", clear_desync_callback)
end

return module
