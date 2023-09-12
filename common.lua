local module = {}

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

function module.clamp(number, min, max)
    if number < min then
        return min
    elseif number > max then
        return max
    else
        return number
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

function module.input_to_string(input)
    return ((input & INPUTS.LEFT > 0) and "<" or "_")
        ..((input & INPUTS.RIGHT > 0) and ">" or "_")
        ..((input & INPUTS.UP > 0) and "^" or "_")
        ..((input & INPUTS.DOWN > 0) and "v" or "_")
        ..((input & INPUTS.JUMP > 0) and "J" or "_")
        ..((input & INPUTS.WHIP > 0) and "W" or "_")
        ..((input & INPUTS.BOMB > 0) and "B" or "_")
        ..((input & INPUTS.ROPE > 0) and "R" or "_")
        ..((input & INPUTS.DOOR > 0) and "D" or "_")
        ..((input & INPUTS.RUN > 0) and "+" or "_")
end

function module.world_level_theme_to_string(world, level, theme)
    local theme_name = module.THEME_NAME[theme] or "Unknown"
    if theme == THEME.BASE_CAMP then
        return theme_name
    elseif world == 8 and theme == THEME.COSMIC_OCEAN then
        return "7-"..level.." "..theme_name
    else
        return world.."-"..level.." "..theme_name
    end
end

function module.level_metadata_to_string(tas, index, include_total)
    local level_data = tas.levels[index]
    local text = tostring(index)..(include_total and ("/"..#tas.levels) or "")
    if level_data and level_data.metadata then
        return text.." ("..module.world_level_theme_to_string(level_data.metadata.world, level_data.metadata.level, level_data.metadata.theme)..")"
    else
        return text
    end
end

return module
