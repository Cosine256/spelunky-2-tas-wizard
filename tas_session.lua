local common = require("common")
local common_enums = require("common_enums")
local game_controller = require("game_controller")
local pause_lib = require("pause")

---@class TasSession A TAS session encapsulates a TAS object and all of the state and functionality it needs in order to interact with the game engine and GUI.
    ---@field tas table The TAS data for this TAS session.
    ---@field mode integer The game interaction mode.
    ---@field playback_target_screen integer? Target screen index for playback. When in playback mode, this field should not be `nil`.
    ---@field playback_target_frame integer? Target frame index for playback. When in playback mode, this field should not be `nil`. A value of 0 means that the playback target is reached as soon at the target screen is loaded.
    ---@field playback_waiting_at_end boolean Whether playback has reached the end of the TAS. This flag is used to prevent "playback target reached" behavior from being repeated every time playback is checked. If frames are added to the end of the TAS, then the playback target will be set to the new end and this flag will be cleared.
    ---@field current_screen_index integer? Index of the current screen in the TAS, or `nil` if undefined. This index is defined if and only if the TAS contains a screen with metadata matching the game's current screen.
    ---@field current_screen_data table? Reference to the TAS's screen data for the `current_screen_index`, if the index is defined.
    ---@field current_tasable_screen TasableScreen? Reference to the TASable screen object for the current screen's metadata, if the screen is defined.
    ---@field current_frame_index integer? Index of the current frame in the TAS, or `nil` if undefined. The "current frame" is the TASable frame that the game most recently executed. The definition of a TASable frame varies depending on the current screen. Generally, its value is incremented after each update where player inputs are processed, but there are some exceptions during screen loading. A value of 0 means that no TASable frames have executed in the current screen. This index is defined if and only if all of the following conditions are met: <br> - `current_screen_index` is defined. <br> - The current frame has been continuously tracked since the screen loaded. <br> - The TAS either contains frame data for this frame, or has general handling for any frame on the current screen.
    ---@field desync table? Data for a TAS desynchronization event.
    ---@field warp_screen_index integer? The screen index being warped to when this session triggers a warp.
    ---@field stored_screen_snapshot table? Temporarily stores a screen snapshot during a screen change update until a TAS screen is ready to receive it.
    ---@field suppress_screen_tas_inputs boolean If true, then do not submit TAS inputs for the current screen. This is cleared when the current screen unloads.
    ---@field set_mode_callback function? Called when a mode setter is executed, right before the new mode is set. This is called even if the old mode is the same as the new one.
local TasSession = {}
TasSession.__index = TasSession

local POSITION_DESYNC_EPSILON = 0.0000000001
-- Menu and journal inputs are not supported. They do not work correctly during recording and playback.
local SUPPORTED_INPUTS_MASK = INPUTS.JUMP | INPUTS.WHIP | INPUTS.BOMB | INPUTS.ROPE | INPUTS.RUN | INPUTS.DOOR | INPUTS.LEFT | INPUTS.RIGHT | INPUTS.UP | INPUTS.DOWN

function TasSession:new(tas)
    local o = {
        tas = tas,
        mode = common_enums.MODE.FREEPLAY,
        suppress_screen_tas_inputs = false
    }
    setmetatable(o, self)
    o:_reset_playback_vars()
    return o
end

function TasSession:set_mode_freeplay()
    self:_reset_playback_vars()
    self.current_frame_index = nil
    if self.set_mode_callback then
        self.set_mode_callback(self.mode, common_enums.MODE.FREEPLAY)
    end
    self.mode = common_enums.MODE.FREEPLAY
end

function TasSession:set_mode_record()
    if self.mode == common_enums.MODE.PLAYBACK then
        self:_reset_playback_vars()
        if self.current_frame_index then
            if options.record_frame_clear_action == "remaining_screen" then
                self.tas:remove_frames_after(self.current_screen_index, self.current_frame_index)
            elseif options.record_frame_clear_action == "remaining_tas" then
                self.tas:remove_frames_after(self.current_screen_index, self.current_frame_index)
                self.tas:remove_screens_after(self.current_screen_index)
            end
        end
    end
    if self.set_mode_callback then
        self.set_mode_callback(self.mode, common_enums.MODE.RECORD)
    end
    self.mode = common_enums.MODE.RECORD
end

-- Sets the current mode to playback and starts playback to the given target. `check_playback` will be executed immediately after the new target is set, possibly changing the mode or target again. If playback is not possible with the given parameters and options, then the current mode and playback target is not changed.
-- `force_tas_start`: Playback will start at the beginning of the TAS, ignoring conflicting options.
-- `force_current_frame`: Playback will start at the current frame, ignoring conflicting options.
function TasSession:set_mode_playback(target_screen_index, target_frame_index, force_tas_start, force_current_frame)
    local can_use_current_frame = not force_tas_start and self.mode ~= common_enums.MODE.FREEPLAY
        and (force_current_frame or options.playback_from == "here_or_nearest_screen" or options.playback_from == "here_else_nearest_screen")
        and self.current_screen_index and self.current_frame_index
        and common.compare_screen_frame_index(target_screen_index, target_frame_index,
            self.current_screen_index, self.current_tasable_screen.record_frames and self.current_frame_index or 0) >= 0

    local best_screen_index
    if force_tas_start then
        best_screen_index = 1
    elseif not force_current_frame then
        if type(options.playback_from) == "string" then
            best_screen_index = 1
            for screen_index = target_screen_index, 2, -1 do
                if self.tas.screens[screen_index].snapshot then
                    best_screen_index = screen_index
                    break
                end
            end
        else
            if options.playback_from <= target_screen_index and (options.playback_from == 1 or self.tas.screens[options.playback_from].snapshot) then
                best_screen_index = options.playback_from
            end
        end
    end

    print_debug("mode", "set_mode_playback: Evaluating method to reach playback target %s-%s: can_use_current_frame=%s best_screen_index=%s",
        target_screen_index, target_frame_index, can_use_current_frame, best_screen_index)
    if can_use_current_frame then
        -- The current frame can be used. Decide whether a warp should be used instead.
        if best_screen_index and (options.playback_from ~= "here_or_nearest_screen" or best_screen_index <= self.current_screen_index) then
            -- Use the current frame.
            best_screen_index = nil
        end
    elseif not best_screen_index then
        -- Can neither use current frame nor use a warp.
        print_warn("Cannot reach playback target %s-%s with current options.", target_screen_index, target_frame_index)
        return
    end

    if best_screen_index then
        -- Warp to a screen to reach the playback target.
        print_debug("mode", "set_mode_playback: Warping to screen %s to reach playback target %s-%s.", best_screen_index, target_screen_index, target_frame_index)
        if not self:trigger_warp(best_screen_index) then
            print_warn("Failed to warp to screen %s to reach playback target %s-%s.", best_screen_index, target_screen_index, target_frame_index)
            return
        end
        if options.playback_from_warp_unpause then
            pause_lib.set_pausing_active(false, "Unpausing for playback from warp.")
        end
    else
        -- Playback from the current frame to reach the playback target.
        print_debug("mode", "set_mode_playback: Playing back from current frame to reach playback target %s-%s.", target_screen_index, target_frame_index)
        if options.playback_from_here_unpause then
            pause_lib.set_pausing_active(false, "Unpausing for playback from current frame.")
        end
    end

    if self.set_mode_callback then
        self.set_mode_callback(self.mode, common_enums.MODE.PLAYBACK)
    end
    self.mode = common_enums.MODE.PLAYBACK
    self.playback_target_screen = target_screen_index
    self.playback_target_frame = target_frame_index
    self.playback_waiting_at_end = false

    -- Immediately check playback in case the target already matches the current screen and frame.
    self:check_playback()
end

function TasSession:_reset_playback_vars()
    self.playback_target_screen = nil
    self.playback_target_frame = nil
    self.playback_waiting_at_end = false
end

function TasSession:reset_tas(is_active_tas_session)
    self:set_mode_freeplay()
    self:unset_current_screen()
    self.desync = nil
    self.tas:reset_data()
    if is_active_tas_session then
        for _, tool_gui in pairs(tool_guis) do
            tool_gui:reset_session_vars()
        end
    end
end

function TasSession:_on_playback_invalid(message)
    print_warn("Invalid playback target (%s): %s Switching to freeplay mode.", self:get_playback_target_string(), message)
    self:set_mode_freeplay()
    pause_lib.set_pausing_active(true, "Invalid playback target.")
end

-- Checks the current playback status. If playback is invalid, then it is stopped. If playback is valid and the target matches the current screen and frame, then the target action is executed. If not in playback mode, or if none of the prior conditions are met, then nothing happens.
function TasSession:check_playback()
    if self.mode ~= common_enums.MODE.PLAYBACK then
        return
    end
    local end_screen_index = self.tas:get_end_screen_index()
    local end_frame_index = self.tas:get_end_frame_index()
    local end_comparison = common.compare_screen_frame_index(self.playback_target_screen, self.playback_target_frame, end_screen_index, end_frame_index)
    if end_comparison > 0 then
        self:_on_playback_invalid("Target is later than end of TAS ("..end_screen_index.."-"..end_frame_index..").")
        return
    end
    if self.playback_target_frame > self.tas:get_end_frame_index(self.playback_target_screen) then
        self:_on_playback_invalid("Target is later than end of screen ("..self.playback_target_screen.."-"..self.tas:get_end_frame_index(self.playback_target_screen)..").")
        return
    end
    if game_controller.is_warping() and (state.loading == 1 or state.loading == 2) then
        -- Don't compare the playback target to the current screen and frame while warping out of the current screen.
        return
    end
    local current_comparison = common.compare_screen_frame_index(self.playback_target_screen, self.playback_target_frame,
    self.current_screen_index, self.current_tasable_screen.record_frames and self.current_frame_index or 0)
    if current_comparison < 0 then
        self:_on_playback_invalid("Current frame ("..self.current_screen_index.."-"..self.current_frame_index..") is later than playback target.")
        return
    elseif current_comparison > 0 then
        -- The playback target is later than the current screen and frame.
        return
    end

    -- The playback target is the current screen and frame.
    local new_mode = common_enums.PLAYBACK_TARGET_MODE:value_by_id(options.playback_target_mode).mode
    local allow_waiting_pause = false
    if new_mode == common_enums.MODE.RECORD then
        print_debug("mode", "check_playback: Playback target (%s) reached. Switching to record mode.", self:get_playback_target_string())
        self:set_mode_record()
    elseif new_mode == common_enums.MODE.FREEPLAY then
        print_debug("mode", "check_playback: Playback target (%s) reached. Switching to freeplay mode.", self:get_playback_target_string())
        self:set_mode_freeplay()
    elseif new_mode == common_enums.MODE.PLAYBACK then
        if end_comparison < 0 then
            -- The playback target is earlier than the end of the TAS.
            if self.playback_waiting_at_end then
                self.playback_waiting_at_end = false
                print_debug("mode", "check_playback: Detected new frames while waiting in playback mode at end of TAS. Setting target to end of TAS.")
            else
                print_debug("mode", "check_playback: Playback target (%s) reached. Staying in playback mode and setting target to end of TAS.",
                    self:get_playback_target_string())
            end
            self.playback_target_screen, self.playback_target_frame = end_screen_index, end_frame_index
        elseif not self.playback_waiting_at_end then
            -- The playback target is the end of the TAS and playback had not reached it until now.
            print_debug("mode", "check_playback: Playback target (%s) reached. Staying in playback mode at end of TAS and waiting for new frames.",
                self:get_playback_target_string())
            self.playback_waiting_at_end = true
            allow_waiting_pause = true
        end
    end

    if options.playback_target_pause and (not self.playback_waiting_at_end or allow_waiting_pause) then
        pause_lib.set_pausing_active(true, "Reached playback target.")
    end
end

function TasSession:get_playback_target_string()
    return self.playback_target_screen.."-"..self.playback_target_frame
end

local function metadata_matches_game_screen(metadata)
    local base_screen = state.screen == SCREEN.OPTIONS and state.screen_last or state.screen
    if metadata.screen == base_screen then
        if base_screen == SCREEN.LEVEL or base_screen == SCREEN.TRANSITION then
            if metadata.world == state.world and metadata.level == state.level and metadata.theme == state.theme then
                return true
            end
        else
            return true
        end
    end
    return false
end

-- Generates a screen metadata object for the game's current screen.
local function generate_screen_metadata()
    local metadata = {
        screen = state.screen
    }
    if metadata.screen == SCREEN.LEVEL or metadata.screen == SCREEN.TRANSITION then
        metadata.world = state.world
        metadata.level = state.level
        metadata.theme = state.theme
        if metadata.screen == SCREEN.LEVEL and (metadata.theme == THEME.OLMEC or metadata.theme == THEME.TIAMAT) then
            metadata.skippable_intro_cutscene = state.logic.olmec_cutscene ~= nil or state.logic.tiamat_cutscene ~= nil
        end
    end
    return metadata
end

-- Creates a new screen at the end of the TAS, sets it as the current screen, and initializes its metadata based on the game's current screen.
function TasSession:_create_end_screen()
    self:unset_current_screen()
    self.current_screen_index = #self.tas.screens + 1
    print_debug("misc", "_create_end_screen: Creating new TAS screen: %s", self.current_screen_index)
    local screen = {
        metadata = generate_screen_metadata()
    }
    self.tas.screens[self.current_screen_index] = screen
    self.current_screen_data = screen
    self.current_tasable_screen = common_enums.TASABLE_SCREEN[screen.metadata.screen]
    if self.current_tasable_screen.record_frames then
        screen.frames = {}
        screen.save_player_positions = self.tas.save_player_positions_default
    end
    if self.current_tasable_screen.can_snapshot and self.current_screen_index > 1 then
        screen.save_screen_snapshot = self.tas.save_screen_snapshot_defaults[self.current_tasable_screen.data_id]
    end
    if screen.metadata.screen == SCREEN.TRANSITION then
        screen.transition_exit_frame = common.TRANSITION_EXIT_FIRST_FRAME
    end
end

-- Sets the current screen to the first TAS screen with metadata that matches the game's current screen. If no valid TAS screen is found, then the current screen is unset.
function TasSession:find_current_screen()
    self:unset_current_screen()
    if common_enums.TASABLE_SCREEN[state.screen] then
        for screen_index = 1, #self.tas.screens do
            local screen = self.tas.screens[screen_index]
            if metadata_matches_game_screen(screen.metadata) then
                self.current_screen_index = screen_index
                self.current_screen_data = screen
                self.current_tasable_screen = common_enums.TASABLE_SCREEN[screen.metadata.screen]
                return
            end
        end
    end
end

-- Sets the current screen to the TAS screen with the given index. If the TAS does not contain this screen index, or if the TAS screen's metadata does not match the game's current screen, then the current screen will be unset. Returns whether the current screen is defined after this operation.
function TasSession:_set_current_screen(screen_index)
    self:unset_current_screen()
    local screen = self.tas.screens[screen_index]
    if screen and metadata_matches_game_screen(screen.metadata) then
        self.current_screen_index = screen_index
        self.current_screen_data = screen
        self.current_tasable_screen = common_enums.TASABLE_SCREEN[screen.metadata.screen]
    end
    return self.current_screen_index ~= nil
end

function TasSession:unset_current_screen()
    self.current_screen_index = nil
    self.current_screen_data = nil
    self.current_tasable_screen = nil
    self.current_frame_index = nil
end

-- Validates whether the current screen and frame indices are within the TAS. Prints a warning, switches to freeplay mode, and requests a pause if the current frame is invalid.
-- Returns whether the current frame valid. Returns true if the current frame is already undefined.
function TasSession:validate_current_frame()
    local unset_current_screen = false
    local message
    if self.current_screen_index then
        if self.current_screen_index > self.tas:get_end_screen_index() then
            message = "Current screen is later than end of TAS ("..self.tas:get_end_screen_index().."-"..self.tas:get_end_frame_index()..")."
            unset_current_screen = true
        elseif self.current_tasable_screen.record_frames and self.current_frame_index
            and self.current_frame_index > self.tas:get_end_frame_index(self.current_screen_index)
        then
            message = "Current frame is later than end of screen ("..self.current_screen_index.."-"..self.tas:get_end_frame_index(self.current_screen_index)..")."
        end
    end
    if message then
        print_warn("Invalid current frame (%s-%s): %s Switching to freeplay mode.", self.current_screen_index, self.current_frame_index, message)
        self:set_mode_freeplay()
        pause_lib.set_pausing_active(true, "Invalid current frame.")
        if unset_current_screen then
            self:unset_current_screen()
        end
        return false
    else
        return true
    end
end

-- Checks whether a player's expected position matches their actual position and sets position desync if they do not match. Does nothing if there is already desync. Returns whether desync was detected.
function TasSession:_check_position_desync(player_index, expected_pos, actual_pos)
    if self.desync or (actual_pos.x and math.abs(expected_pos.x - actual_pos.x) <= POSITION_DESYNC_EPSILON
        and math.abs(expected_pos.y - actual_pos.y) <= POSITION_DESYNC_EPSILON)
    then
        return false
    end

    self.desync = {
        screen_index = self.current_screen_index,
        frame_index = self.current_frame_index,
        desc = "Actual player "..player_index.." position differs from expected position."
    }
    print_warn("Desynchronized on frame %s-%s: %s", self.desync.screen_index, self.desync.frame_index, self.desync.desc)
    print_warn("    Expected: x=%s y=%s", expected_pos.x, expected_pos.y)
    if actual_pos.x then
        print_warn("    Actual: x=%s y=%s", actual_pos.x, actual_pos.y)
        print_warn("    Diff: dx=%s dy=%s", actual_pos.x - expected_pos.x, actual_pos.y - expected_pos.y)
    else
        print_warn("    Actual: undefined")
    end
    return true
end

function TasSession:_set_screen_end_desync()
    self.desync = {
        screen_index = self.current_screen_index,
        frame_index = self.current_frame_index,
        desc = "Expected end of screen."
    }
    print_warn("Desynchronized on frame %s-%s: %s", self.desync.screen_index, self.desync.frame_index, self.desync.desc)
end

-- Triggers a warp to the specified TAS screen. If warping to screen 1, then the TAS start settings will be used. Otherwise, a screen snapshot will be used. No warp will occur if the TAS does not contain the necessary data to warp to the specified screen. Returns whether the warp was triggered successfully.
function TasSession:trigger_warp(screen_index)
    local warp_triggered = false
    if screen_index == 1 then
        if self.tas:is_start_configured() then
            if self.tas.start_type == "simple" then
                warp_triggered = game_controller.trigger_start_simple_warp(self.tas)
            elseif self.tas.start_type == "snapshot" then
                warp_triggered = game_controller.trigger_screen_snapshot_warp(self.tas.start_snapshot)
            end
        end
    else
        local screen = self.tas.screens[screen_index]
        if screen and screen.snapshot then
            warp_triggered = game_controller.trigger_screen_snapshot_warp(screen.snapshot)
        else
            print_info("Cannot trigger warp to screen %s: Missing screen snapshot.", screen_index)
        end
    end
    if warp_triggered then
        self.warp_screen_index = screen_index
    end
    return warp_triggered
end

-- Called before a game update which will load a screen, excluding loading or unloading the options screen.
function TasSession:on_pre_update_load_screen()
    local tasable_screen = common_enums.TASABLE_SCREEN[state.screen_next]
    if not self.warp_screen_index and tasable_screen and tasable_screen.can_snapshot
        and (self.mode == common_enums.MODE.RECORD or (self.mode == common_enums.MODE.PLAYBACK
        and self.current_screen_index < self.tas:get_end_screen_index() and not self.tas.screens[self.current_screen_index + 1].snapshot))
    then
        -- Request a screen snapshot of the upcoming screen.
        game_controller.register_screen_snapshot_request(function(screen_snapshot)
            -- The snapshot request will be fulfilled before the TAS session knows which screen it belongs to. Temporarily store it until a TAS screen is ready for it.
            self.stored_screen_snapshot = screen_snapshot
        end)
    end
end

-- Called after a game update which loaded a screen, excluding loading or unloading the options screen.
function TasSession:on_post_update_load_screen()
    self.suppress_screen_tas_inputs = false

    if not common_enums.TASABLE_SCREEN[state.screen] then
        -- The new screen is not TASable.
        self:unset_current_screen()
        if self.mode ~= common_enums.MODE.FREEPLAY then
            print_debug("mode", "on_post_update_load_screen: Loaded non-TASable screen. Switching to freeplay mode.")
            self:set_mode_freeplay()
        end
    elseif self.warp_screen_index then
        -- This screen change was a known warp.
        if not self:_set_current_screen(self.warp_screen_index) then
            if self.mode == common_enums.MODE.FREEPLAY then
                -- The screen won't exist yet if freeplay warping to screen 1 in a TAS with no recorded data.
                if self.warp_screen_index ~= 1 or #self.tas.screens > 0 then
                    print_warn("Loaded unexpected screen when warping to screen index %s.", self.warp_screen_index)
                end
            else
                if self.mode == common_enums.MODE.RECORD and self.warp_screen_index == #self.tas.screens + 1 then
                    self:_create_end_screen()
                else
                    print_warn("Loaded unexpected screen when warping to screen index %s. Switching to freeplay mode.", self.warp_screen_index)
                    self:set_mode_freeplay()
                end
            end
        end
    elseif self.current_screen_index then
        -- This screen change was not a known warp and the previous screen index is known.
        local prev_screen_index = self.current_screen_index
        if not self:_set_current_screen(prev_screen_index + 1) then
            if self.mode == common_enums.MODE.FREEPLAY then
                self:find_current_screen()
            else
                if prev_screen_index == #self.tas.screens then
                    if self.mode == common_enums.MODE.RECORD then
                        self:_create_end_screen()
                    else
                        print_debug("mode", "Loaded new screen during playback after end of TAS. Switching to freeplay mode.")
                        self:set_mode_freeplay()
                    end
                else
                    print_warn("Loaded unexpected screen after screen change from screen index %s. Switching to freeplay mode.", prev_screen_index)
                    self:set_mode_freeplay()
                end
            end
        end
    else
        -- This screen change was not a known warp and the previous screen index is not known.
        if self.mode == common_enums.MODE.FREEPLAY then
            self:find_current_screen()
        else
            -- Note: This case should not be possible. Playback and recording should always know either the previous screen index or the new screen index.
            print_warn("Loaded new screen during playback or recording with unknown previous screen index and unknown new screen index. Switching to freeplay mode.")
            self:set_mode_freeplay()
        end
    end
    print_debug("screen_load", "on_post_update_load_screen: Current TAS screen updated to %s.", self.current_screen_index)
    if self.mode ~= common_enums.MODE.FREEPLAY then
        self.current_frame_index = 0
        if self.current_tasable_screen.record_frames then
            local start_positions = self.current_screen_data.start_positions
            if not start_positions then
                start_positions = {}
                self.current_screen_data.start_positions = start_positions
            end
            for player_index = 1, self.tas:get_player_count() do
                local player_ent = get_player(player_index, true)
                local actual_pos
                if player_ent then
                    local x, y, l = get_position(player_ent.uid)
                    actual_pos = { x = x, y = y, l = l }
                else
                    actual_pos = {}
                end
                if self.mode == common_enums.MODE.RECORD or not start_positions[player_index] or not start_positions[player_index].x then
                    start_positions[player_index] = actual_pos
                elseif self:_check_position_desync(player_index, start_positions[player_index], actual_pos) and options.desync_pause then
                    pause_lib.set_pausing_active(true, "Detected start position desync.")
                end
            end
        end
        if self.current_tasable_screen.can_snapshot and self.stored_screen_snapshot then
            self.current_screen_data.snapshot = self.stored_screen_snapshot
            print_debug("snapshot", "on_post_update_load_screen: Transferred stored screen snapshot into TAS screen %s.", self.current_screen_index)
        end
        if (self.mode == common_enums.MODE.PLAYBACK and options.playback_screen_load_pause)
            or (self.mode == common_enums.MODE.RECORD and options.record_screen_load_pause)
        then
            pause_lib.set_pausing_active(true, "New screen loaded.")
        end
        if self.mode == common_enums.MODE.PLAYBACK and self.current_screen_index == self.playback_target_screen then
            game_controller.dont_skip_this_screen = true
        end
        -- Check playback in case of a frame 0 playback target.
        self:check_playback()
    end

    self.warp_screen_index = nil
    self.stored_screen_snapshot = nil
end

-- Called before every game update, excluding screen load updates.
function TasSession:on_pre_update()
    -- Exclude updates where there is no chance of a TASable frame executing or where nothing needs to be done.
    if not self:validate_current_frame() or self.mode == common_enums.MODE.FREEPLAY or not self.current_screen_index or not self.current_frame_index
        or self.suppress_screen_tas_inputs or state.screen == SCREEN.OPTIONS or (state.loading ~= 0 and state.loading ~= 3)
    then
        return
    end

    if self.current_tasable_screen.record_frames then
        -- Only playback mode should submit inputs.
        if self.mode == common_enums.MODE.PLAYBACK then
            -- It's acceptable to not have frame data for the upcoming update as long as the game doesn't process player inputs. If inputs are processed with no frame data, then that scenario will be detected and handled after the update.
            local next_frame_data = self.current_screen_data.frames[self.current_frame_index + 1]
            if next_frame_data then
                game_controller.submit_pre_update_inputs(next_frame_data.inputs)
            end
        end
    elseif self.current_screen_data.metadata.screen == SCREEN.TRANSITION then
        -- Exiting is triggered during the first update where the exit input is seen being held down, not when it's released. The earliest update where inputs are processed is the final update of the fade-in. If an exit input is seen during the earliest update, then the fade-out is started in that same update. The update still executes entity state machines, so characters can be seen stepping forward for a single frame. This is the same behavior that occurs in normal gameplay by holding down the exit input while the transition screen fades in. Providing the exit input on later frames has a delay before the fade-out starts because the transition UI panel has to scroll off screen first.
        local frame_inputs = {}
        for player_index = 1, self.tas:get_player_count() do
            -- By default, suppress inputs from every player.
            frame_inputs[player_index] = INPUTS.NONE
        end
        if self.current_frame_index + 1 >= self.current_screen_data.transition_exit_frame then
            -- Have player 1 provide the transition exit input.
            frame_inputs[1] = INPUTS.JUMP
        end
        game_controller.submit_pre_update_inputs(frame_inputs)
    end
    -- Note: There is nothing to do on the spaceship screen except wait for it to end.
end

-- Called after every game update, excluding screen load updates.
function TasSession:on_post_update()
    if self.mode == common_enums.MODE.FREEPLAY or not self.current_screen_index or not self.current_frame_index
        or state.screen == SCREEN.OPTIONS or not game_controller.did_entities_update()
    then
        return
    end

    -- A TASable frame occurred during this update.
    self.current_frame_index = self.current_frame_index + 1

    print_debug("input", "on_post_update: frame=%s-%s p1_inputs=%s", self.current_screen_index, self.current_frame_index,
        common.inputs_to_string(state.player_inputs.player_slots[1].buttons_gameplay))

    if self.current_tasable_screen.record_frames then
        local current_frame_data = self.current_screen_data.frames[self.current_frame_index]
        if self.mode == common_enums.MODE.RECORD then
            -- Only record mode can create new frames. Playback mode should only be active during frames that already exist.
            if options.record_frame_write_type == "overwrite" then
                if not current_frame_data then
                    current_frame_data = {}
                    self.current_screen_data.frames[self.current_frame_index] = current_frame_data
                end
            elseif options.record_frame_write_type == "insert" then
                current_frame_data = {}
                table.insert(self.current_screen_data.frames, self.current_frame_index, current_frame_data)
            end
        elseif self.mode == common_enums.MODE.PLAYBACK and not current_frame_data then
            -- A TASable frame just executed during playback without frame data. This is normal on the last screen of the TAS since it means the user played back past the end of the TAS. Otherwise, it's a desync scenario because the game should be switching to the next screen instead of executing more TASable frames on the current screen.
            if not self.desync and self.current_screen_index < self.tas:get_end_screen_index() then
                self:_set_screen_end_desync()
                if options.desync_pause then
                    pause_lib.set_pausing_active(true, "Detected screen end desync.")
                end
            end
            print_debug("mode", "on_post_update: Executed TASable frame during playback without frame data. Switching to freeplay mode.")
            self:set_mode_freeplay()
            return
        end

        if not current_frame_data.positions then
            current_frame_data.positions = {}
        end
        for player_index = 1, self.tas:get_player_count() do
            local player_ent = get_player(player_index, true)
            local actual_pos
            if player_ent then
                local x, y, l = get_position(player_ent.uid)
                actual_pos = { x = x, y = y, l = l }
            else
                actual_pos = {}
            end
            if self.mode == common_enums.MODE.RECORD then
                -- Record the current player inputs for the frame that just executed.
                local inputs = state.player_inputs.player_slots[player_index].buttons_gameplay & SUPPORTED_INPUTS_MASK
                print_debug("input", "on_post_update: Recording inputs: frame=%s-%s player=%s inputs=%s",
                    self.current_screen_index, self.current_frame_index, player_index, common.inputs_to_string(inputs))
                if not current_frame_data.inputs then
                    current_frame_data.inputs = {}
                end
                current_frame_data.inputs[player_index] = inputs
                current_frame_data.positions[player_index] = actual_pos
            elseif self.mode == common_enums.MODE.PLAYBACK then
                local expected_pos = current_frame_data.positions[player_index]
                if expected_pos and expected_pos.x then
                    if self:_check_position_desync(player_index, expected_pos, actual_pos) and options.desync_pause then
                        pause_lib.set_pausing_active(true, "Detected position desync.")
                    end
                else
                    -- No player positions are stored for this frame. Store the current positions.
                    current_frame_data.positions[player_index] = actual_pos
                end
            end
        end
    end

    self:check_playback()
end

return TasSession
