local S                          = eye_spy.S

eye_spy.render                   = {}
-- Bump this string whenever the HUD layout math, element set, or render key
-- format changes in a way that would make old cached render keys produce a
-- wrong or stale layout for existing players.
local RENDER_LAYOUT_REV          = "advanced-layout-controls-v2-padding-fix"
local ICON_TEXTURE_SIZE          = 32
local ICON_DISPLAY_SIZE          = 56
local ENTITY_ICON_TEXTURE        = "heart.png"
local BASE_LAYOUT_LINE_ROWS      = 6
local MAX_LAYOUT_SCALE_FACTOR    = 3

local FIXED_LINE_ROW_BY_ID       = {
    dig_time = 1,
    light = 2,
    soil = 3,
    growth = 4,
    spawn = 5,
    liquid = 6,
}

local FIXED_LINE_ORDER           = {
    "dig_time",
    "light",
    "soil",
    "growth",
    "spawn",
    "liquid",
}

local layout_key_names           = {
    "es_global_offset_x",
    "es_global_offset_y",
    "es_bg_offset_x",
    "es_bg_offset_y",
    "es_icon_offset_x",
    "es_icon_offset_y",
    "es_title_offset_x",
    "es_title_offset_y",
    "es_subtitle_offset_x",
    "es_subtitle_offset_y",
    "es_lines_offset_x",
    "es_lines_offset_y",
    "es_footer_offset_x",
    "es_footer_offset_y",
    "es_bg_pad_left",
    "es_bg_pad_right",
    "es_bg_pad_top",
    "es_bg_pad_bottom",
    "es_bg_extra_w",
    "es_bg_extra_h",
    "es_bg_scale_x_pct",
    "es_bg_scale_y_pct",
    "es_icon_size",
    "es_title_scale_pct",
    "es_subtitle_scale_pct",
    "es_line_scale_pct",
    "es_footer_scale_pct",
    "es_first_line_y_adj",
    "es_line_step_adj",
    "es_footer_nudge_adj",
    "es_text_base_x_adj",
    "es_icon_base_x_adj",
    "es_top_margin_adj",
    "es_bottom_margin_adj",
}

local layouts                    = {
    ["Top-Middle"] = { pos = { x = 0.5, y = 0 }, x_mode = "center", y_mode = "top" },
    ["Top-Right"] = { pos = { x = 1, y = 0 }, x_mode = "right", y_mode = "top" },
    ["Top-Left"] = { pos = { x = 0, y = 0 }, x_mode = "left", y_mode = "top" },
    ["Middle-Right"] = { pos = { x = 1, y = 0.5 }, x_mode = "right", y_mode = "middle" },
    ["Middle-Left"] = { pos = { x = 0, y = 0.5 }, x_mode = "left", y_mode = "middle" },
    ["Bottom-Right"] = { pos = { x = 1, y = 1 }, x_mode = "right", y_mode = "bottom" },
    ["Bottom-Left"] = { pos = { x = 0, y = 1 }, x_mode = "left", y_mode = "bottom" },
}

-- ---------------------------------------------------------------------------
-- Color math — aliased from colors.lua for local-variable call performance.
-- ---------------------------------------------------------------------------
local clamp                      = eye_spy.colors.clamp
local split_rgb                  = eye_spy.colors.split_rgb
local join_rgb                   = eye_spy.colors.join_rgb
local channel_luminance          = eye_spy.colors.channel_luminance
local color_luminance            = eye_spy.colors.color_luminance
local contrast_ratio             = eye_spy.colors.contrast_ratio
local scale_color                = eye_spy.colors.scale_color
local blend_color                = eye_spy.colors.blend_color
local rgb_to_hsl                 = eye_spy.colors.rgb_to_hsl
local hsl_to_rgb                 = eye_spy.colors.hsl_to_rgb
local get_bg_luminance_rgb       = eye_spy.colors.get_bg_luminance_rgb
local get_bg_luminance           = eye_spy.colors.get_bg_luminance
local best_monochrome_for_bg     = eye_spy.colors.best_monochrome_for_bg
local spectrum_color             = eye_spy.colors.spectrum_color
local adapt_for_bg               = eye_spy.colors.adapt_for_bg
local nudge_contrast             = eye_spy.colors.nudge_contrast
local tune_contrast_preserve_hue = eye_spy.colors.tune_contrast_preserve_hue

local function build_layout_lines(view_model)
    local fixed_slots = {}
    local append_lines = {}

    for _, line in ipairs(view_model.lines or {}) do
        local fixed_row = line.id and FIXED_LINE_ROW_BY_ID[line.id] or nil

        if fixed_row and fixed_slots[line.id] == nil then
            fixed_slots[line.id] = line
        else
            append_lines[#append_lines + 1] = line
        end
    end

    local ordered_lines = {}

    for _, line_id in ipairs(FIXED_LINE_ORDER) do
        if fixed_slots[line_id] then
            ordered_lines[#ordered_lines + 1] = fixed_slots[line_id]
        end
    end

    for _, line in ipairs(append_lines) do
        ordered_lines[#ordered_lines + 1] = line
    end

    local total_rows = #ordered_lines
    local required_rows = math.max(1, total_rows)
    local max_rows = BASE_LAYOUT_LINE_ROWS * MAX_LAYOUT_SCALE_FACTOR
    local visible_rows = math.min(required_rows, max_rows)
    local layout_lines = {}

    for row = 1, visible_rows do
        layout_lines[row] = ordered_lines[row]
    end

    local overflow_count = math.max(0, total_rows - visible_rows)

    if overflow_count > 0 and visible_rows > 0 then
        layout_lines[visible_rows] = {
            id = "overflow",
            text = string.format(S("+%d more"), overflow_count),
            color = 0xAAAAAA,
        }
    end

    return layout_lines, visible_rows
end

local function estimate_panel_width(view_model, layout_lines)
    local max_len = math.max(#(view_model.title or ""), #(view_model.subtitle or ""), #(view_model.footer or ""))

    for _, line in ipairs(layout_lines or view_model.lines or {}) do
        if line then
            max_len = math.max(max_len, #(line.text or ""))
        end
    end

    local baseline_width = view_model.icon and 468 or 420
    local baseline_char_budget = view_model.icon and 176 or 208
    local grow_chars = math.max(0, max_len - baseline_char_budget)
    local required_width = baseline_width + math.floor(grow_chars * 6)

    return clamp(required_width, baseline_width, baseline_width * MAX_LAYOUT_SCALE_FACTOR)
end



local function has_line(view_model, line_id)
    for _, line in ipairs(view_model.lines) do
        if line.id == line_id then
            return true
        end
    end

    return false
end

-- Hue offsets (degrees) spread each line type around the complementary of
-- the background hue so they remain visually distinct from each other.
local LINE_HUE_OFFSETS = {
    growth   = 0,
    soil     = 30,
    dig_time = 55,
    light    = 85,
    spawn    = 45,
    liquid   = -50,
}

local auto_line_color_cache = {}
local auto_line_color_cache_size = 0

local function get_auto_line_accent(line_id, bg_hex, bg_color, base_text, bg_luminance)
    local cache_key = table.concat({ line_id or "", bg_hex or "", tostring(base_text) }, "|")
    local cached = auto_line_color_cache[cache_key]

    if cached then
        return cached
    end

    local bg_r, bg_g, bg_b = split_rgb(bg_color)
    local bg_h, bg_s, bg_l = rgb_to_hsl(bg_r, bg_g, bg_b)

    -- Dynamic accent: complementary hue + per-line offset, lightness inversely
    -- proportional to bg lightness so it remains readable on any saturated bg
    -- without collapsing to a monochrome colour.
    local hue_off = LINE_HUE_OFFSETS[line_id] or 0
    local accent_h = (bg_h + 180 + hue_off) % 360
    local accent_s = clamp(0.60 + bg_s * 0.22, 0.48, 0.88)
    local accent_l = clamp(0.76 - bg_l * 0.52, 0.20, 0.82)
    local dr, dg, db = hsl_to_rgb(accent_h, accent_s, accent_l)
    local dynamic = join_rgb(dr, dg, db)

    -- Fixed palettes are still used as the starting point for near-neutral
    -- backgrounds where the bg hue is undefined or very weak.
    local dark_palette = {
        growth = 0x8BE68B,
        soil = 0xE7C882,
        dig_time = 0xAFC9FF,
        light = 0xF2DE98,
        spawn = 0xF2B189,
        liquid = 0x8CC8FF,
    }
    local light_palette = {
        growth = 0x2D7A35,
        soil = 0x7E5A1F,
        dig_time = 0x345C98,
        light = 0x725C1D,
        spawn = 0x94442A,
        liquid = 0x1E5E9A,
    }
    local lightness_t = clamp((bg_l - 0.35) / 0.30, 0, 1)
    local dark_fixed = dark_palette[line_id] or dynamic
    local light_fixed = light_palette[line_id] or dynamic
    local fixed = blend_color(dark_fixed, light_fixed, lightness_t)

    -- Blend: saturated bg → trust dynamic complementary; neutral bg → fixed.
    local accent = blend_color(fixed, dynamic, clamp(bg_s * 1.3, 0, 1))

    -- Contrast pass without hard-snapping to monochrome fallback.
    local result = tune_contrast_preserve_hue(accent, bg_color, 3.6)
    result = nudge_contrast(result, bg_color, 3.8)

    if auto_line_color_cache_size > 512 then
        auto_line_color_cache = {}
        auto_line_color_cache_size = 0
    end

    if not auto_line_color_cache[cache_key] then
        auto_line_color_cache_size = auto_line_color_cache_size + 1
    end

    auto_line_color_cache[cache_key] = result

    return result
end

local function adjust_semantic_line_color(color, bg_color)
    return nudge_contrast(
        tune_contrast_preserve_hue(color, bg_color, 3.6),
        bg_color,
        3.8
    )
end

local function get_line_color_for_manual(meta, line_id)
    if line_id == "growth" then
        return spectrum_color(meta:get_int("es_growth_color_val"))
    end

    if line_id == "soil" then
        return spectrum_color(meta:get_int("es_soil_color_val"))
    end

    return spectrum_color(meta:get_int("es_line_color_val"))
end

local function position_text(pos)
    if not pos then
        return "0, 0, 0"
    end

    return string.format("%s, %s, %s", eye_spy.round1(pos.x) or 0, eye_spy.round1(pos.y) or 0, eye_spy.round1(pos.z) or 0)
end

local function texture_text(target)
    if target and target.kind == "entity" then
        return ENTITY_ICON_TEXTURE .. "^[resize:" .. ICON_TEXTURE_SIZE .. "x" .. ICON_TEXTURE_SIZE
    end

    local texture = target.texture or "eye_spy_default_texture.png"

    if type(texture) == "table" then
        texture = texture.name or texture.image or "eye_spy_default_texture.png"
    end

    if type(texture) ~= "string" or texture == "" then
        texture = "eye_spy_default_texture.png"
    end

    texture = eye_spy.strip_texture_modifiers(texture)

    if target.color then
        texture = texture .. "^[multiply:" .. target.color
    elseif target.palette then
        texture = texture .. "^[multiply:#7CBD6B"
    end

    -- Normalize every icon texture to the same source size so HUD icon size is consistent.
    texture = texture .. "^[resize:" .. ICON_TEXTURE_SIZE .. "x" .. ICON_TEXTURE_SIZE

    return texture
end

-- Per-player layout signature cache. The 35-key meta scan only needs to run
-- when the player is actively changing layout values in the editor. All other
-- updates (normal play, colour slider dragging) reuse the cached string.
local player_layout_sigs = {}

local function get_player_draft(player)
    if not player or not eye_spy.ui_drafts then
        return nil
    end

    return eye_spy.ui_drafts[player:get_player_name()]
end

local function get_effective_string(meta, draft, key)
    if draft and draft[key] ~= nil then
        return tostring(draft[key])
    end

    return meta:get_string(key)
end

local function get_effective_int(meta, draft, key)
    if draft and draft[key] ~= nil then
        return tonumber(draft[key]) or 0
    end

    return meta:get_int(key)
end

function eye_spy.render.invalidate_layout_sig(player_name)
    player_layout_sigs[player_name] = nil
end

local function get_layout_signature(meta, player_name)
    if player_name and player_layout_sigs[player_name] then
        return player_layout_sigs[player_name]
    end

    local parts = {}

    for _, key in ipairs(layout_key_names) do
        parts[#parts + 1] = tostring(meta:get_int(key))
    end

    local sig = table.concat(parts, ",")

    if player_name then
        player_layout_sigs[player_name] = sig
    end

    return sig
end

local function get_layout_signature_from_values(meta, draft)
    local parts = {}

    for _, key in ipairs(layout_key_names) do
        parts[#parts + 1] = tostring(get_effective_int(meta, draft, key))
    end

    return table.concat(parts, ",")
end

local function build_key(view_model)
    local parts = {
        RENDER_LAYOUT_REV,
        view_model.layout_signature or "",
        view_model.layout,
        view_model.bg_color,
        view_model.title,
        tostring(view_model.title_color),
        view_model.subtitle,
        tostring(view_model.subtitle_color),
        view_model.footer,
        tostring(view_model.footer_color),
        view_model.icon and view_model.icon.text or "",
        tostring(#view_model.lines),
    }

    for _, line in ipairs(view_model.lines) do
        parts[#parts + 1] = line.id
        parts[#parts + 1] = line.text
        parts[#parts + 1] = tostring(line.color)
    end

    return table.concat(parts, "|")
end

local function hud_elem_type(def)
    return def and (def.type or def.hud_elem_type)
end

local function ensure_hud_slot(player, hud_ids, key, expected_type, spec)
    local id = hud_ids[key]

    if id then
        local def = player:hud_get(id)

        if not def or hud_elem_type(def) ~= expected_type then
            if def then
                player:hud_remove(id)
            end

            hud_ids[key] = nil
            id = nil
        end
    end

    if not id then
        hud_ids[key] = player:hud_add(spec)
    end
end

function eye_spy.render.ensure_hud(state, player)
    local hud_ids = state.hud_ids

    ensure_hud_slot(player, hud_ids, "bg", "image", {
        type = "image",
        position = { x = 0.5, y = 0 },
        offset = { x = 0, y = 0 },
        text = "",
        scale = { x = 400, y = 82 },
        alignment = { x = 0, y = 0 },
        z_index = 1,
    })

    ensure_hud_slot(player, hud_ids, "icon", "image", {
        type = "image",
        position = { x = 0.5, y = 0 },
        offset = { x = 0, y = 0 },
        text = "",
        scale = { x = 3.5, y = 3.5 },
        alignment = { x = 0, y = 0 },
        z_index = 2,
    })

    ensure_hud_slot(player, hud_ids, "title", "text", {
        type = "text",
        position = { x = 0.5, y = 0 },
        offset = { x = 0, y = 0 },
        text = "",
        number = 0xFFFFFF,
        alignment = { x = 1, y = 0 },
        z_index = 2,
    })

    ensure_hud_slot(player, hud_ids, "subtitle", "text", {
        type = "text",
        position = { x = 0.5, y = 0 },
        offset = { x = 0, y = 0 },
        text = "",
        number = 0xEBB344,
        alignment = { x = 1, y = 0 },
        z_index = 2,
    })

    ensure_hud_slot(player, hud_ids, "footer", "text", {
        type = "text",
        position = { x = 0.5, y = 0 },
        offset = { x = 0, y = 0 },
        text = "",
        number = 0x4343F0,
        alignment = { x = 1, y = 0 },
        z_index = 2,
    })
end

function eye_spy.render.ensure_line_slots(state, player, count)
    local line_ids = state.hud_ids.lines

    for i = 1, #line_ids do
        local id = line_ids[i]
        local def = id and player:hud_get(id)

        if not def or hud_elem_type(def) ~= "text" then
            if def then
                player:hud_remove(id)
            end

            line_ids[i] = player:hud_add({
                type = "text",
                position = { x = 0.5, y = 0 },
                offset = { x = 0, y = 0 },
                text = "",
                number = 0xFFFFFF,
                alignment = { x = 1, y = 0 },
                z_index = 2,
            })
        end
    end

    while #line_ids < count do
        line_ids[#line_ids + 1] = player:hud_add({
            type = "text",
            position = { x = 0.5, y = 0 },
            offset = { x = 0, y = 0 },
            text = "",
            number = 0xFFFFFF,
            alignment = { x = 1, y = 0 },
            z_index = 2,
        })
    end
end

function eye_spy.render.hide(state, player)
    if not state or not state.hud_ids.bg then
        return
    end

    local hud_ids = state.hud_ids

    player:hud_change(hud_ids.bg, "text", "")
    player:hud_change(hud_ids.icon, "text", "")
    player:hud_change(hud_ids.title, "text", "")
    player:hud_change(hud_ids.subtitle, "text", "")
    player:hud_change(hud_ids.footer, "text", "")

    for _, line_id in ipairs(hud_ids.lines) do
        player:hud_change(line_id, "text", "")
    end
end

function eye_spy.render.remove(player)
    local state = eye_spy.get_player_state(player)
    local hud_ids = state.hud_ids

    for key, value in pairs(hud_ids) do
        if key == "lines" then
            for _, line_id in ipairs(value) do
                if line_id and player:hud_get(line_id) then
                    player:hud_remove(line_id)
                end
            end
        elseif value and player:hud_get(value) then
            player:hud_remove(value)
        end
    end

    state.hud_ids = { lines = {} }
    state.last_render_key = nil
    state.last_geom_key = nil
end

function eye_spy.render.build_view_model(player, target, opts)
    local perf_on = eye_spy.perf and eye_spy.perf.enabled and minetest.get_us_time
    local phase_start_us = perf_on and minetest.get_us_time() or 0
    local meta = player:get_meta()
    local options = opts or {}
    local draft = get_player_draft(player)
    local effective_meta = meta

    if draft then
        effective_meta = {
            get_string = function(_, key)
                return get_effective_string(meta, draft, key)
            end,
            get_int = function(_, key)
                return get_effective_int(meta, draft, key)
            end,
        }
    end

    local r, g, b = eye_spy.get_rgb(get_effective_string(meta, draft, "es_hud_color"))
    local bg_luminance = get_bg_luminance_rgb(r or 26, g or 26, b or 27)
    local bg_color_int = join_rgb(r or 26, g or 26, b or 27)
    local auto_text = get_effective_string(meta, draft, "es_auto_text_color") ~= "false"
    local footer_mode = get_effective_string(meta, draft, "es_footer_mode")
    local show_coords = get_effective_string(meta, draft, "es_show_coords") ~= "false"
    local footer_text
    local coords_text = show_coords and ("  " .. position_text(target.pos)) or ""

    if footer_mode == "advanced" then
        local full_name = target.full_name or target.name or S("Unknown")
        footer_text = "[" .. full_name .. "] [" .. (target.modname or S("Unknown")) .. "]" .. coords_text
    else
        footer_text = "[" .. (target.modname or S("Unknown")) .. "]" .. coords_text
    end

    local view_model = {
        visible = target.kind ~= "air",
        layout = get_effective_string(meta, draft, "es_hud_alignment") ~= "" and
            get_effective_string(meta, draft, "es_hud_alignment") or "Top-Middle",
        bg_color = eye_spy.rgb_to_hex(r or 26, g or 26, b or 27),
        title = target.description or target.name or S("Unknown"),
        title_color = 0xFFFFFF,
        subtitle = target.kind == "entity" and S("Entity") or (target.kind == "item" and S("Item") or S("Node")),
        subtitle_color = 0xF2D23C,
        footer = footer_text,
        footer_color = 0x4C7EE8,
        lines = {},
        layout_signature = draft and get_layout_signature_from_values(meta, draft) or
            get_layout_signature(meta, player:get_player_name()),
    }

    if get_effective_string(meta, draft, "es_show_icons") ~= "false" then
        local icon_size = clamp(get_effective_int(meta, draft, "es_icon_size"), 16, 128)

        if icon_size <= 0 then
            icon_size = ICON_DISPLAY_SIZE
        end

        view_model.icon = {
            text = texture_text(target),
            scale = { x = icon_size / ICON_TEXTURE_SIZE, y = icon_size / ICON_TEXTURE_SIZE },
        }
    end

    eye_spy.enrichers.run({ player = player, meta = effective_meta, preview = options.preview }, target, view_model)
    if perf_on then
        eye_spy.perf_record("build_vm_enrichers", minetest.get_us_time() - phase_start_us)
        phase_start_us = minetest.get_us_time()
    end

    local show_growth = get_effective_string(meta, draft, "es_show_growth") ~= "false"

    if options.preview and target.kind == "node" then
        if show_growth and not has_line(view_model, "growth") then
            view_model.lines[#view_model.lines + 1] = {
                id = "growth",
                text = S("Growth") .. ": " .. S("Preview Sample"),
                color = 0x55FF55,
            }
        end

        if show_growth and not has_line(view_model, "soil") then
            view_model.lines[#view_model.lines + 1] = {
                id = "soil",
                text = S("Soil") .. ": " .. S("Preview Sample"),
                color = 0xD8B46A,
            }
        end
    end

    if auto_text then
        local base_text = best_monochrome_for_bg(bg_color_int)

        view_model.title_color = base_text
        -- Subtitle/footer: preserve semantic colour (amber for tool, red for health,
        -- blue for footer) and nudge toward readable contrast without snapping to
        -- a monochrome fallback.
        view_model.subtitle_color = nudge_contrast(
            tune_contrast_preserve_hue(view_model.subtitle_color, bg_color_int, 3.6),
            bg_color_int, 3.8
        )
        view_model.footer_color = nudge_contrast(
            tune_contrast_preserve_hue(view_model.footer_color, bg_color_int, 3.6),
            bg_color_int, 3.8
        )

        for _, line in ipairs(view_model.lines) do
            if line.id == "growth" or line.id == "soil" then
                line.color = adjust_semantic_line_color(line.color, bg_color_int)
            else
                line.color = get_auto_line_accent(line.id, view_model.bg_color, bg_color_int, base_text, bg_luminance)
            end
        end
    else
        view_model.title_color = spectrum_color(get_effective_int(meta, draft, "es_title_color_val"))
        view_model.subtitle_color = spectrum_color(get_effective_int(meta, draft, "es_subtitle_color_val"))
        view_model.footer_color = spectrum_color(get_effective_int(meta, draft, "es_footer_color_val"))

        for _, line in ipairs(view_model.lines) do
            if line.id == "growth" or line.id == "soil" then
                line.color = adjust_semantic_line_color(line.color, bg_color_int)
            else
                line.color = spectrum_color(get_effective_int(meta, draft, "es_line_color_val"))
            end
        end
    end

    if perf_on then
        eye_spy.perf_record("build_vm_color_pass", minetest.get_us_time() - phase_start_us)
        phase_start_us = minetest.get_us_time()
    end

    view_model.key = build_key(view_model)

    if perf_on then
        eye_spy.perf_record("build_vm_key_build", minetest.get_us_time() - phase_start_us)
    end

    return view_model
end

function eye_spy.render.apply(state, player, view_model)
    local layout_lines, visible_line_rows = build_layout_lines(view_model)

    eye_spy.render.ensure_hud(state, player)
    eye_spy.render.ensure_line_slots(state, player, visible_line_rows)

    local meta = player:get_meta()
    local draft = get_player_draft(player)
    local layout = layouts[view_model.layout] or layouts["Top-Middle"]
    local line_count = visible_line_rows
    local global_offset_x = get_effective_int(meta, draft, "es_global_offset_x")
    local global_offset_y = get_effective_int(meta, draft, "es_global_offset_y")
    local bg_offset_x = get_effective_int(meta, draft, "es_bg_offset_x")
    local bg_offset_y = get_effective_int(meta, draft, "es_bg_offset_y")
    local icon_offset_x = get_effective_int(meta, draft, "es_icon_offset_x")
    local icon_offset_y = get_effective_int(meta, draft, "es_icon_offset_y")
    local title_offset_x = get_effective_int(meta, draft, "es_title_offset_x")
    local title_offset_y = get_effective_int(meta, draft, "es_title_offset_y")
    local subtitle_offset_x = get_effective_int(meta, draft, "es_subtitle_offset_x")
    local subtitle_offset_y = get_effective_int(meta, draft, "es_subtitle_offset_y")
    local lines_offset_x = get_effective_int(meta, draft, "es_lines_offset_x")
    local lines_offset_y = get_effective_int(meta, draft, "es_lines_offset_y")
    local footer_offset_x = get_effective_int(meta, draft, "es_footer_offset_x")
    local footer_offset_y = get_effective_int(meta, draft, "es_footer_offset_y")
    local bg_pad_left = get_effective_int(meta, draft, "es_bg_pad_left")
    local bg_pad_right = get_effective_int(meta, draft, "es_bg_pad_right")
    local bg_pad_top = get_effective_int(meta, draft, "es_bg_pad_top")
    local bg_pad_bottom = get_effective_int(meta, draft, "es_bg_pad_bottom")
    local bg_extra_w = get_effective_int(meta, draft, "es_bg_extra_w")
    local bg_extra_h = get_effective_int(meta, draft, "es_bg_extra_h")
    local text_base_x_adj = get_effective_int(meta, draft, "es_text_base_x_adj")
    local icon_base_x_adj = get_effective_int(meta, draft, "es_icon_base_x_adj")
    local top_margin_adj = get_effective_int(meta, draft, "es_top_margin_adj")
    local bottom_margin_adj = get_effective_int(meta, draft, "es_bottom_margin_adj")

    local title_y = 16 + title_offset_y
    local subtitle_y = 34 + subtitle_offset_y
    local first_line_y = 52 + get_effective_int(meta, draft, "es_first_line_y_adj")
    local line_step = math.max(10, 18 + get_effective_int(meta, draft, "es_line_step_adj"))
    local footer_nudge = -10 + get_effective_int(meta, draft, "es_footer_nudge_adj")
    local footer_y = first_line_y + (line_count * line_step) + 10 + footer_nudge

    local content_top = title_y - 8 - bg_pad_top
    local content_bottom = footer_y + 22 + bg_pad_bottom
    local base_footer_y = first_line_y + (BASE_LAYOUT_LINE_ROWS * line_step) + 10 + footer_nudge
    local base_content_bottom = base_footer_y + 22 + bg_pad_bottom
    local base_bg_height = (base_content_bottom - content_top) + bg_extra_h
    local max_bg_height = math.max(52, math.floor(base_bg_height * MAX_LAYOUT_SCALE_FACTOR))
    local bg_height = (content_bottom - content_top) + bg_extra_h
    local bg_width = estimate_panel_width(view_model, layout_lines) + bg_pad_left + bg_pad_right + bg_extra_w
    local top_screen_margin = 10 + top_margin_adj
    local bottom_screen_margin = 22 + bottom_margin_adj

    bg_height = clamp(bg_height, 52, max_bg_height)
    bg_width = clamp(bg_width, 240, 1260)

    local origin_y

    if layout.y_mode == "top" then
        origin_y = top_screen_margin
    elseif layout.y_mode == "middle" then
        origin_y = -math.floor(bg_height / 2)
    else
        origin_y = -(bg_height + bottom_screen_margin)
    end

    origin_y = origin_y + global_offset_y

    local center_x = global_offset_x

    if layout.x_mode == "right" then
        center_x = -math.floor(bg_width / 2) - 16
    elseif layout.x_mode == "left" then
        center_x = math.floor(bg_width / 2) + 16
    end

    local left_edge_x = center_x - math.floor(bg_width / 2)
    local icon_x = left_edge_x + 28 + bg_pad_left + icon_base_x_adj + icon_offset_x
    local text_x = left_edge_x + (view_model.icon and 68 or 16) + bg_pad_left + text_base_x_adj

    local bg_scale_x_pct = clamp(get_effective_int(meta, draft, "es_bg_scale_x_pct"), 25, 300)
    local bg_scale_y_pct = clamp(get_effective_int(meta, draft, "es_bg_scale_y_pct"), 25, 300)
    local bg_draw_w = math.max(1, math.floor(bg_width * (bg_scale_x_pct / 100)))
    local bg_draw_h = math.max(1, math.floor(bg_height * (bg_scale_y_pct / 100)))

    local title_scale = clamp(get_effective_int(meta, draft, "es_title_scale_pct"), 40, 300) / 100
    local subtitle_scale = clamp(get_effective_int(meta, draft, "es_subtitle_scale_pct"), 40, 300) / 100
    local line_scale = clamp(get_effective_int(meta, draft, "es_line_scale_pct"), 40, 300) / 100
    local footer_scale = clamp(get_effective_int(meta, draft, "es_footer_scale_pct"), 40, 300) / 100

    local bg_center_y = origin_y + math.floor(bg_height / 2) - bg_pad_top

    -- Geometry channel: position, offset, scale.
    -- Only sent when layout or panel dimensions actually changed.
    local geom_key = (view_model.layout or "")
        .. "|" .. (view_model.layout_signature or "")
        .. "|" .. tostring(bg_draw_w)
        .. "|" .. tostring(bg_draw_h)
        .. "|" .. tostring(line_count)
        .. "|" .. (view_model.icon and tostring(math.floor(view_model.icon.scale.x * 64)) or "0")

    if geom_key ~= (state.last_geom_key or "") then
        state.last_geom_key = geom_key

        player:hud_change(state.hud_ids.bg, "position", layout.pos)
        player:hud_change(state.hud_ids.bg, "offset", { x = center_x + bg_offset_x, y = bg_center_y + bg_offset_y })
        player:hud_change(state.hud_ids.bg, "scale", { x = bg_draw_w, y = bg_draw_h })

        player:hud_change(state.hud_ids.title, "position", layout.pos)
        player:hud_change(state.hud_ids.title, "offset", { x = text_x + title_offset_x, y = origin_y + title_y })
        player:hud_change(state.hud_ids.title, "scale", { x = title_scale, y = title_scale })

        player:hud_change(state.hud_ids.subtitle, "position", layout.pos)
        player:hud_change(state.hud_ids.subtitle, "offset", { x = text_x + subtitle_offset_x, y = origin_y + subtitle_y })
        player:hud_change(state.hud_ids.subtitle, "scale", { x = subtitle_scale, y = subtitle_scale })

        player:hud_change(state.hud_ids.footer, "position", layout.pos)
        player:hud_change(state.hud_ids.footer, "offset",
            { x = text_x + footer_offset_x, y = origin_y + footer_y + footer_offset_y })
        player:hud_change(state.hud_ids.footer, "scale", { x = footer_scale, y = footer_scale })

        if view_model.icon then
            player:hud_change(state.hud_ids.icon, "position", layout.pos)
            player:hud_change(state.hud_ids.icon, "offset", { x = icon_x, y = origin_y + 34 + icon_offset_y })
            player:hud_change(state.hud_ids.icon, "scale", view_model.icon.scale)
        end

        -- Geometry for all allocated line slots so new/reactivated slots are positioned correctly.
        for index, line_id in ipairs(state.hud_ids.lines) do
            player:hud_change(line_id, "position", layout.pos)
            player:hud_change(line_id, "offset", {
                x = text_x + lines_offset_x,
                y = origin_y + first_line_y + ((index - 1) * line_step) + lines_offset_y,
            })
            player:hud_change(line_id, "scale", { x = line_scale, y = line_scale })
        end
    end

    -- Content channel: text, number/color -- always applied when view_model changed.
    player:hud_change(state.hud_ids.bg, "text", "eye_spy_hud_bg.png^[multiply:#" .. view_model.bg_color)

    player:hud_change(state.hud_ids.title, "text", view_model.title)
    player:hud_change(state.hud_ids.title, "number", view_model.title_color)

    player:hud_change(state.hud_ids.subtitle, "text", view_model.subtitle)
    player:hud_change(state.hud_ids.subtitle, "number", view_model.subtitle_color)

    player:hud_change(state.hud_ids.footer, "text", view_model.footer)
    player:hud_change(state.hud_ids.footer, "number", view_model.footer_color)

    if view_model.icon then
        player:hud_change(state.hud_ids.icon, "text", view_model.icon.text)
    else
        player:hud_change(state.hud_ids.icon, "text", "")
    end

    for index, line_id in ipairs(state.hud_ids.lines) do
        local line = layout_lines[index]

        if line then
            player:hud_change(line_id, "text", line.text)
            player:hud_change(line_id, "number", line.color)
        else
            player:hud_change(line_id, "text", "")
        end
    end
end
