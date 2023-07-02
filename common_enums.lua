local OrderedTable = require("ordered_table")

local module = {}

module.MODE = {
    -- Keep track of current level, but do not record or playback any frames, and do not execute configured skip inputs.
    FREEPLAY = 0,
    -- Record gameplay frames, and execute configured skip inputs.
    RECORD = 1,
    -- Playback recorded gameplay frames up to the chosen target, and execute configured skip inputs.
    PLAYBACK = 2
}

module.PLAYBACK_TARGET_MODE = OrderedTable:new({
    { id = "playback", name = "Continue playback", mode = module.MODE.PLAYBACK },
    { id = "record", name = "Switch to recording", mode = module.MODE.RECORD },
    { id = "freeplay", name = "Switch to freeplay", mode = module.MODE.FREEPLAY }
})

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

module.SKIP_INPUT = OrderedTable:new({
    { id = "jump", name = "Jump", input = INPUTS.JUMP },
    { id = "bomb", name = "Bomb", input = INPUTS.BOMB }
})

return module
