local TasSession = {}
TasSession.__index = TasSession

function TasSession:new(tas)
    local o = {
        tas = tas,
        --[[
        Index of the current level in the TAS, or -1 if undefined. This index is defined if and only if all of the following conditions are met:
            The game is in a playable level or the camp.
            The level type matches whether the TAS is for regular levels or the tutorial race.
            The TAS contains level data for this level.
        ]]
        current_level_index = -1,
        -- Reference to the TAS's level data for the `current_level_index`, if the index is defined.
        current_level_data = nil
    }
    setmetatable(o, self)
    return o
end

function TasSession:update_current_level_index(can_create)
    self:clear_current_level_index()
    if self.tas.start_type == "simple" then
        if self.tas.start_simple.tutorial_race then
            if state.screen == SCREEN.CAMP or (state.screen_last == SCREEN.CAMP and state.screen == SCREEN.OPTIONS) then
                self.current_level_index = 1
            end
        else
            if state.screen == SCREEN.LEVEL or (state.screen_last == SCREEN.LEVEL and (state.screen == SCREEN.OPTIONS or state.screen == SCREEN.DEATH)) then
                self.current_level_index = state.level_count + 1
            end
        end
    end
    self.current_level_data = self.tas.levels[self.current_level_index]
    if not self.current_level_data then
        if can_create and (self.current_level_index == 1 or self.tas.levels[self.current_level_index - 1]) then
            print("Initializing level data for new level: "..self.current_level_index)
            self.current_level_data = self.tas:create_level_data()
            self.tas.levels[self.current_level_index] = self.current_level_data
        else
            self.current_level_index = -1
        end
    end
end

function TasSession:clear_current_level_index()
    self.current_level_index = -1
    self.current_level_data = nil
end

return TasSession
