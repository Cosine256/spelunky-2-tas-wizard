-- This module provides control over game engine pauses. This module can directly modify the game state.

local module = {}

local common_enums = require("common_enums")

-- Whether a game engine pause has been requested, but has not been applied to the game state yet.
module.pause_requested = false
-- Whether the most recent post-update was engine paused.
module.post_update_engine_paused = false

-- Requests a game engine pause. The pause will be applied after a game update as soon as it's safe to do so.
function module.request_pause(debug_message)
    print_debug("pause", "request_pause: %s", debug_message)
    module.pause_requested = true
end

-- Cancels a requested pause that hasn't be applied to the game engine yet. Does nothing if a pause not requested. Does not unpause the game engine if it is already paused.
function module.cancel_requested_pause()
    print_debug("pause", "cancel_requested_pause")
    module.pause_requested = false
end

-- Immediately clears a game engine pause if one is active and it's safe to do so.
function module.try_unpause()
    if state.loading == 0 and state.pause == PAUSE.FADE then
        state.pause = 0
    end
end

-- Applies a game engine pause if one was requested and it's safe to do so. If a pause was requested but cannot be safely performed, then nothing will happen and this function will try again the next time it's called.
local function try_requested_pause()
    if not module.pause_requested then
        return
    end
    if state.screen == SCREEN.OPTIONS and common_enums.TASABLE_SCREEN[state.screen_last] then
        -- Don't pause in the options screen.
        return
    end
    if not common_enums.TASABLE_SCREEN[state.screen] then
        -- Cancel the pause entirely.
        module.pause_requested = false
        return
    end
    if state.screen == SCREEN.TRANSITION and options.pause_suppress_transition_tas_inputs then
        -- Suppress TAS inputs for the current transition screen instead of pausing.
        module.pause_requested = false
        if active_tas_session then
            active_tas_session.suppress_screen_tas_inputs = true
        end
        print_debug("pause", "try_requested_pause: Suppressing TAS inputs for the current transition screen instead of pausing.")
        return
    end
    if state.loading == 0 and (state.pause == 0 or state.pause == PAUSE.FADE) then
        -- It's safe to pause now.
        -- TODO: OL has an option to change its pause behavior. The FADE pause is the only one that is currently supported by this script. Need to handle the other ones, or instruct the user to only use the FADE pause.
        -- TODO: Pausing is not safe during mixed or non-FADE pause states because OL FADE pauses currently handle them incorrectly and will erase the other pause flags. This causes problems such as level timer desync during cutscenes.
        state.pause = PAUSE.FADE
        module.pause_requested = false
        print_debug("pause", "try_requested_pause: Paused")
    end
end

-- Executes post-update pause behavior.
function module.on_post_update()
    try_requested_pause()
    module.post_update_engine_paused = state.loading == 0 and state.pause & PAUSE.FADE > 0
end

return module
