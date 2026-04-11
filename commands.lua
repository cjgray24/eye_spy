--commands

local S = minetest.get_translator(minetest.get_current_modname())

-- ---------------------------------------------------------------------------
-- Privileges
-- ---------------------------------------------------------------------------

minetest.register_privilege("eye_spy_rate", {
    description = "Manage Eye Spy HUD refresh rates",
    give_to_singleplayer = true,
})

minetest.register_privilege("eye_spy_admin", {
    description = "Manage Eye Spy HUD visibility per player (server-side override).",
    give_to_singleplayer = true,
})

-- ---------------------------------------------------------------------------
-- Helper: clamp an interval value to the permitted range (mirrors functions.lua)
-- ---------------------------------------------------------------------------

local function clamp_ms(value)
    return math.max(50, math.min(5000, tonumber(value) or 250))
end

-- ---------------------------------------------------------------------------
-- /eye_spy_settings — open the settings UI (no priv required, player-only)
-- ---------------------------------------------------------------------------

minetest.register_chatcommand("eye_spy_settings", {
    description = S("Open Eye Spy settings and live preview editor."),
    func = function(name, _param)
        local player = minetest.get_player_by_name(name)

        if not player then
            return false, S("This command can only be used by a player.")
        end

        eye_spy.enter_edit_mode(player)
        return true, ""
    end,
})

-- ---------------------------------------------------------------------------
-- /eye_spy_rate — view/set refresh rate defaults and per-player overrides
-- ---------------------------------------------------------------------------

minetest.register_chatcommand("eye_spy_rate", {
    params = "show | default <ms> | player <name> <ms|default>",
    description = S("Admin: view/set Eye Spy refresh rate defaults and optional per-player overrides"),
    privs = { eye_spy_rate = true },
    func = function(name, param)
        -- Parse
        local args = {}
        for token in (param or ""):gmatch("%S+") do
            args[#args + 1] = token
        end

        local action = args[1]

        -- show (default)
        if not action or action == "" or action == "show" then
            local server_default = eye_spy.get_server_default_interval_ms()
            local self_effective = eye_spy.get_effective_interval_ms(name)
            return true, string.format(
                "Eye Spy rate: server default=%dms, your effective=%dms",
                server_default,
                self_effective
            )
        end

        -- default <ms>
        if action == "default" then
            local ms = tonumber(args[2])

            if not ms then
                return false, "Usage: /eye_spy_rate default <ms>"
            end

            local clamped = clamp_ms(ms)
            eye_spy.set_server_default_interval_ms(clamped)

            -- Apply to all online players that have no personal override
            for _, player in ipairs(minetest.get_connected_players()) do
                local player_name = player:get_player_name()

                if not eye_spy.get_player_interval_override_ms(player_name) then
                    eye_spy.apply_player_interval(player)
                end
            end

            return true, string.format("Eye Spy server default refresh set to %dms", clamped)
        end

        -- player <name> <ms|default>
        if action == "player" then
            local target_name = args[2]
            local value       = args[3]

            if not target_name or not value then
                return false, "Usage: /eye_spy_rate player <name> <ms|default>"
            end

            if value == "default" then
                eye_spy.set_player_interval_override_ms(target_name, nil)
            else
                local ms = tonumber(value)

                if not ms then
                    return false, "Usage: /eye_spy_rate player <name> <ms|default>"
                end

                eye_spy.set_player_interval_override_ms(target_name, clamp_ms(ms))
            end

            local target_player = minetest.get_player_by_name(target_name)

            if target_player then
                eye_spy.apply_player_interval(target_player)
            end

            return true, string.format(
                "Eye Spy rate for %s is now %dms",
                target_name,
                eye_spy.get_effective_interval_ms(target_name)
            )
        end

        return false, "Usage: /eye_spy_rate show | default <ms> | player <name> <ms|default>"
    end,
})

-- ---------------------------------------------------------------------------
-- /eye_spy_perf — show/reset perf stats and enable/disable metrics collection
-- ---------------------------------------------------------------------------

minetest.register_chatcommand("eye_spy_perf", {
    params = "show | reset | on | off",
    description = S("Admin: show/reset Eye Spy perf stats and enable/disable metrics"),
    privs = { eye_spy_rate = true },
    func = function(_name, param)
        -- Parse
        local action = (param or ""):match("^%s*(%S+)") or "show"

        if action == "show" then
            return true, eye_spy.perf_report()
        end

        if action == "reset" then
            eye_spy.perf_reset()
            return true, "Eye Spy perf stats reset"
        end

        if action == "on" then
            eye_spy.perf_set_enabled(true)
            return true, "Eye Spy perf metrics enabled"
        end

        if action == "off" then
            eye_spy.perf_set_enabled(false)
            return true, "Eye Spy perf metrics disabled"
        end

        return false, "Usage: /eye_spy_perf show | reset | on | off"
    end,
})

-- ---------------------------------------------------------------------------
-- /eye_spy_toggle — player toggles their own HUD on/off (player-only)
-- ---------------------------------------------------------------------------

minetest.register_chatcommand("eye_spy_toggle", {
    description = S("Toggle your Eye Spy HUD on or off."),
    func = function(name, _param)
        -- Validate: must be an in-game player
        local player = minetest.get_player_by_name(name)

        if not player then
            return false, S("This command can only be used by a player.")
        end

        local meta    = player:get_meta()
        local enabled = meta:get_string("es_hud_enabled") ~= "false"

        if enabled then
            -- Toggling OFF
            meta:set_string("es_hud_enabled", "false")

            local state = eye_spy.get_player_state(player)
            eye_spy.render.hide(state, player)
            state.last_render_key = nil
            state.cached_target   = nil

            return true, S("Eye Spy HUD disabled.")
        else
            -- Toggling ON — save preference regardless of admin block
            meta:set_string("es_hud_enabled", "true")

            -- Check whether an admin has blocked this player
            local admin_disabled =
                eye_spy.storage:get_string("player_disabled:" .. name) == "true"

            if admin_disabled then
                return true, S(
                    "HUD preference set to enabled, but Eye Spy is currently disabled for you by the server admin."
                )
            end

            -- No admin block — HUD will show on the next step() tick
            return true, S("Eye Spy HUD enabled.")
        end
    end,
})

-- ---------------------------------------------------------------------------
-- /eye_spy_status — shows the player their current HUD status (player-only)
-- ---------------------------------------------------------------------------

minetest.register_chatcommand("eye_spy_status", {
    description = S("Show your current Eye Spy HUD status."),
    func = function(name, _param)
        -- Validate: must be an in-game player
        local player = minetest.get_player_by_name(name)

        if not player then
            return false, S("This command can only be used by a player.")
        end

        local meta           = player:get_meta()
        local self_disabled  = meta:get_string("es_hud_enabled") == "false"
        local admin_disabled = eye_spy.storage:get_string("player_disabled:" .. name) == "true"
        local interval_ms    = eye_spy.get_effective_interval_ms(name)

        local status_line

        if not self_disabled and not admin_disabled then
            status_line = S("Eye Spy HUD: active")
        elseif self_disabled and admin_disabled then
            status_line = S("Eye Spy HUD: disabled by you and by the server admin")
        elseif self_disabled then
            status_line = S("Eye Spy HUD: disabled by you — use /eye_spy_toggle to re-enable")
        else
            -- admin_disabled only
            status_line = S("Eye Spy HUD: disabled by the server admin")
        end

        return true, string.format("%s\n%s", status_line,
            string.format(S("Update rate: %dms"), interval_ms))
    end,
})

-- ---------------------------------------------------------------------------
-- /eye_spy_admin — server-side per-player HUD suppression (eye_spy_admin priv)
-- ---------------------------------------------------------------------------

minetest.register_chatcommand("eye_spy_admin", {
    params = "enable <player> | disable <player> | show [player]",
    description = S("Manage Eye Spy HUD visibility per player (server-side override)."),
    privs = { eye_spy_admin = true },
    func = function(caller, param)
        -- Parse
        local args = {}
        for token in (param or ""):gmatch("%S+") do
            args[#args + 1] = token
        end

        local action      = args[1]
        local target_name = args[2]

        -- -----------------------------------------------------------------------
        -- disable <player>
        -- -----------------------------------------------------------------------
        if action == "disable" then
            if not target_name or target_name == "" then
                return false, "Usage: /eye_spy_admin disable <player>"
            end

            -- Execute
            eye_spy.storage:set_string("player_disabled:" .. target_name, "true")

            minetest.log("action", string.format(
                "[eye_spy] %s disabled Eye Spy HUD for player %s",
                caller, target_name
            ))

            local target_player = minetest.get_player_by_name(target_name)

            if target_player then
                -- Immediately hide the HUD
                local state = eye_spy.get_player_state(target_player)
                eye_spy.render.hide(state, target_player)
                state.last_render_key = nil
                state.cached_target   = nil

                minetest.chat_send_player(
                    target_name,
                    S("Eye Spy has been disabled for you by an administrator.")
                )
            end

            return true, string.format(
                "Eye Spy disabled for %s.", target_name
            )
        end

        -- -----------------------------------------------------------------------
        -- enable <player>
        -- -----------------------------------------------------------------------
        if action == "enable" then
            if not target_name or target_name == "" then
                return false, "Usage: /eye_spy_admin enable <player>"
            end

            -- Execute: clear the admin-disable flag
            eye_spy.storage:set_string("player_disabled:" .. target_name, "")

            minetest.log("action", string.format(
                "[eye_spy] %s re-enabled Eye Spy HUD for player %s",
                caller, target_name
            ))

            local target_player = minetest.get_player_by_name(target_name)

            if target_player then
                -- Let the HUD re-evaluate itself on the next step() tick
                eye_spy.invalidate_player(target_player)

                minetest.chat_send_player(
                    target_name,
                    S("Eye Spy has been re-enabled for you.")
                )
            end

            return true, string.format(
                "Eye Spy re-enabled for %s.", target_name
            )
        end

        -- -----------------------------------------------------------------------
        -- show [player]
        -- -----------------------------------------------------------------------
        if not action or action == "" or action == "show" then
            if target_name and target_name ~= "" then
                -- Status for a specific player (may be offline)
                local admin_disabled = eye_spy.storage:get_string(
                    "player_disabled:" .. target_name
                ) == "true"

                local self_disabled  = false
                local online_note    = "(offline — self-disable state unknown)"
                local target_player  = minetest.get_player_by_name(target_name)

                if target_player then
                    local meta    = target_player:get_meta()
                    self_disabled = meta:get_string("es_hud_enabled") == "false"
                    online_note   = "(online)"
                end

                return true, string.format(
                    "Eye Spy status for %s %s:\n  admin-disabled: %s\n  self-disabled:  %s",
                    target_name,
                    online_note,
                    admin_disabled and "yes" or "no",
                    target_player and (self_disabled and "yes" or "no") or "unknown"
                )
            end

            -- No specific player — list all online players
            local lines = { "Eye Spy status for online players:" }

            for _, player in ipairs(minetest.get_connected_players()) do
                local pname          = player:get_player_name()
                local meta           = player:get_meta()
                local admin_disabled = eye_spy.storage:get_string(
                    "player_disabled:" .. pname
                ) == "true"
                local self_disabled  = meta:get_string("es_hud_enabled") == "false"

                local tag
                if admin_disabled and self_disabled then
                    tag = "disabled (admin + self)"
                elseif admin_disabled then
                    tag = "disabled (admin)"
                elseif self_disabled then
                    tag = "disabled (self)"
                else
                    tag = "active"
                end

                lines[#lines + 1] = string.format("  %s — %s", pname, tag)
            end

            if #lines == 1 then
                lines[#lines + 1] = "  (no players online)"
            end

            return true, table.concat(lines, "\n")
        end

        return false, "Usage: /eye_spy_admin enable <player> | disable <player> | show [player]"
    end,
})
