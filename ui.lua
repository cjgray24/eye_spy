--ui

local S = minetest.get_translator(minetest.get_current_modname())

local old_values = {}
local index = {}
local change_preview_type = {}
local FOOTER_MODE_OPTIONS = { "Compact", "Advanced" }
local SPAWN_THRESHOLD_OPTIONS = { "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "11", "12", "13", "14", "15" }
local HUD_ALIGNMENT_OPTIONS = {
    "Top-Middle",
    "Top-Left",
    "Top-Right",
    "Middle-Left",
    "Middle-Right",
    "Bottom-Left",
    "Bottom-Right",
}
local PREVIEW_DEBOUNCE_SECONDS = 0.4
local LAYOUT_REBUILD_DRAG_IDLE_US = 450000
local LAYOUT_REBUILD_NUDGE_IDLE_US = 60000
local LAYOUT_VAL_AS_NUDGE_GAP_US = 140000

local layout_last_chg_us = {}

eye_spy.ui_drafts = eye_spy.ui_drafts or {}

local LAYOUT_TARGET_OPTIONS = { "Global", "BG", "Icon", "Title", "Subtitle", "Lines", "Footer" }
local LAYOUT_STEP_OPTIONS = { 1, 2, 4, 8 }
local LAYOUT_PAGE_OPTIONS = { "Position", "Panel", "Text" }
local LAYOUT_META_DEFAULTS = {
    es_layout_page = "Position",
    es_layout_target = "Global",
    es_layout_step = 2,
    es_global_offset_x = 0,
    es_global_offset_y = 0,
    es_bg_offset_x = 0,
    es_bg_offset_y = 0,
    es_icon_offset_x = 0,
    es_icon_offset_y = 0,
    es_title_offset_x = 0,
    es_title_offset_y = 0,
    es_subtitle_offset_x = 0,
    es_subtitle_offset_y = 0,
    es_lines_offset_x = 0,
    es_lines_offset_y = 0,
    es_footer_offset_x = 0,
    es_footer_offset_y = 0,
    es_bg_pad_left = 7,
    es_bg_pad_right = 0,
    es_bg_pad_top = 2,
    es_bg_pad_bottom = 0,
    es_bg_extra_w = 0,
    es_bg_extra_h = 0,
    es_bg_scale_x_pct = 100,
    es_bg_scale_y_pct = 100,
    es_icon_size = 20,
    es_title_scale_pct = 100,
    es_subtitle_scale_pct = 100,
    es_line_scale_pct = 100,
    es_footer_scale_pct = 100,
    es_first_line_y_adj = 0,
    es_line_step_adj = -6,
    es_footer_nudge_adj = -4,
    es_text_base_x_adj = 0,
    es_icon_base_x_adj = 0,
    es_top_margin_adj = 0,
    es_bottom_margin_adj = 0,
}

local LAYOUT_TARGET_KEYS = {
    Global = { x = "es_global_offset_x", y = "es_global_offset_y" },
    BG = { x = "es_bg_offset_x", y = "es_bg_offset_y" },
    Icon = { x = "es_icon_offset_x", y = "es_icon_offset_y" },
    Title = { x = "es_title_offset_x", y = "es_title_offset_y" },
    Subtitle = { x = "es_subtitle_offset_x", y = "es_subtitle_offset_y" },
    Lines = { x = "es_lines_offset_x", y = "es_lines_offset_y" },
    Footer = { x = "es_footer_offset_x", y = "es_footer_offset_y" },
}

-- Fix 5: Global reset group now includes es_text_base_x_adj and es_icon_base_x_adj
local LAYOUT_RESET_GROUPS = {
    Global = { "es_global_offset_x", "es_global_offset_y", "es_top_margin_adj", "es_bottom_margin_adj",
        "es_text_base_x_adj", "es_icon_base_x_adj" },
    BG = {
        "es_bg_offset_x",
        "es_bg_offset_y",
        "es_bg_pad_left",
        "es_bg_pad_right",
        "es_bg_pad_top",
        "es_bg_pad_bottom",
        "es_bg_extra_w",
        "es_bg_extra_h",
        "es_bg_scale_x_pct",
        "es_bg_scale_y_pct",
    },
    Icon = { "es_icon_offset_x", "es_icon_offset_y", "es_icon_size", "es_icon_base_x_adj" },
    Title = { "es_title_offset_x", "es_title_offset_y", "es_title_scale_pct" },
    Subtitle = { "es_subtitle_offset_x", "es_subtitle_offset_y", "es_subtitle_scale_pct" },
    Lines = {
        "es_lines_offset_x",
        "es_lines_offset_y",
        "es_line_scale_pct",
        "es_first_line_y_adj",
        "es_line_step_adj",
        "es_text_base_x_adj",
    },
    Footer = { "es_footer_offset_x", "es_footer_offset_y", "es_footer_scale_pct", "es_footer_nudge_adj" },
}

local LAYOUT_PAGE_SLIDERS = {
    Position = {
        ["*"] = {
            { label = "Offset X", key = "$target_x", min = -400, max = 400, x = 0.7, y = 3.7, width = 4.0 },
            { label = "Offset Y", key = "$target_y", min = -400, max = 400, x = 5.0, y = 3.7, width = 4.0 },
        },
        Global = {
            { label = "Top Margin",    key = "es_top_margin_adj",    min = -50,  max = 120, x = 9.3, y = 3.7, width = 4.0 },
            { label = "Bottom Margin", key = "es_bottom_margin_adj", min = -50,  max = 140, x = 0.7, y = 5.1, width = 4.0 },
            { label = "Text Base X",   key = "es_text_base_x_adj",   min = -180, max = 220, x = 5.0, y = 5.1, width = 4.0 },
            { label = "Icon Base X",   key = "es_icon_base_x_adj",   min = -180, max = 220, x = 9.3, y = 5.1, width = 4.0 },
        },
    },
    Panel = {
        BG = {
            { label = "Pad Left",    key = "es_bg_pad_left",    min = -200, max = 400, x = 0.7, y = 3.35, width = 4.0 },
            { label = "Pad Right",   key = "es_bg_pad_right",   min = -200, max = 400, x = 5.0, y = 3.35, width = 4.0 },
            { label = "Pad Top",     key = "es_bg_pad_top",     min = -200, max = 400, x = 9.3, y = 3.35, width = 4.0 },
            { label = "Pad Bottom",  key = "es_bg_pad_bottom",  min = -200, max = 400, x = 0.7, y = 4.75, width = 4.0 },
            { label = "Extra W",     key = "es_bg_extra_w",     min = -300, max = 500, x = 5.0, y = 4.75, width = 4.0 },
            { label = "Extra H",     key = "es_bg_extra_h",     min = -300, max = 500, x = 9.3, y = 4.75, width = 4.0 },
            { label = "Scale X%",    key = "es_bg_scale_x_pct", min = 25,   max = 300, x = 0.7, y = 6.15, width = 4.0 },
            { label = "Scale Y%",    key = "es_bg_scale_y_pct", min = 25,   max = 300, x = 5.0, y = 6.15, width = 4.0 },
            { label = "BG Offset X", key = "es_bg_offset_x",    min = -400, max = 400, x = 9.3, y = 6.15, width = 4.0 },
            { label = "BG Offset Y", key = "es_bg_offset_y",    min = -400, max = 400, x = 0.7, y = 7.55, width = 4.0 },
        },
        Icon = {
            { label = "Icon Offset X", key = "es_icon_offset_x",   min = -400, max = 400, x = 0.7, y = 3.35, width = 4.0 },
            { label = "Icon Offset Y", key = "es_icon_offset_y",   min = -400, max = 400, x = 5.0, y = 3.35, width = 4.0 },
            { label = "Icon Size",     key = "es_icon_size",       min = 16,   max = 128, x = 9.3, y = 3.35, width = 4.0 },
            { label = "Icon Base X",   key = "es_icon_base_x_adj", min = -180, max = 220, x = 0.7, y = 4.75, width = 4.0 },
        },
    },
    Text = {
        Title = {
            { label = "Title Scale", key = "es_title_scale_pct", min = 40,   max = 300, x = 0.7, y = 3.35, width = 4.0 },
            { label = "Title Off X", key = "es_title_offset_x",  min = -400, max = 400, x = 5.0, y = 3.35, width = 4.0 },
            { label = "Title Off Y", key = "es_title_offset_y",  min = -400, max = 400, x = 9.3, y = 3.35, width = 4.0 },
        },
        Subtitle = {
            { label = "Main Scale", key = "es_subtitle_scale_pct", min = 40,   max = 300, x = 0.7, y = 3.35, width = 4.0 },
            { label = "Main Off X", key = "es_subtitle_offset_x",  min = -400, max = 400, x = 5.0, y = 3.35, width = 4.0 },
            { label = "Main Off Y", key = "es_subtitle_offset_y",  min = -400, max = 400, x = 9.3, y = 3.35, width = 4.0 },
        },
        Lines = {
            { label = "Line Scale",   key = "es_line_scale_pct",   min = 40,   max = 300, x = 0.7, y = 3.35, width = 4.0 },
            { label = "Lines Off X",  key = "es_lines_offset_x",   min = -400, max = 400, x = 5.0, y = 3.35, width = 4.0 },
            { label = "Lines Off Y",  key = "es_lines_offset_y",   min = -400, max = 400, x = 9.3, y = 3.35, width = 4.0 },
            { label = "First Line Y", key = "es_first_line_y_adj", min = -120, max = 220, x = 0.7, y = 4.75, width = 4.0 },
            { label = "Line Step",    key = "es_line_step_adj",    min = -8,   max = 50,  x = 5.0, y = 4.75, width = 4.0 },
            { label = "Text Base X",  key = "es_text_base_x_adj",  min = -180, max = 220, x = 9.3, y = 4.75, width = 4.0 },
        },
        Footer = {
            { label = "Footer Scale", key = "es_footer_scale_pct", min = 40,   max = 300, x = 0.7, y = 3.35, width = 4.0 },
            { label = "Footer Off X", key = "es_footer_offset_x",  min = -400, max = 400, x = 5.0, y = 3.35, width = 4.0 },
            { label = "Footer Off Y", key = "es_footer_offset_y",  min = -400, max = 400, x = 9.3, y = 3.35, width = 4.0 },
            { label = "Footer Nudge", key = "es_footer_nudge_adj", min = -120, max = 120, x = 0.7, y = 4.75, width = 4.0 },
        },
    },
}

local LAYOUT_SLIDER_BOUNDS = {
    es_global_offset_x = { min = -400, max = 400 },
    es_global_offset_y = { min = -400, max = 400 },
    es_bg_offset_x = { min = -400, max = 400 },
    es_bg_offset_y = { min = -400, max = 400 },
    es_icon_offset_x = { min = -400, max = 400 },
    es_icon_offset_y = { min = -400, max = 400 },
    es_title_offset_x = { min = -400, max = 400 },
    es_title_offset_y = { min = -400, max = 400 },
    es_subtitle_offset_x = { min = -400, max = 400 },
    es_subtitle_offset_y = { min = -400, max = 400 },
    es_lines_offset_x = { min = -400, max = 400 },
    es_lines_offset_y = { min = -400, max = 400 },
    es_footer_offset_x = { min = -400, max = 400 },
    es_footer_offset_y = { min = -400, max = 400 },
    es_bg_pad_left = { min = -200, max = 400 },
    es_bg_pad_right = { min = -200, max = 400 },
    es_bg_pad_top = { min = -200, max = 400 },
    es_bg_pad_bottom = { min = -200, max = 400 },
    es_bg_extra_w = { min = -300, max = 500 },
    es_bg_extra_h = { min = -300, max = 500 },
    es_bg_scale_x_pct = { min = 25, max = 300 },
    es_bg_scale_y_pct = { min = 25, max = 300 },
    es_icon_size = { min = 16, max = 128 },
    es_title_scale_pct = { min = 40, max = 300 },
    es_subtitle_scale_pct = { min = 40, max = 300 },
    es_line_scale_pct = { min = 40, max = 300 },
    es_footer_scale_pct = { min = 40, max = 300 },
    es_first_line_y_adj = { min = -120, max = 220 },
    es_line_step_adj = { min = -8, max = 50 },
    es_footer_nudge_adj = { min = -120, max = 120 },
    es_text_base_x_adj = { min = -180, max = 220 },
    es_icon_base_x_adj = { min = -180, max = 220 },
    es_top_margin_adj = { min = -50, max = 120 },
    es_bottom_margin_adj = { min = -50, max = 140 },
    es_bg_alpha = { min = 0, max = 255 },
}

local DRAFT_KEY_TYPES = {
    es_hud_color = "string",
    es_hud_alignment = "string",
    es_hud_health_in = "string",
    es_auto_text_color = "string",
    es_title_color_val = "int",
    es_subtitle_color_val = "int",
    es_footer_color_val = "int",
    es_line_color_val = "int",
    es_growth_color_val = "int",
    es_soil_color_val = "int",
    es_footer_mode = "string",
    es_show_coords = "string",
    es_show_light_level = "string",
    es_show_spawn_hint = "string",
    es_show_liquid_info = "string",
    es_show_dig_time = "string",
    es_spawn_safe_light_threshold = "int",
    es_layout_page = "string",
    es_layout_target = "string",
    es_layout_step = "int",
    es_hud_enabled = "string", -- Fix 6: add es_hud_enabled to draft key types
    es_bg_alpha = "int",
}

for key, default_value in pairs(LAYOUT_META_DEFAULTS) do
    if type(default_value) == "number" then
        DRAFT_KEY_TYPES[key] = "int"
    else
        DRAFT_KEY_TYPES[key] = "string"
    end
end

local function get_player_draft(player_name, create)
    if not player_name then
        return nil
    end

    local draft = eye_spy.ui_drafts[player_name]

    if not draft and create then
        draft = {}
        eye_spy.ui_drafts[player_name] = draft
    end

    return draft
end

local function clear_player_draft(player_name)
    if player_name then
        eye_spy.ui_drafts[player_name] = nil
    end
end

local function set_draft_value(player_name, key, value)
    local draft = get_player_draft(player_name, true)

    if draft then
        draft[key] = value
    end
end

local function get_effective_string(meta, player_name, key)
    local draft = get_player_draft(player_name, false)

    if draft and draft[key] ~= nil then
        return tostring(draft[key])
    end

    return meta:get_string(key)
end

local function get_effective_int(meta, player_name, key)
    local draft = get_player_draft(player_name, false)

    if draft and draft[key] ~= nil then
        return tonumber(draft[key]) or 0
    end

    return meta:get_int(key)
end

local function commit_player_draft(player)
    if not player then
        return
    end

    local player_name = player:get_player_name()
    local draft = get_player_draft(player_name, false)

    if not draft then
        return
    end

    local meta = player:get_meta()

    for key, value in pairs(draft) do
        local key_type = DRAFT_KEY_TYPES[key]

        if key_type == "int" then
            meta:set_int(key, tonumber(value) or 0)
        elseif key_type == "string" then
            meta:set_string(key, tostring(value))
        end
    end

    clear_player_draft(player_name)

    if eye_spy.render and eye_spy.render.invalidate_layout_sig then
        eye_spy.render.invalidate_layout_sig(player_name)
    end
end

local function get_option_index(options, value)
    for i, option in ipairs(options) do
        if tostring(option) == tostring(value) then
            return i
        end
    end

    return 1
end

-- Fix 2: save_old_values now includes show_growth and show_icons
local function save_old_values(meta)
    local values = {
        color                      = meta:get_string("es_hud_color"),
        hud_alignment              = meta:get_string("es_hud_alignment"),
        health_in                  = meta:get_string("es_hud_health_in"),
        auto_text_color            = meta:get_string("es_auto_text_color"),
        title_color_val            = meta:get_int("es_title_color_val"),
        subtitle_color_val         = meta:get_int("es_subtitle_color_val"),
        footer_color_val           = meta:get_int("es_footer_color_val"),
        line_color_val             = meta:get_int("es_line_color_val"),
        growth_color_val           = meta:get_int("es_growth_color_val"),
        soil_color_val             = meta:get_int("es_soil_color_val"),
        footer_mode                = meta:get_string("es_footer_mode"),
        show_coords                = meta:get_string("es_show_coords"),
        show_light_level           = meta:get_string("es_show_light_level"),
        show_spawn_hint            = meta:get_string("es_show_spawn_hint"),
        show_liquid_info           = meta:get_string("es_show_liquid_info"),
        show_dig_time              = meta:get_string("es_show_dig_time"),
        spawn_safe_light_threshold = meta:get_int("es_spawn_safe_light_threshold"),
        show_growth                = meta:get_string("es_show_growth"),
        show_icons                 = meta:get_string("es_show_icons"),
        bg_alpha                   = meta:get_int("es_bg_alpha"),
        layout                     = {},
    }

    for key, default_value in pairs(LAYOUT_META_DEFAULTS) do
        if type(default_value) == "number" then
            values.layout[key] = meta:get_int(key)
        else
            values.layout[key] = meta:get_string(key)
        end
    end

    return values
end

local function restore_old_values(meta, values)
    if not values then
        return
    end

    meta:set_string("es_hud_color", values.color)
    meta:set_string("es_hud_alignment", values.hud_alignment)
    meta:set_string("es_hud_health_in", values.health_in)
    meta:set_string("es_auto_text_color", values.auto_text_color)
    meta:set_int("es_title_color_val", values.title_color_val)
    meta:set_int("es_subtitle_color_val", values.subtitle_color_val)
    meta:set_int("es_footer_color_val", values.footer_color_val)
    meta:set_int("es_line_color_val", values.line_color_val)
    meta:set_int("es_growth_color_val", values.growth_color_val)
    meta:set_int("es_soil_color_val", values.soil_color_val)
    meta:set_string("es_footer_mode", values.footer_mode or "compact")
    meta:set_string("es_show_coords", values.show_coords or "false")
    meta:set_string("es_show_light_level", values.show_light_level or "true")
    meta:set_string("es_show_spawn_hint", values.show_spawn_hint or "false")
    meta:set_string("es_show_liquid_info", values.show_liquid_info or "true")
    meta:set_string("es_show_dig_time", values.show_dig_time or "true")
    meta:set_int("es_spawn_safe_light_threshold", values.spawn_safe_light_threshold or 8)
    meta:set_string("es_show_growth", values.show_growth or "true")
    meta:set_string("es_show_icons", values.show_icons or "true")
    meta:set_int("es_bg_alpha", values.bg_alpha or eye_spy.config.default_bg_alpha)

    for key, default_value in pairs(LAYOUT_META_DEFAULTS) do
        local saved_value = values.layout and values.layout[key]

        if type(default_value) == "number" then
            meta:set_int(key, tonumber(saved_value) or default_value)
        else
            meta:set_string(key, tostring(saved_value or default_value))
        end
    end
end

local function reset_layout_target(meta, target)
    local keys = LAYOUT_RESET_GROUPS[target]

    if not keys then
        return
    end

    for _, key in ipairs(keys) do
        local default_value = LAYOUT_META_DEFAULTS[key]

        if type(default_value) == "number" then
            meta:set_int(key, default_value)
        else
            meta:set_string(key, default_value)
        end
    end
end

local function reset_layout_all(meta)
    for key, default_value in pairs(LAYOUT_META_DEFAULTS) do
        if type(default_value) == "number" then
            meta:set_int(key, default_value)
        else
            meta:set_string(key, default_value)
        end
    end
end

local function update_preview(player, preview_type, force)
    local player_name = player and player:get_player_name()

    if not player_name then
        return
    end

    if force then
        eye_spy.pending_preview_updates[player_name] = nil
        eye_spy.get_hud(player, {
            preview = true,
            preview_type = preview_type,
            force = true,
        })
        return
    end

    local due_at_us = 0
    local now_us = minetest.get_us_time and minetest.get_us_time() or 0
    due_at_us = now_us + math.floor(PREVIEW_DEBOUNCE_SECONDS * 1000000)

    eye_spy.pending_preview_updates[player_name] = {
        preview_type = preview_type,
        force = false,
        due_at_us = due_at_us,
    }
end

local function parse_scroll_input(raw, fallback)
    local parsed
    local event_type

    if type(raw) == "string" and minetest.explode_scrollbar_event then
        local event = minetest.explode_scrollbar_event(raw)

        if event and event.value then
            parsed = tonumber(event.value)
            event_type = event.type
        end
    end

    if parsed == nil then
        parsed = tonumber((tostring(raw) or ""):match("-?%d+"))
    end

    return parsed or fallback, event_type
end

local function layout_slider(label, field_name, value, minv, maxv, x, y, width)
    local slider_width = width or 4.2

    return "label[" .. x .. "," .. y .. ";" .. label .. ": " .. value .. "]" ..
        "scrollbaroptions[min=" .. minv .. ";max=" .. maxv .. ";smallstep=1]" ..
        "scrollbar[" .. x .. "," .. (y + 0.35) .. ";" .. slider_width .. ",0.5;horizontal;" ..
        field_name .. ";" .. value .. "]"
end

local function resolve_layout_slider_key(entry, target_keys)
    if entry.key == "$target_x" then
        return target_keys.x
    end

    if entry.key == "$target_y" then
        return target_keys.y
    end

    return entry.key
end

local function get_layout_page_entries(selected_page, selected_target)
    local page = LAYOUT_PAGE_SLIDERS[selected_page] or LAYOUT_PAGE_SLIDERS.Position
    local entries = {}
    local common = page["*"] or {}
    local specific = page[selected_target] or {}

    for _, entry in ipairs(common) do
        entries[#entries + 1] = entry
    end

    for _, entry in ipairs(specific) do
        entries[#entries + 1] = entry
    end

    return entries
end

local function build_layout_page_content(meta, player_name, selected_page, selected_target, target_keys)
    local page_entries = get_layout_page_entries(selected_page, selected_target)
    local parts = {
        "box[0.4,3.0;14.7,6.8;#00000020]",
    }

    if selected_page == "Position" then
        parts[#parts + 1] = "label[0.7,3.25;" .. S("Selected Target Position") .. "]"
    elseif #page_entries == 0 then
        parts[#parts + 1] = "label[0.7,3.45;" .. S("No controls for this target on this page") .. "]"
    end

    for _, entry in ipairs(page_entries) do
        local key = resolve_layout_slider_key(entry, target_keys)
        local value = get_effective_int(meta, player_name, key)

        parts[#parts + 1] = layout_slider(
            S(entry.label),
            key,
            value,
            entry.min,
            entry.max,
            entry.x,
            entry.y,
            entry.width
        )
    end

    return table.concat(parts)
end

function eye_spy.get_layout_ui(player)
    local player_name = player:get_player_name()
    local meta = player:get_meta()
    local selected_page = get_effective_string(meta, player_name, "es_layout_page")
    local selected_target = get_effective_string(meta, player_name, "es_layout_target")

    if selected_page == "" then
        selected_page = "Position"
        meta:set_string("es_layout_page", selected_page)
    end

    if selected_target == "" then
        selected_target = "Global"
        meta:set_string("es_layout_target", selected_target)
    end

    local step = get_effective_int(meta, player_name, "es_layout_step")

    if step <= 0 then
        step = 2
        meta:set_int("es_layout_step", step)
    end

    local target_keys = LAYOUT_TARGET_KEYS[selected_target] or LAYOUT_TARGET_KEYS.Global
    local page_content = build_layout_page_content(meta, player_name, selected_page, selected_target, target_keys)

    local formspec = (
        "formspec_version[6]" ..
        "size[15.5,11.2]" ..
        "no_prepend[]" ..
        "bgcolor[#0F1319C0;false]" ..
        "label[0.4,0.4;" .. S("Advanced Layout Editor") .. "]" ..
        "label[0.4,0.85;" .. S("Use pages to edit layout without crowding the form") .. "]" ..
        "dropdown[0.4,1.25;2.5,0.8;layout_page;Position,Panel,Text;" .. get_option_index(LAYOUT_PAGE_OPTIONS, selected_page) .. ";false]" ..
        "dropdown[3.1,1.25;2.6,0.8;layout_target;Global,BG,Icon,Title,Subtitle,Lines,Footer;" .. get_option_index(LAYOUT_TARGET_OPTIONS, selected_target) .. ";false]" ..
        "dropdown[5.9,1.25;1.4,0.8;layout_step;1,2,4,8;" .. get_option_index(LAYOUT_STEP_OPTIONS, step) .. ";false]" ..
        "label[7.7,1.33;" .. S("Step") .. ": " .. step .. "]" ..
        "button[10.0,1.05;2.2,0.8;reset_layout_target;" .. S("Reset Target") .. "]" ..
        "button[12.4,1.05;2.0,0.8;reset_layout_all;" .. S("Reset All") .. "]" ..
        page_content ..
        "button[11.6,10.05;1.7,0.8;back_main;" .. S("Back") .. "]" ..
        "label[0.5,10.2;" .. S("Tips: use step 1 for fine tuning and drag sliders for live preview") .. "]"
    )

    return formspec
end

minetest.register_on_joinplayer(function(player)
    index[player:get_player_name()] = 0
end)

-- Fix 3: only restore old values when edit_mode is active; always clean up old_values
minetest.register_on_dieplayer(function(player)
    local player_name = player:get_player_name()
    local meta = player:get_meta()
    local state = eye_spy.get_player_state(player)
    if state.edit_mode and old_values[player_name] then
        restore_old_values(meta, old_values[player_name])
    end
    old_values[player_name] = nil -- always clean up
    eye_spy.exit_edit_mode(player)
end)

function eye_spy.get_ui(player, data)
    local player_name = player:get_player_name()

    index[player_name] = index[player_name] + 1

    local player_index = index[player_name]

    local meta = player:get_meta()
    local string_to_num = {
        health_in = {
            ["Points"] = 1, ["Hearts"] = 2
        }
    }

    if not data or not data.reopen then
        change_preview_type[player_name] = "Entity"
        old_values[player_name] = save_old_values(meta)
    end

    -- Fix 7: detect admin-disable state for warning display
    local admin_disabled = eye_spy.is_player_server_disabled(player_name)

    local r, g, b = eye_spy.get_rgb(get_effective_string(meta, player_name, "es_hud_color"))
    local hud_alignment = get_effective_string(meta, player_name, "es_hud_alignment")
    local health_in = get_effective_string(meta, player_name, "es_hud_health_in")
    local auto_text_color = get_effective_string(meta, player_name, "es_auto_text_color") ~= "false"
    local show_light_level = get_effective_string(meta, player_name, "es_show_light_level") ~= "false"
    local show_spawn_hint = get_effective_string(meta, player_name, "es_show_spawn_hint") ~= "false"
    local show_liquid_info = get_effective_string(meta, player_name, "es_show_liquid_info") ~= "false"
    local show_dig_time = get_effective_string(meta, player_name, "es_show_dig_time") ~= "false"
    local show_growth = get_effective_string(meta, player_name, "es_show_growth") ~= "false"
    local show_icons = get_effective_string(meta, player_name, "es_show_icons") ~= "false"
    local show_coords = get_effective_string(meta, player_name, "es_show_coords") ~= "false"
    -- Fix 6: read hud_enabled from effective meta/draft
    local hud_enabled = get_effective_string(meta, player_name, "es_hud_enabled") ~= "false"
    local footer_mode = get_effective_string(meta, player_name, "es_footer_mode") == "advanced" and "Advanced" or
        "Compact"
    local spawn_threshold = math.max(0,
        math.min(15, get_effective_int(meta, player_name, "es_spawn_safe_light_threshold")))
    local footer_mode_idx = get_option_index(FOOTER_MODE_OPTIONS, footer_mode)
    local spawn_threshold_idx = get_option_index(SPAWN_THRESHOLD_OPTIONS, tostring(spawn_threshold))
    local title_color_val = get_effective_int(meta, player_name, "es_title_color_val")
    local subtitle_color_val = get_effective_int(meta, player_name, "es_subtitle_color_val")
    local footer_color_val = get_effective_int(meta, player_name, "es_footer_color_val")
    local line_color_val = get_effective_int(meta, player_name, "es_line_color_val")
    local growth_color_val = get_effective_int(meta, player_name, "es_growth_color_val")
    local soil_color_val = get_effective_int(meta, player_name, "es_soil_color_val")
    local bg_alpha = get_effective_int(meta, player_name, "es_bg_alpha")

    local formspec = table.concat({
        "formspec_version[6]",
        "size[13.4,12.5]",
        "no_prepend[]",
        "bgcolor[#0F1319C0;false]",
        "box[0.2,0.2;13.0,0.5;#1C2433C0]",
        "label[0.45,0.28;Eye Spy]",
        -- Fix 8: show what is currently being previewed directly (no inversion)
        "label[11.4,0.28;" .. S("Preview") .. ": " .. S(change_preview_type[player_name]) .. "]",
        -- Fix 7: admin-disable warning banner
        admin_disabled and ("box[0.3,0.75;12.8,0.45;#7A2020C0]" ..
            "label[0.55,0.82;" .. minetest.formspec_escape(S("Eye Spy is currently disabled for you by the server admin.")) .. "]") or
        "",
        "box[0.3,0.9;6.35,3.9;#00000020]",
        "label[0.55,1.15;" .. S("Background Color") .. "]",
        "scrollbaroptions[min=0;max=255;smallstep=1]",
        "label[0.55,1.55;R]",
        "box[0.88,1.57;5.3,0.34;#FF0000CC]",
        "scrollbar[0.88,1.55;5.3,0.42;horizontal;r_" .. player_index .. ";" .. (r or 26) .. "]",
        "label[0.55,2.25;G]",
        "box[0.88,2.27;5.3,0.34;#00FF00CC]",
        "scrollbar[0.88,2.25;5.3,0.42;horizontal;g_" .. player_index .. ";" .. (g or 26) .. "]",
        "label[0.55,2.95;B]",
        "box[0.88,2.97;5.3,0.34;#0000FFCC]",
        "scrollbar[0.88,2.95;5.3,0.42;horizontal;b_" .. player_index .. ";" .. (b or 27) .. "]",
        "label[0.55,3.45;" .. S("Opacity") .. "]",
        "box[0.88,3.47;5.3,0.34;#AAAAAACC]",
        "scrollbar[0.88,3.45;5.3,0.42;horizontal;bg_alpha_" .. player_index .. ";" .. bg_alpha .. "]",
        "button[0.55,4.15;2.5,0.7;default_color;" .. S("Set to Default") .. "]",

        "box[6.75,0.9;6.35,3.9;#00000020]",
        "label[7.0,1.15;" .. S("HUD Setup") .. "]",
        "label[7.0,1.55;" .. S("Hud Alignment") .. "]",
        "dropdown[7.0,1.8;3.2,0.8;hud_alignment;" ..
        table.concat(HUD_ALIGNMENT_OPTIONS, ",") ..
        ";" .. get_option_index(HUD_ALIGNMENT_OPTIONS, hud_alignment) .. ";false]",
        "button[10.35,1.75;2.55,0.7;default_hud_alignment;" .. S("Default") .. "]",
        "label[7.0,2.85;" .. S("Health in") .. "]",
        "dropdown[7.0,3.1;3.2,0.8;health_in;Points,Hearts;" .. (string_to_num.health_in[health_in] or 1) .. ";false]",
        "button[10.35,3.05;2.55,0.7;default_health_in;" .. S("Default") .. "]",
        "button[7.0,3.85;2.8,0.7;change_change_preview_type;" .. S("Preview Type") .. "]",
        "button[10.0,3.85;2.9,0.7;advanced_layout;" .. S("Advanced Layout") .. "]",
        -- Fix 6: HUD Enabled checkbox in HUD Setup box
        "checkbox[7.0,4.55;hud_enabled;" .. S("HUD Enabled") .. ";" .. (hud_enabled and "true" or "false") .. "]",
        "box[0.3,5.05;12.8,3.5;#00000020]",
        "label[0.55,5.3;" .. S("Text Styling") .. "]",
        "checkbox[0.55,5.65;auto_text_color;" .. S("Auto Text Colors") ..
        ";" .. (auto_text_color and "true" or "false") .. "]",
        "scrollbaroptions[min=0;max=255;smallstep=1]",
        "label[0.55,6.05;" .. S("Title") .. "]",
        "scrollbar[0.55,6.3;3.9,0.45;horizontal;title_color_" .. player_index .. ";" .. title_color_val .. "]",
        "label[4.8,6.05;" .. S("Info") .. "]",
        "scrollbar[4.8,6.3;3.9,0.45;horizontal;subtitle_color_" .. player_index .. ";" .. subtitle_color_val .. "]",
        "label[9.05,6.05;" .. S("Footer") .. "]",
        "scrollbar[9.05,6.3;3.6,0.45;horizontal;footer_color_" .. player_index .. ";" .. footer_color_val .. "]",
        "label[0.55,6.95;" .. S("Line") .. "]",
        "scrollbar[0.55,7.2;3.9,0.45;horizontal;line_color_" .. player_index .. ";" .. line_color_val .. "]",
        "label[4.8,6.95;" .. S("Growth") .. "]",
        "scrollbar[4.8,7.2;3.9,0.45;horizontal;growth_color_" .. player_index .. ";" .. growth_color_val .. "]",
        "label[9.05,6.95;" .. S("Soil") .. "]",
        "scrollbar[9.05,7.2;3.6,0.45;horizontal;soil_color_" .. player_index .. ";" .. soil_color_val .. "]",
        "box[0.3,8.8;12.8,2.15;#00000020]",
        "label[0.55,9.05;" .. S("Info Lines") .. "]",
        "checkbox[0.55,9.4;show_light_level;" .. S("Light Level") .. ";" .. (show_light_level and "true" or "false") ..
        "]",
        "checkbox[0.55,9.78;show_spawn_hint;" .. S("Spawn Hint") .. ";" .. (show_spawn_hint and "true" or "false") .. "]",
        "label[3.25,9.43;" .. S("Spawn Thresh") .. "]",
        "dropdown[3.25,9.66;1.6,0.8;spawn_threshold;0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15;" ..
        spawn_threshold_idx .. ";false]",
        "checkbox[5.45,9.4;show_liquid_info;" .. S("Liquid Info") .. ";" .. (show_liquid_info and "true" or "false") ..
        "]",
        "checkbox[5.45,9.78;show_dig_time;" .. S("Dig Time") .. ";" .. (show_dig_time and "true" or "false") .. "]",
        "checkbox[8.65,9.4;show_growth;" .. S("Growth") .. ";" .. (show_growth and "true" or "false") .. "]",
        "checkbox[11.6,9.4;show_icons;" .. S("Icons") .. ";" .. (show_icons and "true" or "false") .. "]",
        "checkbox[11.6,9.78;show_coords;" .. S("Coords") .. ";" .. (show_coords and "true" or "false") .. "]",
        "label[10.7,10.06;" .. S("Footer Mode") .. "]",
        "dropdown[10.7,10.29;2.0,0.8;footer_mode;Compact,Advanced;" .. footer_mode_idx .. ";false]",
        "style[cancel;bgcolor=#8D2930C0]",
        "style[apply;bgcolor=#2D7F46C0]",
        "button_exit[7.9,11.5;2.4,0.8;cancel;" .. S("Cancel") .. "]",
        "button[10.55,11.5;2.55,0.8;apply;" .. S("Apply Changes") .. "]",
    }, "")

    update_preview(player, change_preview_type[player_name], true)

    return formspec
end

-- Fix 11: is_live_scrollbar hoisted to module level — it's a pure function with no upvalue captures
local function is_live_scrollbar(raw)
    if type(raw) ~= "string" or not minetest.explode_scrollbar_event then
        return false
    end
    local ev = minetest.explode_scrollbar_event(raw)
    return ev and (ev.type == "CHG" or ev.type == "VAL")
end

minetest.register_on_player_receive_fields(function(player, formname, fields)
    if formname ~= "eye_spy:ui" then
        return false
    end

    local player_name = player:get_player_name()
    local meta = player:get_meta()

    local player_index = index[player_name]
    local player_change_preview_type = change_preview_type[player_name]
    local main_slider_event = false

    if fields["r_" .. player_index] or fields["g_" .. player_index] or fields["b_" .. player_index] then
        local current_r, current_g, current_b = eye_spy.get_rgb(get_effective_string(meta, player_name, "es_hud_color"))
        local r = current_r
        local g = current_g
        local b = current_b
        local color_changed = false

        if fields["r_" .. player_index] and is_live_scrollbar(fields["r_" .. player_index]) then
            local value = parse_scroll_input(fields["r_" .. player_index], current_r)
            if value ~= current_r then
                r = value; color_changed = true
            end
        end

        if fields["g_" .. player_index] and is_live_scrollbar(fields["g_" .. player_index]) then
            local value = parse_scroll_input(fields["g_" .. player_index], current_g)
            if value ~= current_g then
                g = value; color_changed = true
            end
        end

        if fields["b_" .. player_index] and is_live_scrollbar(fields["b_" .. player_index]) then
            local value = parse_scroll_input(fields["b_" .. player_index], current_b)
            if value ~= current_b then
                b = value; color_changed = true
            end
        end

        if color_changed then
            set_draft_value(player_name, "es_hud_color", r .. ", " .. g .. ", " .. b)
            main_slider_event = true
        end
    end

    -- Fix 11: apply_main_int_slider stays inner (captures fields, player_name, meta, main_slider_event)
    local function apply_main_int_slider(field_name, meta_key)
        if not fields[field_name] or not is_live_scrollbar(fields[field_name]) then
            return
        end

        local current = get_effective_int(meta, player_name, meta_key)
        local value = parse_scroll_input(fields[field_name], current)

        if value ~= current then
            set_draft_value(player_name, meta_key, value)
            main_slider_event = true
        end
    end

    apply_main_int_slider("title_color_" .. player_index, "es_title_color_val")
    apply_main_int_slider("subtitle_color_" .. player_index, "es_subtitle_color_val")
    apply_main_int_slider("footer_color_" .. player_index, "es_footer_color_val")
    apply_main_int_slider("line_color_" .. player_index, "es_line_color_val")
    apply_main_int_slider("growth_color_" .. player_index, "es_growth_color_val")
    apply_main_int_slider("soil_color_" .. player_index, "es_soil_color_val")
    apply_main_int_slider("bg_alpha_" .. player_index, "es_bg_alpha")

    if main_slider_event then
        local now_us = minetest.get_us_time and minetest.get_us_time() or 0
        eye_spy.pending_preview_updates[player_name] = {
            preview_type = player_change_preview_type,
            force = true,
            due_at_us = now_us,
        }
        return true
    end

    if fields.auto_text_color then
        set_draft_value(player_name, "es_auto_text_color", fields.auto_text_color)
        update_preview(player, player_change_preview_type)
        minetest.show_formspec(player_name, "eye_spy:ui", eye_spy.get_ui(player, { reopen = true }))
    end

    local info_settings_changed = false

    if fields.show_light_level then
        set_draft_value(player_name, "es_show_light_level", fields.show_light_level)
        info_settings_changed = true
    end

    if fields.show_spawn_hint then
        set_draft_value(player_name, "es_show_spawn_hint", fields.show_spawn_hint)
        info_settings_changed = true
    end

    if fields.show_liquid_info then
        set_draft_value(player_name, "es_show_liquid_info", fields.show_liquid_info)
        info_settings_changed = true
    end

    if fields.show_dig_time then
        set_draft_value(player_name, "es_show_dig_time", fields.show_dig_time)
        info_settings_changed = true
    end

    if fields.show_growth then
        set_draft_value(player_name, "es_show_growth", fields.show_growth)
        info_settings_changed = true
    end

    if fields.show_icons then
        set_draft_value(player_name, "es_show_icons", fields.show_icons)
        info_settings_changed = true
    end

    if fields.show_coords then
        set_draft_value(player_name, "es_show_coords", fields.show_coords)
        info_settings_changed = true
    end

    -- Fix 6: handle hud_enabled checkbox
    if fields.hud_enabled ~= nil then
        set_draft_value(player_name, "es_hud_enabled", fields.hud_enabled)
        info_settings_changed = true
    end

    if fields.footer_mode then
        if fields.footer_mode == "Advanced" then
            set_draft_value(player_name, "es_footer_mode", "advanced")
        else
            set_draft_value(player_name, "es_footer_mode", "compact")
        end

        info_settings_changed = true
    end

    if fields.spawn_threshold then
        local threshold = tonumber(fields.spawn_threshold)

        if threshold then
            set_draft_value(player_name, "es_spawn_safe_light_threshold", math.max(0, math.min(15, threshold)))
            info_settings_changed = true
        end
    end

    if info_settings_changed then
        update_preview(player, player_change_preview_type)
        minetest.show_formspec(player_name, "eye_spy:ui", eye_spy.get_ui(player, { reopen = true }))
    end

    if fields.default_color then
        set_draft_value(player_name, "es_hud_color", "26, 26, 27")
        minetest.show_formspec(player_name, "eye_spy:ui", eye_spy.get_ui(player, { reopen = true }))
        update_preview(player, player_change_preview_type)
    end

    if fields.hud_alignment then
        set_draft_value(player_name, "es_hud_alignment", fields.hud_alignment)
        update_preview(player, player_change_preview_type)
    end

    if fields.default_hud_alignment then
        set_draft_value(player_name, "es_hud_alignment", "Top-Middle")
        minetest.show_formspec(player_name, "eye_spy:ui", eye_spy.get_ui(player, { reopen = true }))
        update_preview(player, player_change_preview_type)
    end

    if fields.health_in then
        set_draft_value(player_name, "es_hud_health_in", fields.health_in)
        update_preview(player, player_change_preview_type)
    end

    if fields.default_health_in then
        set_draft_value(player_name, "es_hud_health_in", "Points")
        minetest.show_formspec(player_name, "eye_spy:ui", eye_spy.get_ui(player, { reopen = true }))
        update_preview(player, player_change_preview_type)
    end

    if fields.change_change_preview_type then
        if player_change_preview_type == "Node" then
            change_preview_type[player_name] = "Entity"
            minetest.show_formspec(player_name, "eye_spy:ui", eye_spy.get_ui(player, { reopen = true }))
        else
            change_preview_type[player_name] = "Node"
            minetest.show_formspec(player_name, "eye_spy:ui", eye_spy.get_ui(player, { reopen = true }))
        end
    end

    if fields.advanced_layout then
        eye_spy.pending_layout_refreshes[player_name] = nil
        layout_last_chg_us[player_name] = nil
        minetest.close_formspec(player_name, "eye_spy:ui")
        minetest.show_formspec(player_name, "eye_spy:layout_ui", eye_spy.get_layout_ui(player))
        return true
    end

    -- Fix 1: clear old_values before closing so death cannot revert applied settings
    if fields.apply then
        commit_player_draft(player)
        old_values[player_name] = nil -- prevent death from reverting applied settings
        minetest.close_formspec(player_name, formname)
        eye_spy.exit_edit_mode(player)
        eye_spy.update_player(player, { preview = false, force = true })
        return true
    end

    if fields.quit then
        restore_old_values(meta, old_values[player_name])
        clear_player_draft(player_name)
        eye_spy.pending_preview_updates[player_name] = nil

        eye_spy.exit_edit_mode(player)
        eye_spy.update_player(player, { preview = false, force = true })
    end

    return true
end)

minetest.register_on_player_receive_fields(function(player, formname, fields)
    if formname ~= "eye_spy:layout_ui" then
        return false
    end

    local player_name = player:get_player_name()
    local meta = player:get_meta()
    local player_change_preview_type = change_preview_type[player_name] or "Entity"
    local selected_page = get_effective_string(meta, player_name, "es_layout_page")

    local selected_target = get_effective_string(meta, player_name, "es_layout_target")

    if selected_page == "" then
        selected_page = "Position"
        set_draft_value(player_name, "es_layout_page", selected_page)
    end

    if selected_target == "" then
        selected_target = "Global"
        set_draft_value(player_name, "es_layout_target", selected_target)
    end

    if fields.back_main then
        eye_spy.pending_layout_refreshes[player_name] = nil
        layout_last_chg_us[player_name] = nil
        minetest.close_formspec(player_name, "eye_spy:layout_ui")
        minetest.show_formspec(player_name, "eye_spy:ui", eye_spy.get_ui(player, { reopen = true }))
        return true
    end

    if fields.quit then
        eye_spy.pending_layout_refreshes[player_name] = nil
        layout_last_chg_us[player_name] = nil
        minetest.close_formspec(player_name, "eye_spy:layout_ui")
        minetest.show_formspec(player_name, "eye_spy:ui", eye_spy.get_ui(player, { reopen = true }))
        return true
    end

    local rebuild = false

    if fields.layout_page and fields.layout_page ~= selected_page then
        set_draft_value(player_name, "es_layout_page", fields.layout_page)
        selected_page = fields.layout_page
        rebuild = true
    end

    if fields.layout_target and LAYOUT_TARGET_KEYS[fields.layout_target] then
        if fields.layout_target ~= selected_target then
            set_draft_value(player_name, "es_layout_target", fields.layout_target)
            selected_target = fields.layout_target
            rebuild = true
        end
    end

    if fields.layout_step then
        local new_step = tonumber(fields.layout_step)

        if new_step then
            local clamped_step = math.max(1, new_step)

            if clamped_step ~= get_effective_int(meta, player_name, "es_layout_step") then
                set_draft_value(player_name, "es_layout_step", clamped_step)
                rebuild = true
            end
        end
    end

    local step = math.max(1, get_effective_int(meta, player_name, "es_layout_step"))

    local slider_event = false
    local slider_had_chg = false
    local slider_had_val = false
    local slider_chg_count = 0
    local slider_val_count = 0
    local slider_max_delta = 0
    local slider_had_small_step_val = false

    -- Fix 11: apply_slider stays inner (captures fields, player_name, meta, and slider tracking locals)
    local function apply_slider(name, minv, maxv)
        if fields[name] == nil then
            return
        end

        local current = get_effective_int(meta, player_name, name)
        local value, event_type = parse_scroll_input(fields[name], current)

        -- Ignore values from full form submissions (button clicks, quit).
        -- Only act on live scrollbar CHG/VAL events.
        if event_type ~= "CHG" and event_type ~= "VAL" then
            return
        end

        if event_type == "CHG" then
            slider_had_chg = true
            slider_chg_count = slider_chg_count + 1
        elseif event_type == "VAL" then
            slider_had_val = true
            slider_val_count = slider_val_count + 1
        end

        if minv then
            value = math.max(minv, value)
        end

        if maxv then
            value = math.min(maxv, value)
        end

        local delta = math.abs(value - current)
        slider_max_delta = math.max(slider_max_delta, delta)

        if event_type == "VAL" and delta <= 2 then
            slider_had_small_step_val = true
        end

        if value ~= current then
            set_draft_value(player_name, name, value)
        end

        slider_event = true
    end

    for key, bounds in pairs(LAYOUT_SLIDER_BOUNDS) do
        apply_slider(key, bounds.min, bounds.max)
    end

    if slider_event and not fields.reset_layout_target and not fields.reset_layout_all then
        -- Queue a HUD update rather than calling get_hud directly. Multiple CHG
        -- events between step ticks overwrite the same entry, so the HUD fires at
        -- most once per step tick instead of on every CHG.
        local now_us = minetest.get_us_time and minetest.get_us_time() or 0
        eye_spy.pending_preview_updates[player_name] = {
            preview_type = player_change_preview_type,
            force = true,
            due_at_us = now_us,
        }

        if slider_had_chg then
            layout_last_chg_us[player_name] = now_us
        end

        local rebuild_delay_us = LAYOUT_REBUILD_DRAG_IDLE_US
        local last_chg_us = layout_last_chg_us[player_name] or 0
        local recent_chg = last_chg_us > 0 and (now_us - last_chg_us) <= LAYOUT_VAL_AS_NUDGE_GAP_US

        -- Treat tiny VAL deltas as click-like nudges unless they are part of a
        -- recent drag burst.
        if slider_had_small_step_val and slider_chg_count <= 1 and not recent_chg then
            rebuild_delay_us = LAYOUT_REBUILD_NUDGE_IDLE_US
        elseif slider_had_val and slider_val_count > 0 and slider_chg_count == 0 and not recent_chg then
            rebuild_delay_us = LAYOUT_REBUILD_NUDGE_IDLE_US
        end

        eye_spy.pending_layout_refreshes[player_name] = {
            due_at_us = now_us + rebuild_delay_us,
        }
        return true
    end

    if fields.reset_layout_target then
        local keys = LAYOUT_RESET_GROUPS[selected_target]

        if keys then
            for _, key in ipairs(keys) do
                set_draft_value(player_name, key, LAYOUT_META_DEFAULTS[key])
            end
        end

        rebuild = true
    end

    if fields.reset_layout_all then
        for key, default_value in pairs(LAYOUT_META_DEFAULTS) do
            set_draft_value(player_name, key, default_value)
        end

        selected_target = "Global"
        set_draft_value(player_name, "es_layout_target", selected_target)
        rebuild = true
    end

    if rebuild then
        eye_spy.pending_preview_updates[player_name] = nil
        eye_spy.get_hud(player, {
            preview = true,
            preview_type = player_change_preview_type,
            force = true,
        })
        minetest.show_formspec(player_name, "eye_spy:layout_ui", eye_spy.get_layout_ui(player))
    end

    return true
end)

-- Fix 10: clean up all UI-local tables when a player leaves
minetest.register_on_leaveplayer(function(player)
    local player_name                = player:get_player_name()
    old_values[player_name]          = nil
    index[player_name]               = nil
    change_preview_type[player_name] = nil
    layout_last_chg_us[player_name]  = nil
end)
