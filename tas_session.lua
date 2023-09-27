local common_enums = require("common_enums")

---@class TasSession
    ---@field tas table The TAS data for this TAS session.
    ---@field current_level_index integer? Index of the current level in the TAS, or `nil` if undefined. This index is defined if and only if the TAS contains a level with metadata matching the game's current level.
    ---@field current_level_data table? Reference to the TAS's level data for the `current_level_index`, if the index is defined.
    ---@field current_tasable_screen TasableScreen? Reference to the TASable screen object for the current level's metadata, if the level is defined.
    ---@field current_frame_index integer? Index of the current frame in the TAS, or `nil` if undefined. The "current frame" is the TASable frame that the game most recently executed. The definition of a TASable frame varies depending on the current screen. Generally, its value is incremented after each update where player inputs are processed, but there are some exceptions for loading and cutscenes. A value of 0 means that no TASable frames have executed in the current level. This index is defined if and only if all of the following conditions are met: <br> - `current_level_index` is defined. <br> - The current frame has been continuously tracked since the level loaded. <br> - The TAS either contains frame data for this frame, or has general handling for any frame on the current screen.
    ---@field desync table? Data for a TAS desynchronization event.
    ---@field stored_level_snapshot table? Temporarily stores a level snapshot during a screen change update until a TAS level is ready to receive it.
local TasSession = {}
TasSession.__index = TasSession

function TasSession:new(tas)
    local o = {
        tas = tas
    }
    setmetatable(o, self)
    return o
end

local function metadata_matches_game_level(metadata)
    local base_screen = state.screen == SCREEN.OPTIONS and state.screen_last or state.screen
    return metadata.screen == base_screen and ((base_screen ~= SCREEN.LEVEL and base_screen ~= SCREEN.TRANSITION)
        or (metadata.world == state.world and metadata.level == state.level and metadata.theme == state.theme))
end

-- Generates a level metadata object for the game's current level.
local function generate_level_metadata()
    local metadata = {
        screen = state.screen
    }
    if state.screen == SCREEN.LEVEL or state.screen == SCREEN.TRANSITION then
        metadata.world = state.world
        metadata.level = state.level
        metadata.theme = state.theme
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

return TasSession
