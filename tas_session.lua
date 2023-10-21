local common = require("common")
local common_enums = require("common_enums")

---@class TasSession
    ---@field tas table The TAS data for this TAS session.
    ---@field mode integer The game interaction mode.
    ---@field current_level_index integer? Index of the current level in the TAS, or `nil` if undefined. This index is defined if and only if the TAS contains a level with metadata matching the game's current level.
    ---@field current_level_data table? Reference to the TAS's level data for the `current_level_index`, if the index is defined.
    ---@field current_tasable_screen TasableScreen? Reference to the TASable screen object for the current level's metadata, if the level is defined.
    ---@field current_frame_index integer? Index of the current frame in the TAS, or `nil` if undefined. The "current frame" is the TASable frame that the game most recently executed. The definition of a TASable frame varies depending on the current screen. Generally, its value is incremented after each update where player inputs are processed, but there are some exceptions during screen loading. A value of 0 means that no TASable frames have executed in the current level. This index is defined if and only if all of the following conditions are met: <br> - `current_level_index` is defined. <br> - The current frame has been continuously tracked since the level loaded. <br> - The TAS either contains frame data for this frame, or has general handling for any frame on the current screen.
    ---@field playback_target_level integer? Target level index for playback. When in playback mode, this field should not be `nil`.
    ---@field playback_target_frame integer? Target frame index for playback. When in playback mode, this field should not be `nil`. A value of 0 means that the playback target is reached as soon at the target level is loaded.
    ---@field playback_waiting_at_end boolean Whether playback has reached the end of the TAS. This flag is used to prevent "playback target reached" behavior from being repeated every time playback is checked. If frames are added to the end of the TAS, then the playback target will be set to the new end and this flag will be cleared.
    ---@field playback_force_full_run boolean
    ---@field playback_force_current_frame boolean
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
    o:reset_playback_vars()
    return o
end

function TasSession:reset_playback_vars()
    self.playback_target_level = nil
    self.playback_target_frame = nil
    self.playback_waiting_at_end = false
    self.playback_force_full_run = false
    self.playback_force_current_frame = false
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

function TasSession:get_playback_target_string()
    return self.playback_target_level.."-"..self.playback_target_frame
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
