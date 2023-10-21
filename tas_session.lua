local common = require("common")
local common_enums = require("common_enums")
local game_controller = require("game_controller")

---@class TasSession
    ---@field tas table The TAS data for this TAS session.
    ---@field mode integer The game interaction mode.
    ---@field playback_target_level integer? Target level index for playback. When in playback mode, this field should not be `nil`.
    ---@field playback_target_frame integer? Target frame index for playback. When in playback mode, this field should not be `nil`. A value of 0 means that the playback target is reached as soon at the target level is loaded.
    ---@field playback_waiting_at_end boolean Whether playback has reached the end of the TAS. This flag is used to prevent "playback target reached" behavior from being repeated every time playback is checked. If frames are added to the end of the TAS, then the playback target will be set to the new end and this flag will be cleared.
    ---@field current_level_index integer? Index of the current level in the TAS, or `nil` if undefined. This index is defined if and only if the TAS contains a level with metadata matching the game's current level.
    ---@field current_level_data table? Reference to the TAS's level data for the `current_level_index`, if the index is defined.
    ---@field current_tasable_screen TasableScreen? Reference to the TASable screen object for the current level's metadata, if the level is defined.
    ---@field current_frame_index integer? Index of the current frame in the TAS, or `nil` if undefined. The "current frame" is the TASable frame that the game most recently executed. The definition of a TASable frame varies depending on the current screen. Generally, its value is incremented after each update where player inputs are processed, but there are some exceptions during screen loading. A value of 0 means that no TASable frames have executed in the current level. This index is defined if and only if all of the following conditions are met: <br> - `current_level_index` is defined. <br> - The current frame has been continuously tracked since the level loaded. <br> - The TAS either contains frame data for this frame, or has general handling for any frame on the current screen.
    ---@field desync table? Data for a TAS desynchronization event.
    ---@field stored_level_snapshot table? Temporarily stores a level snapshot during a screen change update until a TAS level is ready to receive it.
local TasSession = {}
TasSession.__index = TasSession

local POSITION_DESYNC_EPSILON = 0.0000000001

function TasSession:new(tas)
    local o = {
        tas = tas,
        mode = common_enums.MODE.FREEPLAY
    }
    setmetatable(o, self)
    o:_reset_playback_vars()
    return o
end

function TasSession:set_mode_freeplay()
    self:_reset_playback_vars()
    self.current_frame_index = nil
    self.mode = common_enums.MODE.FREEPLAY
end

function TasSession:set_mode_record()
    if self.mode == common_enums.MODE.PLAYBACK then
        self:_reset_playback_vars()
        if self.current_frame_index then
            if options.record_frame_clear_action == "remaining_level" then
                self.tas:remove_frames_after(self.current_level_index, self.current_frame_index)
            elseif options.record_frame_clear_action == "remaining_run" then
                self.tas:remove_frames_after(self.current_level_index, self.current_frame_index)
                self.tas:remove_levels_after(self.current_level_index)
            end
        end
    end
    self.mode = common_enums.MODE.RECORD
end

-- Sets the current mode to playback and starts playback to the given target. `check_playback` will be executed immediately after the new target is set, possibly changing the mode or target again. If playback is not possible with the given parameters and options, then the current mode and playback target is not changed.
-- `force_tas_start`: Playback will start at the beginning of the TAS, ignoring conflicting options.
-- `force_current_frame`: Playback will start at the current frame, ignoring conflicting options.
function TasSession:set_mode_playback(target_level_index, target_frame_index, force_tas_start, force_current_frame)
    local can_use_current_frame = not force_tas_start and self.mode ~= common_enums.MODE.FREEPLAY
        and (force_current_frame or options.playback_from == common_enums.PLAYBACK_FROM.HERE_OR_NEAREST_LEVEL
            or options.playback_from == common_enums.PLAYBACK_FROM.HERE_ELSE_NEAREST_LEVEL)
        and self.current_level_index and self.current_frame_index
        and common.compare_level_frame_index(target_level_index, target_frame_index,
            self.current_level_index, self.current_tasable_screen.record_frames and self.current_frame_index or 0) >= 0

    local load_level_index
    if force_tas_start then
        load_level_index = 1
    elseif not force_current_frame then
        if options.playback_from <= 3 then
            load_level_index = 1
            for level_index = target_level_index, 2, -1 do
                if self.tas.levels[level_index].snapshot then
                    load_level_index = level_index
                    break
                end
            end
        else
            local playback_from_level_index = options.playback_from - 3
            if playback_from_level_index <= target_level_index and (playback_from_level_index == 1 or self.tas.levels[playback_from_level_index].snapshot) then
                load_level_index = playback_from_level_index
            end
        end
    end

    if options.debug_print_mode then
        print("Evaluating method to reach playback target "..target_level_index.."-"..target_frame_index
            ..": can_use_current_frame="..tostring(can_use_current_frame).." load_level_index="..tostring(load_level_index))
    end
    if can_use_current_frame then
        -- The current frame can be used. Decide whether a level should be loaded instead.
        if load_level_index and (options.playback_from ~= common_enums.PLAYBACK_FROM.HERE_OR_NEAREST_LEVEL or load_level_index <= self.current_level_index) then
            -- Use the current frame.
            load_level_index = nil
        end
    elseif not load_level_index then
        -- Can neither use current frame nor load a level state.
        print("Warning: Cannot reach playback target "..target_level_index.."-"..target_frame_index.." with current options.")
        return
    end

    if load_level_index then
        -- Load a level to reach the playback target.
        if options.debug_print_mode then
            print("Loading level "..load_level_index.." to reach playback target "..target_level_index.."-"..target_frame_index..".")
        end
        local load_success
        if load_level_index == 1 then
            load_success = game_controller.apply_start_state()
        else
            load_success = game_controller.apply_level_snapshot(load_level_index)
        end
        if not load_success then
            print("Warning: Failed to load level "..load_level_index.." to reach playback target "..target_level_index.."-"..target_frame_index..".")
            return
        end
    else
        -- Playback from the current frame to reach the playback target.
        if options.debug_print_mode then
            print("Playing back from current frame to reach playback target "..target_level_index.."-"..target_frame_index..".")
        end
    end

    self.mode = common_enums.MODE.PLAYBACK
    self.playback_target_level = target_level_index
    self.playback_target_frame = target_frame_index
    self.playback_waiting_at_end = false

    -- Immediately check playback in case the target already matches the current level and frame.
    self:check_playback()
end

function TasSession:_reset_playback_vars()
    self.playback_target_level = nil
    self.playback_target_frame = nil
    self.playback_waiting_at_end = false
end

function TasSession:_on_playback_invalid(message)
    print("Warning: Invalid playback target ("..self:get_playback_target_string().."): "..message.." Switching to freeplay mode.")
    self:set_mode_freeplay()
    game_controller.request_pause("Invalid playback target.")
end

-- Checks the current playback status. If playback is invalid, then it is stopped. If playback is valid and the target matches the current level and frame, then the target action is executed. If not in playback mode, or if none of the prior conditions are met, then nothing happens.
function TasSession:check_playback()
    if self.mode ~= common_enums.MODE.PLAYBACK then
        return
    end
    local end_level_index, end_frame_index = self.tas:get_end_indices()
    local end_comparison = common.compare_level_frame_index(self.playback_target_level, self.playback_target_frame, end_level_index, end_frame_index)
    if end_comparison > 0 then
        self:_on_playback_invalid("Target is later than end of TAS ("..end_level_index.."-"..end_frame_index..").")
        return
    end
    if self.playback_target_frame > self.tas:get_end_frame_index(self.playback_target_level) then
        self:_on_playback_invalid("Target is later than end of level ("..self.playback_target_level.."-"..self.tas:get_end_frame_index(self.playback_target_level)..").")
        return
    end
    if game_controller.is_warping() and (state.loading == 1 or state.loading == 2) then
        -- Don't compare the playback target to the current level and frame while warping out of the current level.
        return
    end
    local current_comparison = common.compare_level_frame_index(self.playback_target_level, self.playback_target_frame,
    self.current_level_index, self.current_tasable_screen.record_frames and self.current_frame_index or 0)
    if current_comparison < 0 then
        self:_on_playback_invalid("Current frame ("..self.current_level_index.."-"..self.current_frame_index..") is later than playback target.")
        return
    elseif current_comparison > 0 then
        -- The playback target is later than the current level and frame.
        return
    end

    -- The playback target is the current level and frame.
    local new_mode = common_enums.PLAYBACK_TARGET_MODE:value_by_id(options.playback_target_mode).mode
    local allow_waiting_pause = false
    if new_mode == common_enums.MODE.RECORD then
        if options.debug_print_mode then
            print("Playback target ("..self:get_playback_target_string()..") reached. Switching to record mode.")
        end
        self:set_mode_record()
    elseif new_mode == common_enums.MODE.FREEPLAY then
        if options.debug_print_mode then
            print("Playback target ("..self:get_playback_target_string()..") reached. Switching to freeplay mode.")
        end
        self:set_mode_freeplay()
    elseif new_mode == common_enums.MODE.PLAYBACK then
        if end_comparison < 0 then
            -- The playback target is earlier than the end of the TAS.
            if self.playback_waiting_at_end then
                self.playback_waiting_at_end = false
                if options.debug_print_mode then
                    print("Detected new frames while waiting in playback mode at end of TAS. Setting target to end of TAS.")
                end
            elseif options.debug_print_mode then
                print("Playback target ("..self:get_playback_target_string()..") reached. Staying in playback mode and setting target to end of TAS.")
            end
            self.playback_target_level, self.playback_target_frame = end_level_index, end_frame_index
        elseif not self.playback_waiting_at_end then
            -- The playback target is the end of the TAS and playback had not reached it until now.
            if options.debug_print_mode then
                print("Playback target ("..self:get_playback_target_string()..") reached. Staying in playback mode at end of TAS and waiting for new frames.")
            end
            self.playback_waiting_at_end = true
            allow_waiting_pause = true
        end
    end

    if options.playback_target_pause and (not self.playback_waiting_at_end or allow_waiting_pause) then
        game_controller.request_pause("Reached playback target.")
    end
end

function TasSession:get_playback_target_string()
    return self.playback_target_level.."-"..self.playback_target_frame
end

local function metadata_matches_game_level(metadata)
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

-- Generates a level metadata object for the game's current level.
local function generate_level_metadata()
    local metadata = {
        screen = state.screen
    }
    if metadata.screen == SCREEN.LEVEL or metadata.screen == SCREEN.TRANSITION then
        metadata.world = state.world
        metadata.level = state.level
        metadata.theme = state.theme
        if metadata.screen == SCREEN.LEVEL and (metadata.theme == THEME.OLMEC or metadata.theme == THEME.TIAMAT) then
            metadata.cutscene = state.logic.olmec_cutscene ~= nil or state.logic.tiamat_cutscene ~= nil
        end
    end
    return metadata
end

-- Creates a new level at the end of the TAS, sets it as the current level, and initializes its metadata based on the game's current level.
function TasSession:create_end_level()
    self:unset_current_level()
    self.current_level_index = #self.tas.levels + 1
    print("Creating new TAS level: "..self.current_level_index)
    local level = {
        metadata = generate_level_metadata()
    }
    self.tas.levels[self.current_level_index] = level
    self.current_level_data = level
    self.current_tasable_screen = common_enums.TASABLE_SCREEN[level.metadata.screen]
    if self.current_tasable_screen.record_frames then
        level.frames = {}
        level.players = {}
        for player_index = 1, self.tas:get_player_count() do
            level.players[player_index] = {}
        end
    end
    if level.metadata.screen == SCREEN.TRANSITION then
        level.transition_exit_frame_index = common.TRANSITION_EXIT_FIRST_FRAME
    end
end

-- Sets the current level to the first TAS level with metadata that matches the game's current level. If no valid TAS level is found, then the current level is unset.
function TasSession:find_current_level()
    self:unset_current_level()
    if common_enums.TASABLE_SCREEN[state.screen] then
        for level_index = 1, #self.tas.levels do
            local level = self.tas.levels[level_index]
            if metadata_matches_game_level(level.metadata) then
                self.current_level_index = level_index
                self.current_level_data = level
                self.current_tasable_screen = common_enums.TASABLE_SCREEN[level.metadata.screen]
                return
            end
        end
    end
end

-- Sets the current level to the TAS level with the given index. If the TAS does not contain this level index, or if the TAS level's metadata does not match the game's current level, then the current level will be unset. Returns whether the current level is defined after this operation.
function TasSession:set_current_level(level_index)
    self:unset_current_level()
    local level = self.tas.levels[level_index]
    if level and metadata_matches_game_level(level.metadata) then
        self.current_level_index = level_index
        self.current_level_data = level
        self.current_tasable_screen = common_enums.TASABLE_SCREEN[level.metadata.screen]
    end
    return self.current_level_index ~= nil
end

function TasSession:unset_current_level()
    self.current_level_index = nil
    self.current_level_data = nil
    self.current_tasable_screen = nil
    self.current_frame_index = nil
end

-- Validates whether the current level and frame indices are within the TAS. Prints a warning, switches to freeplay mode, and requests a pause if the current frame is invalid.
-- Returns whether the current frame valid. Returns true if the current frame is already undefined.
function TasSession:validate_current_frame()
    local unset_current_level = false
    local message
    if self.current_level_index then
        if self.current_level_index > self.tas:get_end_level_index() then
            message = "Current level is later than end of TAS ("..self.tas:get_end_level_index().."-"..self.tas:get_end_frame_index()..")."
            unset_current_level = true
        elseif self.current_tasable_screen.record_frames and self.current_frame_index
            and self.current_frame_index > self.tas:get_end_frame_index(self.current_level_index)
        then
            message = "Current frame is later than end of level ("..self.current_level_index.."-"..self.tas:get_end_frame_index(self.current_level_index)..")."
        end
    end
    if message then
        print("Warning: Invalid current frame ("..self.current_level_index.."-"..tostring(self.current_frame_index).."): "..message.." Switching to freeplay mode.")
        self:set_mode_freeplay()
        game_controller.request_pause("Invalid current frame.")
        if unset_current_level then
            self:unset_current_level()
        end
        return false
    else
        return true
    end
end

-- Checks whether a player's expected position matches their actual position and sets position desync if they do not match. Does nothing if there is already desync. Returns whether desync was detected.
function TasSession:check_position_desync(player_index, expected_pos, actual_pos)
    if self.desync or (actual_pos and math.abs(expected_pos.x - actual_pos.x) <= POSITION_DESYNC_EPSILON
        and math.abs(expected_pos.y - actual_pos.y) <= POSITION_DESYNC_EPSILON)
    then
        return false
    end

    self.desync = {
        level_index = self.current_level_index,
        frame_index = self.current_frame_index,
        desc = "Actual player "..player_index.." position differs from expected position."
    }
    print("Desynchronized on frame "..self.desync.level_index.."-"..self.desync.frame_index..": "..self.desync.desc)
    print("    Expected: x="..expected_pos.x.." y="..expected_pos.y)
    if actual_pos then
        print("    Actual: x="..actual_pos.x.." y="..actual_pos.y)
        print("    Diff: dx="..(actual_pos.x - expected_pos.x).." dy="..(actual_pos.y - expected_pos.y))
    else
        print("    Actual: nil")
    end
    return true
end

function TasSession:set_level_end_desync()
    self.desync = {
        level_index = self.current_level_index,
        frame_index = self.current_frame_index,
        desc = "Expected end of level."
    }
    print("Desynchronized on frame "..self.desync.level_index.."-"..self.desync.frame_index..": "..self.desync.desc)
end

return TasSession
