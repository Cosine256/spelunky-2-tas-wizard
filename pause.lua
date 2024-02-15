-- This module adds TAS Wizard pause features on top of the pause API. Unless specified otherwise, the term "pause" refers to a game engine pause, not the pause menu or `state.pause` flags.

local module = {}

module.SUPPORTED_PAUSE_TYPE =
    -- Need to freeze game state updates to allow pause API logic to run during fast updates.
    PAUSE_TYPE.PRE_UPDATE
    -- Need to freeze game loop for clean pausing of game state and menus.
    | PAUSE_TYPE.PRE_GAME_LOOP
    -- Need to freeze input processing when the game loop is frozen, or else menu input changes can be missed.
    | PAUSE_TYPE.PRE_PROCESS_INPUT

-- Whether to suppress the pause type warning when the current value is not supported.
local suppress_pause_type_warning = false

-- Activate or deactivate pausing, or apply the special behavior for transition screens.
function module.set_pausing_active(pausing_active, debug_message)
    print_debug("pause", "pause.set_pausing_active(%s): %s", pausing_active, debug_message)
    if pause:paused() ~= pausing_active then
        if pausing_active then
            if not options.pause_suppress_transition_tas_inputs or state.screen ~= SCREEN.TRANSITION then
                pause:set_paused(true)
            else
                -- Suppress TAS inputs for the current transition screen instead of pausing.
                print_debug("pause", "pause.set_pausing_active(true): Suppressing TAS inputs for the current transition screen instead of pausing.")
                if active_tas_session and not active_tas_session.suppress_screen_tas_inputs then
                    active_tas_session.suppress_screen_tas_inputs = true
                end
            end
        else
            pause:set_paused(false)
        end
    end
end

function module.on_gui_frame()
    if pause.pause_type ~= module.SUPPORTED_PAUSE_TYPE then
        if options.pause_type_force_supported then
            print_info("Setting pause type to supported value ("..module.SUPPORTED_PAUSE_TYPE..").")
            pause.pause_type = module.SUPPORTED_PAUSE_TYPE
        elseif not suppress_pause_type_warning then
            print_warn("Pause type is set to an unsupported value ("..pause.pause_type..").")
            suppress_pause_type_warning = true
        end
    elseif suppress_pause_type_warning then
        suppress_pause_type_warning = false
    end
end

return module
