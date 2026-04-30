local S = eye_spy.S

eye_spy.target = {}

-- Returns the first line of a string, or nil if empty.
local function first_line(text)
    if not text or text == "" then
        return nil
    end

    return text:match("^[^\n]*")
end

-- Returns a compact cache key string for a position.
local function pos_key(pos)
    return string.format("%d,%d,%d", pos.x, pos.y, pos.z)
end

-- Extracts the best available texture from a node definition.
local function extract_node_texture(def)
    if not def or not def.tiles then
        return "eye_spy_default_texture.png"
    end

    return def.tiles[6] or def.tiles[1] or "eye_spy_default_texture.png"
end

-- Normalises a single tile entry (string or table) to a texture string.
local function extract_tile_texture(tile)
    if type(tile) == "table" then
        return tile.name or tile.image or ""
    end

    return type(tile) == "string" and tile or ""
end

-- Common suffixes used by technical/auxiliary nodes (doors, beds, double chests, etc.)
local TECHNICAL_SUFFIXES = {
    "_t_1$", "_t_2$", "_b_1$", "_b_2$",
    "_left$", "_right$",
    "_open$", "_closed$",
}

-- Attempts to resolve a technical node name to its base item name.
-- Priority: 1) def.drop string, 2) suffix stripping heuristic.
local function resolve_base_item(node_name, def)
    if not node_name or node_name == "" then
        return nil
    end

    -- Priority 1: use the drop field if it points to a different item
    if def and type(def.drop) == "string" and def.drop ~= "" and def.drop ~= node_name then
        return def.drop
    end

    -- Priority 2: strip known technical suffixes and verify existence
    local base = node_name
    for _, pattern in ipairs(TECHNICAL_SUFFIXES) do
        local candidate = base:gsub(pattern, "")
        if candidate ~= base and minetest.registered_items[candidate] then
            return candidate
        end
    end

    return nil
end

-- Extracts the best available texture from an item/node definition.
local function extract_item_texture(item_name, def)
    local item_def = def or (item_name and minetest.registered_items[item_name]) or nil

    if not item_def then
        return "eye_spy_default_texture.png"
    end

    if item_def.inventory_image and item_def.inventory_image ~= "" then
        return item_def.inventory_image
    end

    if item_def.wield_image and item_def.wield_image ~= "" then
        return item_def.wield_image
    end

    if item_def.tiles then
        local tile = extract_tile_texture(item_def.tiles[1])

        if tile ~= "" then
            return tile
        end
    end

    return "eye_spy_default_texture.png"
end

-- Extracts the first texture from a luaentity definition.
local function extract_entity_texture(entity)
    if not entity then
        return "eye_spy_default_texture.png"
    end

    if entity.initial_properties and entity.initial_properties.textures then
        return entity.initial_properties.textures[1] or "eye_spy_default_texture.png"
    end

    if entity.textures then
        return entity.textures[1] or "eye_spy_default_texture.png"
    end

    return "eye_spy_default_texture.png"
end

-- Attempts to retrieve an ItemStack carried by a dropped-item entity.
local function get_entity_itemstack(entity)
    if not entity then
        return nil
    end

    local raw = entity.itemstring or entity._itemstring or entity.item or entity.stackstring
    local stack

    if type(raw) == "string" and raw ~= "" then
        stack = ItemStack(raw)
    elseif raw and type(raw) == "userdata" and raw.get_name then
        stack = raw
    end

    if stack and not stack:is_empty() then
        return stack
    end

    return nil
end

-- Returns a brief summary of item-stack metadata for display purposes.
-- Returns: summary_string, has_meta (bool), has_custom_description (bool)
local function summarize_item_meta(stack)
    if not stack or stack:is_empty() then
        return nil, false, false
    end

    local meta = stack:get_meta()

    if not meta then
        return nil, false, false
    end

    local custom_description = first_line(meta:get_string("description"))
    local table_data = meta:to_table() or {}
    local fields = table_data.fields or {}
    local field_count = 0

    for key, value in pairs(fields) do
        if key ~= "description" and value ~= nil and tostring(value) ~= "" then
            field_count = field_count + 1
        end
    end

    local inv_count = 0
    local inventory = table_data.inventory or {}

    for _, list in pairs(inventory) do
        if type(list) == "table" and #list > 0 then
            inv_count = inv_count + 1
        end
    end

    local parts = {}

    if field_count > 0 then
        parts[#parts + 1] = tostring(field_count) .. "f"
    end

    if inv_count > 0 then
        parts[#parts + 1] = tostring(inv_count) .. "inv"
    end

    local has_meta = #parts > 0

    return table.concat(parts, ", "), has_meta, custom_description ~= nil and custom_description ~= ""
end

-- Builds a target table for a dropped-item entity, or returns nil if not applicable.
local function get_dropped_item_target(ref, entity)
    local stack = get_entity_itemstack(entity)

    if not stack then
        return nil
    end

    local item_name = stack:get_name()

    if item_name == "" then
        return nil
    end

    local item_def = minetest.registered_items[item_name] or {}
    local entity_pos = ref and ref:get_pos() or { x = 0, y = 0, z = 0 }
    local count = stack:get_count() or 1
    local meta_summary, has_meta, has_custom_description = summarize_item_meta(stack)
    local custom_description = has_custom_description and first_line(stack:get_meta():get_string("description")) or nil
    local stack_description = nil

    if stack.get_short_description then
        stack_description = first_line(stack:get_short_description())
    end

    if not stack_description and stack.get_description then
        stack_description = first_line(stack:get_description())
    end

    local base_description = custom_description
        or stack_description
        or first_line(item_def.short_description)
        or first_line(item_def.description)
        or eye_spy.readable_name_from_id(item_name)
        or S("Unknown")
    local description = count > 1 and (base_description .. " x" .. count) or base_description

    return {
        kind = "item",
        key = "item:" .. item_name .. ":" .. count .. ":" .. tostring(ref),
        name = item_name,
        full_name = item_name,
        description = description,
        modname = eye_spy.get_modname_from_obj(item_name) or S("Unknown"),
        pos = vector.new(entity_pos),
        ref = ref,
        stack = stack,
        stack_count = count,
        stack_wear = stack:get_wear() or 0,
        stack_has_meta = has_meta,
        stack_meta_summary = meta_summary,
        stack_has_custom_description = has_custom_description,
        texture = extract_item_texture(item_name, item_def),
        inventory_texture = core.get_item_inventory_texture(item_name, 32),
        mesh = nil,
        light_level = nil,
        item_def_description = item_def.short_description or item_def.description or "",
    }
end

-- Returns positions to sample when determining a node's ambient light level.
local function get_light_sample_positions(pos, def)
    local positions = {
        { x = pos.x,     y = pos.y,     z = pos.z },
        { x = pos.x,     y = pos.y + 1, z = pos.z },
        { x = pos.x + 1, y = pos.y,     z = pos.z },
        { x = pos.x - 1, y = pos.y,     z = pos.z },
        { x = pos.x,     y = pos.y,     z = pos.z + 1 },
        { x = pos.x,     y = pos.y,     z = pos.z - 1 },
    }

    -- For non-walkable nodes also sample below (e.g. torches, plants).
    if def and not def.walkable then
        positions[#positions + 1] = { x = pos.x, y = pos.y - 1, z = pos.z }
    end

    return positions
end

-- Microsecond TTL for the light-sample cache.
local LIGHT_CACHE_TTL_US = 200000
local light_sample_cache = {}
local light_sample_cache_size = 0

-- Returns the highest light value among all sampled neighbour positions.
local function get_best_node_light(pos, def)
    local best_light

    for _, sample_pos in ipairs(get_light_sample_positions(pos, def)) do
        local light = minetest.get_node_light(sample_pos)

        if light ~= nil and (best_light == nil or light > best_light) then
            best_light = light
        end
    end

    return best_light
end

-- Cached wrapper around get_best_node_light; evicts the cache when it grows
-- beyond 1 024 entries.
local function get_cached_node_light(pos, def)
    local now_us = minetest.get_us_time and minetest.get_us_time() or 0

    if now_us <= 0 then
        return get_best_node_light(pos, def)
    end

    local cache_key = pos_key(pos) .. ":" .. ((def and def.walkable) and "w" or "nw")
    local cached = light_sample_cache[cache_key]

    if cached and (now_us - cached.time_us) <= LIGHT_CACHE_TTL_US then
        return cached.value
    end

    local sampled = get_best_node_light(pos, def)

    if light_sample_cache_size > 1024 then
        light_sample_cache = {}
        light_sample_cache_size = 0
    end

    if not light_sample_cache[cache_key] then
        light_sample_cache_size = light_sample_cache_size + 1
    end

    light_sample_cache[cache_key] = {
        value = sampled,
        time_us = now_us,
    }

    return sampled
end

-- Returns the current HP of an entity, preferring the luaentity field over the
-- object method.
local function get_entity_hp(ref, entity)
    local hp = entity and (entity.health or entity.hp)

    if hp == nil and ref then
        hp = ref:get_hp()
    end

    return hp
end

-- Fix 3: Returns the maximum HP of an entity.
-- Checks luaentity fields first, then the Minetest 5.8+ get_max_hp() API,
-- and only falls back to current HP as a last resort.
local function get_entity_max_hp(ref, entity)
    if entity then
        local m = entity.max_health or entity.max_hp or entity.hp_max
        if m then return m end
    end

    -- Use get_max_hp() if available (Minetest 5.8+)
    if ref and ref.get_max_hp then
        local max_hp = ref:get_max_hp()
        if max_hp and max_hp > 0 then return max_hp end
    end

    if ref then
        return ref:get_hp() -- last resort: current HP
    end
end

-- Fix 4: Returns a synthetic target table used for UI preview rendering.
-- When preview_type == "Node" a node target is returned; otherwise an entity
-- target is returned (this was previously inverted).
function eye_spy.target.get_preview(preview_type)
    if preview_type == "Node" then
        local def = minetest.registered_nodes["eye_spy:preview_node"]

        return {
            kind = "node",
            key = "preview:node",
            name = "eye_spy:preview_node",
            full_name = "eye_spy:preview_node",
            description = def and def.description or S("Preview") .. " " .. S("Node"),
            modname = "eye_spy",
            pos = { x = 0, y = 0, z = 0 },
            def = def,
            texture = def and def.tiles and def.tiles[1] or "eye_spy_default_texture.png",
            inventory_texture = core.get_item_inventory_texture("eye_spy:preview_node", 32),
            mesh = def and def.mesh or "eye_spy_default_mesh.obj",
            color = def and def.color,
            palette = def and def.palette,
            light_level = 15,
            is_liquid = false,
        }
    end

    -- Default (including "Entity"): return an entity preview target.
    local entity_def = minetest.registered_entities["eye_spy:preview_entity"]
    local props = entity_def and entity_def.initial_properties or {}

    return {
        kind = "entity",
        key = "preview:entity",
        name = "eye_spy:preview_entity",
        full_name = "eye_spy:preview_entity",
        description = props.description or S("Preview") .. " " .. S("Entity"),
        modname = "eye_spy",
        pos = { x = 0, y = 0, z = 0 },
        texture = props.textures and props.textures[1] or "eye_spy_default_texture.png",
        mesh = props.mesh or "eye_spy_default_mesh.obj",
        hp = props.health or props.hp or 8,
        max_hp = props.max_health or props.max_hp or props.hp_max or 10,
        light_level = 15,
    }
end

-- Casts a ray from the player's eye and returns a target table describing
-- whatever the player is looking at (node, entity, dropped item, or air).
function eye_spy.target.acquire(player, opts)
    local options = opts or {}

    if options.preview then
        return eye_spy.target.get_preview(options.preview_type)
    end

    local pos              = player:get_pos()
    local meta             = player and player:get_meta() or nil

    -- Fix 1: (meta and X) or true is always true in Lua.
    -- Correct form: absent meta means show everything; present meta is checked.
    local show_light_level = (not meta) or (meta:get_string("es_show_light_level") ~= "false")
    local show_spawn_hint  = (not meta) or (meta:get_string("es_show_spawn_hint") ~= "false")
    local show_liquid_info = (not meta) or (meta:get_string("es_show_liquid_info") ~= "false")

    local need_node_light  = show_light_level or show_spawn_hint

    local properties       = player:get_properties()
    local eye_height       = properties.eye_height or 1.625

    -- Fix 5: delegate range calculation to the shared helper in tools.lua.
    local range            = eye_spy.get_player_range(player)

    pos.y                  = pos.y + eye_height

    local dir              = player:get_look_dir()
    local start            = vector.add(pos, vector.multiply(dir, 0.2))
    local finish           = vector.add(start, vector.multiply(dir, range))
    local allow_liquids    = eye_spy.config.show_liquids == true and show_liquid_info
    local ray              = minetest.raycast(start, finish, eye_spy.config.show_entities, allow_liquids)
    local first_liquid     = nil
    local primary_target   = nil

    -- Builds a complete node target table.
    local function make_node_target(node, under_pos, def, is_liquid, liquid_type, liquid_level)
        local base_item = resolve_base_item(node.name, def)
        local base_def = base_item and minetest.registered_items[base_item]
        local display_name = base_item or node.name

        return {
            kind = "node",
            key = "node:" .. node.name .. "@" .. pos_key(under_pos),
            name = node.name,
            full_name = node.name,
            description = first_line(def and def.description)
                or first_line(base_def and base_def.description)
                or eye_spy.readable_name_from_id(display_name)
                or S("Unknown"),
            modname = eye_spy.get_modname_from_obj(node.name) or S("Unknown"),
            pos = vector.new(under_pos),
            def = def,
            texture = extract_node_texture(def),
            inventory_texture = core.get_item_inventory_texture(base_item or node.name, 32),
            mesh = def and def.mesh or "eye_spy_default_mesh.obj",
            color = def and def.color,
            palette = def and def.palette,
            light_level = need_node_light and get_cached_node_light(under_pos, def) or nil,
            is_liquid = is_liquid,
            liquid_type = liquid_type,
            liquid_level = liquid_level,
            behind_liquid = false,
            liquid_obstacle = nil,
        }
    end

    for hit in ray do
        if hit.type == "node" then
            local node = minetest.get_node(hit.under)

            if node.name ~= "air" then
                local def = minetest.registered_nodes[node.name]
                local liquid_type = def and def.liquidtype or "none"
                local is_liquid = liquid_type ~= "none"
                local liquid_level

                if is_liquid then
                    if liquid_type == "source" then
                        liquid_level = 8
                    else
                        liquid_level = ((node.param2 or 0) % 8) + 1
                    end

                    if not first_liquid then
                        first_liquid = {
                            name = node.name,
                            full_name = node.name,
                            pos = vector.new(hit.under),
                            liquid_type = liquid_type,
                            liquid_level = liquid_level,
                        }
                    end
                else
                    primary_target = make_node_target(node, hit.under, def, false, liquid_type, liquid_level)
                    break
                end
            end
        elseif hit.type == "object" and hit.ref and not hit.ref:is_player() then
            local entity = hit.ref:get_luaentity()
            local dropped_item = get_dropped_item_target(hit.ref, entity)

            if dropped_item then
                dropped_item.behind_liquid = false
                dropped_item.liquid_obstacle = nil
                primary_target = dropped_item
                break
            end

            local entity_name = entity and entity.name or "unknown"
            local entity_pos = hit.ref:get_pos() or { x = 0, y = 0, z = 0 }

            primary_target = {
                kind = "entity",
                key = "entity:" .. entity_name .. ":" .. tostring(hit.ref),
                name = entity_name,
                full_name = entity_name,
                description = first_line(entity and entity.description)
                    or eye_spy.readable_name_from_id(entity_name)
                    or S("Unknown"),
                modname = eye_spy.get_modname_from_obj(entity_name) or S("Unknown"),
                pos = vector.new(entity_pos),
                ref = hit.ref,
                texture = extract_entity_texture(entity),
                mesh = entity and entity.mesh or "eye_spy_default_mesh.obj",
                hp = get_entity_hp(hit.ref, entity),
                max_hp = get_entity_max_hp(hit.ref, entity),
                light_level = nil,
                behind_liquid = false,
                liquid_obstacle = nil,
            }

            break
        end
    end

    if primary_target then
        if first_liquid then
            primary_target.behind_liquid = true
            primary_target.liquid_obstacle = first_liquid
        end

        return primary_target
    end

    -- No solid target found — return the liquid itself if one was encountered.
    if first_liquid then
        local node_name = first_liquid.name
        local node_pos = first_liquid.pos
        local def = minetest.registered_nodes[node_name]

        return {
            kind = "node",
            key = "node:" .. node_name .. "@" .. pos_key(node_pos),
            name = node_name,
            full_name = node_name,
            description = first_line(def and def.description)
                or eye_spy.readable_name_from_id(node_name)
                or S("Unknown"),
            modname = eye_spy.get_modname_from_obj(node_name) or S("Unknown"),
            pos = vector.new(node_pos),
            def = def,
            texture = extract_node_texture(def),
            mesh = def and def.mesh or "eye_spy_default_mesh.obj",
            color = def and def.color,
            palette = def and def.palette,
            light_level = need_node_light and get_cached_node_light(node_pos, def) or nil,
            is_liquid = true,
            liquid_type = first_liquid.liquid_type,
            liquid_level = first_liquid.liquid_level,
            behind_liquid = false,
            liquid_obstacle = nil,
        }
    end

    return { kind = "air", key = "air", behind_liquid = false, liquid_obstacle = nil }
end
