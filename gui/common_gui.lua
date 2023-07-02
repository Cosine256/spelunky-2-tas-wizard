local common = require("common")
local common_enums = require("common_enums")
local ComboInput = require("gui/combo_input")
local OrderedTable = require("ordered_table")

local module = {}

module.INDENT_SECTION = 5
module.INDENT_SUB_INPUT = 10

local RUN_START_LEVEL = OrderedTable:new({
    { id = "dwelling", name = "Dwelling", world = 1, level = 1, theme = THEME.DWELLING, shortcut = false, tutorial_race = false },
    { id = "quillback_shortcut", name = "Quillback Shortcut", world = 1, level = 4, theme = THEME.DWELLING, shortcut = true, tutorial_race = false },
    { id = "olmec_shortcut", name = "Olmec Shortcut", world = 3, level = 1, theme = THEME.OLMEC, shortcut = true, tutorial_race = false },
    { id = "ice_caves_shortcut", name = "Ice Caves Shortcut", world = 5, level = 1, theme = THEME.ICE_CAVES, shortcut = true, tutorial_race = false },
    { id = "tutorial_race", name = "Tutorial Race", world = 1, level = 1, theme = THEME.BASE_CAMP, shortcut = false, tutorial_race = true },
    { id = "custom", name = "Custom" }
})
local RUN_START_LEVEL_BY_INDEX = RUN_START_LEVEL:values_by_index()
local RUN_START_LEVEL_COMBO = ComboInput:new(RUN_START_LEVEL)

local VANILLA_LEVEL
do
    VANILLA_LEVEL = {
        { id = "dwelling", name = common.THEME_NAME[THEME.DWELLING], theme = THEME.DWELLING, world = 1, levels = { 1, 2, 3, 4 } },
        { id = "jungle", name = common.THEME_NAME[THEME.JUNGLE], theme = THEME.JUNGLE, world = 2, levels = { 1, 2, 3, 4 } },
        { id = "volcana", name = common.THEME_NAME[THEME.VOLCANA], theme = THEME.VOLCANA, world = 2, levels = { 1, 2, 3, 4 } },
        { id = "olmec", name = common.THEME_NAME[THEME.OLMEC], theme = THEME.OLMEC, world = 3, levels = { 1 } },
        { id = "tide_pool", name = common.THEME_NAME[THEME.TIDE_POOL], theme = THEME.TIDE_POOL, world = 4, levels = { 1, 2, 3, 4 } },
        { id = "abzu", name = common.THEME_NAME[THEME.ABZU], theme = THEME.ABZU, world = 4, levels = { 4 } },
        { id = "temple", name = common.THEME_NAME[THEME.TEMPLE], theme = THEME.TEMPLE, world = 4, levels = { 1, 2, 3, 4 } },
        { id = "city_of_gold", name = common.THEME_NAME[THEME.CITY_OF_GOLD], theme = THEME.CITY_OF_GOLD, world = 4, levels = { 3 } },
        { id = "duat", name = common.THEME_NAME[THEME.DUAT], theme = THEME.DUAT, world = 4, levels = { 4 } },
        { id = "ice_caves", name = common.THEME_NAME[THEME.ICE_CAVES], theme = THEME.ICE_CAVES, world = 5, levels = { 1 } },
        { id = "neo_babylon", name = common.THEME_NAME[THEME.NEO_BABYLON], theme = THEME.NEO_BABYLON, world = 6, levels = { 1, 2, 3 } },
        { id = "tiamat", name = common.THEME_NAME[THEME.TIAMAT], theme = THEME.TIAMAT, world = 6, levels = { 4 } },
        { id = "sunken_city", name = common.THEME_NAME[THEME.SUNKEN_CITY], theme = THEME.SUNKEN_CITY, world = 7, levels = { 1, 2, 3 } },
        { id = "eggplant_world", name = common.THEME_NAME[THEME.EGGPLANT_WORLD], theme = THEME.EGGPLANT_WORLD, world = 7, levels = { 2 } },
        { id = "hundun", name = common.THEME_NAME[THEME.HUNDUN], theme = THEME.HUNDUN, world = 7, levels = { 4 } },
        { id = "cosmic_ocean", name = common.THEME_NAME[THEME.COSMIC_OCEAN], theme = THEME.COSMIC_OCEAN, world = 8 }
    }
    local levels = {}
    for i = 5, 98 do
        levels[i - 4] = i
    end
    VANILLA_LEVEL[#VANILLA_LEVEL].levels = levels
    VANILLA_LEVEL = OrderedTable:new(VANILLA_LEVEL)
end
local VANILLA_LEVEL_BY_INDEX = VANILLA_LEVEL:values_by_index()
local VANILLA_LEVEL_COMBO = ComboInput:new(VANILLA_LEVEL)

local SEED_TYPE = OrderedTable:new({
    { id = "seeded", name = "Seeded", desc = "Seed chosen by the user for normal seeded runs." },
    { id = "adventure", name = "Adventure", desc = "Internal seed used for adventure runs. Not normally accessible to the user." }
})
local SEED_TYPE_COMBO = ComboInput:new(SEED_TYPE)

local PLAYER_COUNT_COMBO = ComboInput:new(OrderedTable:new({ 1, 2, 3, 4 }))

local PLAYER_CHAR_COMBO = ComboInput:new(common_enums.PLAYER_CHAR)

function module.draw_tas_start_settings(ctx, tas, id)
    ctx:win_pushid(id)

    local run_start_level_id = "custom"
    if not tas.custom_start then
        for _, run_start_level in ipairs(RUN_START_LEVEL_BY_INDEX) do
            if tas.world_start == run_start_level.world and tas.level_start == run_start_level.level and tas.theme_start == run_start_level.theme
                and tas.shortcut == run_start_level.shortcut and tas.tutorial_race == run_start_level.tutorial_race
            then
                run_start_level_id = run_start_level.id
                break
            end
        end
    end
    run_start_level_id = RUN_START_LEVEL_COMBO:draw(ctx, "Start area", run_start_level_id)
    if run_start_level_id == "custom" then
        ctx:win_indent(module.INDENT_SUB_INPUT)
        tas.custom_start = true
        tas.shortcut = false
        tas.tutorial_race = false
        local vanilla_level_id
        for _, vanilla_level in ipairs(VANILLA_LEVEL_BY_INDEX) do
            if tas.world_start == vanilla_level.world and tas.theme_start == vanilla_level.theme then
                vanilla_level_id = vanilla_level.id
                break
            end
        end
        vanilla_level_id = VANILLA_LEVEL_COMBO:draw(ctx, "World", vanilla_level_id)
        local vanilla_level = VANILLA_LEVEL:value_by_id(vanilla_level_id)
        tas.world_start = vanilla_level.world
        tas.theme_start = vanilla_level.theme
        if #vanilla_level.levels == 1 then
            tas.level_start = vanilla_level.levels[1]
        else
            local level_choices = {}
            for i, level in ipairs(vanilla_level.levels) do
                level_choices[i] = { id = level }
            end
            local level_combo = ComboInput:new(OrderedTable:new(level_choices))
            tas.level_start = level_combo:draw(ctx, "Level", tas.level_start)
        end
        ctx:win_indent(-module.INDENT_SUB_INPUT)
    else
        tas.custom_start = false
        local run_start_level = RUN_START_LEVEL:value_by_id(run_start_level_id)
        tas.world_start = run_start_level.world
        tas.level_start = run_start_level.level
        tas.theme_start = run_start_level.theme
        tas.shortcut = run_start_level.shortcut
        tas.tutorial_race = run_start_level.tutorial_race
    end

    local new_seed_type_id = SEED_TYPE_COMBO:draw(ctx, "Seed type", tas.seed_type)
    local is_seeded = new_seed_type_id == "seeded"
    if tas.seed_type ~= new_seed_type_id then
        tas.seed_type = new_seed_type_id
        if is_seeded then
            tas.seeded_seed = options.new_seeded_seed
            tas.adventure_seed = nil
        else
            tas.seeded_seed = nil
            tas.adventure_seed = common.deep_copy(options.new_adventure_seed)
        end
    end
    ctx:win_indent(module.INDENT_SUB_INPUT)
    local seed_type = SEED_TYPE:value_by_id(new_seed_type_id)
    ctx:win_text(seed_type.name..": "..seed_type.desc)
    if is_seeded then
        local new_seed = common.string_to_seed(
            ctx:win_input_text("Seed##new_seed_text", common.seed_to_string(tas.seeded_seed)))
        if new_seed and tas.seeded_seed ~= new_seed then
            tas.seeded_seed = new_seed
            tas.adventure_seed = nil
        end
    else
        local new_seed = {}
        new_seed[1] = common.string_to_adventure_seed_part(
            ctx:win_input_text("Part 1##new_seed_1_text", common.adventure_seed_part_to_string(tas.adventure_seed[1])))
        new_seed[2] = common.string_to_adventure_seed_part(
            ctx:win_input_text("Part 2##new_seed_2_text", common.adventure_seed_part_to_string(tas.adventure_seed[2])))
        if new_seed[1] and new_seed[2] then
            tas.adventure_seed = new_seed
        end
    end
    if ctx:win_button("Randomize seed") then
        if is_seeded then
            tas.seeded_seed = math.random(0, 0xFFFFFFFF)
            tas.adventure_seed = nil
        else
            -- Lua uses 64-bit signed integers, so the random ranges need to be specified like this.
            tas.adventure_seed = { math.random(math.mininteger, math.maxinteger), math.random(math.mininteger, math.maxinteger) }
        end
    end
    ctx:win_indent(-module.INDENT_SUB_INPUT)

    if tas.tutorial_race then
        tas.tutorial_race_referee = PLAYER_CHAR_COMBO:draw(ctx, "Tutorial race referee", tas.tutorial_race_referee or options.new_tas.tutorial_race_referee)
    end

    local new_player_count
    if tas.tutorial_race then
        new_player_count = 1
    else
        new_player_count = PLAYER_COUNT_COMBO:draw(ctx, "Player count", tas.player_count)
    end
    if tas.player_count ~= new_player_count then
        -- Update all level and frame data to match the new player count.
        print("Player count changed from "..tas.player_count.." to "..new_player_count..". Updating level and frame data.")
        tas.player_count = new_player_count
        -- TODO: Loop nesting here feels odd. There are probably other ways I could do it. Is this the best one?
        for _, level in ipairs(tas.levels) do
            for player_index = 1, CONST.MAX_PLAYERS do
                if player_index > new_player_count then
                    level.players[player_index] = nil
                elseif not level.players[player_index] then
                    level.players[player_index] = {}
                end
            end
            for _, frame in ipairs(level.frames) do
                for player_index = 1, CONST.MAX_PLAYERS do
                    if player_index > new_player_count then
                        frame.players[player_index] = nil
                    elseif not frame.players[player_index] then
                        frame.players[player_index] = {
                            input = INPUTS.NONE
                        }
                    end
                end
            end
        end
    end
    for player_index = 1, tas.player_count do
        tas.players[player_index] = PLAYER_CHAR_COMBO:draw(ctx, "Player "..player_index, tas.players[player_index])
    end

    ctx:win_popid()
end

return module
