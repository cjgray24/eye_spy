-- colors.lua
-- Pure color math utilities for eye_spy.
-- No minetest API calls: safe to use from any context.

eye_spy.colors = {}

-- ---------------------------------------------------------------------------
-- Clamp
-- ---------------------------------------------------------------------------

--- Clamp v to [minv, maxv].
local function clamp(v, minv, maxv)
    return math.max(minv, math.min(maxv, v))
end

-- ---------------------------------------------------------------------------
-- RGB packing / unpacking
-- ---------------------------------------------------------------------------

--- Split a packed 24-bit integer into its R, G, B byte components.
local function split_rgb(color)
    local r = math.floor(color / 65536) % 256
    local g = math.floor(color / 256) % 256
    local b = color % 256
    return r, g, b
end

--- Pack R, G, B byte components into a 24-bit integer.
local function join_rgb(r, g, b)
    return (r * 65536) + (g * 256) + b
end

-- ---------------------------------------------------------------------------
-- Luminance helpers
-- ---------------------------------------------------------------------------

--- Linearise a single 0–255 channel value for WCAG relative-luminance maths.
local function channel_luminance(channel)
    local c = channel / 255

    if c <= 0.03928 then
        return c / 12.92
    end

    return ((c + 0.055) / 1.055) ^ 2.4
end

--- WCAG 2.1 relative luminance of a packed 24-bit RGB integer.
local function color_luminance(color)
    local r, g, b = split_rgb(color)

    return (0.2126 * channel_luminance(r))
        + (0.7152 * channel_luminance(g))
        + (0.0722 * channel_luminance(b))
end

--- WCAG 2.1 contrast ratio between two packed 24-bit colours.
local function contrast_ratio(color_a, color_b)
    local a_l = color_luminance(color_a)
    local b_l = color_luminance(color_b)

    return (math.max(a_l, b_l) + 0.05) / (math.min(a_l, b_l) + 0.05)
end

-- ---------------------------------------------------------------------------
-- Colour arithmetic
-- ---------------------------------------------------------------------------

--- Multiply every channel of a packed colour by factor and re-pack.
local function scale_color(color, factor)
    local r, g, b = split_rgb(color)
    r = clamp(math.floor(r * factor), 0, 255)
    g = clamp(math.floor(g * factor), 0, 255)
    b = clamp(math.floor(b * factor), 0, 255)
    return join_rgb(r, g, b)
end

--- Linear interpolation between two packed colours.
-- t = 0 → color_a, t = 1 → color_b.
local function blend_color(color_a, color_b, t)
    local factor = clamp(t or 0.5, 0, 1)
    local ar, ag, ab = split_rgb(color_a)
    local br, bg, bb = split_rgb(color_b)

    return join_rgb(
        math.floor((ar * (1 - factor)) + (br * factor) + 0.5),
        math.floor((ag * (1 - factor)) + (bg * factor) + 0.5),
        math.floor((ab * (1 - factor)) + (bb * factor) + 0.5)
    )
end

-- ---------------------------------------------------------------------------
-- HSL conversion
-- ---------------------------------------------------------------------------

--- Convert R, G, B bytes to HSL (hue 0–360, saturation 0–1, lightness 0–1).
local function rgb_to_hsl(r, g, b)
    local rn, gn, bn = r / 255, g / 255, b / 255
    local max_c = math.max(rn, gn, bn)
    local min_c = math.min(rn, gn, bn)
    local l = (max_c + min_c) * 0.5

    if max_c == min_c then
        return 0, 0, l
    end

    local d = max_c - min_c
    local s = l > 0.5 and d / (2 - max_c - min_c) or d / (max_c + min_c)
    local h

    if max_c == rn then
        h = ((gn - bn) / d) % 6
    elseif max_c == gn then
        h = (bn - rn) / d + 2
    else
        h = (rn - gn) / d + 4
    end

    return (h / 6) * 360, s, l
end

-- Hoisted helper for hsl_to_rgb — avoids allocating a new closure per call.
-- Converts a hue position p/q at offset t (all normalised 0–1) to a channel value.
local function hue2rgb(p, q, t)
    t = t % 1.0
    if t < 1 / 6 then return p + (q - p) * 6 * t end
    if t < 1 / 2 then return q end
    if t < 2 / 3 then return p + (q - p) * (2 / 3 - t) * 6 end
    return p
end

--- Convert HSL (hue 0–360, saturation 0–1, lightness 0–1) to R, G, B bytes.
local function hsl_to_rgb(h, s, l)
    if s <= 0 then
        local v = clamp(math.floor(l * 255 + 0.5), 0, 255)
        return v, v, v
    end

    h = h / 360
    local q = l < 0.5 and l * (1 + s) or l + s - l * s
    local p = 2 * l - q

    return clamp(math.floor(hue2rgb(p, q, h + 1 / 3) * 255 + 0.5), 0, 255),
        clamp(math.floor(hue2rgb(p, q, h) * 255 + 0.5), 0, 255),
        clamp(math.floor(hue2rgb(p, q, h - 1 / 3) * 255 + 0.5), 0, 255)
end

-- ---------------------------------------------------------------------------
-- Background luminance (BT.601 perceived brightness, not WCAG)
-- ---------------------------------------------------------------------------

--- Perceived brightness (BT.601) from R, G, B bytes (0–255 range).
-- Returns a value in [0, 255].
local function get_bg_luminance_rgb(r, g, b)
    return (r * 0.299) + (g * 0.587) + (b * 0.114)
end

--- Perceived brightness (BT.601) from a 6-character lowercase hex string
-- such as "1a1a1b".  Returns a value in [0, 255].
local function get_bg_luminance(rgb_hex)
    local r = tonumber(rgb_hex:sub(1, 2), 16) or 26
    local g = tonumber(rgb_hex:sub(3, 4), 16) or 26
    local b = tonumber(rgb_hex:sub(5, 6), 16) or 27
    return get_bg_luminance_rgb(r, g, b)
end

-- ---------------------------------------------------------------------------
-- Foreground selection helpers
-- ---------------------------------------------------------------------------

--- Return whichever of near-black or near-white has the higher contrast ratio
-- against bg_color (packed 24-bit integer).
local function best_monochrome_for_bg(bg_color)
    local dark  = 0x111111
    local light = 0xF0F0F0

    if contrast_ratio(light, bg_color) >= contrast_ratio(dark, bg_color) then
        return light
    end

    return dark
end

--- Map a value in [0, 255] to a spectrum colour (red → green → blue → white).
local function spectrum_color(val)
    local v = clamp(val or 255, 0, 255)
    local r, g, b = 0, 0, 0

    if v < 85 then
        r = 255 - (v * 3)
        g = v * 3
    elseif v < 170 then
        local x = v - 85
        g = 255 - (x * 3)
        b = x * 3
    elseif v < 230 then
        local x = v - 170
        r = x * 4
        b = 255 - (x * 4)
    else
        local x = math.floor((v - 230) * (255 / 25))
        r, g, b = x, x, x
    end

    return join_rgb(r, g, b)
end

--- Darken color when the background (given as a hex string) is light,
-- so the colour remains legible.
-- Uses get_bg_luminance_rgb + split_rgb to avoid duplicating the BT.601 formula.
local function adapt_for_bg(color, bg_hex)
    if get_bg_luminance(bg_hex) <= 140 then
        return color
    end

    local luminance = get_bg_luminance_rgb(split_rgb(color))

    if luminance > 130 then
        return scale_color(color, 0.45)
    end

    return color
end

--- Iteratively blend color toward black or white until it reaches min_ratio
-- contrast against bg_color.  Makes up to 5 nudge passes.
local function nudge_contrast(color, bg_color, min_ratio)
    local candidate = color
    local bg_l = color_luminance(bg_color)

    for _ = 1, 5 do
        if contrast_ratio(candidate, bg_color) >= (min_ratio or 4.5) then
            return candidate
        end

        local fg_l = color_luminance(candidate)

        if fg_l < bg_l then
            candidate = blend_color(candidate, 0x000000, 0.32)
        else
            candidate = blend_color(candidate, 0xFFFFFF, 0.32)
        end
    end

    return candidate
end

--- Adjust color to meet min_ratio contrast against bg_color while
-- preserving hue by blending toward white or black (whichever gives
-- the better contrast) in up to 8 steps.
local function tune_contrast_preserve_hue(color, bg_color, min_ratio)
    local required_ratio = min_ratio or 4.0
    local candidate = color

    if contrast_ratio(candidate, bg_color) >= required_ratio then
        return candidate
    end

    for step = 1, 8 do
        if contrast_ratio(candidate, bg_color) >= required_ratio then
            return candidate
        end

        local t       = clamp(step * 0.09, 0, 0.70)
        local lighter = blend_color(color, 0xFFFFFF, t)
        local darker  = blend_color(color, 0x000000, t)

        if contrast_ratio(lighter, bg_color) >= contrast_ratio(darker, bg_color) then
            candidate = lighter
        else
            candidate = darker
        end
    end

    return candidate
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

eye_spy.colors.clamp                      = clamp
eye_spy.colors.split_rgb                  = split_rgb
eye_spy.colors.join_rgb                   = join_rgb
eye_spy.colors.channel_luminance          = channel_luminance
eye_spy.colors.color_luminance            = color_luminance
eye_spy.colors.contrast_ratio             = contrast_ratio
eye_spy.colors.scale_color                = scale_color
eye_spy.colors.blend_color                = blend_color
eye_spy.colors.rgb_to_hsl                 = rgb_to_hsl
eye_spy.colors.hsl_to_rgb                 = hsl_to_rgb
eye_spy.colors.get_bg_luminance_rgb       = get_bg_luminance_rgb
eye_spy.colors.get_bg_luminance           = get_bg_luminance
eye_spy.colors.best_monochrome_for_bg     = best_monochrome_for_bg
eye_spy.colors.spectrum_color             = spectrum_color
eye_spy.colors.adapt_for_bg               = adapt_for_bg
eye_spy.colors.nudge_contrast             = nudge_contrast
eye_spy.colors.tune_contrast_preserve_hue = tune_contrast_preserve_hue
