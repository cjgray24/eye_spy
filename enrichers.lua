local S = eye_spy.S

eye_spy.enrichers = {
    registry = {},
}

local node_tool_state_by_player = {}

-- Called by init.lua's on_leaveplayer handler to free per-player cached state.
function eye_spy.enrichers.on_player_leave(player_name)
    node_tool_state_by_player[player_name] = nil
end

local function add_line(view_model, id, text, color)
    view_model.lines[#view_model.lines + 1] = {
        id = id,
        text = text,
        color = color,
    }
end

local function meta_bool(meta, key, default_value)
    local raw = meta:get_string(key)

    if raw == "" then
        return default_value == true
    end

    return raw ~= "false"
end

local function growth_bar(percent)
    local slots = 10
    local p = math.max(0, math.min(100, percent or 0))
    local filled = math.floor((p / 100) * slots + 0.5)

    return "[" .. string.rep("|", filled) .. string.rep(" ", slots - filled) .. "] " .. p .. "%"
end

local function liquid_name_from_node(name)
    if not name or name == "" then
        return S("Unknown")
    end

    if name:find("water", 1, true) then
        return S("Water")
    end

    if name:find("lava", 1, true) then
        return S("Lava")
    end

    return eye_spy.readable_name_from_id(name) or S("Unknown")
end

local ETHEREAL_SAPLING_SOILS = {
    ["ethereal:basandra_bush_sapling"] = "ethereal:fiery_dirt",
    ["ethereal:yellow_tree_sapling"] = "group:soil",
    ["ethereal:big_tree_sapling"] = "default:dirt_with_grass",
    ["ethereal:banana_tree_sapling"] = "ethereal:grove_dirt",
    ["ethereal:frost_tree_sapling"] = "ethereal:crystal_dirt",
    ["ethereal:mushroom_sapling"] = "ethereal:mushroom_dirt",
    ["ethereal:mushroom_brown_sapling"] = "ethereal:mushroom_dirt",
    ["ethereal:palm_sapling"] = "default:sand",
    ["ethereal:willow_sapling"] = "ethereal:gray_dirt",
    ["ethereal:redwood_sapling"] = "default:dirt_with_dry_grass",
    ["ethereal:giant_redwood_sapling"] = "default:dirt_with_dry_grass",
    ["ethereal:orange_tree_sapling"] = "ethereal:prairie_dirt",
    ["ethereal:birch_sapling"] = "default:dirt_with_grass",
    ["ethereal:sakura_sapling"] = "ethereal:bamboo_dirt",
    ["ethereal:olive_tree_sapling"] = "ethereal:grove_dirt",
    ["ethereal:lemon_tree_sapling"] = "ethereal:grove_dirt",
}

local function get_current_dig_result(player, nodename)
    if not player or not nodename or nodename == "" then
        return false, nil
    end

    local wielded = player:get_wielded_item()
    local can_dig, dig_time = eye_spy.tool_can_dig_node(wielded, nodename)

    if can_dig then
        return true, dig_time
    end

    local hand_can_dig, hand_dig_time = eye_spy.tool_can_dig_node(ItemStack(""), nodename)

    if hand_can_dig then
        return true, hand_dig_time
    end

    return false, nil
end

local function get_below_node(pos)
    if not pos then
        return nil, nil
    end

    local below_pos = { x = pos.x, y = pos.y - 1, z = pos.z }
    local below = minetest.get_node_or_nil(below_pos)

    if not below then
        return nil, nil
    end

    return below, minetest.registered_nodes[below.name]
end

local function is_water_node(node, def)
    local name = node and node.name or ""

    if name == "" then
        return false
    end

    if name:find("water", 1, true) then
        return true
    end

    local source_name = def and def.liquid_alternative_source or ""
    local flowing_name = def and def.liquid_alternative_flowing or ""

    return source_name:find("water", 1, true) ~= nil or flowing_name:find("water", 1, true) ~= nil
end

local function has_nearby_water(pos, radius)
    if not pos then
        return false
    end

    local scan_radius = math.max(1, tonumber(radius) or 3)

    for dx = -scan_radius, scan_radius do
        for dz = -scan_radius, scan_radius do
            for dy = -1, 1 do
                if dx ~= 0 or dy ~= 0 or dz ~= 0 then
                    local neighbor = minetest.get_node_or_nil({
                        x = pos.x + dx,
                        y = pos.y + dy,
                        z = pos.z + dz,
                    })

                    if neighbor then
                        local neighbor_def = minetest.registered_nodes[neighbor.name]

                        if is_water_node(neighbor, neighbor_def) then
                            return true
                        end
                    end
                end
            end
        end
    end

    return false
end

local function is_soil_wet(soil_pos, soil_group)
    if (tonumber(soil_group) or 0) >= 3 then
        return true
    end

    return has_nearby_water(soil_pos, 3)
end

local function get_node_label(name)
    if not name or name == "" then
        return S("Unknown")
    end

    if name:sub(1, 6) == "group:" then
        local group_name = name:sub(7)

        if group_name == "soil" then
            return S("Soil")
        end

        return group_name
    end

    local def = minetest.registered_nodes[name]
    local desc = def and def.description

    if desc and desc ~= "" then
        return desc:match("^[^\n]*") or desc
    end

    return name
end

local function get_soil_state(pos)
    local below, below_def = get_below_node(pos)
    local soil_group = below and minetest.get_item_group(below.name, "soil") or 0
    local below_pos = pos and { x = pos.x, y = pos.y - 1, z = pos.z } or nil
    local is_wet = soil_group > 0 and is_soil_wet(below_pos, soil_group)

    return {
        node = below,
        def = below_def,
        soil_group = soil_group,
        is_soil = soil_group > 0,
        is_wet = is_wet,
    }
end

local function get_target_soil_state(target)
    local soil_group = minetest.get_item_group(target.name or "", "soil")

    if soil_group <= 0 then
        return nil
    end

    return {
        node = {
            name = target.name,
            param1 = target.node and target.node.param1 or 0,
            param2 = target.node and target.node.param2 or 0,
        },
        def = target.def,
        soil_group = soil_group,
        is_soil = true,
        is_wet = is_soil_wet(target.pos, soil_group),
    }
end

local function infer_max_stage(base_name, current_stage)
    local max_stage = current_stage or 0

    for stage = max_stage + 1, 16 do
        if minetest.registered_nodes[base_name .. "_" .. stage] then
            max_stage = stage
        else
            break
        end
    end

    if max_stage > 0 then
        return max_stage
    end
end

local function get_registered_crop_info(base_name)
    if farming and farming.registered_plants and farming.registered_plants[base_name] then
        local plant = farming.registered_plants[base_name]

        return {
            system = "farming",
            steps = plant.steps,
            minlight = plant.minlight or (farming and farming.min_light) or 12,
            maxlight = plant.maxlight or (farming and farming.max_light) or 15,
        }
    end

    if x_farming and x_farming.registered_plants then
        local short_name = base_name:match(":(.+)$")
        local plant = short_name and x_farming.registered_plants[short_name]

        if plant then
            return {
                system = "x_farming",
                steps = plant.steps,
                minlight = plant.minlight or 13,
                maxlight = plant.maxlight or 14,
                fertility = plant.fertility,
            }
        end
    end
end

local function soil_matches_fertility(soil_state, fertility)
    if not fertility or #fertility == 0 then
        return true
    end

    local below_def = soil_state.def
    local groups = below_def and below_def.groups or nil

    if not groups then
        return false
    end

    for _, group_name in ipairs(fertility) do
        if groups[group_name] and groups[group_name] > 0 then
            return true
        end
    end

    return false
end

local function get_growth_light(pos)
    if not pos then
        return nil
    end

    return minetest.get_node_light(pos)
end

local function get_growth_info(target)
    local def = target.def
    local groups = def and def.groups or {}

    if groups.sapling then
        local meta = minetest.get_meta(target.pos)

        return {
            kind = "sapling",
            age = meta and meta:get_int("age") or 0,
            groups = groups,
        }
    end

    local stage_suffix = target.name:match("_(%d+)$")
    local base_name = stage_suffix and target.name:gsub("_(%d+)$", "", 1) or nil
    local plant = base_name and get_registered_crop_info(base_name) or nil

    if not stage_suffix or not (groups.plant or groups.crop or groups.growing or plant) then
        return nil
    end

    local stage = tonumber(stage_suffix) or 0
    plant = plant or {}
    local max_stage = plant.steps or infer_max_stage(base_name, stage)

    if not max_stage or max_stage <= 0 then
        return nil
    end

    return {
        kind = "crop",
        system = plant.system or "generic",
        stage = stage,
        max_stage = max_stage,
        minlight = plant.minlight or def.minlight,
        maxlight = plant.maxlight or def.maxlight,
        fertility = plant.fertility,
    }
end

local function get_sapling_soil_requirement(target)
    local requirement = ETHEREAL_SAPLING_SOILS[target.name]

    if requirement then
        return requirement
    end

    return "group:soil"
end

local function soil_matches_requirement(soil_state, requirement)
    if not requirement or requirement == "" then
        return true
    end

    if requirement:sub(1, 6) == "group:" then
        return minetest.get_item_group(soil_state.node and soil_state.node.name or "", requirement:sub(7)) > 0
    end

    return soil_state.node and soil_state.node.name == requirement or false
end

local function get_crop_conditions(target, growth_info)
    local soil_state = get_soil_state(target.pos)
    local light = target.light_level

    if light == nil then
        light = get_growth_light(target.pos)
    end

    local minlight = growth_info.minlight
    local maxlight = growth_info.maxlight
    local fertility_ok = soil_matches_fertility(soil_state, growth_info.fertility)
    local soil_ok = soil_state.is_wet and fertility_ok
    local light_ok = true

    if minlight and light and light < minlight then
        light_ok = false
    end

    if maxlight and light and light > maxlight then
        light_ok = false
    end

    if light == nil and (minlight or maxlight) then
        light_ok = false
    end

    return {
        soil = soil_state,
        light = light,
        soil_ok = soil_ok,
        light_ok = light_ok,
        fertility_ok = fertility_ok,
    }
end

local function get_soil_line(target, growth_info)
    local soil_state = get_soil_state(target.pos)
    local target_groups = target.def and target.def.groups or {}

    if growth_info and growth_info.kind == "crop" then
        local suitable = soil_state.is_soil and soil_matches_fertility(soil_state, growth_info.fertility)
        local moisture_label

        if soil_state.is_wet then
            moisture_label = S("Wet")
        elseif soil_state.is_soil then
            moisture_label = S("Dry")
        else
            moisture_label = S("No Soil")
        end

        local color

        if suitable and soil_state.is_wet then
            color = 0x6BD66B
        elseif suitable then
            color = 0xFFAA55
        else
            color = 0xE56363
        end

        return {
            text = S("Soil") .. ": " .. moisture_label .. " | " .. (suitable and S("Suitable") or S("Unsuitable")),
            color = color,
        }
    end

    if growth_info and growth_info.kind == "sapling" then
        local requirement = get_sapling_soil_requirement(target)
        local suitable = soil_matches_requirement(soil_state, requirement)

        return {
            text = S("Soil") ..
            ": " .. get_node_label(requirement) .. " | " .. (suitable and S("Suitable") or S("Unsuitable")),
            color = suitable and 0x6BD66B or 0xE56363,
        }
    end

    if target_groups.flora or target_groups.attached_node then
        return nil
    end

    local target_soil_state = get_target_soil_state(target)

    if target_soil_state then
        return {
            text = S("Soil") .. ": " .. (target_soil_state.is_wet and S("Wet") or S("Dry")),
            color = target_soil_state.is_wet and 0x5555FF or 0xFFAA55,
        }
    end
end

function eye_spy.enrichers.register(id, spec)
    eye_spy.enrichers.registry[#eye_spy.enrichers.registry + 1] = {
        id = id,
        enabled = spec.enabled,
        apply = spec.apply,
    }
end

local function ensure_shared_context(context, target)
    local shared = context.shared

    if shared and shared._target_key == (target.key or target.name) then
        return shared
    end

    shared = {
        _target_key = target.key or target.name,
        dig_cached = false,
        growth_cached = false,
        conditions_cached = false,
        soil_line_cached = false,
    }

    function shared:get_dig_result()
        if not self.dig_cached then
            self.dig_cached = true
            self.can_dig, self.dig_time = get_current_dig_result(context.player, target.name)
        end

        return self.can_dig, self.dig_time
    end

    function shared:get_growth_info()
        if not self.growth_cached then
            self.growth_cached = true
            self.growth_info = get_growth_info(target)
        end

        return self.growth_info
    end

    function shared:get_crop_conditions()
        if not self.conditions_cached then
            self.conditions_cached = true
            local growth_info = self:get_growth_info()

            if growth_info and growth_info.kind == "crop" then
                self.crop_conditions = get_crop_conditions(target, growth_info)
            else
                self.crop_conditions = nil
            end
        end

        return self.crop_conditions
    end

    function shared:get_soil_line()
        if not self.soil_line_cached then
            self.soil_line_cached = true
            self.soil_line = get_soil_line(target, self:get_growth_info())
        end

        return self.soil_line
    end

    context.shared = shared
    return shared
end

local function get_cached_node_tool(context, target)
    local player = context and context.player

    if not player then
        return nil
    end

    local shared = ensure_shared_context(context, target)
    local player_name = player:get_player_name()
    local wielded = player:get_wielded_item()
    local wield_name = wielded:get_name() or ""
    local target_key = target.key or target.name or ""
    local cached = node_tool_state_by_player[player_name]

    if cached and cached.target_key == target_key and cached.wield_name == wield_name then
        return cached.tool
    end

    local can_dig = shared:get_dig_result()
    local tool_type_hint, matches_tool_type = nil, false

    if eye_spy.get_node_tool_hint_and_match then
        tool_type_hint, matches_tool_type = eye_spy.get_node_tool_hint_and_match(target.name, wielded)
    end

    local label = tool_type_hint or S("Unknown")
    local color

    if can_dig then
        color = 0x6BD66B
    elseif matches_tool_type then
        color = 0xFFAA55
    else
        color = 0xE56363
    end

    local tool = {
        description = label,
        color = color,
    }

    node_tool_state_by_player[player_name] = {
        target_key = target_key,
        wield_name = wield_name,
        tool = tool,
    }

    return tool
end

function eye_spy.enrichers.run(context, target, view_model)
    ensure_shared_context(context, target)

    for _, enricher in ipairs(eye_spy.enrichers.registry) do
        if not enricher.enabled or enricher.enabled(context, target, view_model) then
            local perf_on = eye_spy.perf and eye_spy.perf.enabled and minetest.get_us_time
            local start_us = perf_on and minetest.get_us_time() or 0

            local ok, err = pcall(enricher.apply, context, target, view_model)
            if not ok then
                minetest.log("error", "[eye_spy] enricher '" .. (enricher.id or "?") ..
                    "' error: " .. tostring(err))
            end

            if perf_on then
                eye_spy.perf_record("enricher_" .. (enricher.id or "unknown"), minetest.get_us_time() - start_us)
            end
        end
    end
end

eye_spy.enrichers.register("node_tool", {
    enabled = function(_, target)
        return target.kind == "node"
    end,
    apply = function(context, target, view_model)
        local tool = get_cached_node_tool(context, target) or {
            description = S("Unknown"),
            color = 0xEBB344,
        }

        view_model.subtitle = tool.description ~= "" and tool.description or S("Unknown")
        view_model.subtitle_color = tool.color or 0xEBB344
    end,
})

eye_spy.enrichers.register("entity_health", {
    enabled = function(_, target)
        return target.kind == "entity"
    end,
    apply = function(context, target, view_model)
        if context.meta:get_string("es_hud_health_in") == "Hearts" then
            view_model.subtitle = S("Health") ..
            ": " ..
            (eye_spy.round1((target.hp or 0) / 2) or S("Unknown")) ..
            "♥/" .. (eye_spy.round1((target.max_hp or 0) / 2) or S("Unknown")) .. "♥"
        else
            view_model.subtitle = S("Health") ..
            ": " .. (eye_spy.round1(target.hp) or S("Unknown")) .. "/" .. (eye_spy.round1(target.max_hp) or S("Unknown"))
        end

        view_model.subtitle_color = 0xFF4040
    end,
})

eye_spy.enrichers.register("item_details", {
    enabled = function(_, target)
        return target.kind == "item"
    end,
    apply = function(_, target, view_model)
        local count = tonumber(target.stack_count) or 1

        if count > 1 then
            add_line(view_model, "item_count", S("Count") .. ": " .. tostring(count), 0xE8D37A)
        end

        local wear = tonumber(target.stack_wear) or 0

        if wear > 0 then
            local remain_pct = math.floor(math.max(0, 1 - (wear / 65535)) * 100 + 0.5)
            local wear_color = 0xE56363

            if remain_pct >= 60 then
                wear_color = 0x6BD66B
            elseif remain_pct >= 30 then
                wear_color = 0xF0B35E
            end

            add_line(view_model, "item_wear", S("Durability") .. ": " .. tostring(remain_pct) .. "%", wear_color)
        end

        if target.item_def_description and target.item_def_description ~= "" then
            local lines = {}
            for line in target.item_def_description:gmatch("[^\n]+") do
                table.insert(lines, line)
            end

            for i = 2, #lines do
                add_line(view_model, "item_def_line_" .. i, lines[i], 0xCCCCCC)
            end
        end

        if target.stack_has_meta then
            local detail = target.stack_meta_summary

            if detail and detail ~= "" then
                add_line(view_model, "item_meta", S("Metadata") .. ": " .. detail, 0x98C9FF)
            else
                add_line(view_model, "item_meta", S("Metadata"), 0x98C9FF)
            end
        end
    end,
})

eye_spy.enrichers.register("growth", {
    enabled = function(context, target)
        return target.kind == "node" and meta_bool(context.meta, "es_show_growth", eye_spy.config.show_growth)
    end,
    apply = function(context, target, view_model)
        local shared = ensure_shared_context(context, target)
        local growth_info = shared:get_growth_info()

        if not growth_info then
            return
        end

        if growth_info.kind == "sapling" then
            local age = growth_info.age or 0

            if age > 0 then
                local percent = math.min(math.floor((age / 20) * 100), 100)
                add_line(view_model, "growth", S("Maturity") .. ": " .. growth_bar(percent), 0xAAAAFF)
            else
                add_line(view_model, "growth", S("Status") .. ": " .. S("Rooting"), 0x888888)
            end

            return
        end

        if growth_info.kind == "crop" then
            local percent = math.floor(math.min(growth_info.stage / math.max(growth_info.max_stage, 1), 1) * 100)
            local conditions = shared:get_crop_conditions() or get_crop_conditions(target, growth_info)
            local stalled = growth_info.stage < growth_info.max_stage and
            (not conditions.soil_ok or not conditions.light_ok)
            local status = ""

            if stalled then
                local reasons = {}

                if not conditions.soil_ok then
                    if not conditions.soil.is_wet then
                        -- Soil is dry (and may also be wrong type)
                        reasons[#reasons + 1] = conditions.soil.is_soil and S("Dry Soil") or S("Bad Soil")
                    else
                        -- Soil is wet but wrong fertility type for this crop
                        reasons[#reasons + 1] = S("Bad Soil")
                    end
                end

                if not conditions.light_ok then
                    reasons[#reasons + 1] = S("Bad Light")
                end

                status = " (" .. S("Stalled")

                if #reasons > 0 then
                    status = status .. ": " .. table.concat(reasons, ", ")
                end

                status = status .. ")"
            end

            add_line(
                view_model,
                "growth",
                S("Growth") .. ": " .. growth_bar(percent) .. status,
                stalled and 0xFFAA55 or 0x55FF55
            )
        end
    end,
})

eye_spy.enrichers.register("dig_time", {
    enabled = function(context, target)
        return target.kind == "node" and meta_bool(context.meta, "es_show_dig_time", true)
    end,
    apply = function(context, target, view_model)
        local shared = ensure_shared_context(context, target)
        local diggable, time = shared:get_dig_result()

        if not diggable then
            add_line(view_model, "dig_time", S("Dig Time") .. ": ∞", 0xA9C5FF)
            return
        end

        local t = tonumber(time) or 0
        add_line(view_model, "dig_time", S("Dig Time") .. ": " .. string.format("%.2fs", t), 0xA9C5FF)
    end,
})

eye_spy.enrichers.register("soil", {
    enabled = function(context, target)
        return target.kind == "node" and meta_bool(context.meta, "es_show_growth", eye_spy.config.show_growth)
    end,
    apply = function(context, target, view_model)
        local shared = ensure_shared_context(context, target)
        local soil_line = shared:get_soil_line()

        if not soil_line then
            return
        end

        add_line(view_model, "soil", soil_line.text, soil_line.color)
    end,
})

eye_spy.enrichers.register("light_level", {
    enabled = function(context, target)
        return target.kind == "node" and meta_bool(context.meta, "es_show_light_level", true)
    end,
    apply = function(_, target, view_model)
        if target.light_level == nil then
            add_line(view_model, "light", S("Light") .. ": " .. S("Unknown"), 0xAAAAAA)
            return
        end

        add_line(view_model, "light", S("Light") .. ": " .. tostring(target.light_level), 0xF2DD88)
    end,
})

eye_spy.enrichers.register("spawn_risk", {
    enabled = function(context, target)
        return target.kind == "node" and meta_bool(context.meta, "es_show_spawn_hint", false)
    end,
    apply = function(context, target, view_model)
        if target.light_level == nil then
            add_line(view_model, "spawn", S("Spawn Risk") .. " (" .. S("Est") .. "): " .. S("Unknown"), 0xAAAAAA)
            return
        end

        local threshold = context.meta:get_int("es_spawn_safe_light_threshold")

        if threshold < 0 or threshold > 15 then
            threshold = 8
        end

        if target.light_level <= threshold then
            add_line(view_model, "spawn", S("Spawn Risk") .. " (" .. S("Est") .. "): " .. S("Dark Enough"), 0xF08A55)
        else
            add_line(view_model, "spawn", S("Spawn Risk") .. " (" .. S("Est") .. "): " .. S("Likely Safe"), 0x6BD66B)
        end
    end,
})

eye_spy.enrichers.register("liquid_info", {
    enabled = function(context, target)
        if not eye_spy.config.show_liquids then
            return false
        end

        local show_liquid = meta_bool(context.meta, "es_show_liquid_info", true)

        if not show_liquid then
            return false
        end

        return target.is_liquid or target.liquid_obstacle ~= nil
    end,
    apply = function(_, target, view_model)
        local liquid_target = target.is_liquid and target or target.liquid_obstacle

        if not liquid_target then
            return
        end

        local name = liquid_name_from_node(liquid_target.full_name or liquid_target.name)
        local detail

        if liquid_target.liquid_type == "source" then
            detail = S("Source")
        elseif liquid_target.liquid_level then
            detail = S("Level") .. ": " .. tostring(liquid_target.liquid_level)
        else
            detail = S("Flowing")
        end

        add_line(view_model, "liquid", S("Liquid") .. ": " .. name .. " (" .. detail .. ")", 0x6FB8FF)
    end,
})
