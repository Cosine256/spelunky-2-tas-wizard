-- This module is an interface for Overlunky's game engine pauses. Unless specified otherwise, the term "pause" refers to an OL game engine pause, not the pause menu or `state.pause` flags. This module can directly modify the game state.

local module = {}

local OL_FREEZE_GAME_LOOP_PAUSE = 0x80

-- Whether to suppress the OL pause type warning when the current value is not recommended.
local suppress_ol_pause_type_warning = false

-- Gets whether OL engine pausing is currently set to become active, but is not yet active.
function module.is_pausing_pending()
    local ol = get_bucket().overlunky
    return ol and not ol.options.paused and ol.set_options.paused
end

-- Gets whether OL engine pausing is currently active or set to become active.
function module.is_pausing_pending_or_active()
    local ol = get_bucket().overlunky
    return ol and (ol.options.paused or ol.set_options.paused)
end

-- Activate or deactivate OL engine pausing.
function module.set_pausing_active(pausing_active, debug_message)
    print_debug("pause", "pause.set_pausing_active(%s): %s", pausing_active, debug_message)
    local ol = get_bucket().overlunky
    if ol then
        if ol.options.paused ~= pausing_active or (ol.set_options.paused ~= nil and ol.set_options.paused ~= pausing_active) then
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
    else
        if pausing_active and options.pause_suppress_transition_tas_inputs and state.screen == SCREEN.TRANSITION then
            -- Suppress TAS inputs for the current transition screen.
            print_debug("pause", "pause.set_pausing_active(true): Suppressing TAS inputs for the current transition screen.")
            if active_tas_session and not active_tas_session.suppress_screen_tas_inputs then
                active_tas_session.suppress_screen_tas_inputs = true
            end
        else
            print_debug("pause", "pause.set_pausing_active(%s): Cannot change OL pause state: OL is not attached.", pausing_active)
        end
    end
end

function module.on_post_game_loop()
    -- On the final fade-in update, the OL "Auto (fade) pause on level start" option allows the game to finish the fade-in, but skips the code that clears the fade pause and updates entities. The leaves the game in a fade pause while `state.loading` is 0, even if the OL pause type is not configured for fade pauses. Detect this scenario and replace the fade pause with an OL pause.
    local ol = get_bucket().overlunky
    if ol and options.pause_on_level_start_fix and state.loading == 0 and state.pause & PAUSE.FADE > 0 and ol.options.pause_type & PAUSE.FADE == 0 then
        print_debug("pause", "pause.on_post_game_loop: Replacing \"Auto (fade) pause on level start\" fade pause with OL pause.")
        state.pause = state.pause & ~PAUSE.FADE
        module.set_pausing_active(true, "Fixing \"Auto (fade) pause on level start\" fade pause.")
    end
end

function module.on_gui_frame()
    local ol = get_bucket().overlunky
    if ol and ol.options.pause_type ~= OL_FREEZE_GAME_LOOP_PAUSE then
        if options.ol_pause_type_force_recommended then
            print_debug("pause", "pause.on_gui_frame: Setting OL pause type to recommended value.")
            ol.set_options.pause_type = OL_FREEZE_GAME_LOOP_PAUSE
        elseif not suppress_ol_pause_type_warning then
            print_warn("Overlunky pause type is set to a non-recommended value. The recommended pause type is \"Freeze game loop\" with no additional pause type flags.")
            suppress_ol_pause_type_warning = true
        end
    elseif suppress_ol_pause_type_warning then
        suppress_ol_pause_type_warning = false
    end
end

return module
