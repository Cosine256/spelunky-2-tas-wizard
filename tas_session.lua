---@class TasSession
    ---@field tas any
    ---@field current_level_index integer? Index of the current level in the TAS, or `nil` if undefined. This index is defined if and only if all of the following conditions are met: <br> - The game is in a playable level or the camp. <br> - The level type matches whether the TAS is for regular levels or the tutorial race. <br> - The TAS contains level data for this level.
    ---@field current_level_data any Reference to the TAS's level data for the `current_level_index`, if the index is defined.
    ---@field current_frame_index integer? Index of the current frame in the TAS, or `nil` if undefined. The "current frame" is the frame that the game most recently executed, and its value is incremented after an update where a frame of gameplay occurred. A value of 0 means that no gameplay frames have occurred in the current level. This index is defined if and only if all of the following conditions are met: <br> - `current_level_index` is defined. <br> - The current frame has been continuously tracked since the level loaded. <br> - The TAS contains frame data for this frame.
    ---@field desync table? Data for desynchronization of the TAS.
local TasSession = {}
TasSession.__index = TasSession

function TasSession:new(tas)
    local o = {
        tas = tas
    }
    setmetatable(o, self)
    return o
end

-- Gets whether the current or underlying screen is the camp, or whether the game is loading into a new camp screen.
local function is_base_screen_camp()
    if state.loading == 2 then
        return state.screen ~= SCREEN.OPTIONS and state.screen_next == SCREEN.CAMP
    else
        return state.screen == SCREEN.CAMP or (state.screen_last == SCREEN.CAMP and state.screen == SCREEN.OPTIONS)
    end
end

-- Gets whether the current or underlying screen is a level, or whether the game is loading into a new level screen.
local function is_base_screen_level()
    if state.loading == 2 then
        return state.screen ~= SCREEN.OPTIONS and state.screen_next == SCREEN.LEVEL
    else
        return state.screen == SCREEN.LEVEL or (state.screen_last == SCREEN.LEVEL and (state.screen == SCREEN.OPTIONS or state.screen == SCREEN.DEATH))
    end
end

function TasSession:update_current_level_index(can_create)
    self:clear_current_level_index()
    if self.tas:is_start_configured() then
        -- TODO: current_level_index is miscalculated for either start type if the TAS starts in the camp and contains more than one level.
        if self.tas.start_type == "simple" then
            if self.tas.start_simple.tutorial_race then
                if is_base_screen_camp() then
                    self.current_level_index = 1
                end
            else
                if is_base_screen_level() then
                    if state.loading == 2 and test_flag(state.quest_flags, QUEST_FLAG.RESET) then
                        self.current_level_index = 1
                    else
                        self.current_level_index = state.level_count + 1
                    end
                end
            end
        elseif self.tas.start_type == "full" then
            if is_base_screen_level() then
                if state.loading == 2 and test_flag(state.quest_flags, QUEST_FLAG.RESET) then
                    if self.tas.start_full.state_memory.level_count == 0 then
                        self.current_level_index = 1
                    end
                else
                    self.current_level_index = state.level_count - self.tas.start_full.state_memory.level_count + 1
                end
            elseif is_base_screen_camp() then
                self.current_level_index = 1
            end
        end
    end
    if self.current_level_index then
        self.current_level_data = self.tas.levels[self.current_level_index]
        if not self.current_level_data then
            if can_create and (self.current_level_index == 1 or self.tas.levels[self.current_level_index - 1]) then
                print("Initializing level data for new level: "..self.current_level_index)
                self.current_level_data = self.tas:create_level_data()
                self.tas.levels[self.current_level_index] = self.current_level_data
            else
                self.current_level_index = nil
            end
        end
    end
end

function TasSession:clear_current_level_index()
    self.current_level_index = nil
    self.current_level_data = nil
    self.current_frame_index = nil
end

return TasSession
