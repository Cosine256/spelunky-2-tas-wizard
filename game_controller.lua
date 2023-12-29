-- The game controller provides additional game engine controls and functionality. This includes snapshot capturing, snapshot warping, and fast updates. All game update callbacks are handled here, with calls forwarded to TAS sessions and other modules as needed. The calls must always occur in a consistent order in order to work properly with TAS sessions and game controller features. This module can directly modify the game state.

--[[ Order of callbacks and events during a typical mid-screen TAS frame:
    PRE_PROCESS_INPUT
        Pause API: If PRE_PROCESS_INPUT pause active, then skip to BLOCKED_PROCESS_INPUT.
    Game: Update `game_manager.game_props` inputs.
    POST_PROCESS_INPUT
    BLOCKED_PROCESS_INPUT (only if input processing skipped)
    PRE_GAME_LOOP
        Pause API: If PRE_GAME_LOOP pause active, then skip to BLOCKED_GAME_LOOP.
    Game: Apply `game_manager.game_props` inputs to `state.player_inputs`.
    PRE_UPDATE
        TASW: Overwrite `state.player_inputs` with TAS inputs if in playback mode.
        Pause API: If PRE_UPDATE pause active, then skip to BLOCKED_UPDATE.
    Game: Update entities if required by game state.
    POST_UPDATE
        TASW: Advance frame index if TASable frame executed.
        TASW: Record `state.player_inputs` if TASable frame executed in record mode.
    BLOCKED_UPDATE (only if update skipped)
    Game: Apply `game_manager.game_props` inputs to menus.
    POST_GAME_LOOP
    BLOCKED_GAME_LOOP (only if game loop skipped)
    GUIFRAME(s)
        May execute more than once per game loop for frame rates greater than 60Hz, or be skipped sometimes for lower frame rates.
]]

local module = {}

local common = require("common")
local common_enums = require("common_enums")
local introspection = require("introspection")
local GAME_TYPES = introspection.register_types({}, require("raw_game_types"))

-- The maximum amount of time to spend executing one batch of fast updates, in milliseconds.
local FAST_UPDATE_BATCH_DURATION = 100
-- Vanilla number of frames used to fade into and out of the transition screen.
local TRANSITION_FADE_LENGTH = 18
local WARP_FADE_OUT_LENGTH = 8

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

local warp_screen_snapshot
-- Whether a new screen is being warped to. This is cleared at the end of screen change updates.
local is_warping = false

-- The start time of the current fast update batch. Any game updates that occur while this is set are fast updates initiated by `update_frame()`.
local fast_update_start_time
-- Whether the most recent game loop executed a fast update batch.
module.game_loop_executed_fast_update_batch = false
-- Whether to not skip the current screen even if it qualifies to be skipped. Does nothing if set outside `on_post_update_load_screen`.
module.dont_skip_this_screen = false

local pre_update_loading
local pre_update_pause

local screen_snapshot_requests = {}
local screen_snapshot_request_count = 0
local screen_snapshot_request_next_id = 1
local captured_screen_snapshot = nil

function module.register_screen_snapshot_request(callback)
    local request_id = screen_snapshot_request_next_id
    screen_snapshot_request_next_id = screen_snapshot_request_next_id + 1
    screen_snapshot_requests[request_id] = callback
    screen_snapshot_request_count = screen_snapshot_request_count + 1
    print_debug("snapshot", "register_screen_snapshot_request: Registered screen snapshot request %s.", request_id)
    return request_id
end

function module.clear_screen_snapshot_request(request_id)
    if screen_snapshot_requests[request_id] then
        screen_snapshot_requests[request_id] = nil
        screen_snapshot_request_count = screen_snapshot_request_count - 1
        print_debug("snapshot", "clear_screen_snapshot_request: Cleared screen snapshot request %s.", request_id)
    end
end

function module.is_warping()
    return is_warping
end

-- Validates whether a warp can be performed and prepares for screen-specific warp behavior. Returns false if it isn't currently safe to warp from this screen.
local function prepare_warp_from_screen()
    if state.loading == 2 then
        print_info("Cannot warp during screen change update.")
        return false
    end
    local screen_can_warp = SCREEN_WARP_HANDLER[state.screen]
    local can_warp = type(screen_can_warp) == "function" and screen_can_warp() or screen_can_warp == true
    if not can_warp then
        print_info("Cannot warp from current screen.")
    end
    return can_warp
end

-- Forces the game to start unloading the current screen. If nothing else is done, then this will just reload the current screen, but it can be combined with game state changes in order to perform sophisticated warps.
local function trigger_warp_unload()
    state.loading = 1
    state.pause = PAUSE.FADE
    state.fade_timer = WARP_FADE_OUT_LENGTH
    state.fade_length = WARP_FADE_OUT_LENGTH
    state.fade_value = 0.0
    -- Note: The game normally sets this variable to 1 when it starts loading a non-menu screen. Its exact behavior is uncertain, but fade-ins don't work properly for TASable screens unless it's set to 1. Since warps currently only support TASable screens, it's safe to always set it to 1 here.
    state.ingame = 1
end

-- Forces the game to warp to a screen initialized with the simple start settings of the given TAS. This sets the run reset flag, prepares the game state, and then triggers the game to start unloading the current screen. The reset flag handles the most of the process on its own. Returns whether the warp was triggered successfully.
function module.trigger_start_simple_warp(tas)
    print_debug("screen_load", "trigger_start_simple_warp")

    if not prepare_warp_from_screen() then
        return false
    end

    local start = tas.start_simple
    warp_screen_snapshot = nil

    state.quest_flags = common.flag_to_value(QUEST_FLAG.RESET)
    if start.seed_type == "seeded" then
        state.seed = start.seeded_seed
        state.quest_flags = state.quest_flags | common.flag_to_value(QUEST_FLAG.SEEDED)
        -- The adventure seed will be generated by the game based on the seeded seed.
    else
        -- The adventure seed needs to be set later in the loading process.
        warp_screen_snapshot = {
            adventure_seed = start.adventure_seed
        }
        -- The seeded seed does not affect adventure runs.
    end
    state.screen_next = start.screen
    state.world_next = start.world
    state.level_next = start.level
    state.theme_next = start.theme
    if start.screen == SCREEN.CAMP then
        state.world_start = 1
        state.level_start = 1
        state.theme_start = THEME.DWELLING
        if start.screen_last then
            if not warp_screen_snapshot then
                warp_screen_snapshot = {}
            end
            -- This affects where the players spawn in the camp.
            warp_screen_snapshot.pre_level_gen_screen_last = start.screen_last
        end
        if start.tutorial_race then
            state.speedrun_activation_trigger = true
            state.speedrun_character = common_enums.PLAYER_CHAR:value_by_id(start.tutorial_race_referee).ent_type_id
        else
            state.speedrun_activation_trigger = false
        end
    elseif start.screen == SCREEN.LEVEL then
        state.world_start = start.world
        state.level_start = start.level
        state.theme_start = start.theme
        if start.shortcut then
            state.quest_flags = state.quest_flags | common.flag_to_value(QUEST_FLAG.SHORTCUT_USED)
        end
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

-- Forces the game to warp to a screen initialized with the given screen snapshot. This triggers the game to start unloading the current screen, and then it hooks into the loading process at specific points to apply the snapshot. Returns whether the warp was triggered successfully.
function module.trigger_screen_snapshot_warp(screen_snapshot)
    print_debug("screen_load", "trigger_screen_snapshot_warp")

    if not prepare_warp_from_screen() then
        return false
    end

    trigger_warp_unload()
    active_tas_session.desync = nil
    warp_screen_snapshot = screen_snapshot
    is_warping = true

    return true
end

local function on_pre_game_loop()
    module.game_loop_executed_fast_update_batch = false
end

-- Called right before an update which is going to load a screen. The screen value itself might not change since the game may be loading the same type of screen. For screens that include level generation, this is the last place to read or write the adventure seed. Between this function and `on_pre_level_gen`, the game will unload the current screen and increment the adventure seed to generate PRNG for the upcoming level generation.
local function on_pre_update_load_screen()
    print_debug("screen_load", "on_pre_update_load_screen: %s -> %s", state.screen, state.screen_next)

    if warp_screen_snapshot then
        -- Apply a screen snapshot instead of loading the original destination for this screen change.
        if warp_screen_snapshot.state_memory then
            -- Apply the state memory snapshot.
            print_debug("snapshot", "on_pre_update_load_screen: Applying state memory from screen snapshot.")
            introspection.apply_snapshot(state, warp_screen_snapshot.state_memory, GAME_TYPES.StateMemory_ScreenSnapshot)
        end
        if warp_screen_snapshot.adventure_seed then
            -- Apply the adventure seed.
            print_debug("snapshot", "on_pre_update_load_screen: Applying adventure seed from screen snapshot: %s-%s",
                common.adventure_seed_part_to_string(warp_screen_snapshot.adventure_seed[1]),
                common.adventure_seed_part_to_string(warp_screen_snapshot.adventure_seed[2]))
            set_adventure_seed(table.unpack(warp_screen_snapshot.adventure_seed))
        end
        print_debug("snapshot", "on_pre_update_load_screen: Screen change with snapshot: %s -> %s", state.screen, state.screen_next)
    end

    if state.screen_next == SCREEN.OPTIONS or state.screen == SCREEN.OPTIONS then
        -- This update is either entering or exiting the options screen. This does not change the underlying screen and is not a relevant event for this script.
        return
    end

    if active_tas_session then
        active_tas_session:on_pre_update_load_screen()
    end

    local tasable_screen = common_enums.TASABLE_SCREEN[state.screen_next]
    if tasable_screen and tasable_screen.can_snapshot and screen_snapshot_request_count > 0 then
        -- Begin capturing a screen snapshot for the upcoming screen.
        print_debug("snapshot", "on_pre_update_load_screen: Starting capture of screen snapshot for %s requests.", screen_snapshot_request_count)
        -- Capture a state memory snapshot.
        captured_screen_snapshot = {
            state_memory = introspection.create_snapshot(state, GAME_TYPES.StateMemory_ScreenSnapshot)
        }
        if not (test_flag(state.quest_flags, QUEST_FLAG.RESET) and test_flag(state.quest_flags, QUEST_FLAG.SEEDED)) then
            -- Capture the adventure seed, unless the upcoming screen change includes a reset for a seeded run. The current adventure seed is irrelevant for that scenario.
            local part_1, part_2 = get_adventure_seed()
            captured_screen_snapshot.adventure_seed = { part_1, part_2 }
        end
    end
end

-- Called before level generation for the `CAMP` and `LEVEL` screens. This callback occurs within a game update where `state.loading` is initially 2. The previous screen has been unloaded at this point. This is the last place to manipulate the state memory before level generation. The state memory's player inventory data is fully set and can be read or written here. Shortly after level generation, the game will advance `state.loading` from 2 to 3.
local function on_pre_level_gen()
    print_debug("screen_load", "on_pre_level_gen")

    if warp_screen_snapshot then
        if warp_screen_snapshot.state_memory then
            -- The `player_inventory` array is applied pre-update, but it may be modified by the game when the previous screen is unloaded. Reapply it here.
            print_debug("snapshot", "on_pre_level_gen: Reapplying player inventory array snapshot.")
            introspection.apply_snapshot(state.items.player_inventory, warp_screen_snapshot.state_memory.items.player_inventory,
                GAME_TYPES.Items.fields_by_name["player_inventory"].type)
        end
        if warp_screen_snapshot.pre_level_gen_screen_last then
            state.screen_last = warp_screen_snapshot.pre_level_gen_screen_last
        end
        print_debug("snapshot", "on_pre_level_gen: Finished applying screen snapshot.")
        warp_screen_snapshot = nil
    end

    if captured_screen_snapshot then
        -- Recapture the `player_inventory` array in the state memory. Earlier in this update, the game may have modified the player inventories based on the player entities that were unloaded in the previous screen. Assuming that updates are not affected by the contents of the `player_inventory` array before level generation, it should be safe to overwrite the `player_inventory` array that was captured pre-update.
        print_debug("snapshot", "on_pre_level_gen: Recapturing player inventory array snapshot.")
        captured_screen_snapshot.state_memory.items.player_inventory =
            introspection.create_snapshot(state.items.player_inventory, GAME_TYPES.Items.fields_by_name["player_inventory"].type)
        if state.screen == SCREEN.CAMP then
            -- Capture the previous screen value. It affects how the player spawns into the camp.
            captured_screen_snapshot.pre_level_gen_screen_last = state.screen_last
        end
        -- The screen snapshot capture is finished. Fulfill all of the requests.
        for request_id, callback in pairs(screen_snapshot_requests) do
            if screen_snapshot_request_count > 1 then
                callback(common.deep_copy(captured_screen_snapshot))
            else
                callback(captured_screen_snapshot)
            end
            print_debug("snapshot", "on_pre_level_gen: Fulfilled screen snapshot request %s.", request_id)
            screen_snapshot_requests[request_id] = nil
            screen_snapshot_request_count = screen_snapshot_request_count - 1
        end
        captured_screen_snapshot = nil
    end
end

-- Applies the given inputs to the player slots in the state memory. The game sets the player inputs before pre-update, so calling this function in pre-update overwrites the game's inputs for the upcoming update. The script doesn't know whether an update will actually process player inputs. If it does process them, then it will use the submitted inputs. If it doesn't process them, such as due to the game being paused, then nothing will happen and the same inputs can be submitted in the next pre-update to try again.
function module.submit_pre_update_inputs(frame_inputs)
    for player_index, player_inputs in ipairs(frame_inputs) do
        state.player_inputs.player_slots[player_index].buttons = player_inputs
        state.player_inputs.player_slots[player_index].buttons_gameplay = player_inputs
    end
end

local function can_fast_update()
    return options.playback_fast_update and not presentation_active and active_tas_session and active_tas_session.mode == common_enums.MODE.PLAYBACK
        and common_enums.TASABLE_SCREEN[state.screen] and state.pause & PAUSE.MENU == 0 and not (pause:paused() and (pause.blocked or pause.skip))
        and not active_tas_session.suppress_screen_tas_inputs
end

local function on_pre_update()
    -- Before executing the upcoming normal update, check whether a batch of fast updates should occur instead. Fast updates are identical to normal updates as far as the game state is concerned, and they trigger OL callbacks just like normal updates. However, they do not perform any rendering and are not locked to any frame rate, so fast updates can be executed as quickly as the computer is capable of doing so. This is usually significantly faster than the 60 FPS of normal updates.
    -- Only a finite batch of fast updates will be executed. The batch will end once the maximum duration is reached, or if any checks stop the batch early. Once the batch ends, the pending normal update is skipped to prevent an extra update from executing. Rendering will occur after this function returns, allowing input processing and GUI interactions to occur, although the performance will be very laggy. This will let the user see the progress of fast playback rather than the game appearing to be frozen until fast playback stops, and it will prevent an uninterruptible infinite loop if fast playback fails to reach a stopping point for whatever reason. Before the next normal update, the script will check again whether another batch of fast updates should occur.
    --  Note: `get_frame()` and `state.time_startup` are not incremented by fast updates, so they are not reliable update counters.
    if not fast_update_start_time and can_fast_update() then
        fast_update_start_time = get_ms()
        print_debug("fast_update", "on_pre_update: Starting fast update batch. fast_update_start_time=%s", fast_update_start_time)
        while true do
            update_state()
            local duration = get_ms() - fast_update_start_time
            if duration >= FAST_UPDATE_BATCH_DURATION then
                print_debug("fast_update", "on_pre_update: Stopping fast update batch after %sms: Max duration reached.", duration)
                break
            end
            if not can_fast_update() then
                print_debug("fast_update", "on_pre_update: Stopping fast update batch after %sms: Fast update conditions no longer met.", duration)
                break
            end
        end
        fast_update_start_time = nil
        module.game_loop_executed_fast_update_batch = true
        return true
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
    print_debug("screen_load", "on_post_update_load_screen: %s -> %s", state.screen_last, state.screen)

    module.dont_skip_this_screen = false

    if active_tas_session then
        active_tas_session:on_post_update_load_screen()
    end
    if ghost_tas_session then
        -- The ghost TAS session updates its current screen index in the same way as the active TAS session, except it's always in freeplay mode.
        ghost_tas_session:on_post_update_load_screen()
    end

    is_warping = false

    if (state.screen == SCREEN.TRANSITION or state.screen == SCREEN.SPACESHIP) and not module.dont_skip_this_screen
        and options.transition_skip and not presentation_active
    then
        -- The screen couldn't be skipped entirely. The transition screen needed to be loaded in order for pet health to be applied to players. The spaceship screen is also handled in this way for simplicity, even though it doesn't affect pet health. Now the screen can be immediately unloaded.
        print_debug("screen_load", "on_post_update_load_screen: Skipping transition/spaceship screen.")
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
        state.fade_timer = 1 -- The fade-out will finish on the next update and the screen will unload.
        state.fade_length = TRANSITION_FADE_LENGTH
        state.fade_value = 1.0
        state.loading = 1
    end
end

-- Gets whether entity state machines were executed during the most recent non-screen-change update.
function module.did_entities_update()
    -- TODO: This logic is only guessing whether entities were updated based on the state memory before and after the update. This seems to work for vanilla game behavior, but it doesn't properly handle engine pauses and other scripted scenarios. It would be better if it could check whether the entities were actually updated. Is there a way to do this for any screen capable of having entities, even if it has 0 entities in it?
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
end

function module.initialize()
    set_callback(on_pre_game_loop, ON.PRE_GAME_LOOP)
    set_callback(on_pre_update, ON.PRE_UPDATE)
    set_callback(on_post_update, ON.POST_UPDATE)
    set_callback(on_pre_level_gen, ON.PRE_LEVEL_GENERATION)
end

return module
