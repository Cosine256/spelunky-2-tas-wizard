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

-- TODO: Reset format to 1 and remove these development updaters before the first release. 
-- Note: These updaters don't cover some edge cases when I know that none of my test TASes contain that edge case. Post-release updaters will need to handle every possible edge case.
local CURRENT_FORMAT = 26
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
        output_format = 7,
        update = function(o)
            if o.levels then
                for _, level in ipairs(o.levels) do
                    if level.snapshot then
                        level.snapshot = level.snapshot.state
                    end
                end
            end
        end
    },
    [7] = {
        output_format = 8,
        update = function(o)
            o.name = ""
            o.description = ""
        end
    },
    [8] = {
        output_format = 9,
        update = function(o)
            o.start = {
                type = "simple",
                seed_type = o.seed_type,
                seeded_seed = o.seeded_seed,
                adventure_seed = o.adventure_seed,
                is_custom_area_choice = o.custom_start,
                world = o.world_start,
                level = o.level_start,
                theme = o.theme_start,
                shortcut = o.shortcut,
                tutorial_race = o.tutorial_race,
                tutorial_race_referee = o.tutorial_race_referee,
                player_count = o.player_count,
                players = o.players
            }
        end
    },
    [9] = {
        output_format = 10,
        update = function(o)
            if o.levels then
                for _, level in ipairs(o.levels) do
                    if level.snapshot then
                        level.snapshot = {
                            state_memory = level.snapshot
                        }
                    end
                end
            end
        end
    },
    [10] = {
        output_format = 11,
        update = function(o)
            o.start_simple = o.start
            o.start = nil
            o.start_type = o.start_simple.type
            o.start_simple.type = nil
        end
    },
    [11] = {
        output_format = 12,
        update = function(o)
            if o.start_full and o.start_full.state_memory then
                o.start_full.state_memory.screen_next = SCREEN.LEVEL
            end
            if o.levels then
                for _, level in ipairs(o.levels) do
                    if level.snapshot and level.snapshot.state_memory then
                        level.snapshot.state_memory.screen_next = SCREEN.LEVEL
                    end
                end
            end
        end
    },
    [12] = {
        output_format = 13,
        update = function(o)
            if o.start_full and o.start_full.state_memory then
                o.start_full.state_memory.speedrun_character = ENT_TYPE.CHAR_MARGARET_TUNNEL
                o.start_full.state_memory.speedrun_activation_trigger = false
            end
            if o.levels then
                for _, level in ipairs(o.levels) do
                    if level.snapshot and level.snapshot.state_memory then
                        level.snapshot.state_memory.speedrun_character = ENT_TYPE.CHAR_MARGARET_TUNNEL
                        level.snapshot.state_memory.speedrun_activation_trigger = false
                    end
                end
            end
        end
    },
    [13] = {
        output_format = 14,
        update = function(o)
            local function add_journal_progress(state_memory)
                state_memory.journal_progress_sticker_count = 0
                state_memory.journal_progress_sticker_slots = {}
                state_memory.journal_progress_stain_count = 0
                state_memory.journal_progress_stain_slots = {}
                state_memory.journal_progress_theme_count = 0
                state_memory.journal_progress_theme_slots = {}
                for i = 1, 40 do
                    state_memory.journal_progress_sticker_slots[i] = {
                        theme = 0,
                        grid_position = 0,
                        entity_type = 0,
                        x = 0.0,
                        y = 0.0,
                        angle = 0.0
                    }
                end
                for i = 1, 30 do
                    state_memory.journal_progress_stain_slots[i] = {
                        x = 0.0,
                        y = 0.0,
                        angle = 0.0,
                        scale = 0.0,
                        texture_column = 0,
                        texture_row = 0,
                        texture_range = 0
                    }
                end
                for i = 1, 9 do
                    state_memory.journal_progress_theme_slots[i] = 0
                end
            end
            if o.start_full and o.start_full.state_memory then
                add_journal_progress(o.start_full.state_memory)
            end
            if o.levels then
                for _, level in ipairs(o.levels) do
                    if level.snapshot and level.snapshot.state_memory then
                        add_journal_progress(level.snapshot.state_memory)
                    end
                end
            end
        end
    },
    [14] = {
        output_format = 15,
        update = function(o)
            local new_levels = {}
            for level_index, level in ipairs(o.levels) do
                table.insert(new_levels, level)
                if level.metadata.theme == THEME.BASE_CAMP then
                    level.metadata = {
                        screen = SCREEN.CAMP
                    }
                else
                    level.metadata.screen = SCREEN.LEVEL
                    if level_index < #o.levels and level.metadata.theme ~= THEME.TIAMAT and level.metadata.theme ~= THEME.HUNDUN then
                        table.insert(new_levels, {
                            metadata = {
                                screen = SCREEN.TRANSITION,
                                world = level.metadata.world,
                                level = level.metadata.level,
                                theme = level.metadata.theme
                            }
                        })
                    end
                end
            end
            o.levels = new_levels
        end
    },
    [15] = {
        output_format = 16,
        update = function(o)
            for _, level in ipairs(o.levels) do
                if level.metadata.screen == SCREEN.LEVEL then
                    if level.metadata.theme == THEME.OLMEC then
                        level.metadata.cutscene = true
                        level.cutscene_skip_frame_index = o.olmec_cutscene_skip_frame
                        level.cutscene_skip_input = o.olmec_cutscene_skip_input
                    elseif level.metadata.theme == THEME.TIAMAT then
                        level.metadata.cutscene = true
                        level.cutscene_skip_frame_index = o.tiamat_cutscene_skip_frame
                        level.cutscene_skip_input = o.tiamat_cutscene_skip_input
                    end
                elseif level.metadata.screen == SCREEN.TRANSITION then
                    level.transition_exit_frame_index = o.transition_exit_frame
                end
            end
            o.olmec_cutscene_skip_frame = nil
            o.olmec_cutscene_skip_input = nil
            o.tiamat_cutscene_skip_frame = nil
            o.tiamat_cutscene_skip_input = nil
            o.transition_exit_frame = nil
        end
    },
    [16] = {
        output_format = 17,
        update = function(o)
            for _, level in ipairs(o.levels) do
                if level.cutscene_skip_frame_index == -1 then
                    level.cutscene_skip_frame_index = nil
                end
                if level.transition_exit_frame_index == -1 then
                    level.transition_exit_frame_index = nil
                end
            end
        end
    },
    [17] = {
        output_format = 18,
        update = function(o)
            for _, level in ipairs(o.levels) do
                if level.metadata.cutscene then
                    local player_count = #level.frames[1].players
                    local cutscene_last_frame_index = level.metadata.theme == THEME.OLMEC
                        and common.OLMEC_CUTSCENE_LAST_FRAME or common.TIAMAT_CUTSCENE_LAST_FRAME
                    local new_frames = {}
                    for frame_index = 1, level.cutscene_skip_frame_index and level.cutscene_skip_frame_index - 1 or cutscene_last_frame_index do
                        local frame = {
                            players = {}
                        }
                        for player_index = 1, player_count do
                            frame.players[player_index] = {}
                        end
                        new_frames[frame_index] = frame
                        for player_index, player in ipairs(frame.players) do
                            -- Player 1 is the leader here in all of my test TASes.
                            if level.cutscene_skip_frame_index and frame_index == level.cutscene_skip_frame_index - 1 and player_index == 1 then
                                player.input = level.cutscene_skip_input == "jump" and INPUTS.JUMP or INPUTS.BOMB
                            else
                                player.input = INPUTS.NONE
                            end
                        end
                    end
                    for frame_index = 1, #level.frames do
                        new_frames[#new_frames + 1] = level.frames[frame_index]
                    end
                    level.frames = new_frames
                    level.cutscene_skip_frame_index = nil
                    level.cutscene_skip_input = nil
                end
            end
        end
    },
    [18] = {
        output_format = 19,
        update = function(o)
            for _, level in ipairs(o.levels) do
                if level.frames then
                    for _, frame in ipairs(level.frames) do
                        for _, player in ipairs(frame.players) do
                            player.inputs = player.input
                            player.input = nil
                        end
                    end
                end
            end
        end
    },
    [19] = {
        output_format = 20,
        update = function(o)
            o.frame_tags = o.tagged_frames
            o.tagged_frames = nil
            table.insert(o.frame_tags, 1, {
                name = "Start",
                level = 1,
                frame = 0
            })
            table.insert(o.frame_tags, 2, {
                name = "End",
                level = -1,
                frame = -1
            })
        end
    },
    [20] = {
        output_format = 21,
        update = function(o)
            o.screens = o.levels
            o.levels = nil
            for _, frame_tag in ipairs(o.frame_tags) do
                frame_tag.screen = frame_tag.level
                frame_tag.level = nil
            end
            o.save_screen_snapshots = o.save_level_snapshots
            o.save_level_snapshots = nil
        end
    },
    [21] = {
        output_format = 22,
        update = function(o)
            if o.start_simple then
                o.is_custom_preset = o.is_custom_area_choice
                o.is_custom_area_choice = nil
                if o.start_simple.tutorial_race then
                    o.start_simple.screen = SCREEN.CAMP
                    o.start_simple.screen_last = SCREEN.CAMP
                else
                    o.start_simple.screen = SCREEN.LEVEL
                end
            end
        end
    },
    [22] = {
        output_format = 23,
        update = function(o)
            if o.start_type == "full" then
                o.start_type = "snapshot"
            end
            o.start_snapshot = o.start_full
            o.start_full = nil
        end
    },
    [23] = {
        output_format = 24,
        update = function(o)
            for _, screen in ipairs(o.screens) do
                if screen.metadata.screen == SCREEN.TRANSITION and not screen.transition_exit_frame_index then
                    screen.transition_exit_frame_index = 1
                end
            end
        end
    },
    [24] = {
        output_format = 25,
        update = function(o)
            for _, screen in ipairs(o.screens) do
                if screen.players then
                    screen.start_positions = {}
                    for player_index, player in ipairs(screen.players) do
                        screen.start_positions[player_index] = player.start_position or {}
                    end
                    screen.players = nil
                end
                if screen.frames then
                    for _, frame in ipairs(screen.frames) do
                        frame.inputs = {}
                        frame.positions = {}
                        for player_index, player in ipairs(frame.players) do
                            frame.inputs[player_index] = player.inputs
                            frame.positions[player_index] = player.position or {}
                        end
                        frame.players = nil
                    end
                end
            end
        end
    },
    [25] = {
        output_format = CURRENT_FORMAT,
        update = function(o)
            for _, frame_tag in ipairs(o.frame_tags) do
                frame_tag.show_on_path = frame_tag.frame ~= 0 and frame_tag.frame ~= -1
            end
        end
    }
}

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
        save_player_positions = self.save_player_positions,
        save_screen_snapshots = self.save_screen_snapshots
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
            transition_exit_frame_index = self_screen.transition_exit_frame_index
        }
        copy.screens[screen_index] = copy_screen
        if (serial_mod == Tas.SERIAL_MODS.NONE or self.save_player_positions) and self_screen.start_positions then
            copy_screen.start_positions = common.deep_copy(self_screen.start_positions)
        end
        if (serial_mod == Tas.SERIAL_MODS.NONE or self.save_screen_snapshots) and self_screen.snapshot then
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
                if (serial_mod == Tas.SERIAL_MODS.NONE or self.save_player_positions) and self_frame.positions then
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

-- Gets the player count configured in the start settings.
function Tas:get_player_count()
    if self.start_type == "simple" then
        return self.start_simple.player_count
    elseif self.start_type == "snapshot" and self.start_snapshot.state_memory then
        return self.start_snapshot.state_memory.items.player_count
    end
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

return Tas
