local common = require("common")
local common_enums = require("common_enums")
local persistence = require("persistence")

local Tas = {}
Tas.__index = Tas

-- Additional modifications to make to a raw TAS object for (de)serializion.
Tas.SERIAL_MODS = {
    -- Don't make any modifications.
    NONE = 1,
    -- Make modifications for a normal TAS. Unused values are considered transient and omitted from serialization.
    NORMAL = 2,
    -- Make modifications for the "new" TAS stored in the options. Unused values are kept for serialization.
    OPTIONS = 3
}

function Tas:new(obj, copy_obj)
    local o
    if obj == nil then
        o = {}
    else
        o = copy_obj and common.deep_copy(obj) or obj
    end
    setmetatable(o, self)
    return o
end

-- Create a copy of this TAS.
function Tas:copy()
    return Tas:new(self:to_raw(Tas.SERIAL_MODS.NONE), false)
end

local CURRENT_FORMAT = 1
local FORMAT_UPDATERS = {}

-- Create a raw copy of this TAS, containing only tables and primitive types, with no functions or prototyping.
-- serial_mod: Pre-serialization modifications to make to the raw object.
function Tas:to_raw(serial_mod)
    local copy = {
        name = self.name,
        description = self.description,
        start_type = self.start_type,
        start_simple = common.deep_copy(self.start_simple),
        start_snapshot = common.deep_copy(self.start_snapshot),
        screens = {},
        frame_tags = common.deep_copy(self.frame_tags),
        save_player_positions_default = self.save_player_positions_default,
        save_screen_snapshot_defaults = common.deep_copy(self.save_screen_snapshot_defaults)
    }
    if serial_mod ~= Tas.SERIAL_MODS.NONE then
        copy.format = CURRENT_FORMAT
        if serial_mod == Tas.SERIAL_MODS.NORMAL then
            -- Remove unused start values.
            if copy.start_type == "simple" then
                if copy.start_simple.seed_type ~= "seeded" then
                    copy.start_simple.seeded_seed = nil
                end
                if copy.start_simple.seed_type ~= "adventure" then
                    copy.start_simple.adventure_seed = nil
                end
                if not copy.start_simple.tutorial_race then
                    copy.start_simple.tutorial_race_referee = nil
                end
                for player_index = CONST.MAX_PLAYERS, copy.start_simple.player_count + 1, -1 do
                    copy.start_simple.players[player_index] = nil
                end
            else
                copy.start_simple = nil
            end
            if copy.start_type ~= "snapshot" then
                copy.start_snapshot = nil
            end
        end
        -- The JSON serializer doesn't handle the 64-bit integer pairs correctly and converts them into lossy floats. Save them as 128-bit hex strings instead.
        if copy.start_simple and copy.start_simple.adventure_seed then
            copy.start_simple.adventure_seed = common.adventure_seed_to_string(copy.start_simple.adventure_seed)
        end
        if copy.start_snapshot and copy.start_snapshot.adventure_seed then
            copy.start_snapshot.adventure_seed = common.adventure_seed_to_string(copy.start_snapshot.adventure_seed)
        end
    end
    for screen_index, self_screen in ipairs(self.screens) do
        local copy_screen = {
            metadata = common.deep_copy(self_screen.metadata),
            transition_exit_frame = self_screen.transition_exit_frame,
            save_player_positions = self_screen.save_player_positions,
            save_screen_snapshot = self_screen.save_screen_snapshot
        }
        copy.screens[screen_index] = copy_screen
        if self_screen.start_positions and (serial_mod == Tas.SERIAL_MODS.NONE or self_screen.save_player_positions) then
            copy_screen.start_positions = common.deep_copy(self_screen.start_positions)
        end
        if self_screen.snapshot and (serial_mod == Tas.SERIAL_MODS.NONE or self_screen.save_screen_snapshot) then
            copy_screen.snapshot = common.deep_copy(self_screen.snapshot)
            if serial_mod ~= Tas.SERIAL_MODS.NONE and copy_screen.snapshot.adventure_seed then
                copy_screen.snapshot.adventure_seed = common.adventure_seed_to_string(copy_screen.snapshot.adventure_seed)
            end
        end
        if self_screen.frames then
            copy_screen.frames = {}
            for frame_index, self_frame in ipairs(self_screen.frames) do
                local copy_frame = {
                    inputs = common.deep_copy(self_frame.inputs)
                }
                copy_screen.frames[frame_index] = copy_frame
                if self_frame.positions and (serial_mod == Tas.SERIAL_MODS.NONE or self_screen.save_player_positions) then
                    copy_frame.positions = common.deep_copy(self_frame.positions)
                end
            end
        end
    end
    return copy
end

-- Create a TAS class instance from a raw object.
-- raw: The raw object to use. It will be converted into a class instance without being copied.
-- serial_mod: Post-deserialization modifications to make to the raw object.
function Tas:from_raw(raw, serial_mod)
    if serial_mod ~= Tas.SERIAL_MODS.NONE then
        persistence.update_format(raw, CURRENT_FORMAT, FORMAT_UPDATERS)
        raw.format = nil
        -- Convert the 128-bit adventure seed hex strings back into a 64-bit integer pairs.
        if raw.start_simple and raw.start_simple.adventure_seed then
            raw.start_simple.adventure_seed = common.string_to_adventure_seed(raw.start_simple.adventure_seed)
        end
        if raw.start_snapshot and raw.start_snapshot.adventure_seed then
            raw.start_snapshot.adventure_seed = common.string_to_adventure_seed(raw.start_snapshot.adventure_seed)
        end
        if raw.screens then
            for _, screen in ipairs(raw.screens) do
                if screen.snapshot and screen.snapshot.adventure_seed then
                    screen.snapshot.adventure_seed = common.string_to_adventure_seed(screen.snapshot.adventure_seed)
                end
            end
        end
    end
    return Tas:new(raw, false)
end

-- Gets the final screen index.
function Tas:get_end_screen_index()
    return #self.screens
end

-- Gets the final frame index of the specified screen, or the final screen if `nil`. Returns 0 if the screen does not store frame data or does not exist.
function Tas:get_end_frame_index(screen_index)
    local screen = self.screens[screen_index or #self.screens]
    return screen and common_enums.TASABLE_SCREEN[screen.metadata.screen].record_frames and #screen.frames or 0
end

-- Removes screens after (but not including) the specified screen.
function Tas:remove_screens_after(screen_index)
    for i = screen_index + 1, #self.screens do
        self.screens[i] = nil
    end
end

-- Removes frames after (but not including) the specified frame within only the specified screen.
function Tas:remove_frames_after(screen_index, frame_index)
    local screen = self.screens[screen_index]
    if common_enums.TASABLE_SCREEN[screen.metadata.screen].record_frames then
        for i = frame_index + 1, #screen.frames do
            screen.frames[i] = nil
        end
    end
end

-- TODO: This inserts after the start frame. Would it make more sense to insert before? Does that mess with how I handle frame 0? Maybe "frame_start_index" isn't a good name since it's more of a cursor pointing to the boundary between two frames.
function Tas:insert_frames(screen_index, frame_start_index, frame_count, frame_inputs)
    local screen = self.screens[screen_index]
    -- Shift existing frames to create space, and delete position data.
    local original_last_frame = #screen.frames
    for i = original_last_frame, frame_start_index + 1, -1 do
        screen.frames[i + frame_count] = screen.frames[i]
        screen.frames[i].positions = nil
    end
    -- Insert the new frames.
    for i = frame_start_index + 1, frame_start_index + frame_count do
        screen.frames[i] = {
            inputs = common.deep_copy(frame_inputs)
        }
    end
end

function Tas:delete_frames(screen_index, frame_start_index, frame_count)
    local screen = self.screens[screen_index]
    -- Delete position data.
    for i = frame_start_index, #screen.frames do
        screen.frames[i].positions = nil
    end
    -- Shift existing frames into the deleted space.
    local shift_count = math.max(frame_count, #screen.frames - frame_count - frame_start_index + 1)
    for i = frame_start_index, frame_start_index + shift_count - 1 do
        screen.frames[i] = screen.frames[i + frame_count]
        screen.frames[i + frame_count] = nil
    end
end

-- Clears player position data starting at (and including) the specified frame for the specified player within only the specified screen.
function Tas:clear_player_positions_starting_at(screen_index, start_frame_index, player_index)
    local screen = self.screens[screen_index]
    if common_enums.TASABLE_SCREEN[screen.metadata.screen].record_frames then
        for frame_index = start_frame_index, #screen.frames do
            local frame = screen.frames[frame_index]
            if frame.positions then
                frame.positions[player_index] = {}
            end
        end
    end
end

function Tas:clear_player_positions(screen_index)
    local screen = self.screens[screen_index]
    if common_enums.TASABLE_SCREEN[screen.metadata.screen].record_frames then
        screen.start_positions = nil
        for _, frame in ipairs(screen.frames) do
            frame.positions = nil
        end
    end
end

function Tas:clear_all_player_positions()
    for screen_index = 1, #self.screens do
        self:clear_player_positions(screen_index)
    end
end

function Tas:clear_screen_snapshot(screen_index)
    self.screens[screen_index].snapshot = nil
end

function Tas:clear_all_screen_snapshots()
    for _, screen in ipairs(self.screens) do
        screen.snapshot = nil
    end
end

function Tas:is_start_configured()
    if self.start_type == "simple" then
        return true
    elseif self.start_type == "snapshot" then
        return self.start_snapshot.state_memory ~= nil
    end
    return false
end

-- Gets the player count configured in the start settings. Returns 0 if the start settings are not configured.
function Tas:get_player_count()
    if self.start_type == "simple" then
        return self.start_simple.player_count
    end
    if self.start_type == "snapshot" and self.start_snapshot.state_memory then
        return self.start_snapshot.state_memory.items.player_count
    end
    return 0
end

-- Gets the array of player characters configured in the start settings. The array size will at least match the configured player count, but will be larger if additional unused player characters are stored.
function Tas:get_player_chars()
    if self.start_type == "simple" then
        return self.start_simple.players
    elseif self.start_type == "snapshot" and self.start_snapshot.state_memory then
        local player_chars = {}
        for player_index = 1, CONST.MAX_PLAYERS do
            player_chars[player_index] = common_enums.PLAYER_CHAR_BY_ENT_TYPE[
                self.start_snapshot.state_memory.items.player_select[player_index].character].id
        end
        return player_chars
    end
end

-- Updates screen and frame data to match a new player count. This function only uses the given player count arguments, and does not read or write to the player count stored in the start settings.
function Tas:update_data_player_count(old_count, new_count)
    for _, screen in ipairs(self.screens) do
        if common_enums.TASABLE_SCREEN[screen.metadata.screen].record_frames then
            if old_count < new_count then
                -- Create data for the added players.
                for player_index = old_count + 1, new_count do
                    if screen.start_positions then
                        screen.start_positions[player_index] = {}
                    end
                    for _, frame in ipairs(screen.frames) do
                        frame.inputs[player_index] = INPUTS.NONE
                        if frame.positions then
                            frame.positions[player_index] = {}
                        end
                    end
                end
            else
                -- Delete data for the removed players.
                for player_index = new_count + 1, old_count do
                    if screen.start_positions then
                        screen.start_positions[player_index] = nil
                    end
                    for _, frame in ipairs(screen.frames) do
                        frame.inputs[player_index] = nil
                        if frame.positions then
                            frame.positions[player_index] = nil
                        end
                    end
                end
            end
        end
    end
end

-- Resets the TAS to an empty state, clearing all recorded inputs and generated data. This does not reset TAS settings and frame tags.
function Tas:reset_data()
    self.screens = {}
end

return Tas
