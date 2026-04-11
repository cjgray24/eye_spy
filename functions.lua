--functions

eye_spy                          = {}
local S                          = minetest.get_translator(minetest.get_current_modname())
eye_spy.S                        = S
-- eye_spy.cg is set in init.lua after game detection

------------------------------------------------------------
-- Mod storage (called ONCE at load time)
------------------------------------------------------------
eye_spy.storage                  = minetest.get_mod_storage()

------------------------------------------------------------
-- Shared runtime tables
------------------------------------------------------------
eye_spy.state                    = { players = {} }
eye_spy.cache                    = { tool_info = {} }
eye_spy.edit_mode                = {}
eye_spy.pending_preview_updates  = {}
eye_spy.pending_layout_refreshes = {}
eye_spy.ui_drafts                = {}

------------------------------------------------------------
-- Shared helper functions
------------------------------------------------------------

-- Returns a human-readable name from a node/item id string, or nil on failure.
-- Callers are responsible for providing their own fallback string.
function eye_spy.readable_name_from_id(name)
    if not name or name == "" then
        return nil
    end

    local raw      = tostring(name)
    local stripped = raw:match(":(.+)$") or raw

    stripped       = stripped
        :gsub("_source$", "")
        :gsub("_flowing$", "")
        :gsub("[_%-%./]+", " ")
        :gsub("%s+", " ")
        :gsub("^%s+", "")
        :gsub("%s+$", "")

    if stripped == "" then
        return nil
    end

    return (stripped:gsub("(%a)([%w']*)", function(a, b)
        return string.upper(a) .. string.lower(b)
    end))
end

-- Returns the mod portion of a namespaced id (e.g. "default" from "default:stone").
function eye_spy.get_modname_from_obj(obj_name)
    if not obj_name then return nil end
    return obj_name:match("([^:]+)")
end

-- Rounds x to one decimal place, or returns nil if x is falsy.
function eye_spy.round1(x)
    if x then
        return math.floor(x * 10 + 0.5) / 10
    else
        return nil
    end
end

-- Strips everything from the first texture-modifier caret (^) onwards.
function eye_spy.strip_texture_modifiers(tex)
    if type(tex) ~= "string" then
        return tex
    end

    local pos = tex:find("%^")
    if not pos then
        return tex
    end

    return tex:sub(1, pos - 1)
end

-- Parses an "R, G, B" string and returns three numbers.
-- Falls back to 26, 26, 27 for any component that cannot be parsed.
function eye_spy.get_rgb(v)
    if not v or v == "" then
        return 26, 26, 27
    end

    v = v:gsub("%s", "")

    local r, g, b = v:match("^(%d+),(%d+),(%d+)$")
    r, g, b = tonumber(r), tonumber(g), tonumber(b)

    return r or 26, g or 26, b or 27
end

-- Converts three 0-255 channel values to an uppercase hex string.
function eye_spy.rgb_to_hex(r, g, b)
    return string.format("%02X%02X%02X", r, g, b)
end

------------------------------------------------------------
-- Interval system
------------------------------------------------------------

local function clamp_interval_ms(value)
    return math.max(50, math.min(5000, tonumber(value) or 250))
end

local function default_interval_for_mode()
    if minetest.is_singleplayer and minetest.is_singleplayer() then
        return 100
    end
    return 150
end

function eye_spy.get_server_default_interval_ms()
    local raw = eye_spy.storage:get_string("server_default_interval_ms")
    if raw and raw ~= "" then
        return clamp_interval_ms(raw)
    end
    return default_interval_for_mode()
end

function eye_spy.set_server_default_interval_ms(interval_ms)
    eye_spy.storage:set_string(
        "server_default_interval_ms",
        tostring(clamp_interval_ms(interval_ms))
    )
end

function eye_spy.get_player_interval_override_ms(player_name)
    if not player_name or player_name == "" then
        return nil
    end

    local raw = eye_spy.storage:get_string("player_interval_ms:" .. player_name)
    if raw == "" then
        return nil
    end

    return clamp_interval_ms(raw)
end

function eye_spy.set_player_interval_override_ms(player_name, interval_ms)
    if not player_name or player_name == "" then
        return
    end

    local key = "player_interval_ms:" .. player_name

    if interval_ms == nil then
        eye_spy.storage:set_string(key, "")
        return
    end

    eye_spy.storage:set_string(key, tostring(clamp_interval_ms(interval_ms)))
end

function eye_spy.get_effective_interval_ms(player_name)
    return eye_spy.get_player_interval_override_ms(player_name)
        or eye_spy.get_server_default_interval_ms()
end

function eye_spy.apply_player_interval(player)
    if not player then return end
    local meta        = player:get_meta()
    local player_name = player:get_player_name()
    meta:set_int("es_update_interval_ms", eye_spy.get_effective_interval_ms(player_name))
end

------------------------------------------------------------
-- Admin / player disable system
------------------------------------------------------------

-- Returns true if a server admin has suppressed this player's HUD.
function eye_spy.is_player_server_disabled(player_name)
    if not player_name or player_name == "" then return false end
    return eye_spy.storage:get_string("player_disabled:" .. player_name) == "true"
end

-- Sets or clears the server-level disable flag for a player.
function eye_spy.set_player_server_disabled(player_name, disabled)
    if not player_name or player_name == "" then return end
    eye_spy.storage:set_string(
        "player_disabled:" .. player_name,
        disabled and "true" or ""
    )
end

-- Returns true if the player has self-disabled their HUD via meta.
function eye_spy.is_player_self_disabled(player_name)
    local player = minetest.get_player_by_name(player_name)
    if not player then return false end
    return player:get_meta():get_string("es_hud_enabled") == "false"
end

------------------------------------------------------------
-- Player state management
------------------------------------------------------------

-- Returns the runtime state table for a player, creating it if absent.
function eye_spy.get_player_state(player)
    local player_name = player:get_player_name()
    local state       = eye_spy.state.players[player_name]

    if not state then
        state = {
            timer               = 0,
            edit_mode           = false,
            last_target_key     = nil,
            last_render_key     = nil,
            last_geom_key       = nil,
            last_probe_pos      = nil,
            last_probe_dir      = nil,
            cached_target       = nil,
            skip_static_acquire = false,
            hud_hidden_since_us = nil,
            last_recover_try_us = 0,
            hud_ids             = { lines = {} },
        }
        eye_spy.state.players[player_name] = state
    end

    return state
end

-- Clears all cached per-player data and the layout signature.
function eye_spy.invalidate_player(player)
    local player_name         = player:get_player_name()
    local state               = eye_spy.get_player_state(player)

    state.last_target_key     = nil
    state.last_render_key     = nil
    state.last_geom_key       = nil
    state.cached_target       = nil
    state.last_probe_pos      = nil
    state.last_probe_dir      = nil
    state.skip_static_acquire = false
    state.hud_hidden_since_us = nil
    state.last_recover_try_us = 0

    if eye_spy.render and eye_spy.render.invalidate_layout_sig then
        eye_spy.render.invalidate_layout_sig(player_name)
    end
end

------------------------------------------------------------
-- Edit mode
------------------------------------------------------------

function eye_spy.enter_edit_mode(player)
    if not player then return end

    local player_name = player:get_player_name()
    local state       = eye_spy.get_player_state(player)

    if not state.edit_mode then
        eye_spy.ensure_player_defaults(player)
        state.edit_mode                = true
        state.timer                    = 0
        eye_spy.edit_mode[player_name] = true

        if eye_spy.ui_drafts then
            eye_spy.ui_drafts[player_name] = nil
        end

        minetest.show_formspec(player_name, "eye_spy:ui", eye_spy.get_ui(player, { reopen = false }))
    end
end

function eye_spy.exit_edit_mode(player)
    if not player then return end

    local player_name = player:get_player_name()
    local state       = eye_spy.get_player_state(player)

    if state.edit_mode then
        local meta = player:get_meta()
        meta:set_string("es_last_obj", "")
        meta:set_int("es_last_health", -1)

        state.edit_mode                              = false
        state.last_render_key                        = nil
        state.timer                                  = 0

        eye_spy.edit_mode[player_name]               = false
        eye_spy.pending_preview_updates[player_name] = nil

        if eye_spy.ui_drafts then
            eye_spy.ui_drafts[player_name] = nil
        end

        minetest.close_formspec(player_name, "eye_spy:ui")
        minetest.close_formspec(player_name, "eye_spy:layout_ui")

        if eye_spy.render and eye_spy.render.hide then
            eye_spy.render.hide(state, player)
        end

        if eye_spy.render and eye_spy.render.invalidate_layout_sig then
            eye_spy.render.invalidate_layout_sig(player_name)
        end
    end
end

------------------------------------------------------------
-- Player defaults
------------------------------------------------------------

function eye_spy.ensure_player_defaults(player)
    local meta = player:get_meta()

    if meta:get_string("es_hud_color") == "" then
        meta:set_string("es_hud_color", "26, 26, 27")
    end

    if meta:get_string("es_hud_alignment") == "" then
        meta:set_string("es_hud_alignment", "Top-Middle")
    end

    if meta:get_string("es_hud_health_in") == "" then
        meta:set_string("es_hud_health_in", "Points")
    end

    if meta:get_string("es_auto_text_color") == "" then
        meta:set_string("es_auto_text_color", "true")
    end

    if meta:get_string("es_title_color_val") == "" then
        meta:set_int("es_title_color_val", 255)
    end

    if meta:get_string("es_subtitle_color_val") == "" then
        meta:set_int("es_subtitle_color_val", 255)
    end

    if meta:get_string("es_footer_color_val") == "" then
        meta:set_int("es_footer_color_val", 255)
    end

    if meta:get_string("es_line_color_val") == "" then
        meta:set_int("es_line_color_val", 255)
    end

    if meta:get_string("es_growth_color_val") == "" then
        meta:set_int("es_growth_color_val", 110)
    end

    if meta:get_string("es_soil_color_val") == "" then
        meta:set_int("es_soil_color_val", 165)
    end

    if meta:get_string("es_show_growth") == "" then
        meta:set_string("es_show_growth", eye_spy.config.show_growth and "true" or "false")
    end

    if meta:get_string("es_show_icons") == "" then
        meta:set_string("es_show_icons", eye_spy.config.show_icons and "true" or "false")
    end

    if meta:get_string("es_layout_target") == "" then
        meta:set_string("es_layout_target", "Global")
    end

    if meta:get_string("es_layout_step") == "" then
        meta:set_int("es_layout_step", 2)
    end

    if meta:get_string("es_layout_page") == "" then
        meta:set_string("es_layout_page", "Position")
    end

    if meta:get_string("es_footer_mode") == "" then
        meta:set_string("es_footer_mode", "compact")
    end

    if meta:get_string("es_show_coords") == "" then
        meta:set_string("es_show_coords", eye_spy.config.default_show_coords and "true" or "false")
    end

    if meta:get_string("es_show_light_level") == "" then
        meta:set_string("es_show_light_level", eye_spy.config.default_show_light_level and "true" or "false")
    end

    if meta:get_string("es_show_spawn_hint") == "" then
        meta:set_string("es_show_spawn_hint", eye_spy.config.default_show_spawn_hint and "true" or "false")
    end

    if meta:get_string("es_show_liquid_info") == "" then
        meta:set_string("es_show_liquid_info", eye_spy.config.default_show_liquid_info and "true" or "false")
    end

    if meta:get_string("es_show_dig_time") == "" then
        meta:set_string("es_show_dig_time", eye_spy.config.default_show_dig_time and "true" or "false")
    end

    if meta:get_string("es_spawn_safe_light_threshold") == "" then
        meta:set_int("es_spawn_safe_light_threshold", 8)
    end

    -- Initialise hud-enabled flag so the disable check has a reliable baseline.
    if meta:get_string("es_hud_enabled") == "" then
        meta:set_string("es_hud_enabled", "true")
    end

    eye_spy.apply_player_interval(player)

    local int_defaults = {
        es_global_offset_x    = 0,
        es_global_offset_y    = 0,
        es_bg_offset_x        = 0,
        es_bg_offset_y        = 0,
        es_icon_offset_x      = 0,
        es_icon_offset_y      = 0,
        es_title_offset_x     = 0,
        es_title_offset_y     = 0,
        es_subtitle_offset_x  = 0,
        es_subtitle_offset_y  = 0,
        es_lines_offset_x     = 0,
        es_lines_offset_y     = 0,
        es_footer_offset_x    = 0,
        es_footer_offset_y    = 0,
        es_bg_pad_left        = 7,
        es_bg_pad_right       = 0,
        es_bg_pad_top         = 5,
        es_bg_pad_bottom      = 0,
        es_bg_extra_w         = 0,
        es_bg_extra_h         = 0,
        es_bg_scale_x_pct     = 100,
        es_bg_scale_y_pct     = 100,
        es_icon_size          = 56,
        es_title_scale_pct    = 100,
        es_subtitle_scale_pct = 100,
        es_line_scale_pct     = 100,
        es_footer_scale_pct   = 100,
        es_first_line_y_adj   = 0,
        es_line_step_adj      = -2, -- matches LAYOUT_META_DEFAULTS in ui.lua
        es_footer_nudge_adj   = 0,
        es_text_base_x_adj    = 0,
        es_icon_base_x_adj    = 0,
        es_top_margin_adj     = 0,
        es_bottom_margin_adj  = 0,
    }

    for key, value in pairs(int_defaults) do
        if meta:get_string(key) == "" then
            meta:set_int(key, value)
        end
    end
end

------------------------------------------------------------
-- Core update pipeline
------------------------------------------------------------

local function probe_state_matches(state, player)
    if not state.last_probe_pos or not state.last_probe_dir then
        return false
    end

    local pos = player:get_pos()
    local dir = player:get_look_dir()
    local dx  = math.abs((pos.x or 0) - (state.last_probe_pos.x or 0))
    local dy  = math.abs((pos.y or 0) - (state.last_probe_pos.y or 0))
    local dz  = math.abs((pos.z or 0) - (state.last_probe_pos.z or 0))
    local ddx = math.abs((dir.x or 0) - (state.last_probe_dir.x or 0))
    local ddy = math.abs((dir.y or 0) - (state.last_probe_dir.y or 0))
    local ddz = math.abs((dir.z or 0) - (state.last_probe_dir.z or 0))

    return dx < 0.05 and dy < 0.05 and dz < 0.05
        and ddx < 0.01 and ddy < 0.01 and ddz < 0.01
end

local function remember_probe_state(state, player, target)
    local pos            = player:get_pos()
    local dir            = player:get_look_dir()
    state.last_probe_pos = vector.new(pos)
    state.last_probe_dir = vector.new(dir)
    state.cached_target  = target
end

function eye_spy.update_player(player, opts)
    if not player or not eye_spy.target or not eye_spy.render then
        return
    end

    local perf_on         = eye_spy.perf.enabled and minetest.get_us_time
    local update_start_us = perf_on and minetest.get_us_time() or 0
    local options         = opts or {}
    local state           = eye_spy.get_player_state(player)
    local target

    if not options.force
        and not options.preview
        and state.cached_target
        and probe_state_matches(state, player)
        and state.skip_static_acquire
    then
        target = state.cached_target
        state.skip_static_acquire = false
    else
        local acquire_start_us = perf_on and minetest.get_us_time() or 0
        target = eye_spy.target.acquire(player, options)
        if perf_on then
            eye_spy.perf_record("target_acquire", minetest.get_us_time() - acquire_start_us)
        end

        if not options.preview then
            remember_probe_state(state, player, target)
            state.skip_static_acquire = target and target.kind ~= "air"
        end
    end

    if not target or target.kind == "air" then
        local now_us = minetest.get_us_time and minetest.get_us_time() or 0

        eye_spy.render.hide(state, player)
        state.last_target_key     = nil
        state.last_render_key     = nil
        state.cached_target       = nil
        state.skip_static_acquire = false

        if now_us > 0 and not state.hud_hidden_since_us then
            state.hud_hidden_since_us = now_us
        end

        if perf_on then
            eye_spy.perf_record("update_player_total", minetest.get_us_time() - update_start_us)
        end
        return
    end

    local build_start_us = perf_on and minetest.get_us_time() or 0
    local view_model     = eye_spy.render.build_view_model(player, target, options)
    if perf_on then
        eye_spy.perf_record("build_view_model", minetest.get_us_time() - build_start_us)
    end

    if not options.force and view_model.key == state.last_render_key then
        state.last_target_key = target.key
        eye_spy.perf_inc_counter("render_skip_same_key")
        if perf_on then
            eye_spy.perf_record("update_player_total", minetest.get_us_time() - update_start_us)
        end
        return
    end

    local render_start_us = perf_on and minetest.get_us_time() or 0
    eye_spy.render.apply(state, player, view_model)
    if perf_on then
        eye_spy.perf_record("render_apply", minetest.get_us_time() - render_start_us)
    end

    state.last_target_key     = target.key
    state.last_render_key     = view_model.key
    state.hud_hidden_since_us = nil
    state.last_recover_try_us = 0

    if perf_on then
        eye_spy.perf_record("update_player_total", minetest.get_us_time() - update_start_us)
    end
end

-- Thin wrapper used by the UI and preview system.
function eye_spy.get_hud(player, data)
    eye_spy.update_player(player, data or {})
end

------------------------------------------------------------
-- Main step function
------------------------------------------------------------

function eye_spy.step(dtime)
    local perf_on       = eye_spy.perf.enabled and minetest.get_us_time
    local step_start_us = perf_on and minetest.get_us_time() or 0
    local now_us        = minetest.get_us_time and minetest.get_us_time() or 0

    for _, player in ipairs(minetest.get_connected_players()) do
        local state           = eye_spy.get_player_state(player)
        local player_name     = player:get_player_name()
        local pending_preview = eye_spy.pending_preview_updates[player_name]

        -- Service pending edit-mode preview updates.
        if state.edit_mode and pending_preview then
            local due_at = pending_preview.due_at_us or 0

            if pending_preview.force or due_at <= now_us then
                eye_spy.pending_preview_updates[player_name] = nil
                eye_spy.update_player(player, {
                    preview      = true,
                    preview_type = pending_preview.preview_type,
                    force        = pending_preview.force == true,
                })
            end
        end

        -- Service pending layout-UI refreshes.
        local pending_layout_refresh = eye_spy.pending_layout_refreshes[player_name]
        if state.edit_mode
            and pending_layout_refresh
            and pending_layout_refresh.due_at_us <= now_us
        then
            eye_spy.pending_layout_refreshes[player_name] = nil
            minetest.show_formspec(player_name, "eye_spy:layout_ui", eye_spy.get_layout_ui(player))
        end

        if not state.edit_mode then
            local meta = player:get_meta()

            -- Check both server-admin and player-self disable flags.
            local hud_disabled = eye_spy.is_player_server_disabled(player_name)
                or (meta:get_string("es_hud_enabled") == "false")

            if hud_disabled then
                if state.last_render_key then
                    eye_spy.render.hide(state, player)
                    state.last_target_key     = nil
                    state.last_render_key     = nil
                    state.cached_target       = nil
                    state.skip_static_acquire = false
                end
                state.timer = 0
                goto continue_player
            end

            local interval_ms = meta:get_int("es_update_interval_ms")
            local interval    = eye_spy.get_server_default_interval_ms() / 1000

            if interval_ms > 0 then
                interval = interval_ms / 1000
            end

            interval    = math.max(0.05, math.min(5, interval))
            state.timer = state.timer + math.min(dtime, interval)

            if state.timer >= interval then
                state.timer = 0
                eye_spy.update_player(player, { preview = false })
            end

            -- Focus-loss / self-heal: if the HUD appears stuck hidden while we still
            -- have a valid cached target, force an occasional refresh attempt.
            if state.hud_hidden_since_us
                and state.cached_target
                and state.cached_target.kind ~= "air"
            then
                local hidden_for_us       = now_us - state.hud_hidden_since_us
                local recover_cooldown_us = 900000

                if hidden_for_us >= 1200000
                    and (state.last_recover_try_us or 0) + recover_cooldown_us <= now_us
                then
                    state.last_recover_try_us = now_us
                    eye_spy.perf_inc_counter("hud_recover_forced_refresh")
                    eye_spy.update_player(player, { preview = false, force = true })
                end
            end
        end

        ::continue_player::
    end

    if perf_on then
        eye_spy.perf_record("step_total", minetest.get_us_time() - step_start_us)
    end
end

------------------------------------------------------------
-- HUD cleanup
------------------------------------------------------------

function eye_spy.remove_huds(player)
    if eye_spy.render then eye_spy.render.remove(player) end
end
