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
    { id = "snapshot", name = "Snapshot" }
})
local START_TYPE_COMBO = ComboInput:new(START_TYPE)

local START_PRESET_BY_INDEX = {
    {
        id = "dwelling_start", name = "Dwelling Start",
        screen = SCREEN.LEVEL, world = 1, level = 1, theme = THEME.DWELLING, shortcut = false, tutorial_race = false
    },
    {
        id = "quillback_shortcut", name = "Quillback Shortcut",
        screen = SCREEN.LEVEL, world = 1, level = 4, theme = THEME.DWELLING, shortcut = true, tutorial_race = false
    },
    {
        id = "olmec_shortcut", name = "Olmec Shortcut",
        screen = SCREEN.LEVEL, world = 3, level = 1, theme = THEME.OLMEC, shortcut = true, tutorial_race = false
    },
    {
        id = "ice_caves_shortcut", name = "Ice Caves Shortcut",
        screen = SCREEN.LEVEL, world = 5, level = 1, theme = THEME.ICE_CAVES, shortcut = true, tutorial_race = false
    },
    {
        id = "tutorial_race", name = "Tutorial Race",
        screen = SCREEN.CAMP, world = 1, level = 1, theme = THEME.BASE_CAMP, shortcut = false, tutorial_race = true, screen_last = SCREEN.CAMP
    },
    {
        id = "custom", name = "Custom"
    }
}
local START_PRESET = OrderedTable:new(START_PRESET_BY_INDEX)
local START_PRESET_COMBO = ComboInput:new(START_PRESET)

local START_SCREEN = OrderedTable:new({
    { id = SCREEN.LEVEL, name = "Level" },
    { id = SCREEN.CAMP, name = "Camp" }
})
local START_SCREEN_COMBO = ComboInput:new(START_SCREEN)

local VANILLA_LEVEL_BY_INDEX
do
    local cosmic_ocean_levels = {}
    for i = 5, 98 do
        cosmic_ocean_levels[i - 4] = i
    end
    VANILLA_LEVEL_BY_INDEX = {
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
    }
end
local VANILLA_LEVEL = OrderedTable:new(VANILLA_LEVEL_BY_INDEX)
local VANILLA_LEVEL_COMBO = ComboInput:new(VANILLA_LEVEL)

local SHORTCUTS = {
    { world = 1, level = 4, theme = THEME.DWELLING },
    { world = 3, level = 1, theme = THEME.OLMEC },
    { world = 5, level = 1, theme = THEME.ICE_CAVES }
}

local CAMP_START_TYPE_BY_INDEX = {
    { id = "tutorial_race", name = "Tutorial Race", screen_last = SCREEN.CAMP, tutorial_race = true },
    { id = "on_rope", name = "On Rope", screen_last = SCREEN.LEVEL, tutorial_race = false },
    { id = "below_rope", name = "Below Rope", screen_last = SCREEN.CAMP, tutorial_race = false },
    { id = "door_ejection", name = "Door Ejection", screen_last = SCREEN.DEATH, tutorial_race = false }
}
local CAMP_START_TYPE = OrderedTable:new(CAMP_START_TYPE_BY_INDEX)
local CAMP_START_TYPE_COMBO = ComboInput:new(CAMP_START_TYPE)

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

function module.draw_player_combo_input(ctx, tas, label, selected_player_index)
    local player_chars = tas:get_player_chars()
    local player_choices = {}
    for i = 1, tas:get_player_count() do
        player_choices[i] = i.." ("..common_enums.PLAYER_CHAR:value_by_id(player_chars[i]).name..")"
    end
    local player_combo = ComboInput:new(OrderedTable:new(player_choices))
    return player_combo:draw(ctx, label, selected_player_index)
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

    local start_preset_id = "custom"
    if not start.is_custom_preset then
        for _, start_preset in ipairs(START_PRESET_BY_INDEX) do
            if start.screen == start_preset.screen and start.world == start_preset.world and start.level == start_preset.level and start.theme == start_preset.theme
                and start.shortcut == start_preset.shortcut and start.screen_last == start_preset.screen_last and start.tutorial_race == start_preset.tutorial_race
            then
                start_preset_id = start_preset.id
                break
            end
        end
    end
    start_preset_id = START_PRESET_COMBO:draw(ctx, "Preset", start_preset_id)

    if start_preset_id == "custom" then
        ctx:win_indent(module.INDENT_SUB_INPUT)
        start.is_custom_preset = true
        start.screen = START_SCREEN_COMBO:draw(ctx, "Screen", start.screen)
        if start.screen == SCREEN.LEVEL then
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
            local can_shortcut = false
            for _, shortcut in ipairs(SHORTCUTS) do
                if start.world == shortcut.world and start.level == shortcut.level and start.theme == shortcut.theme then
                    can_shortcut = true
                    break
                end
            end
            if can_shortcut then
                start.shortcut = ctx:win_check("Shortcut", start.shortcut)
            else
                start.shortcut = false
            end
            start.screen_last = nil
            start.tutorial_race = false
        elseif start.screen == SCREEN.CAMP then
            local camp_start_type_id
            for _, camp_start_type in ipairs(CAMP_START_TYPE_BY_INDEX) do
                if start.screen_last == camp_start_type.screen_last and start.tutorial_race == camp_start_type.tutorial_race
                then
                    camp_start_type_id = camp_start_type.id
                    break
                end
            end
            camp_start_type_id = CAMP_START_TYPE_COMBO:draw(ctx, "Camp start type", camp_start_type_id)
            local camp_start_type = CAMP_START_TYPE:value_by_id(camp_start_type_id)
            start.world = 1
            start.level = 1
            start.theme = THEME.BASE_CAMP
            start.shortcut = false
            start.screen_last = camp_start_type.screen_last
            start.tutorial_race = camp_start_type.tutorial_race
        end
        ctx:win_indent(-module.INDENT_SUB_INPUT)
    else
        local start_preset = START_PRESET:value_by_id(start_preset_id)
        start.is_custom_preset = false
        start.screen = start_preset.screen
        start.world = start_preset.world
        start.level = start_preset.level
        start.theme = start_preset.theme
        start.shortcut = start_preset.shortcut
        start.screen_last = start_preset.screen_last
        start.tutorial_race = start_preset.tutorial_race
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
        print("Player count changed from "..start.player_count.." to "..new_player_count..". Updating screen and frame data.")
        start.player_count = new_player_count
        -- Populate unassigned player characters.
        for player_index = 1, new_player_count do
            if not start.players[player_index] then
                start.players[player_index] = options.new_tas.start_simple.players[player_index]
            end
        end
        -- Update all screen and frame data to match the new player count.
        for _, screen in ipairs(tas.screens) do
            if common_enums.TASABLE_SCREEN[screen.metadata.screen].record_frames then
                for player_index = 1, CONST.MAX_PLAYERS do
                    if player_index > new_player_count then
                        screen.players[player_index] = nil
                    elseif not screen.players[player_index] then
                        screen.players[player_index] = {}
                    end
                end
                for _, frame in ipairs(screen.frames) do
                    for player_index = 1, CONST.MAX_PLAYERS do
                        if player_index > new_player_count then
                            frame.players[player_index] = nil
                        elseif not frame.players[player_index] then
                            frame.players[player_index] = {
                                inputs = INPUTS.NONE
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

local function draw_tas_start_settings_snapshot(ctx, tas, is_options_tas)
    ctx:win_text(START_TYPE:value_by_id("snapshot").name..": The run is initialized by applying a screen snapshot.")
    ctx:win_section("More info", function()
        ctx:win_indent(module.INDENT_SECTION)
        ctx:win_text("A snapshot start is configured by playing the game (with or without cheating) up to right before the desired starting screen, and then capturing a snapshot of the game state while loading that screen. Runs will then start on a screen with initial conditions that are identical to the game state at the time that the snapshot was captured.")
        ctx:win_text("Snapshot starts only support levels and the camp. A snapshot start cannot be used for other screens, such as transitions and menus.")
        ctx:win_text("The TAS Tool does not currently provide an editor for snapshot starts. The only built-in way to configure a snapshot start is via snapshot capture. However, you can still edit a snapshot start by modifying the saved TAS file in a text editor. The snapshot is stored in \"start_snapshot\". The structure of \"start_snapshot.state_memory\" matches the \"StateMemory\" type in Overlunky's documentation, though it only includes fields that are necessary for a screen snapshot. Be very careful when manually editing a TAS file. The TAS Tool has almost no file validation and a corrupted TAS file can cause many problems and errors.")
        ctx:win_indent(-module.INDENT_SECTION)
    end)

    if is_options_tas then
        -- Snapshot starts are enormous. Avoid storing them in the options.
        ctx:win_text("Snapshot starts cannot be captured for the default TAS settings.")
    else
        if tas:is_start_configured() then
            local metadata = {
                screen = tas.start_snapshot.state_memory.screen_next
            }
            if metadata.screen == SCREEN.LEVEL or metadata.screen == SCREEN.TRANSITION then
                metadata.world = tas.start_snapshot.state_memory.world_next
                metadata.level = tas.start_snapshot.state_memory.level_next
                metadata.theme = tas.start_snapshot.state_memory.theme_next
            end
            local start_area_name = common.screen_metadata_to_string(metadata)
            ctx:win_text("Current screen snapshot: "..start_area_name)
        else
            ctx:win_text("Current screen snapshot: None")
            if not tas.screen_snapshot_request_id then
                ctx:win_text("To capture a screen snapshot, prepare your run in the prior screen, and then press \"Request capture\".")
            end
        end
        if tas.screen_snapshot_request_id then
            ctx:win_text("Capture status: Awaiting screen change. A snapshot of the next valid screen you load into will be captured.")
            if ctx:win_button("Cancel capture") then
                game_controller.clear_screen_snapshot_request(tas.screen_snapshot_request_id)
                tas.screen_snapshot_request_id = nil
            end
            ctx:win_text("Cancel the requested screen snapshot capture.")
        else
            if ctx:win_button("Request capture") then
                tas.screen_snapshot_request_id = game_controller.register_screen_snapshot_request(function(screen_snapshot)
                    tas.screen_snapshot_request_id = nil
                    tas.start_snapshot = screen_snapshot
                end)
            end
            ctx:win_text("Request a new screen snapshot capture.")
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
            if tas.screen_snapshot_request_id then
                game_controller.clear_screen_snapshot_request(tas.screen_snapshot_request_id)
                tas.screen_snapshot_request_id = nil
            end
        elseif new_choice_id == "snapshot" then
            if not tas.start_snapshot then
                tas.start_snapshot = common.deep_copy(options.new_tas.start_snapshot)
            end
        end
    end)
    if tas.start_type == "simple" then
        draw_tas_start_settings_simple(ctx, tas)
    elseif tas.start_type == "snapshot" then
        draw_tas_start_settings_snapshot(ctx, tas, is_options_tas)
    end
end

return module
