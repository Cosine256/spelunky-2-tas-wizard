local common = require("common")
local common_gui = require("gui/common_gui")
local Tas = require("tas")
local Tool_GUI = require("gui/tool_gui")

local module = Tool_GUI:new("New", "new_window")

function module:draw_panel(ctx, is_window)
    ctx:win_pushid("new_tas_start_settings")
    common_gui.draw_tas_start_settings(ctx, options.new_tas)
    ctx:win_popid()
    if options.new_tas.start.seed_type == "seeded" then
        options.new_seeded_seed = options.new_tas.start.seeded_seed
    else
        options.new_adventure_seed = common.deep_copy(options.new_tas.start.adventure_seed)
    end
    if ctx:win_button("Create") then
        set_current_tas(Tas:new(options.new_tas, true))
    end
    ctx:win_text("Create a new TAS with these settings.")
end

return module
