local common = require("common")
local common_enums = require("common_enums")
local ComboInput = require("gui/combo_input")
local game_controller = require("game_controller")
local OrderedTable = require("ordered_table")

local module = {}

module.INDENT_SECTION = 5
module.INDENT_SUB_INPUT = 10

local START_TYPE = OrderedTable:new({
    { id = "simple", name = "Simple" },
    { id = "full", name = "Full" }
})
local START_TYPE_COMBO = ComboInput:new(START_TYPE)

local RUN_START_AREA = OrderedTable:new({
    { id = "dwelling", name = "Dwelling", world = 1, level = 1, theme = THEME.DWELLING, shortcut = false, tutorial_race = false },
    { id = "quillback_shortcut", name = "Quillback Shortcut", world = 1, level = 4, theme = THEME.DWELLING, shortcut = true, tutorial_race = false },
    { id = "olmec_shortcut", name = "Olmec Shortcut", world = 3, level = 1, theme = THEME.OLMEC, shortcut = true, tutorial_race = false },
    { id = "ice_caves_shortcut", name = "Ice Caves Shortcut", world = 5, level = 1, theme = THEME.ICE_CAVES, shortcut = true, tutorial_race = false },
    { id = "tutorial_race", name = "Tutorial Race", world = 1, level = 1, theme = THEME.BASE_CAMP, shortcut = false, tutorial_race = true },
    { id = "custom", name = "Custom" }
})
local RUN_START_AREA_BY_INDEX = RUN_START_AREA:values_by_index()
local RUN_START_AREA_COMBO = ComboInput:new(RUN_START_AREA)

local VANILLA_LEVEL
do
    local cosmic_ocean_levels = {}
    for i = 5, 98 do
        cosmic_ocean_levels[i - 4] = i
    end
    VANILLA_LEVEL = OrderedTable:new({
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
        { id = "cosmic_ocean", name = common.THEME_NAME[THEME.COSMIC_OCEAN], theme = THEME.COSMIC_OCEAN, world = 8, levels = cosmic_ocean_levels }
    })
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

function module.draw_drag_int_clamped(ctx, label, value, min, max, clamp_min, clamp_max)
    value = ctx:win_drag_int(label, value, min, max)
    if (clamp_min or clamp_min == nil) and value < min then
        return min
    elseif (clamp_max or clamp_max == nil) and value > max then
        return max
    else
        return value
    end
end

local function draw_inputs_editor_check(ctx, inputs, input, label)
    return ctx:win_check(label, inputs & input > 0) and (inputs | input) or (inputs & ~input)
end

function module.draw_inputs_editor(ctx, inputs)
    inputs = draw_inputs_editor_check(ctx, inputs, INPUTS.LEFT, "Left")
    ctx:win_inline()
    inputs = draw_inputs_editor_check(ctx, inputs, INPUTS.RIGHT, "Right")
    ctx:win_inline()
    inputs = draw_inputs_editor_check(ctx, inputs, INPUTS.UP, "Up")
    ctx:win_inline()
    inputs = draw_inputs_editor_check(ctx, inputs, INPUTS.DOWN, "Down")

    inputs = draw_inputs_editor_check(ctx, inputs, INPUTS.JUMP, "Jump")
    ctx:win_inline()
    inputs = draw_inputs_editor_check(ctx, inputs, INPUTS.WHIP, "Whip")
    ctx:win_inline()
    inputs = draw_inputs_editor_check(ctx, inputs, INPUTS.BOMB, "Bomb")
    ctx:win_inline()
    inputs = draw_inputs_editor_check(ctx, inputs, INPUTS.ROPE, "Rope")

    inputs = draw_inputs_editor_check(ctx, inputs, INPUTS.DOOR, "Door")
    ctx:win_inline()
    inputs = draw_inputs_editor_check(ctx, inputs, INPUTS.RUN, "Run")

    return inputs
end

function module.draw_tool_gui_panels(ctx, tool_guis)
    ctx:win_pushid("tool_gui_panels")
    local panel_drawn = false
    for _, tool_gui in ipairs(tool_guis) do
        if not tool_gui:is_window_open() then
            if panel_drawn then
                ctx:win_separator()
            else
                panel_drawn = true
            end
            ctx:win_pushid(tool_gui.id)
            ctx:win_section(tool_gui.name, function()
                ctx:win_indent(module.INDENT_SECTION)
                tool_gui:draw_panel(ctx, false)
                ctx:win_indent(-module.INDENT_SECTION)
            end)
            ctx:win_popid()
        end
    end
    ctx:win_popid()
    if not panel_drawn then
        ctx:win_text("All panels detached into separate windows.")
    end
end

local function draw_tas_start_settings_simple(ctx, tas)
    local start = tas.start_simple
    ctx:win_text(START_TYPE:value_by_id("simple").name..": Provides basic start settings, such as the starting area and player characters. All other aspects of the run (health, items, etc) use the default behavior from starting a new run.")
    local run_start_area_id = "custom"
    if not start.is_custom_area_choice then
        for _, run_start_area in ipairs(RUN_START_AREA_BY_INDEX) do
            if start.world == run_start_area.world and start.level == run_start_area.level and start.theme == run_start_area.theme
                and start.shortcut == run_start_area.shortcut and start.tutorial_race == run_start_area.tutorial_race
            then
                run_start_area_id = run_start_area.id
                break
            end
        end
    end
    run_start_area_id = RUN_START_AREA_COMBO:draw(ctx, "Start area", run_start_area_id)
    if run_start_area_id == "custom" then
        ctx:win_indent(module.INDENT_SUB_INPUT)
        start.is_custom_area_choice = true
        start.shortcut = false
        start.tutorial_race = false
        local vanilla_level_id
        for _, vanilla_level in ipairs(VANILLA_LEVEL_BY_INDEX) do
            if start.world == vanilla_level.world and start.theme == vanilla_level.theme then
                vanilla_level_id = vanilla_level.id
                break
            end
        end
        vanilla_level_id = VANILLA_LEVEL_COMBO:draw(ctx, "World", vanilla_level_id)
        local vanilla_level = VANILLA_LEVEL:value_by_id(vanilla_level_id)
        start.world = vanilla_level.world
        start.theme = vanilla_level.theme
        if #vanilla_level.levels == 1 then
            start.level = vanilla_level.levels[1]
        else
            local level_choices = {}
            for i, level in ipairs(vanilla_level.levels) do
                level_choices[i] = { id = level }
            end
            local level_combo = ComboInput:new(OrderedTable:new(level_choices))
            start.level = level_combo:draw(ctx, "Level", start.level)
        end
        ctx:win_indent(-module.INDENT_SUB_INPUT)
    else
        start.is_custom_area_choice = false
        local run_start_area = RUN_START_AREA:value_by_id(run_start_area_id)
        start.world = run_start_area.world
        start.level = run_start_area.level
        start.theme = run_start_area.theme
        start.shortcut = run_start_area.shortcut
        start.tutorial_race = run_start_area.tutorial_race
    end

    local new_seed_type_id = SEED_TYPE_COMBO:draw(ctx, "Seed type", start.seed_type)
    local is_seeded = new_seed_type_id == "seeded"
    if start.seed_type ~= new_seed_type_id then
        start.seed_type = new_seed_type_id
        if is_seeded then
            if not start.seeded_seed then
                start.seeded_seed = options.new_tas.start_simple.seeded_seed
            end
        else
            if not start.adventure_seed then
                start.adventure_seed = common.deep_copy(options.new_tas.start_simple.adventure_seed)
            end
        end
    end
    ctx:win_indent(module.INDENT_SUB_INPUT)
    local seed_type = SEED_TYPE:value_by_id(new_seed_type_id)
    ctx:win_text(seed_type.name..": "..seed_type.desc)
    if is_seeded then
        local new_seed = common.string_to_seed(
            ctx:win_input_text("Seed##new_seed_text", common.seed_to_string(start.seeded_seed)))
        if new_seed then
            start.seeded_seed = new_seed
        end
    else
        local new_part_1 = common.string_to_adventure_seed_part(
            ctx:win_input_text("Part 1##new_seed_1_text", common.adventure_seed_part_to_string(start.adventure_seed[1])))
        local new_part_2 = common.string_to_adventure_seed_part(
            ctx:win_input_text("Part 2##new_seed_2_text", common.adventure_seed_part_to_string(start.adventure_seed[2])))
        if new_part_1 then
            start.adventure_seed[1] = new_part_1
        end
        if new_part_2 then
            start.adventure_seed[2] = new_part_2
        end
    end
    if ctx:win_button("Randomize seed") then
        if is_seeded then
            start.seeded_seed = math.random(0, 0xFFFFFFFF)
        else
            -- Lua uses 64-bit signed integers, so the random ranges need to be specified like this.
            start.adventure_seed = { math.random(math.mininteger, math.maxinteger), math.random(math.mininteger, math.maxinteger) }
        end
    end
    ctx:win_indent(-module.INDENT_SUB_INPUT)

    if start.tutorial_race then
        start.tutorial_race_referee = PLAYER_CHAR_COMBO:draw(ctx, "Tutorial race referee", start.tutorial_race_referee or options.new_tas.start_simple.tutorial_race_referee)
    end

    local new_player_count
    if start.tutorial_race then
        new_player_count = 1
    else
        new_player_count = PLAYER_COUNT_COMBO:draw(ctx, "Player count", start.player_count)
    end
    if start.player_count ~= new_player_count then
        -- Update all level and frame data to match the new player count.
        print("Player count changed from "..start.player_count.." to "..new_player_count..". Updating level and frame data.")
        start.player_count = new_player_count
        for _, level in ipairs(tas.levels) do
            if common_enums.TASABLE_SCREEN[level.metadata.screen].record_frames then
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
    end
    for player_index = 1, start.player_count do
        start.players[player_index] = PLAYER_CHAR_COMBO:draw(ctx, "Player "..player_index, start.players[player_index])
    end
end

local function draw_tas_start_settings_full(ctx, tas, is_options_tas)
    ctx:win_text(START_TYPE:value_by_id("full").name..": The run is initialized by applying a full level snapshot.")
    ctx:win_section("More info", function()
        ctx:win_indent(module.INDENT_SECTION)
        ctx:win_text("A full start is configured by playing the game (with or without cheating) up to right before the desired starting level, and then capturing a snapshot of the game state while loading that level. Runs will then start on a level with initial conditions that are identical to the game state at the time that the snapshot was captured.")
        ctx:win_text("Full starts only support levels and the camp. A full start cannot be used for other areas, such as level transitions and menus.")
        ctx:win_text("The TAS Tool does not currently provide an editor for full starts. The only built-in way to configure a full start is via snapshot capture. However, you can still edit a full start by modifying the saved TAS file in a text editor. The full start is stored in \"start_full\". The structure of \"start_full.state_memory\" matches the \"StateMemory\" type in Overlunky's documentation, though it only includes fields that are necessary for a full start. Be very careful when manually editing a TAS file. The TAS Tool has almost no file validation and a corrupted TAS file can cause many problems and errors.")
        ctx:win_indent(-module.INDENT_SECTION)
    end)

    if is_options_tas then
        -- Full start snapshots are enormous. Avoid storing them in the options.
        ctx:win_text("Full starts cannot be captured for the default TAS settings.")
    else
        if tas:is_start_configured() then
            local metadata = {
                screen = tas.start_full.state_memory.screen_next
            }
            if metadata.screen == SCREEN.LEVEL or metadata.screen == SCREEN.TRANSITION then
                metadata.world = tas.start_full.state_memory.world_next
                metadata.level = tas.start_full.state_memory.level_next
                metadata.theme = tas.start_full.state_memory.theme_next
            end
            local start_area_name = common.level_metadata_to_string(metadata)
            ctx:win_text("Current level snapshot: "..start_area_name)
        else
            ctx:win_text("Current level snapshot: None")
            if not tas.level_snapshot_request_id then
                ctx:win_text("To capture a level snapshot, prepare your run in the prior level, and then press \"Request capture\".")
            end
        end
        if tas.level_snapshot_request_id then
            ctx:win_text("Capture status: Awaiting level start. A snapshot of the next level you load into will be captured.")
            if ctx:win_button("Cancel capture") then
                game_controller.clear_level_snapshot_request(tas.level_snapshot_request_id)
                tas.level_snapshot_request_id = nil
            end
            ctx:win_text("Cancel the requested level snapshot capture.")
        else
            if ctx:win_button("Request capture") then
                tas.level_snapshot_request_id = game_controller.register_level_snapshot_request(function(level_snapshot)
                    tas.level_snapshot_request_id = nil
                    tas.start_full = level_snapshot
                end)
            end
            ctx:win_text("Request a new level snapshot capture.")
        end
    end
end

function module.draw_tas_start_settings(ctx, tas, is_options_tas)
    tas.start_type = START_TYPE_COMBO:draw(ctx, "Start type", tas.start_type, function(current_choice_id, new_choice_id)
        -- TODO: Handle possible player count change when switching start types.
        if new_choice_id == "simple" then
            if not tas.start_simple then
                tas.start_simple = common.deep_copy(options.new_tas.start_simple)
            end
            if tas.level_snapshot_request_id then
                game_controller.clear_level_snapshot_request(tas.level_snapshot_request_id)
                tas.level_snapshot_request_id = nil
            end
        elseif new_choice_id == "full" then
            if not tas.start_full then
                tas.start_full = common.deep_copy(options.new_tas.start_full)
            end
        end
    end)
    if tas.start_type == "simple" then
        draw_tas_start_settings_simple(ctx, tas)
    elseif tas.start_type == "full" then
        draw_tas_start_settings_full(ctx, tas, is_options_tas)
    end
end

return module
