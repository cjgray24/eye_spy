--init

local modpath = minetest.get_modpath("eye_spy")

-- Load modules in dependency order:
-- 1. Core declarations + helpers (defines eye_spy = {})
dofile(modpath .. "/functions.lua")

-- 2. Config (needs eye_spy.storage from functions.lua)
dofile(modpath .. "/config.lua")

-- 3. Performance metrics (needs eye_spy.config)
dofile(modpath .. "/perf.lua")

-- 4. Pure utilities (no minetest runtime deps)
dofile(modpath .. "/colors.lua")
dofile(modpath .. "/tools.lua") -- needs eye_spy.S

-- 5. Target acquisition + enrichment
dofile(modpath .. "/target.lua")
dofile(modpath .. "/enrichers.lua")

-- 6. Rendering
dofile(modpath .. "/render.lua")

-- 7. Registration (entities, nodes)
dofile(modpath .. "/preview.lua")

-- 8. UI + Commands (last, can reference everything above)
dofile(modpath .. "/ui.lua")
dofile(modpath .. "/commands.lua")

-- Detect game type — sets eye_spy.cg used by tools.lua at runtime.
-- tools.lua reads eye_spy.cg inside function bodies, not at load time, so this is fine.
if minetest.get_modpath("default") then
    eye_spy.cg = "minetest_game"
elseif minetest.get_modpath("mcl_core") then
    eye_spy.cg = "mineclone"
    -- Note: voxelibre/mineclonia distinction reserved for future differentiation.
    if minetest.get_modpath("vl_legacy") then
        eye_spy.cgs = "voxelibre"
    else
        eye_spy.cgs = "mineclonia"
    end
end

-- Player join: initialise per-player state and defaults.
minetest.register_on_joinplayer(function(player)
    local meta = player:get_meta()

    -- Clear legacy tracking keys.
    meta:set_string("es_last_obj", "")
    meta:set_int("es_last_health", -1)

    -- Apply defaults for any keys not yet set.
    eye_spy.ensure_player_defaults(player)

    -- Initialise runtime state.
    local state                                 = eye_spy.get_player_state(player)
    state.timer                                 = 0
    state.edit_mode                             = false

    eye_spy.edit_mode[player:get_player_name()] = false
end)

-- Player leave: clean up ALL per-player runtime data.
minetest.register_on_leaveplayer(function(player)
    local player_name                             = player:get_player_name()

    -- Runtime state tables.
    eye_spy.state.players[player_name]            = nil
    eye_spy.edit_mode[player_name]                = nil
    eye_spy.pending_preview_updates[player_name]  = nil
    eye_spy.pending_layout_refreshes[player_name] = nil
    eye_spy.ui_drafts[player_name]                = nil

    -- Invalidate render layout signature cache.
    if eye_spy.render and eye_spy.render.invalidate_layout_sig then
        eye_spy.render.invalidate_layout_sig(player_name)
    end

    -- Enricher tool-hint cache.
    if eye_spy.enrichers and eye_spy.enrichers.on_player_leave then
        eye_spy.enrichers.on_player_leave(player_name)
    end

    -- HUD elements are automatically destroyed by the engine when a player leaves,
    -- but we must remove our engine references to prevent stale ID usage on rejoin.
    eye_spy.remove_huds(player)
end)

-- Main game loop.
minetest.register_globalstep(function(dtime)
    eye_spy.step(dtime)
end)

minetest.log("action", "[eye_spy] Mod loaded successfully.")
