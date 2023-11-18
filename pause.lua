-- This module is an interface for Overlunky's game engine pauses. Unless specified otherwise, the term "pause" refers to an OL game engine pause, not the pause menu or `state.pause` flags. This module can directly modify the game state.

local module = {}

-- Gets whether OL engine pausing is active.
function module.is_pausing_active()
    local ol = get_bucket().overlunky
    if ol then
        return ol.options.paused
    end
    return false
end

-- Activate or deactivate OL engine pausing.
function module.set_pausing_active(pausing_active, debug_message)
    print_debug("pause", "pause.set_pausing_active(%s): %s", pausing_active, debug_message)
    local ol = get_bucket().overlunky
    if not ol then
        print_debug("pause", "pause.set_pausing_active(%s): Cannot change OL pause state: OL is not attached.", pausing_active)
        return
    end
    if ol.options.paused ~= pausing_active then
        if pausing_active then
            if not options.pause_suppress_transition_tas_inputs or state.screen ~= SCREEN.TRANSITION then
                ol.set_options.paused = true
            else
                -- Suppress TAS inputs for the current transition screen instead of pausing.
                print_debug("pause", "pause.set_pausing_active(true): Suppressing TAS inputs for the current transition screen instead of activating OL pausing.")
                if active_tas_session and not active_tas_session.suppress_screen_tas_inputs then
                    active_tas_session.suppress_screen_tas_inputs = true
                end
            end
        else
            ol.set_options.paused = false
        end
    end
end

function module.on_post_game_loop()
    local ol = get_bucket().overlunky
    if ol and state.loading == 0 and state.pause & PAUSE.FADE > 0 and ol.options.pause_type & PAUSE.FADE == 0 then
        -- Replace the "pause on level start" fade pause with an OL pause.
        print_debug("pause", "pause.on_post_game_loop: Replacing \"pause on level start\" fade pause with OL pause.")
        state.pause = state.pause & ~PAUSE.FADE
        if not ol.options.paused then
            ol.set_options.paused = true
        end
    end
end

return module
