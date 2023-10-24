local common_enums = require("common_enums")

local module = {}

-- The earliest frame in which a boss cutscene can be skipped.
module.CUTSCENE_SKIP_FIRST_FRAME = 2
-- The highest value of the Olmec cutscene logic timer before the cutscene ends.
module.OLMEC_CUTSCENE_LAST_FRAME = 809
-- The highest value of the Tiamat cutscene logic timer before the cutscene ends.
module.TIAMAT_CUTSCENE_LAST_FRAME = 379
-- The earliest frame in which a transition can be exited.
module.TRANSITION_EXIT_FIRST_FRAME = 1

module.THEME_NAME = {
    [THEME.BASE_CAMP] = "Base Camp",
    [THEME.DWELLING] = "Dwelling",
    [THEME.JUNGLE] = "Jungle",
    [THEME.VOLCANA] = "Volcana",
    [THEME.OLMEC] = "Olmec",
    [THEME.TIDE_POOL] = "Tide Pool",
    [THEME.ABZU] = "Abzu",
    [THEME.TEMPLE] = "Temple",
    [THEME.CITY_OF_GOLD] = "City of Gold",
    [THEME.DUAT] = "Duat",
    [THEME.ICE_CAVES] = "Ice Caves",
    [THEME.NEO_BABYLON] = "Neo Babylon",
    [THEME.TIAMAT] = "Tiamat",
    [THEME.SUNKEN_CITY] = "Sunken City",
    [THEME.EGGPLANT_WORLD] = "Eggplant World",
    [THEME.HUNDUN] = "Hundun",
    [THEME.COSMIC_OCEAN] = "Cosmic Ocean"
}

function module.deep_copy(obj)
    if type(obj) == "table" then
        local copy = {}
        for k, v in pairs(obj) do
            copy[k] = module.deep_copy(v)
        end
        return copy
    else
        return obj
    end
end

-- Converts a flag index (1-based) into an integer value. For example, flag 5 is converted into value 16.
function module.flag_to_value(flag)
    return 1 << (flag - 1)
end

function module.seed_to_string(seed)
    return string.format("%08X", seed)
end

function module.string_to_seed(s)
    return tonumber(s, 16)
end

function module.adventure_seed_to_string(pair)
    return string.format("%016X", pair[1])..string.format("%016X", pair[2])
end

function module.string_to_adventure_seed(s)
    return { tonumber(string.sub(s, 1, 16), 16), tonumber(string.sub(s, 17, 32), 16) }
end

function module.adventure_seed_part_to_string(part)
    return string.format("%016X", part)
end

function module.string_to_adventure_seed_part(s)
    return tonumber(s, 16)
end

local INPUT_TO_CHAR = {
    [INPUTS.LEFT] = "<",
    [INPUTS.RIGHT] = ">",
    [INPUTS.UP] = "^",
    [INPUTS.DOWN] = "v",
    [INPUTS.JUMP] = "J",
    [INPUTS.WHIP] = "W",
    [INPUTS.BOMB] = "B",
    [INPUTS.ROPE] = "R",
    [INPUTS.DOOR] = "D",
    [INPUTS.RUN] = "+"
}

local CHAR_TO_INPUT = {}
for input, c in pairs(INPUT_TO_CHAR) do
    CHAR_TO_INPUT[c:upper()] = input
end

function module.inputs_to_string(inputs)
    return ((inputs & INPUTS.LEFT > 0) and INPUT_TO_CHAR[INPUTS.LEFT] or "_")
        ..((inputs & INPUTS.RIGHT > 0) and INPUT_TO_CHAR[INPUTS.RIGHT] or "_")
        ..((inputs & INPUTS.UP > 0) and INPUT_TO_CHAR[INPUTS.UP] or "_")
        ..((inputs & INPUTS.DOWN > 0) and INPUT_TO_CHAR[INPUTS.DOWN] or "_")
        ..((inputs & INPUTS.JUMP > 0) and INPUT_TO_CHAR[INPUTS.JUMP] or "_")
        ..((inputs & INPUTS.WHIP > 0) and INPUT_TO_CHAR[INPUTS.WHIP] or "_")
        ..((inputs & INPUTS.BOMB > 0) and INPUT_TO_CHAR[INPUTS.BOMB] or "_")
        ..((inputs & INPUTS.ROPE > 0) and INPUT_TO_CHAR[INPUTS.ROPE] or "_")
        ..((inputs & INPUTS.DOOR > 0) and INPUT_TO_CHAR[INPUTS.DOOR] or "_")
        ..((inputs & INPUTS.RUN > 0) and INPUT_TO_CHAR[INPUTS.RUN] or "_")
end

function module.string_to_inputs(s)
    local inputs = INPUTS.NONE
    for i = 1, #s do
        local input = CHAR_TO_INPUT[s:sub(i, i):upper()]
        if input then
            inputs = inputs | input
        end
    end
    return inputs
end

local function world_level_theme_to_string(world, level, theme)
    local theme_name = module.THEME_NAME[theme] or "Unknown"
    if world == 8 and theme == THEME.COSMIC_OCEAN then
        return "7-"..level.." "..theme_name
    else
        return world.."-"..level.." "..theme_name
    end
end

function module.screen_metadata_to_string(metadata)
    local tasable_screen = common_enums.TASABLE_SCREEN[metadata.screen]
    if metadata.screen == SCREEN.LEVEL or metadata.screen == SCREEN.TRANSITION then
        local wlt_text = world_level_theme_to_string(metadata.world, metadata.level, metadata.theme)
        if metadata.screen == SCREEN.TRANSITION then
            return wlt_text.." "..tasable_screen.name
        else
            return wlt_text
        end
    else
        return tasable_screen.name
    end
end

function module.tas_screen_to_string(tas, screen_index, include_total)
    local text = tostring(screen_index)
    if include_total then
        text = text.."/"..#tas.screens
    end
    local screen = tas.screens[screen_index]
    if screen then
        text = text.." ("..module.screen_metadata_to_string(screen.metadata)..")"
    end
    return text
end

-- Compares two screen index and frame index pairs and returns the result as a signed integer.
-- Negative: Pair 1 is before pair 2.
-- Zero: Pair 1 is equal to pair 2.
-- Positive: Pair 1 is after pair 2.
function module.compare_screen_frame_index(screen_index_1, frame_index_1, screen_index_2, frame_index_2)
    return screen_index_1 == screen_index_2 and frame_index_1 - frame_index_2 or screen_index_1 - screen_index_2
end

return module
