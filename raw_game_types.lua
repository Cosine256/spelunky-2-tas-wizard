local introspection = require("introspection")

local CLASSES = {
    -- This is a subset of the StateMemory class containing only necessary fields for level snapshots.
    StateMemory_LevelSnapshot = {
        fields = {
            { type = "SCREEN", name = "screen_next" },
            { type = "int", name = "kali_favor" },
            { type = "int", name = "kali_status" },
            { type = "int", name = "kali_altars_destroyed" },
            { type = "int", name = "kali_gifts" },
            { type = "int", name = "seed" },
            { type = "int", name = "time_total" },
            { type = "int", name = "world" },
            { type = "int", name = "world_next" },
            { type = "int", name = "world_start" },
            { type = "int", name = "level" },
            { type = "int", name = "level_next" },
            { type = "int", name = "level_start" },
            { type = "THEME", name = "theme" },
            { type = "THEME", name = "theme_next" },
            { type = "int", name = "theme_start" },
            { type = "int", name = "shoppie_aggro" },
            { type = "int", name = "shoppie_aggro_next" },
            { type = "int", name = "outposts_spawned" },
            { type = "int", name = "merchant_aggro" },
            { type = "int", name = "kills_npc" },
            { type = "int", name = "level_count" },
            { type = "int", name = "damage_taken" },
            { type = "JOURNAL_FLAG", name = "journal_flags" },
            { type = "int", name = "time_last_level" },
            { type = "int", name = "time_level" },
            { type = "QUEST_FLAG", name = "quest_flags" },
            { type = "int", name = "saved_dogs" },
            { type = "int", name = "saved_cats" },
            { type = "int", name = "saved_hamsters" },
            { type = "int", name = "win_state" },
            { type = "int", name = "money_last_levels" },
            { type = "int", name = "money_shop_total" },
            { type = "QuestsInfo", name = "quests" },
            { type = "int", name = "correct_ushabti" },
            { type = "Items", name = "items" },
            { type = "bool", name = "world2_coffin_spawned" },
            { type = "bool", name = "world4_coffin_spawned" },
            { type = "bool", name = "world6_coffin_spawned" },
            { type = "ENT_TYPE", name = "first_damage_cause" },
            { type = "int", name = "first_damage_world" },
            { type = "int", name = "first_damage_level" },
            { type = "ENT_TYPE", array_size = 99, name = "waddler_storage" },
            { type = "int", array_size = 99, name = "waddler_metadata" }
        }
    },
    QuestsInfo = {
        fields = {
            { type = "int", name = "yang_state" },
            { type = "int", name = "jungle_sisters_flags" },
            { type = "int", name = "van_horsing_state" },
            { type = "int", name = "sparrow_state" },
            { type = "int", name = "madame_tusk_state" },
            { type = "int", name = "beg_state" }
        }
    },
    Items = {
        fields = {
            { type = "int", name = "player_count" },
            { type = "int", name = "saved_pets_count" },
            { type = "ENT_TYPE", array_size = 4, name = "saved_pets" },
            { type = "bool", array_size = 4, name = "is_pet_cursed" },
            { type = "bool", array_size = 4, name = "is_pet_poisoned" },
            { type = "int", name = "leader" },
            { type = "Inventory", array_size = CONST.MAX_PLAYERS, name = "player_inventory" },
            { type = "SelectPlayerSlot", array_size = CONST.MAX_PLAYERS, name = "player_select" }
        }
    },
    Inventory = {
        fields = {
            { type = "int", name = "money" },
            { type = "int", name = "bombs" },
            { type = "int", name = "ropes" },
            { type = "int", name = "player_slot" },
            { type = "int", name = "poison_tick_timer" },
            { type = "bool", name = "cursed" },
            { type = "bool", name = "elixir_buff" },
            { type = "int", name = "health" },
            { type = "int", name = "kapala_blood_amount" },
            { type = "int", name = "time_of_death" },
            { type = "ENT_TYPE", name = "held_item" },
            { type = "int", name = "held_item_metadata" },
            { type = "ENT_TYPE", name = "mount_type" },
            { type = "int", name = "mount_metadata" },
            { type = "int", name = "kills_level" },
            { type = "int", name = "kills_total" },
            { type = "int", name = "collected_money_total" },
            { type = "int", name = "collected_money_count" },
            { type = "ENT_TYPE", array_size = 512, name = "collected_money" },
            { type = "int", array_size = 512, name = "collected_money_values" },
            { type = "ENT_TYPE", array_size = 256, name = "killed_enemies" },
            { type = "int", name = "companion_count" },
            { type = "ENT_TYPE", array_size = 8, name = "companions" },
            { type = "ENT_TYPE", array_size = 8, name = "companion_held_items" },
            { type = "int", array_size = 8, name = "companion_held_item_metadatas" },
            { type = "int", array_size = 8, name = "companion_trust" },
            { type = "int", array_size = 8, name = "companion_health" },
            { type = "int", array_size = 8, name = "companion_poison_tick_timers" },
            { type = "bool", array_size = 8, name = "is_companion_cursed" },
            { type = "ENT_TYPE", array_size = 30, name = "acquired_powerups" }
        }
    },
    SelectPlayerSlot = {
        fields = {
            { type = "bool", name = "activated" },
            { type = "ENT_TYPE", name = "character" },
            { type = "int", name = "texture" }
        }
    }
}

local types = {
    int = {},
    bool = {},
    ENT_TYPE = {},
    JOURNAL_FLAG = {},
    QUEST_FLAG = {},
    SCREEN = {},
    THEME = {}
}

-- TODO: Consider moving this class restructuring code into the introspection module.
for class_name, class in pairs(CLASSES) do
    types[class_name] = class
    class.traversal_type = introspection.TRAVERSAL_TYPE.CLASS
    if class.fields then
        for _, field in ipairs(class.fields) do
            if field.is_array or field.array_size then
                field.type = {
                    array_size = field.array_size,
                    element_type = field.type
                }
                if field.array_size then
                    field.type.traversal_type = introspection.TRAVERSAL_TYPE.STRUCTURAL_ARRAY
                    field.type.name = field.type.element_type.."["..field.array_size.."]"
                else
                    field.type.traversal_type = introspection.TRAVERSAL_TYPE.ARRAY
                    field.type.name = field.type.element_type.."[]"
                end
                field.is_array = nil
                field.array_size = nil
            end
        end
    end
end

return types
