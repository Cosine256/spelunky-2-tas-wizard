local common = require("common")
local persistence = require("persistence")

local Tas = {}
Tas.__index = Tas

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
    return Tas:new(self:to_raw(false), false)
end

-- TODO: Reset format to 1 and remove updaters before first release.
local CURRENT_FORMAT = 7
local FORMAT_UPDATERS = {
    [1] = {
        output_format = 2,
        update = function(o)
            o.levels = {}
            for i = 1, #o.frames do
                o.levels[i] = {
                    frames = o.frames[i]
                }
                if o.positions and o.positions[i] then
                    o.levels[i].player_positions = o.positions[i]
                end
            end
        end
    },
    [2] = {
        output_format = 3,
        update = function(o)
            o.player_count = #o.players
            for player_index = 1, CONST.MAX_PLAYERS do
                if not o.players[player_index] then
                    o.players[player_index] = options.new_tas.players[player_index]
                end
            end
            for level_index = 1, #o.levels do
                local old_level = o.levels[level_index]
                local new_level = {
                    metadata = old_level.metadata,
                    start_state = old_level.start_state,
                    players = {},
                    frames = {}
                }
                o.levels[level_index] = new_level
                for player_index = 1, o.player_count do
                    if player_index == 1 then
                        new_level.players[player_index] = {
                            start_position = old_level.player_start_position
                        }
                    else
                        new_level.players[player_index] = {}
                    end
                end
                for frame_index = 1, #old_level.frames do
                    local new_frame = {
                        players = {}
                    }
                    new_level.frames[frame_index] = new_frame
                    for player_index = 1, o.player_count do
                        if player_index == 1 then
                            new_frame.players[player_index] = {
                                input = old_level.frames[frame_index],
                                position = old_level.player_positions[frame_index]
                            }
                        else
                            new_frame.players[player_index] = {
                                input = INPUTS.NONE
                            }
                        end
                    end
                end
            end
        end
    },
    [3] = {
        output_format = 4,
        update = function(o)
            if o.seed then
                o.seed_type = "seeded"
                o.seed = tonumber(o.seed, 16)
            else
                o.seed_type = "adventure"
                o.seed = o.adventure_seed
            end
            o.custom_start = false
            o.shortcut = false
        end
    },
    [4] = {
        output_format = 5,
        update = function(o)
            o.save_level_snapshots = o.save_level_states
            if o.levels then
                for _, level in ipairs(o.levels) do
                    level.snapshot = level.start_state
                end
            end
        end
    },
    [5] = {
        output_format = 6,
        update = function(o)
            if o.seed_type == "seeded" then
                o.seeded_seed = o.seed
            else
                o.adventure_seed = o.seed
            end
        end
    },
    [6] = {
        output_format = CURRENT_FORMAT,
        update = function(o)
            if o.levels then
                for _, level in ipairs(o.levels) do
                    if level.snapshot then
                        -- TODO: Revert this format change and unflatten this object. Right now it only contains the StateMemory, but in the future I may need to store other stuff in the snapshot, such as for modded runs. Call it "state_memory" when you unflatten it instead of just "state".
                        level.snapshot = level.snapshot.state
                    end
                end
            end
        end
    }
}

-- Create a raw copy of this TAS, containing only tables and primitive types, with no functions or prototyping.
-- is_serial_format: Format the raw copy for serialization.
function Tas:to_raw(is_serial_format)
    local copy = {
        seed_type = self.seed_type,
        seeded_seed = self.seeded_seed,
        adventure_seed = common.deep_copy(self.adventure_seed),
        custom_start = self.custom_start,
        world_start = self.world_start,
        level_start = self.level_start,
        theme_start = self.theme_start,
        shortcut = self.shortcut,
        tutorial_race = self.tutorial_race,
        tutorial_race_referee = self.tutorial_race_referee,
        player_count = self.player_count,
        players = common.deep_copy(self.players),
        levels = {},
        olmec_cutscene_skip_frame = self.olmec_cutscene_skip_frame,
        olmec_cutscene_skip_input = self.olmec_cutscene_skip_input,
        tiamat_cutscene_skip_frame = self.tiamat_cutscene_skip_frame,
        tiamat_cutscene_skip_input = self.tiamat_cutscene_skip_input,
        transition_exit_frame = self.transition_exit_frame,
        tagged_frames = common.deep_copy(self.tagged_frames),
        save_player_positions = self.save_player_positions,
        save_level_snapshots = self.save_level_snapshots
    }
    if is_serial_format then
        copy.format = CURRENT_FORMAT
        if copy.adventure_seed then
            -- The JSON serializer doesn't handle the 64-bit integer pair correctly and converts it into lossy floats. Save it as a 128-bit hex string instead.
            copy.adventure_seed = common.adventure_seed_to_string(copy.adventure_seed)
        end
    end
    for level_index, self_level in ipairs(self.levels) do
        local copy_level = {
            metadata = common.deep_copy(self_level.metadata),
            players = {},
            frames = {}
        }
        copy.levels[level_index] = copy_level
        for player_index, self_player in ipairs(self_level.players) do
            copy_level.players[player_index] = {}
            if not is_serial_format or self.save_player_positions then
                copy_level.players[player_index].start_position = common.deep_copy(self_player.start_position)
            end
        end
        if (not is_serial_format or self.save_level_snapshots) and self_level.snapshot then
            copy_level.snapshot = common.deep_copy(self_level.snapshot)
        end
        for frame_index, self_frame in ipairs(self_level.frames) do
            local copy_frame = {
                players = {}
            }
            copy_level.frames[frame_index] = copy_frame
            for player_index, self_player in ipairs(self_frame.players) do
                copy_frame.players[player_index] = {
                    input = self_player.input
                }
                if not is_serial_format or self.save_player_positions then
                    copy_frame.players[player_index].position = common.deep_copy(self_player.position)
                end
            end
        end
    end
    return copy
end

-- Create a TAS class instance from a raw object.
-- is_serial_format: The raw object is formatted for serialization.
function Tas:from_raw(raw, is_serial_format)
    raw = common.deep_copy(raw)
    if is_serial_format then
        persistence.update_format(raw, CURRENT_FORMAT, FORMAT_UPDATERS)
        raw.format = nil
        -- Convert the 128-bit adventure seed hex string back into a 64-bit integer pair.
        if raw.adventure_seed then
            raw.adventure_seed = common.string_to_adventure_seed(raw.adventure_seed)
        end
    end
    return Tas:new(raw, false)
end

function Tas:create_level_data()
    local level_data = {
        players = {},
        frames = {}
    }
    for player_index = 1, self.player_count do
        level_data.players[player_index] = {}
    end
    return level_data
end

function Tas:create_frame_data()
    local frame_data = {
        players = {}
    }
    for player_index = 1, self.player_count do
        frame_data.players[player_index] = {}
    end
    return frame_data
end

-- Gets the final level index.
function Tas:get_end_level_index()
    return #self.levels
end

-- Gets the final frame index of the specified level, or the last level if `nil`.
function Tas:get_end_frame_index(level_index)
    return #self.levels[level_index or #self.levels].frames
end

-- Gets the final level index and frame index.
function Tas:get_end_indices()
    return #self.levels, #self.levels[#self.levels].frames
end

-- Removes frames after (but not including) the specified frame.
function Tas:remove_frames_after(level_index, frame_index, only_level)
    if only_level then
        for i = frame_index + 1, #self.levels[level_index].frames do
            self.levels[level_index].frames[i] = nil
        end
    else
        for i = level_index, #self.levels do
            if i == level_index then
                for j = frame_index + 1, #self.levels[i].frames do
                    self.levels[i].frames[j] = nil
                end
            else
                self.levels[i] = nil
            end
        end
    end
end

-- TODO: This inserts after the start frame. Would it make more sense to insert before? Does that mess with how I handle frame 0? Maybe "frame_start_index" isn't a good name since it's more of a cursor pointing to the boundary between two frames.
function Tas:insert_frames(level_index, frame_start_index, frame_count, inputs)
    local level_data = self.levels[level_index]
    -- Shift existing frames to create space, and delete position data.
    local original_last_frame = #level_data.frames
    for i = original_last_frame, frame_start_index + 1, -1 do
        level_data.frames[i + frame_count] = level_data.frames[i]
        for _, player in ipairs(level_data.frames[i].players) do
            player.position = nil
        end
    end
    -- Insert the new frames.
    for i = frame_start_index + 1, frame_start_index + frame_count do
        local new_frame = self:create_frame_data()
        for player_index, player in ipairs(new_frame.players) do
            player.input = inputs[player_index]
        end
        level_data.frames[i] = new_frame
    end
end

function Tas:delete_frames(level_index, frame_start_index, frame_count)
    local level_data = self.levels[level_index]
    -- Delete position data.
    for i = frame_start_index, #level_data.frames do
        for _, player in ipairs(level_data.frames[i].players) do
            player.position = nil
        end
    end
    -- Shift existing frames into the deleted space.
    local shift_count = math.max(frame_count, #level_data.frames - frame_count - frame_start_index + 1)
    for i = frame_start_index, frame_start_index + shift_count - 1 do
        level_data.frames[i] = level_data.frames[i + frame_count]
        level_data.frames[i + frame_count] = nil
    end
end

function Tas:clear_player_positions()
    for _, level in ipairs(self.levels) do
        for _, player in ipairs(level.players) do
            player.start_position = nil
        end
        for _, frame in ipairs(level.frames) do
            for _, player in ipairs(frame.players) do
                player.position = nil
            end
        end
    end
end

function Tas:clear_level_snapshots()
    for _, level in ipairs(self.levels) do
        level.snapshot = nil
    end
end

function Tas:find_closest_level_with_snapshot(target_level)
    for level_index = target_level, 2, -1 do
        if self.levels[level_index].snapshot then
            return level_index
        end
    end
    return -1
end

-- Compute the adventure seed that would exist right before the given level initializes PRNG and advances the adventure seed.
function Tas:compute_level_adventure_seed(level_index)
    -- Right before the game generates a level, it uses the adventure seed to initialize PRNG, and it advances the adventure seed to its next value. This advancement is very simple, and just increases the adventure seed's second part by its first part, allowing integer overflow. Thanks to two's complement arithmetic, this calculation works even with Lua's signed integers.
    return { self.adventure_seed[1], self.adventure_seed[2] + (self.adventure_seed[1] * (level_index - 1)) }
end

return Tas
