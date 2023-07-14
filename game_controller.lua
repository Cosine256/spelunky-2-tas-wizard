local module = {}

local common = require("common")
local common_enums = require("common_enums")
local introspection = require("introspection")
local GAME_TYPES = introspection.register_types({}, require("raw_game_types"))
local TasSession = require("tas_session")

local POSITION_DESYNC_EPSILON = 0.0000000001
-- Vanilla frames used to fade into and out of the transition screen.
local TRANSITION_FADE_FRAMES = 18
local WARP_FADE_OUT_FRAMES = 5

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

-- TODO: Rename to active_tas_session?
module.current = nil
module.ghost_tas_session = nil
local desync_callbacks = {}
local next_callback_id = 0

module.mode = common_enums.MODE.FREEPLAY
module.playback_target_level = -1
module.playback_target_frame = -1
module.playback_force_full_run = nil
module.playback_force_current_frame = nil
module.desync_level = -1
module.desync_frame = -1
local need_pause
local load_level_snapshot_index
local force_level_gen_screen_last

--[[
Index of the current frame in a run, or -1 if undefined. The "current frame" is the frame that the game most recently executed, and its value is incremented after an update where a frame of gameplay occurred. A value of 0 means that no gameplay frames have occurred in the current level. This index is defined if and only if all of the following conditions are met:
    The current TAS's `current_level_index` is defined.
    The script has not been in freeplay mode at any point during the level.
    The current TAS has not been replaced at any point during the level.
    The current TAS contains frame data for this index.
]]
module.current_frame_index = nil
-- The number of frames that have executed on the transition screen, based on `get_frame()`.
local transition_frame
local transition_last_get_frame_seen

local pre_update_loading
local pre_update_time_level
local pre_update_cutscene_active

function module.set_tas(tas)
    module.reset_session_vars()
    if tas then
        module.current = TasSession:new(tas)
        module.current:update_current_level_index()
    else
        module.current = nil
    end
end

function module.set_ghost_tas(tas)
    if tas then
        module.ghost_tas_session = TasSession:new(tas)
        module.ghost_tas_session:update_current_level_index()
    else
        module.ghost_tas_session = nil
    end
end

-- Reset variables with the scope of a single frame.
local function reset_frame_vars()
    pre_update_loading = -1
    pre_update_time_level = -1
    pre_update_cutscene_active = false
end

-- Reset variables with the scope of a single level, camp, or transition.
local function reset_level_vars()
    if module.current then
        module.current:clear_current_level_index()
    end
    if module.ghost_tas_session then
        module.ghost_tas_session:clear_current_level_index()
    end
    module.current_frame_index = -1
    transition_frame = nil
    transition_last_get_frame_seen = nil
    reset_frame_vars()
end

-- Reset the entire TAS session by resetting all session and level variables. Does not unload the current TAS.
-- TODO: "session" is a confusing name since there are also TasSession objects.
function module.reset_session_vars()
    module.mode = common_enums.MODE.FREEPLAY
    module.playback_target_level = -1
    module.playback_target_frame = -1
    module.playback_force_full_run = false
    module.playback_force_current_frame = false
    module.desync_level = -1
    module.desync_frame = -1
    need_pause = false
    load_level_snapshot_index = nil -- TODO: Why not -1? Why not nil for the others?
    force_level_gen_screen_last = nil
    reset_level_vars()
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
    if module.desync_level ~= -1 then
        return
    end
    if not actual_pos or math.abs(expected_pos.x - actual_pos.x) > POSITION_DESYNC_EPSILON
            or math.abs(expected_pos.y - actual_pos.y) > POSITION_DESYNC_EPSILON then
        module.desync_level = module.current.current_level_index
        module.desync_frame = module.current_frame_index
        if actual_pos then
            print("Desynchronized on frame "..module.desync_level.."-"..module.desync_frame..": Actual position differs from expected position:")
            print("    Player: "..player_index)
            print("    Expected: x="..expected_pos.x.." y="..expected_pos.y)
            print("    Actual: x="..actual_pos.x.." y="..actual_pos.y)
            print("    Diff: dx="..(expected_pos.x - actual_pos.x).." dy="..(expected_pos.y - actual_pos.y))
        else
            print("Desynchronized on frame "..module.desync_level.."-"..module.desync_frame..": Actual position differs from expected position:")
            print("    Player: "..player_index)
            print("    Expected: x="..expected_pos.x.." y="..expected_pos.y)
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
    if module.desync_level ~= -1 then
        return
    end
    module.desync_level = module.current.current_level_index
    module.desync_frame = module.current_frame_index
    print("Desynchronized on frame "..module.desync_level.."-"..module.desync_frame..": Expected end of level.")
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

-- Prepares the game state and triggers the loading sequence for loading from the TAS's starting state.
-- TODO: This fades in really fast if warping from another level. I use a fast fade-out for these warps, but I'm not sure how the game decides how many fade-in frames to use after that.
function module.apply_start_state()
    if not prepare_warp_from_screen() then
        return false
    end

    local tas = module.current.tas

    state.quest_flags = common.flag_to_value(QUEST_FLAG.RESET)
    if tas.seed_type == "seeded" then
        state.seed = tas.seeded_seed
        state.quest_flags = state.quest_flags | common.flag_to_value(QUEST_FLAG.SEEDED)
        -- The adventure seed will be generated by the game based on the seeded seed.
    else
        set_adventure_seed(tas.adventure_seed[1], tas.adventure_seed[2])
        -- The seeded seed does not affect adventure runs.
    end
    if tas.shortcut then
        state.quest_flags = state.quest_flags | common.flag_to_value(QUEST_FLAG.SHORTCUT_USED)
    end
    state.world_next = tas.world_start
    state.level_next = tas.level_start
    state.theme_next = tas.theme_start
    if tas.tutorial_race then
        state.screen_next = SCREEN.CAMP
        state.world_start = 1
        state.level_start = 1
        state.theme_start = THEME.DWELLING
        state.speedrun_activation_trigger = true
        state.speedrun_character = common_enums.PLAYER_CHAR:value_by_id(tas.tutorial_race_referee).ent_type_id
        -- Ensure that the player spawns in the tutorial area, instead of the rope or large door.
        force_level_gen_screen_last = SCREEN.CAMP
    else
        state.screen_next = SCREEN.LEVEL
        state.world_start = tas.world_start
        state.level_start = tas.level_start
        state.theme_start = tas.theme_start
        state.speedrun_activation_trigger = false
    end
    state.items.player_count = tas.player_count;
    for player_index = 1, CONST.MAX_PLAYERS do
        local player_char = common_enums.PLAYER_CHAR:value_by_id(tas.players[player_index])
        state.items.player_select[player_index].activated = player_index <= tas.player_count
        state.items.player_select[player_index].character = player_char.ent_type_id
        state.items.player_select[player_index].texture = player_char.texture_id
    end
    state.loading = 1
    state.pause = PAUSE.FADE
    state.fadeout = WARP_FADE_OUT_FRAMES
    state.fadein = WARP_FADE_OUT_FRAMES

    module.desync_level = -1
    module.desync_frame = -1

    return true
end

-- Prepares the game state and triggers the loading sequence for loading a level snapshot. Tutorial race level snapshots are not currently supported.
function module.apply_level_snapshot(level_index)
    if not prepare_warp_from_screen() then
        return false
    end

    if not module.current.tas.adventure_seed then
        -- TODO: Explain to the user that they need to record or playback to level 1 first, even in seeded runs. Show this warning in the UI before they press the button.
        print("Warning: Missing adventure seed.")
        return false
    end

    local level_snapshot = module.current.tas.levels[level_index].snapshot
    if level_snapshot then
        if options.debug_print_load or options.debug_print_snapshot then
            print("apply_level_snapshot: Applying state memory snapshot for level index "..level_index..".")
        end
        -- TODO: What do I actually need to set here to get the game to load the state correctly? The game sometimes loads the wrong level or crashes if I don't do this. Maybe the game checks some of the state before PRE_LEVEL_GENERATION is called. I apply the snapshot a second time when I intercept the load in PRE_LEVEL_GENERATION because that's the only place I can override the player inventories. Perhaps I don't need to apply the snapshot here, but need to do it in the PRE_UPDATE which will unload the current level and then run the next level's generation.
        introspection.apply_snapshot(state, level_snapshot, GAME_TYPES.StateMemory_LevelSnapshot)
        state.screen_next = SCREEN.LEVEL
        state.loading = 1
        state.pause = PAUSE.FADE
        state.fadeout = WARP_FADE_OUT_FRAMES
        state.fadein = WARP_FADE_OUT_FRAMES
        -- Additional loading behavior needs to occur later.
        load_level_snapshot_index = level_index
        module.desync_level = -1
        module.desync_frame = -1
        return true
    else
        print("Warning: Missing level state data for level index "..level_index..".")
        return false
    end
end

function module.set_mode(new_mode)
    if new_mode == common_enums.MODE.FREEPLAY then
        module.playback_target_level = -1
        module.playback_target_frame = -1
        module.playback_force_full_run = false
        module.playback_force_current_frame = false
        module.current_frame_index = -1

    elseif new_mode == common_enums.MODE.RECORD then
        if module.mode == common_enums.MODE.PLAYBACK then
            module.playback_target_level = -1
            module.playback_target_frame = -1
            if module.current_frame_index ~= -1 then
                if options.record_frame_clear_action == "remaining_level" then
                    module.current.tas:remove_frames_after(module.current.current_level_index, module.current_frame_index, true)
                elseif options.record_frame_clear_action == "remaining_run" then
                    module.current.tas:remove_frames_after(module.current.current_level_index, module.current_frame_index, false)
                end
            end
        end

    elseif new_mode == common_enums.MODE.PLAYBACK then
        local need_load = false
        local load_level_index = -1

        local can_use_current_frame = not module.playback_force_full_run and module.mode ~= common_enums.MODE.FREEPLAY
            and (module.playback_force_current_frame or options.playback_from == module.PLAYBACK_FROM.NOW_OR_LEVEL or options.playback_from == module.PLAYBACK_FROM.NOW)
            and ((module.playback_target_level == module.current.current_level_index and module.playback_target_frame >= module.current_frame_index) or module.playback_target_level > module.current.current_level_index)

        local best_load_level_index = -1
        if module.playback_force_full_run then
            best_load_level_index = 1
        elseif not module.playback_force_current_frame then
            if module.mode == common_enums.MODE.FREEPLAY or options.playback_from == module.PLAYBACK_FROM.NOW_OR_LEVEL or options.playback_from == module.PLAYBACK_FROM.LEVEL then
                best_load_level_index = module.current.tas:find_closest_level_with_snapshot(module.playback_target_level)
                if best_load_level_index == -1 then
                    best_load_level_index = 1
                end
            elseif options.playback_from == 4 then
                best_load_level_index = 1
            elseif options.playback_from > 4 and module.current.tas.levels[options.playback_from - 3].snapshot then
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
                if module.current.current_level_index < best_load_level_index then
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
            if module.current.current_level_index == module.playback_target_level and module.current_frame_index == module.playback_target_frame then
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
    if module.current.current_level_index > module.current.tas:get_end_level_index() then
        message = "Current level is later than end of TAS ("..module.current.tas:get_end_level_index().."-"..module.current.tas:get_end_frame_index()..")."
        clear_current_level_index = true
    elseif module.current.current_level_index ~= -1 and module.current_frame_index > module.current.tas:get_end_frame_index(module.current.current_level_index) then
        message = "Current frame is later than end of level ("..module.current.current_level_index.."-"..module.current.tas:get_end_frame_index(module.current.current_level_index)..")."
    end
    if message then
        print("Warning: Invalid current frame ("..module.current.current_level_index.."-"..module.current_frame_index.."): "..message.." Switching to freeplay mode.")
        if options.debug_print_pause then
            prinspect("validate_current_frame: Invalid current frame pause", get_frame())
        end
        module.set_mode(common_enums.MODE.FREEPLAY)
        need_pause = true
        if clear_current_level_index then
            module.current:clear_current_level_index()
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
    if module.playback_target_level > #module.current.tas.levels then
        message = "Target is later than end of TAS ("..#module.current.tas.levels.."-"..#module.current.tas.levels[module.playback_target_level].frames..")."
    elseif module.playback_target_frame > #module.current.tas.levels[module.playback_target_level].frames then
        message = "Target is later than end of level ("..module.playback_target_level.."-"..#module.current.tas.levels[module.playback_target_level].frames..")."
    elseif (state.loading == 0 or state.loading == 3) and (module.current.current_level_index > module.playback_target_level
            or (module.current.current_level_index == module.playback_target_level and module.current_frame_index > module.playback_target_frame)) then
        message = "Current frame ("..module.current.current_level_index.."-"..module.current_frame_index..") is later than playback target."
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

-- Called right before the game updates the adventure seed and PRNG in order to generate a playable level or the camp.
local function on_pre_update_adventure_seed()
    if options.debug_print_load then
        print("on_pre_update_adventure_seed")
    end
    if load_level_snapshot_index then
        -- This level will be overridden by a stored level snapshot. Only apply the computed adventure seed here. The state memory snapshot will be applied right before level generation.
        local adventure_seed = module.current.tas:compute_level_adventure_seed(load_level_snapshot_index)
        set_adventure_seed(table.unpack(adventure_seed))
        if options.debug_print_load or options.debug_print_snapshot then
            print("on_pre_update_adventure_seed: Applying computed adventure seed for level index "..load_level_snapshot_index..": "
                ..common.adventure_seed_part_to_string(adventure_seed[1]).."-"
                ..common.adventure_seed_part_to_string(adventure_seed[2]))
        end
    end
end

-- Called right before an update which is going to load a screen. The screen value itself might not change, since the game may be loading the same type of screen.
local function on_pre_screen_change()
    if ((state.screen == SCREEN.LEVEL or state.screen == SCREEN.CAMP or state.screen == SCREEN.TRANSITION)
        and state.screen_next ~= SCREEN.OPTIONS and state.screen_next ~= SCREEN.DEATH)
        or state.screen == SCREEN.DEATH
    then
        -- This update is going to unload the current level, camp, or transition screen.
        reset_level_vars()
    end
    if state.screen ~= SCREEN.OPTIONS and (state.screen_next == SCREEN.LEVEL or state.screen_next == SCREEN.CAMP) then
        on_pre_update_adventure_seed()
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

    if force_level_gen_screen_last then
        state.screen_last = force_level_gen_screen_last
        force_level_gen_screen_last = nil
    end

    if load_level_snapshot_index then
        -- This level needs to be overridden by a stored level snapshot before generation.
        local load_level_data = module.current.tas.levels[load_level_snapshot_index]
        if load_level_data and load_level_data.snapshot then
            if options.debug_print_load or options.debug_print_snapshot then
                print("on_pre_level_gen: Applying state memory snapshot for level index "..load_level_snapshot_index..".")
            end
            introspection.apply_snapshot(state, load_level_data.snapshot, GAME_TYPES.StateMemory_LevelSnapshot)
        else
            print("Warning: Missing state memory snapshot for level index "..load_level_snapshot_index..". Switching to freeplay mode.")
            module.set_mode(common_enums.MODE.FREEPLAY)
        end
    end

    if module.current then
        module.current:update_current_level_index(module.mode == common_enums.MODE.RECORD)
    end
    if module.ghost_tas_session then
        module.ghost_tas_session:update_current_level_index()
    end

    if not module.current then
        return
    end

    if options.debug_print_load then
        print("on_pre_level_gen: current_level_index="..module.current.current_level_index)
    end

    if module.mode == common_enums.MODE.PLAYBACK and module.current.current_level_index == -1 then
        print("Warning: Loading level with no level data during playback. Switching to freeplay mode.")
        module.set_mode(common_enums.MODE.FREEPLAY)
    end

    if load_level_snapshot_index then
        load_level_snapshot_index = nil
    elseif module.mode ~= common_enums.MODE.FREEPLAY and module.current.current_level_index > 1
        and (not module.current.current_level_data.snapshot or module.mode == common_enums.MODE.RECORD)
    then
        module.current.current_level_data.snapshot = introspection.create_snapshot(state, GAME_TYPES.StateMemory_LevelSnapshot)
        if options.debug_print_load or options.debug_print_snapshot then
            print("on_pre_level_gen: Storing state memory snapshot for level index "..module.current.current_level_index..".")
        end
    end
end

-- Called after level generation for any playable level or the camp. This callback occurs within a game update, right before the game advances `state.loading` from 2 to 3.
local function on_post_level_gen()
    if module.mode == common_enums.MODE.FREEPLAY or not module.current or module.current.current_level_index == -1 then
        return
    end

    if options.debug_print_load then
        print("on_post_level_gen: current_level_index="..module.current.current_level_index)
    end

    module.current_frame_index = 0
    if (module.mode == common_enums.MODE.PLAYBACK and options.pause_playback_on_level_start) or (module.mode == common_enums.MODE.RECORD and options.pause_recording_on_level_start) then
        need_pause = true
    end

    if module.current.current_level_index == 1 and module.current.tas.seed_type == "seeded" then
        if options.debug_print_load and not module.current.tas.adventure_seed then
            print("on_post_level_gen: Storing initial adventure seed.")
        end
        -- Decrement and store the adventure seed. That adventure seed is the one that was generated by the seeded seed.
        local part_1, part_2 = get_adventure_seed()
        module.current.tas.adventure_seed = { part_1, part_2 - part_1 }
    end
    module.current.current_level_data.metadata = {
        world = state.world,
        level = state.level,
        theme = state.theme
    }

    for player_index, player in ipairs(module.current.current_level_data.players) do
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
        -- The transition screen can't be skipped entirely. It needs to run its unload behavior in order for things like pet health to be applied to players.
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
            print("get_cutscene_input: Sending cutscene skip input: frame="..module.current.current_level_index.."-"..module.current_frame_index.." timer="..logic_cutscene.timer)
        end
        return common_enums.SKIP_INPUT:value_by_id(skip_input_id).input
    elseif logic_cutscene.timer == skip_frame then
        if options.debug_print_input then
            print("get_cutscene_input: Deferring to recorded input: frame="..module.current.current_level_index.."-"..module.current_frame_index.." timer="..logic_cutscene.timer)
        end
        return nil
    else
        -- Prevent the player from pressing any buttons and interfering with the cutscene.
        return INPUTS.NONE
    end
end

-- Called before every game update in a playable level that is part of the current TAS.
local function on_pre_update_level()
    reset_frame_vars()
    pre_update_loading = state.loading
    pre_update_time_level = state.time_level
    pre_update_cutscene_active = state.logic.olmec_cutscene ~= nil or state.logic.tiamat_cutscene ~= nil

    module.validate_current_frame()
    module.validate_playback_target()

    if module.mode ~= common_enums.MODE.FREEPLAY and (state.loading == 0 or state.loading == 3) then
        -- Submit the desired inputs for the upcoming update. The script doesn't know whether this update will actually execute player inputs. If it does execute them, then it will execute the submitted inputs. If it doesn't execute them, such as due to the game being paused, then nothing will happen and the script can try again on the next update.
        for player_index = 1, module.current.tas.player_count do
            local input
            -- Record and playback modes should both automatically skip cutscenes.
            if state.logic.olmec_cutscene then
                input = get_cutscene_input(player_index, state.logic.olmec_cutscene, module.OLMEC_CUTSCENE_LAST_FRAME, module.current.tas.olmec_cutscene_skip_frame, module.current.tas.olmec_cutscene_skip_input)
            elseif state.logic.tiamat_cutscene then
                input = get_cutscene_input(player_index, state.logic.tiamat_cutscene, module.TIAMAT_CUTSCENE_LAST_FRAME, module.current.tas.tiamat_cutscene_skip_frame, module.current.tas.tiamat_cutscene_skip_input)
            end
            if not input and module.mode == common_enums.MODE.PLAYBACK then
                -- Only playback mode should submit normal gameplay inputs.
                if module.current.current_level_data.frames[module.current_frame_index + 1] then
                    -- Submit the input from the upcoming frame.
                    input = module.current.current_level_data.frames[module.current_frame_index + 1].players[player_index].input
                else
                    -- There is no upcoming frame stored for the current level. The level should have ended during the previous update.
                    set_level_end_desync()
                    module.set_mode(common_enums.MODE.FREEPLAY)
                end
            end
            if input then
                state.player_inputs.player_slots[player_index].buttons = input
                state.player_inputs.player_slots[player_index].buttons_gameplay = input
                if options.debug_print_frame or options.debug_print_input then
                    -- TODO: This is super spammy when paused.
                    --print("on_pre_update_level: Sending input for upcoming frame: frame="..module.current.current_level_index.."-"..(module.current_frame_index + 1).." input="..common.input_to_string(input))
                end
            end
        end
    end
end

-- Called before every game update in a transition while a current TAS exists.
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
    if module.current.tas.transition_exit_frame ~= -1 then
        for player_index = 1, module.current.tas.player_count do
            -- By default, suppress inputs from every player.
            state.player_inputs.player_slots[player_index].buttons = INPUTS.NONE
            state.player_inputs.player_slots[player_index].buttons_gameplay = INPUTS.NONE
        end
        if transition_frame >= module.current.tas.transition_exit_frame then
            -- Have player 1 provide the transition exit input. The exit is triggered during the first update where the input is seen, not when it's released.
            if options.debug_print_input then
                print("on_pre_update_transition: Submitting transition exit input.")
            end
            state.player_inputs.player_slots[1].buttons = INPUTS.JUMP
            state.player_inputs.player_slots[1].buttons_gameplay = INPUTS.JUMP
        end
    end
end

-- TODO: Review and clean up the various "current TAS", "current_level_index", "state.loading", and "MODE.FREEPLAY" checks in these pre-update functions. Some of them are probably redundant.
local function on_pre_update()
    if state.loading == 2 then
        on_pre_screen_change()
    else
        if not module.current then
            return
        end
        -- TODO: I would like to unify some behavior for levels and transitions. I could do this if I get them to both use the current_frame_index variable.
        if state.screen == SCREEN.LEVEL or state.screen == SCREEN.CAMP then
            -- TODO: current_level_index won't be set if I'm not on one of these screens. Do I even need to check the screens?
            if module.current.current_level_index ~= -1 then
                on_pre_update_level()
            end
        elseif state.screen == SCREEN.TRANSITION then
            on_pre_update_transition()
        end
    end
end

local function handle_playback_target()
    if module.validate_playback_target() and module.current.current_level_index == module.playback_target_level and module.current_frame_index == module.playback_target_frame then
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
        elseif new_mode == common_enums.MODE.FREEPLAY or (module.current.current_level_index == #module.current.tas.levels and module.current_frame_index == #module.current.current_level_data.frames) then
            if options.debug_print_mode then
                print("Playback target ("..module.playback_target_level.."-"..module.playback_target_frame..") reached. Switching to freeplay mode.")
            end
            module.set_mode(common_enums.MODE.FREEPLAY)
        else
            if options.debug_print_mode then
                print("Playback target ("..module.playback_target_level.."-"..module.playback_target_frame..") reached. Staying in playback mode.")
            end
            module.playback_target_level, module.playback_target_frame = module.current.tas:get_end_indices()
        end
    end
end

-- Called after every game update where the current TAS frame was incremented.
local function on_post_update_frame_advanced()
    if options.debug_print_frame or options.debug_print_input then
        print("on_post_update_frame_advanced: frame="..module.current.current_level_index.."-"..module.current_frame_index.." input="..common.input_to_string(state.player_inputs.player_slots[1].buttons_gameplay))
    end

    local current_frame_data = module.current.current_level_data.frames[module.current_frame_index]
    if module.mode == common_enums.MODE.RECORD then
        -- Only record mode can create new frames. Playback mode should only be active during frames that already exist.
        if options.record_frame_write_type == "overwrite" then
            if not current_frame_data then
                current_frame_data = module.current.tas:create_frame_data()
                module.current.current_level_data.frames[module.current_frame_index] = current_frame_data
            end
        elseif options.record_frame_write_type == "insert" then
            current_frame_data = module.current.tas:create_frame_data()
            table.insert(module.current.current_level_data.frames, module.current_frame_index, current_frame_data)
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
            if options.debug_print_frame or options.debug_print_input then
                print("on_post_update: Recording input: frame="..module.current.current_level_index.."-"..module.current_frame_index
                    .." player="..player_index.." input="..common.input_to_string(state.player_inputs.player_slots[player_index].buttons_gameplay))
            end
            player.input = state.player_inputs.player_slots[player_index].buttons_gameplay
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

-- TODO: Review and clean up the various "current TAS", "current_level_index", "state.loading", and "MODE.FREEPLAY" checks in these post-update functions. Some of them are probably redundant.
local function on_post_update()
    if module.mode ~= common_enums.MODE.FREEPLAY and module.current and module.current.current_level_index ~= -1 and module.current_frame_index ~= -1 then
        -- Check whether this update advanced the TAS by one frame.
        -- TODO: This check feels messy. Is there a more concise way that I can check whether the previous update should advance the TAS by one frame?
        -- TODO: What does time_level do for loading 0->1? Should the TAS actually advance one frame? Can non-exiting players perform an action on this frame?
        if ((pre_update_loading == 3 and state.loading == 0) or (pre_update_loading == 0 and (state.loading == 0 or state.loading == 1)))
                and (pre_update_time_level ~= state.time_level or (pre_update_cutscene_active and not state.logic.olmec_cutscene and not state.logic.tiamat_cutscene)) then
            module.current_frame_index = module.current_frame_index + 1
            on_post_update_frame_advanced()
        elseif module.current_frame_index == 0 and module.mode == common_enums.MODE.PLAYBACK then
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
