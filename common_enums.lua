local OrderedTable = require("ordered_table")

local module = {}

-- The game interaction mode for a TAS session.
module.MODE = {
    -- Keep track of current screen, but do not record or playback any TAS frames, and do not execute configured transition exits.
    FREEPLAY = 0,
    -- Record TAS frames, and execute configured transition exits.
    RECORD = 1,
    -- Playback recorded TAS frames up to the chosen target, and execute configured transition exits.
    PLAYBACK = 2
}

-- The point in the TAS to start playback from.
module.PLAYBACK_FROM = {
    -- Use current frame or warp to the nearest screen to reach the target, preferring whichever is closer.
    { id = "here_or_nearest_screen", name = "Here or nearest screen" },
    -- Prefer current frame if it can reach the target. Otherwise, warp to the nearest screen.
    { id = "here_else_nearest_screen", name = "Here, else nearest screen" },
    -- Warp to the nearest screen to reach the target.
    { id = "nearest_screen", name = "Nearest screen" }
}

module.PLAYBACK_TARGET_MODE = OrderedTable:new({
    { id = "playback", name = "Continue playback", mode = module.MODE.PLAYBACK },
    { id = "record", name = "Switch to recording", mode = module.MODE.RECORD },
    { id = "freeplay", name = "Switch to freeplay", mode = module.MODE.FREEPLAY }
})

---@class TasableScreen Attributes for a TASable screen. A TASable screen is a screen which supports TAS recording and playback.
---@field data_id string Data ID for this screen. Can be used as a key where the integer ID will not work, such as JSON.
---@field name string Display name for this screen.
---@field record_frames boolean Whether the screen supports recording data for individual frames and playback to specific frames. Frame data includes player inputs and positions.
---@field can_snapshot boolean Whether the screen supports capturing and applying screen snapshots. Snapshots are currently limited to screens that trigger the `PRE_LEVEL_GENERATION` callback due to the need for a mid-update callback to apply certain changes.
---@type { [SCREEN]: TasableScreen } Table of all TASable screens.
module.TASABLE_SCREEN = {
    [SCREEN.CAMP] = {
        data_id = "camp",
        name = "Base Camp",
        record_frames = true,
        can_snapshot = true
    },
    [SCREEN.LEVEL] = {
        data_id = "level",
        name = "Level",
        record_frames = true,
        can_snapshot = true
    },
    [SCREEN.TRANSITION] = {
        data_id = "transition",
        name = "Transition",
        record_frames = false,
        can_snapshot = false
    },
    [SCREEN.SPACESHIP] = {
        data_id = "spaceship",
        name = "Spaceship Cutscene",
        record_frames = false,
        can_snapshot = false
    }
}

module.PLAYER_CHAR = OrderedTable:new({
    { id = "ana", name = "Ana", ent_type_id = ENT_TYPE.CHAR_ANA_SPELUNKY, texture_id = TEXTURE.DATA_TEXTURES_CHAR_YELLOW_0 },
    { id = "margaret", name = "Margaret", ent_type_id = ENT_TYPE.CHAR_MARGARET_TUNNEL, texture_id = TEXTURE.DATA_TEXTURES_CHAR_MAGENTA_0 },
    { id = "colin", name = "Colin", ent_type_id = ENT_TYPE.CHAR_COLIN_NORTHWARD, texture_id = TEXTURE.DATA_TEXTURES_CHAR_CYAN_0 },
    { id = "roffy", name = "Roffy", ent_type_id = ENT_TYPE.CHAR_ROFFY_D_SLOTH, texture_id = TEXTURE.DATA_TEXTURES_CHAR_BLACK_0 },
    { id = "alto", name = "Alto", ent_type_id = ENT_TYPE.CHAR_BANDA, texture_id = TEXTURE.DATA_TEXTURES_CHAR_CINNABAR_0 },
    { id = "liz", name = "Liz", ent_type_id = ENT_TYPE.CHAR_GREEN_GIRL, texture_id = TEXTURE.DATA_TEXTURES_CHAR_GREEN_0 },
    { id = "nekka", name = "Nekka", ent_type_id = ENT_TYPE.CHAR_AMAZON, texture_id = TEXTURE.DATA_TEXTURES_CHAR_OLIVE_0 },
    { id = "lise", name = "LISE", ent_type_id = ENT_TYPE.CHAR_LISE_SYSTEM, texture_id = TEXTURE.DATA_TEXTURES_CHAR_WHITE_0 },
    { id = "coco", name = "Coco", ent_type_id = ENT_TYPE.CHAR_COCO_VON_DIAMONDS, texture_id = TEXTURE.DATA_TEXTURES_CHAR_CERULEAN_0 },
    { id = "manfred", name = "Manfred", ent_type_id = ENT_TYPE.CHAR_MANFRED_TUNNEL, texture_id = TEXTURE.DATA_TEXTURES_CHAR_BLUE_0 },
    { id = "jay", name = "Jay", ent_type_id = ENT_TYPE.CHAR_OTAKU, texture_id = TEXTURE.DATA_TEXTURES_CHAR_LIME_0 },
    { id = "tina", name = "Tina", ent_type_id = ENT_TYPE.CHAR_TINA_FLAN, texture_id = TEXTURE.DATA_TEXTURES_CHAR_LEMON_0 },
    { id = "valerie", name = "Valerie", ent_type_id = ENT_TYPE.CHAR_VALERIE_CRUMP, texture_id = TEXTURE.DATA_TEXTURES_CHAR_IRIS_0 },
    { id = "au", name = "Au", ent_type_id = ENT_TYPE.CHAR_AU, texture_id = TEXTURE.DATA_TEXTURES_CHAR_GOLD_0 },
    { id = "demi", name = "Demi", ent_type_id = ENT_TYPE.CHAR_DEMI_VON_DIAMONDS, texture_id = TEXTURE.DATA_TEXTURES_CHAR_RED_0 },
    { id = "pilot", name = "Pilot", ent_type_id = ENT_TYPE.CHAR_PILOT, texture_id = TEXTURE.DATA_TEXTURES_CHAR_PINK_0 },
    { id = "airyn", name = "Airyn", ent_type_id = ENT_TYPE.CHAR_PRINCESS_AIRYN, texture_id = TEXTURE.DATA_TEXTURES_CHAR_VIOLET_0 },
    { id = "dirk", name = "Dirk", ent_type_id = ENT_TYPE.CHAR_DIRK_YAMAOKA, texture_id = TEXTURE.DATA_TEXTURES_CHAR_GRAY_0 },
    { id = "guy", name = "Guy", ent_type_id = ENT_TYPE.CHAR_GUY_SPELUNKY, texture_id = TEXTURE.DATA_TEXTURES_CHAR_KHAKI_0 },
    { id = "classic_guy", name = "Classic Guy", ent_type_id = ENT_TYPE.CHAR_CLASSIC_GUY, texture_id = TEXTURE.DATA_TEXTURES_CHAR_ORANGE_0 }
})

module.PLAYER_CHAR_BY_ENT_TYPE = {}
for _, player_char in pairs(module.PLAYER_CHAR:values_by_id()) do
    module.PLAYER_CHAR_BY_ENT_TYPE[player_char.ent_type_id] = player_char
end

return module
