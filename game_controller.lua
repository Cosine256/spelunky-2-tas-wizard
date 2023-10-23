local module = {}

local common = require("common")
local common_enums = require("common_enums")
local introspection = require("introspection")
local GAME_TYPES = introspection.register_types({}, require("raw_game_types"))

-- The maximum amount of time to spend executing one batch of fast updates, in milliseconds.
local FAST_UPDATE_BATCH_DURATION = 100
-- Vanilla frames used to fade into and out of the transition screen.
local TRANSITION_FADE_FRAMES = 18
local WARP_FADE_OUT_FRAMES = 5

local SCREEN_WARP_HANDLER
do
    local function stop_main_menu_music()
        if game_manager.main_menu_music then
            game_manager.main_menu_music.playing = false
            game_manager.main_menu_music = nil
        end
        return true
    end
    SCREEN_WARP_HANDLER = {
        [SCREEN.LOGO] = false, -- Controls don't bind properly.
        [SCREEN.INTRO] = true,
        [SCREEN.PROLOGUE] = false, -- Controls don't bind properly.
        [SCREEN.TITLE] = false, -- Controls don't bind properly.
        [SCREEN.MENU] = function()
            stop_main_menu_music()
            if game_manager.screen_menu.cthulhu_sound then
                -- Stop the stone door sound effects that play the first time the main menu is loaded.
                game_manager.screen_menu.cthulhu_sound.playing = false
            end
            return true
        end,
        [SCREEN.OPTIONS] = false,
        [SCREEN.PLAYER_PROFILE] = stop_main_menu_music,
        [SCREEN.LEADERBOARD] = stop_main_menu_music,
        [SCREEN.SEED_INPUT] = stop_main_menu_music,
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

local need_pause = false
-- Whether to ignore submitted TAS inputs for the current transition screen.
local suppress_transition_tas_inputs = false
local force_level_snapshot
-- Whether a new screen is being warped to. This is cleared at the end of screen change updates.
local is_warping = false

-- The start time of the current fast update batch. Any game updates that occur while this is set are fast updates initiated by `update_frame()`.
local fast_update_start_time

local pre_update_loading
local pre_update_pause

local level_snapshot_requests = {}
local level_snapshot_request_count = 0
local level_snapshot_request_next_id = 1
local captured_level_snapshot = nil

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

-- Requests a game engine pause. The pause will be applied after a game update as soon as it's safe to do so.
function module.request_pause(debug_message)
    if options.debug_print_pause then
        print("request_pause: "..debug_message)
    end
    need_pause = true
end

-- Cancels a requested pause that hasn't be applied to the game engine yet. Does nothing if there is no requested pause. Does not unpause the game engine if it is already paused.
function module.cancel_requested_pause()
    if options.debug_print_pause then
        print("cancel_requested_pause")
    end
    need_pause = false
end

-- Apply a game engine pause if one is needed and it's safe to do so. If a pause is needed but cannot be safely performed, then nothing will happen and this function can be called after the next game update to try again.
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
    if state.screen == SCREEN.TRANSITION and options.pause_suppress_auto_transition_exit then
        -- Suppress TAS inputs for the current transition screen instead of pausing.
        need_pause = false
        suppress_transition_tas_inputs = true
        if options.debug_print_pause then
            print("try_pause: Suppressing TAS inputs for the current transition screen instead of pausing.")
        end
        return
    end
    if state.loading == 0 and (state.pause == 0 or state.pause == PAUSE.FADE) then
        -- It's safe to pause now.
        -- TODO: OL has an option to change its pause behavior. The FADE pause is the only one that is currently supported by this script. Need to handle the other ones, or instruct the user to only use the FADE pause.
        -- TODO: Pausing is not safe during mixed or non-FADE pause states because OL FADE pauses currently handle them incorrectly and will erase the other pause flags. This causes problems such as level timer desync during cutscenes.
        state.pause = PAUSE.FADE
        need_pause = false
        if options.debug_print_pause then
            print("try_pause: Paused")
        end
    end
end

function module.is_warping()
    return is_warping
end

-- Validates whether a warp can be performed and prepares for screen-specific warp behavior. Returns false if it isn't currently safe to warp from this screen.
local function prepare_warp_from_screen()
    if state.loading == 2 then
        print("Cannot warp during screen change update.")
        return false
    end
    local screen_can_warp = SCREEN_WARP_HANDLER[state.screen]
    local can_warp = type(screen_can_warp) == "function" and screen_can_warp() or screen_can_warp == true
    if not can_warp then
        print("Cannot warp from current screen.")
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

-- Forces the game to warp to a level initialized with the simple start settings of the given TAS. This sets the run reset flag, prepares the game state, and then triggers the game to start unloading the current screen. The reset flag handles the most of the process on its own. Returns whether the warp was triggered successfully.
function module.trigger_start_simple_warp(tas)
    if options.debug_print_load then
        print("trigger_start_simple_warp")
    end

    if not prepare_warp_from_screen() then
        return false
    end

    local start = tas.start_simple
    force_level_snapshot = nil

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
        if player_index <= start.player_count then
            local player_char = common_enums.PLAYER_CHAR:value_by_id(start.players[player_index])
            state.items.player_select[player_index].activated = true
            state.items.player_select[player_index].character = player_char.ent_type_id
            state.items.player_select[player_index].texture = player_char.texture_id
        else
            state.items.player_select[player_index].activated = false
        end
    end

    trigger_warp_unload()
    active_tas_session.desync = nil
    is_warping = true

    return true
end

-- Forces the game to warp to a level initialized with the given level snapshot. This triggers the game to start unloading the current screen, and then it hooks into the loading process at specific points to apply the snapshot. Returns whether the warp was triggered successfully.
function module.trigger_level_snapshot_warp(level_snapshot)
    if options.debug_print_load then
        print("trigger_level_snapshot_warp")
    end

    if not prepare_warp_from_screen() then
        return false
    end

    trigger_warp_unload()
    active_tas_session.desync = nil
    force_level_snapshot = level_snapshot
    is_warping = true

    return true
end

-- Called right before an update which is going to load a screen. The screen value itself might not change since the game may be loading the same type of screen. For screens that include level generation, this is the last place to read or write the adventure seed. Between this function and `on_pre_level_gen`, the game will unload the current screen and increment the adventure seed to generate PRNG for the upcoming level generation.
local function on_pre_update_load_screen()
    if options.debug_print_load then
        print("on_pre_update_load_screen: "..state.screen.." -> "..state.screen_next)
    end

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
        if options.debug_print_load or options.debug_print_snapshot then
            print("on_pre_update_load_screen: Screen change with snapshot: "..state.screen.." -> "..state.screen_next)
        end
    end

    if state.screen_next == SCREEN.OPTIONS or state.screen == SCREEN.OPTIONS then
        -- This update is either entering or exiting the options screen. This does not change the underlying screen and is not a relevant event for this script.
        return
    end

    suppress_transition_tas_inputs = false

    if active_tas_session then
        active_tas_session:on_pre_update_load_screen()
    end

    local tasable_screen = common_enums.TASABLE_SCREEN[state.screen_next]
    if tasable_screen and tasable_screen.can_snapshot and level_snapshot_request_count > 0 then
        -- Begin capturing a level snapshot for the upcoming level.
        if options.debug_print_load or options.debug_print_snapshot then
            print("on_pre_update_load_screen: Starting capture of level snapshot for "..level_snapshot_request_count.." requests.")
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

-- Applies the given inputs to the player slots in the state memory. The game sets the player inputs before pre-update, so calling this function in pre-update overwrites the game's inputs for the upcoming update. The script doesn't know whether an update will actually process player inputs. If it does process them, then it will use the submitted inputs. If it doesn't process them, such as due to the game being paused, then nothing will happen and the same inputs can be submitted in the next pre-update to try again.
function module.submit_pre_update_inputs(frame_inputs)
    if state.screen ~= SCREEN.TRANSITION or not suppress_transition_tas_inputs then
        for player_index, player_inputs in ipairs(frame_inputs) do
            state.player_inputs.player_slots[player_index].buttons = player_inputs
            state.player_inputs.player_slots[player_index].buttons_gameplay = player_inputs
        end
    end
end

local function can_fast_update()
    return options.fast_update_playback and not options.presentation_enabled and active_tas_session and active_tas_session.mode == common_enums.MODE.PLAYBACK
        and state.screen ~= SCREEN.OPTIONS and state.pause & PAUSE.MENU == 0 and not (state.loading == 0 and state.pause & PAUSE.FADE > 0)
        and (not active_tas_session.current_level_data or active_tas_session.current_level_data.metadata.screen ~= SCREEN.TRANSITION
            or (not suppress_transition_tas_inputs and active_tas_session.current_level_data.transition_exit_frame_index ~= nil))
end

local function on_pre_update()
    -- Before executing the upcoming normal update, check whether a batch of fast updates should occur. Fast updates are identical to normal updates as far the game state is concerned, and they trigger OL callbacks just like normal updates. However, they do not perform any rendering and are not locked to any frame rate, so fast updates can be executed as quickly as the computer is capable of doing so. This is usually significantly faster than the 60 FPS of normal updates.
    -- Only a finite batch of fast updates will be executed. The batch will end once the maximum duration is reached, or if any checks stop the batch early. Once the batch ends, the pending normal update will be allowed to execute. Unlike the fast updates, rendering will occur after the normal update. This will allow pausing and GUI interactions to occur, although the performance will be very laggy. It will also let the user see the progress of fast playback rather than the game appearing to be frozen until fast playback stops, and it will prevent an uninterruptible infinite loop if fast playback fails to reach a stopping point for whatever reason. Before the next normal update, the script will check again whether another batch of fast updates should occur.
    --  Note: `get_frame()` and `state.time_startup` are not incremented by fast updates, so they are not reliable update counters.
    if not fast_update_start_time and can_fast_update() then
        fast_update_start_time = get_ms()
        if options.debug_print_fast_update then
            print("on_pre_update: Starting fast update batch. fast_update_start_time="..fast_update_start_time)
        end
        while true do
            update_state()
            local duration = get_ms() - fast_update_start_time
            if duration >= FAST_UPDATE_BATCH_DURATION then
                if options.debug_print_fast_update then
                    print("on_pre_update: Stopping fast update batch after "..duration.."ms: Max duration reached.")
                end
                break
            end
            if not can_fast_update() then
                if options.debug_print_fast_update then
                    print("on_pre_update: Stopping fast update batch after "..duration.."ms: Fast update conditions no longer met.")
                end
                break
            end
        end
        fast_update_start_time = nil
    end

    pre_update_loading = state.loading
    pre_update_pause = state.pause

    if state.loading == 2 then
        on_pre_update_load_screen()
    elseif active_tas_session then
        active_tas_session:on_pre_update()
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
        active_tas_session:on_post_update_load_screen()
    end
    if ghost_tas_session then
        -- The ghost TAS session updates its current level index in the same way as the active TAS session, except it's always in freeplay mode.
        ghost_tas_session:on_post_update_load_screen()
    end

    is_warping = false

    if (state.screen == SCREEN.TRANSITION or state.screen == SCREEN.SPACESHIP) and not need_pause and options.transition_skip
        and not (active_tas_session and active_tas_session.mode == common_enums.MODE.PLAYBACK and options.presentation_enabled)
    then
        -- The screen couldn't be skipped entirely. The transition screen needed to be loaded in order for pet health to be applied to players. The spaceship screen is also handled in this way for simplicity, even though it doesn't affect pet health. Now the screen can be immediately unloaded.
        if options.debug_print_load then
            print("on_post_update_load_screen: Skipping transition/spaceship screen.")
        end
        if state.screen == SCREEN.TRANSITION then
            state.screen_next = SCREEN.LEVEL
        else
            state.screen_next = SCREEN.TRANSITION
            -- The spaceship screen initially loads as 6-1 BASE_CAMP for some reason. It sets these specific fields when the fade-out begins.
            state.world = 6
            state.level = 4
            state.world_next = 7
            state.level_next = 1
            state.theme_next = THEME.SUNKEN_CITY
        end
        state.fadeout = 1 -- The fade-out will finish on the next update and the screen will unload.
        state.fadein = TRANSITION_FADE_FRAMES
        state.loading = 1
    end
end

-- Gets whether entity state machines were executed during the most recent non-screen-change update.
function module.did_entities_update()
    -- TODO: This logic is only guessing whether entities were updated based on the state memory before and after the update. This seems to work for vanilla game behavior, but it doesn't properly handle OL freeze pauses and other scripted scenarios. It would be better if it could check whether the entities were actually updated. Is there a way to do this for any screen capable of having entities, even if it has 0 entities in it?
    -- TODO: There is an entity update that seems to occur when loading screens that generate entities. Does it always happen for these screens? It should count as an entity update here even if it isn't a TASable frame.
    return ((pre_update_loading == 3 and (state.loading == 0 or state.loading == 1)) or (pre_update_loading == 0 and (state.loading == 0 or state.loading == 1)))
        -- Within an update, the vanilla game sets specific pause flags either before or after entities are updated. A pause flag that prevents entity updating will only have an effect if it's set before the game starts the entity updates. This means that this logic needs to check the pre-update value for some pause flags instead of the post-update value depending on when the game sets them. Some pause flags are not checked here because they either don't prevent entity updates or they have an unknown purpose.
        and (pre_update_pause & PAUSE.ANKH == 0 and state.pause & (PAUSE.MENU | PAUSE.FADE) == 0)
end

local function on_post_update()
    if pre_update_loading == 2 then
        on_post_update_load_screen()
    elseif active_tas_session then
        active_tas_session:on_post_update()
    end

    try_pause()
end

function module.initialize()
    set_callback(on_pre_update, ON.PRE_UPDATE)
    set_callback(on_post_update, ON.POST_UPDATE)
    set_callback(on_pre_level_gen, ON.PRE_LEVEL_GENERATION)
end

return module
