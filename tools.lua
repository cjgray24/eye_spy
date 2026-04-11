-- eye_spy/tools.lua
-- Tool detection and dig-hint helpers.
-- Extracted from functions.lua.  Runs after functions.lua, so eye_spy.S and
-- eye_spy.cg are already available when this file is executed.

local S = eye_spy.S

------------------------------------------------------------
-- Group → tool-type mappings for Minetest Game
------------------------------------------------------------

-- Maps dig group names to human-readable tool-type labels (MTG).
local GROUP_TO_TOOL_MTG = {
    cracky        = S("Pickaxe"),
    crumbly       = S("Shovel"),
    choppy        = S("Axe"),
    snappy        = S("Sword"),
    dig_immediate = S("Hand"),
}

-- Priority order for MTG group lookup (most-specific first).
local GROUP_ORDER_MTG = { "dig_immediate", "snappy", "crumbly", "choppy", "cracky" }

------------------------------------------------------------
-- Group → tool-type mappings for MineClone / VoxeLibre
------------------------------------------------------------

-- Maps dig group names to human-readable tool-type labels (MCL).
local GROUP_TO_TOOL_MC = {
    swordy        = S("Sword"),
    handy         = S("Hand"),
    pickaxey      = S("Pickaxe"),
    shovely       = S("Shovel"),
    axey          = S("Axe"),
    shearsy       = S("Shears"),
    dig_immediate = S("Hand"),
}

-- Priority order for MCL group lookup (most-specific first).
local GROUP_ORDER_MC = { "dig_immediate", "handy", "swordy", "shearsy", "shovely", "axey", "pickaxey" }

------------------------------------------------------------
-- Internal helpers
------------------------------------------------------------

-- Returns a shallow copy of an ipairs-iterable list.
local function clone_list(values)
    local result = {}

    for index, value in ipairs(values or {}) do
        result[index] = value
    end

    return result
end

-- Appends `value` to `list` only when it is not already present.
-- Ignores nil and empty-string values.
local function append_unique(list, value)
    if not value or value == "" then
        return
    end

    for _, existing in ipairs(list) do
        if existing == value then
            return
        end
    end

    list[#list + 1] = value
end

-- Returns the group→tool map and ordered group list appropriate for the
-- currently-running game.  Uses eye_spy.cg (set by init.lua).
local function get_tool_mapping(game_id)
    if game_id == "mineclone" then
        return GROUP_TO_TOOL_MC, GROUP_ORDER_MC
    end

    return GROUP_TO_TOOL_MTG, GROUP_ORDER_MTG
end

-- Collects every tool-type label that applies to `node_groups`, in priority
-- order, de-duplicated.
local function collect_tool_types(node_groups, group_to_tool, group_order)
    local result = {}

    for _, group in ipairs(group_order) do
        if node_groups[group] and group_to_tool[group] then
            append_unique(result, group_to_tool[group])
        end
    end

    return result
end

-- Returns the single highest-priority dig group and its tool-type label for
-- `node_groups`.  Returns nil, S("None") when no matching group is found.
local function get_preferred_tool_group(node_groups, group_to_tool, group_order)
    for _, group in ipairs(group_order) do
        if node_groups[group] and group_to_tool[group] then
            return group, group_to_tool[group]
        end
    end

    return nil, S("None")
end

-- Builds a display string from the full set of required tool types and the
-- single best/preferred tool type.
--
-- Examples:
--   { "Pickaxe" }, "Pickaxe"  →  "Pickaxe"
--   { "Axe", "Pickaxe" }, "Pickaxe"  →  "Axe / Pickaxe | Pickaxe"
local function format_tool_summary(minimum_types, best_type)
    local minimum_label = table.concat(minimum_types or {}, " / ")

    if best_type and best_type ~= "" and best_type ~= S("None") and best_type ~= S("Unknown") then
        if minimum_label == "" then
            return best_type
        end

        -- Single entry that matches best_type exactly — no need to repeat it.
        if #minimum_types == 1 and minimum_types[1] == best_type then
            return best_type
        end

        -- If best_type is already listed in minimum_types, just show the list.
        for _, minimum_type in ipairs(minimum_types or {}) do
            if minimum_type == best_type then
                return minimum_label
            end
        end

        -- best_type is not in the minimum list — append it after a separator.
        return minimum_label .. " | " .. best_type
    end

    if minimum_label ~= "" then
        return minimum_label
    end

    return S("Unknown")
end

-- Returns true when `itemdef` has groupcaps for `preferred_group`.
-- dig_immediate is never considered a "match" because any item can break those
-- nodes instantly.
local function tool_matches_group(itemdef, preferred_group)
    if not preferred_group or preferred_group == "dig_immediate" then
        return false
    end

    local caps      = itemdef and itemdef.tool_capabilities
    local groupcaps = caps and caps.groupcaps

    return groupcaps and groupcaps[preferred_group] ~= nil or false
end

------------------------------------------------------------
-- Public API
------------------------------------------------------------

-- Returns whether `toolstack` can dig `nodename`, plus the dig time.
-- Returns false, nil when `toolstack` is nil or the node is unknown.
function eye_spy.tool_can_dig_node(toolstack, nodename)
    -- Nil-guard: no stack means no digging ability.
    if not toolstack then
        return false, nil
    end

    local ndef = minetest.registered_nodes[nodename]

    if not ndef then
        return false, nil
    end

    local tool_caps = toolstack:get_tool_capabilities()
    local node_groups = ndef.groups or {}
    local dig_params = minetest.get_dig_params(node_groups, tool_caps)

    return dig_params.diggable, dig_params.time
end

-- Returns a filtered copy of `source` that omits every entry whose `.name`
-- field contains any substring listed in `blocked`.
function eye_spy.filter_out_by_name(source, blocked)
    local result = {}

    for _, entry in ipairs(source) do
        local name = entry.name or ""
        local keep = true

        for _, word in ipairs(blocked) do
            if string.find(name, word, 1, true) then
                keep = false
                break
            end
        end

        if keep then
            table.insert(result, entry)
        end
    end

    return result
end

-- Returns the highest `maxlevel` value found across all groupcaps of
-- `itemdef`.  Returns 0 when `itemdef` has no tool_capabilities.
function eye_spy.get_tool_maxlevel(itemdef)
    local maxlevel = 0

    if not itemdef.tool_capabilities then
        return 0
    end

    for _, gc in pairs(itemdef.tool_capabilities.groupcaps or {}) do
        if gc.maxlevel and gc.maxlevel > maxlevel then
            maxlevel = gc.maxlevel
        end
    end

    return maxlevel
end

-- Returns a human-readable tool-hint string for `node_name` (or nil when no
-- hint is applicable) and a boolean indicating whether the currently wielded
-- `toolstack` is an appropriate tool for digging that node.
function eye_spy.get_node_tool_hint_and_match(node_name, toolstack)
    if not node_name or node_name == "" then
        return nil, false
    end

    local def = minetest.registered_nodes[node_name]

    if not def or not def.groups then
        return nil, false
    end

    local node_groups                = def.groups
    local group_to_tool, group_order = get_tool_mapping(eye_spy.cg)
    local minimum_types              = collect_tool_types(node_groups, group_to_tool, group_order)
    local preferred_group, tooltype  = get_preferred_tool_group(node_groups, group_to_tool, group_order)
    local summary                    = format_tool_summary(minimum_types, tooltype)

    -- Suppress generic/unhelpful labels.
    if summary == S("Unknown") or summary == S("None") then
        summary = nil
    end

    -- Nodes with no preferred dig group (or dig_immediate) are considered
    -- compatible with any held item for colour-state purposes.
    if not preferred_group or preferred_group == "dig_immediate" then
        return summary, true
    end

    local itemdef   = toolstack and toolstack.get_definition and toolstack:get_definition() or nil
    local caps      = itemdef and itemdef.tool_capabilities or nil
    local groupcaps = caps and caps.groupcaps or nil
    local matches   = groupcaps and groupcaps[preferred_group] ~= nil or false

    return summary, matches
end

-- Returns the effective reach range for `player` based on the wielded item
-- definition, falling back to creative-mode range (10) or default range (4).
function eye_spy.get_player_range(player)
    local wield = player:get_wielded_item()
    local def   = wield:get_definition()

    -- Nil-guard: definition may be absent for unknown item types.
    if def and def.range then
        return def.range
    end

    if minetest.is_creative_enabled(player:get_player_name()) then
        return 10
    end

    return 4
end
