-- eye_spy/config.lua
-- Loads all mod settings from minetest.settings and exposes them as
-- eye_spy.config.  Also handles the one-time migration of the legacy
-- eye_spy.update_interval (seconds) setting into the ms-based storage key
-- used by the interval system defined in functions.lua.
--
-- Load order requirement: runs AFTER eye_spy = {} is declared in functions.lua,
-- so eye_spy, eye_spy.storage, and eye_spy.set_server_default_interval_ms are
-- all guaranteed to be available here.

-- ---------------------------------------------------------------------------
-- Internal helpers
-- ---------------------------------------------------------------------------

-- Map the human-readable texture_pack_size enum value to a pixel count, or
-- nil when the user has not forced a size (i.e. the "None" default).
local TEXTURE_SIZE_MAP = {
    ["None"]        = nil,
    ["1x1px"]       = 1,
    ["2x2px"]       = 2,
    ["4x4px"]       = 4,
    ["8x8px"]       = 8,
    ["16x16px"]     = 16,
    ["32x32px"]     = 32,
    ["64x64px"]     = 64,
    ["128x128px"]   = 128,
    ["256x256px"]   = 256,
    ["512x512px"]   = 512,
    ["1024x1024px"] = 1024,
}

-- ---------------------------------------------------------------------------
-- Raw setting reads
-- (each variable is local to this file; the canonical values live in
--  eye_spy.config so the rest of the mod always reads from one place)
-- ---------------------------------------------------------------------------

local settings = minetest.settings

-- Texture pack size enum (raw string, used both stored and for derived value)
local texture_pack_size_raw = settings:get("eye_spy.texture_pack_size") or "None"

-- ---------------------------------------------------------------------------
-- eye_spy.config
-- ---------------------------------------------------------------------------
-- Every entry is documented so server admins can understand what each key
-- controls by reading this file alone.

eye_spy.config = {

    -- -------------------------------------------------------------------------
    -- Entity / liquid display
    -- -------------------------------------------------------------------------

    -- Whether to show entity info (health, name) when looking at a mob or
    -- dropped item.  Corresponds to eye_spy.show_entities in settings.
    show_entities = settings:get_bool("eye_spy.show_entities") ~= false,

    -- Whether liquid-aware targeting is active.  When true Eye Spy can scan
    -- through liquid blocks and still show what is behind them.
    -- Corresponds to eye_spy.show_liquids in settings.
    show_liquids = settings:get_bool("eye_spy.show_liquids") or false,

    -- -------------------------------------------------------------------------
    -- Creative / tool display
    -- -------------------------------------------------------------------------

    -- When true the HUD always shows "Hand" as the wielded tool while the
    -- player is in creative mode, regardless of what is actually held.
    -- Corresponds to eye_spy.always_show_hand_in_creative in settings.
    always_show_hand_in_creative = settings:get_bool("eye_spy.always_show_hand_in_creative") ~= false,

    -- -------------------------------------------------------------------------
    -- Texture / icon sizing
    -- -------------------------------------------------------------------------

    -- The raw enum string chosen by the admin ("None", "16x16px", etc.).
    -- Stored here for reference; use forced_texture_size for numeric logic.
    texture_pack_size = texture_pack_size_raw,

    -- Numeric pixel size derived from texture_pack_size, or nil when no size
    -- is forced.  When mod_security is false the engine can determine sizes
    -- automatically; this override is intended for texture packs that lie
    -- about their resolution.
    forced_texture_size = TEXTURE_SIZE_MAP[texture_pack_size_raw],

    -- Absolute path to the active texture pack directory as reported by the
    -- engine.  May be nil when no texture pack is in use.  Used to resolve
    -- icon paths at runtime.  Corresponds to texture_path in settings.
    texture_pack_path = settings:get("texture_path"),

    -- -------------------------------------------------------------------------
    -- Security
    -- -------------------------------------------------------------------------

    -- Mirror of secure.enable_security.  When true, certain filesystem
    -- operations (e.g. automatic icon-size detection) are restricted by the
    -- engine sandbox and Eye Spy falls back to the admin-configured size.
    mod_security = settings:get_bool("secure.enable_security") == true,

    -- -------------------------------------------------------------------------
    -- Update interval (legacy float, seconds)
    -- The authoritative runtime value is stored in mod storage as
    -- "server_default_interval_ms" and managed by the interval API in
    -- functions.lua.  This field is retained only for the one-time migration
    -- performed at the bottom of this file.
    -- -------------------------------------------------------------------------

    -- How often (in seconds) the HUD was refreshed under the old single-float
    -- scheme.  Default 0.25 s = 250 ms.
    -- Corresponds to eye_spy.update_interval in settings.
    update_interval = tonumber(settings:get("eye_spy.update_interval")) or 0.1,

    -- -------------------------------------------------------------------------
    -- Performance metrics
    -- -------------------------------------------------------------------------

    -- Whether the lightweight perf-metrics system starts enabled.  Can be
    -- toggled at runtime via /eye_spy_perf without changing this setting.
    -- Corresponds to eye_spy.enable_perf_metrics in settings.
    perf_metrics_enabled = settings:get_bool("eye_spy.enable_perf_metrics") or false,

    -- -------------------------------------------------------------------------
    -- Growth / plant display
    -- -------------------------------------------------------------------------

    -- When true Eye Spy shows growth-stage and soil-status lines for nodes
    -- that expose supported plant/sapling metadata.
    -- Corresponds to eye_spy.show_growth in settings.
    show_growth = settings:get_bool("eye_spy.show_growth") ~= false,

    -- -------------------------------------------------------------------------
    -- Icon display
    -- -------------------------------------------------------------------------

    -- When true a small icon representing the targeted node or entity is shown
    -- in the HUD alongside the text lines.
    -- Corresponds to eye_spy.show_icons in settings.
    show_icons = settings:get_bool("eye_spy.show_icons") ~= false,

    -- -------------------------------------------------------------------------
    -- Per-player HUD element defaults (applied on first join)
    -- These values are written into player meta the first time a player joins
    -- and can be changed per-player at runtime.  Changing these settings only
    -- affects players who have never joined before (or whose meta was reset).
    -- -------------------------------------------------------------------------

    -- Show coordinates in the HUD footer.
    -- Corresponds to eye_spy.default_show_coords in settings.
    default_show_coords = settings:get_bool("eye_spy.default_show_coords") or false,

    -- Show the ambient light level at the player's position.
    -- Corresponds to eye_spy.default_show_light_level in settings.
    default_show_light_level = settings:get_bool("eye_spy.default_show_light_level") ~= false,

    -- Show the mob-spawning hint line (indicates whether the light level is
    -- low enough for hostile mobs to spawn nearby).
    -- Corresponds to eye_spy.default_show_spawn_hint in settings.
    default_show_spawn_hint = settings:get_bool("eye_spy.default_show_spawn_hint") or false,

    -- Show the liquid-info line when looking at or through a liquid node.
    -- Corresponds to eye_spy.default_show_liquid_info in settings.
    default_show_liquid_info = settings:get_bool("eye_spy.default_show_liquid_info") ~= false,

    -- Show the estimated dig-time line for the targeted node.
    -- Corresponds to eye_spy.default_show_dig_time in settings.
    default_show_dig_time = settings:get_bool("eye_spy.default_show_dig_time") ~= false,

    -- Background opacity (alpha) for the HUD panel. 0 = fully transparent,
    -- 255 = fully opaque. Corresponds to eye_spy.default_bg_alpha in settings.
    default_bg_alpha = tonumber(settings:get("eye_spy.default_bg_alpha")) or 200,

    -- -------------------------------------------------------------------------
    -- Content rows (extra HUD rows for mod integrations)
    -- -------------------------------------------------------------------------
    -- When true, Eye Spy renders optional content rows below the standard
    -- info lines.  Each row is an array of {type="image"|"text", ...}
    -- elements supplied by external enrichers via view_model.content_rows.
    -- Corresponds to eye_spy.show_content_rows in settings.
    show_content_rows = settings:get_bool("eye_spy.show_content_rows") ~= false,

    -- Pixel size of the small item icons shown inside content rows.
    -- Corresponds to eye_spy.content_row_icon_size in settings.
    content_row_icon_size = tonumber(settings:get("eye_spy.content_row_icon_size")) or 16,

    -- Horizontal offset (in pixels) applied to content row elements.
    -- Corresponds to eye_spy.content_row_offset_x in settings.
    content_row_offset_x = tonumber(settings:get("eye_spy.content_row_offset_x")) or 0,

    -- Vertical offset (in pixels) applied to content row elements.
    -- Corresponds to eye_spy.content_row_offset_y in settings.
    content_row_offset_y = tonumber(settings:get("eye_spy.content_row_offset_y")) or 0,

    -- Horizontal padding (in pixels) between elements inside the same row.
    -- Corresponds to eye_spy.content_row_element_padding in settings.
    content_row_element_padding = tonumber(settings:get("eye_spy.content_row_element_padding")) or 4,

    -- Extra gap (in pixels) between the icon and the first text element
    -- inside a content row.  Added on top of element_padding so the
    -- icon is visually separated from the label.
    -- Corresponds to eye_spy.content_row_icon_text_gap in settings.
    content_row_icon_text_gap = tonumber(settings:get("eye_spy.content_row_icon_text_gap")) or 16,

    -- Vertical step (in pixels) between consecutive content rows.
    -- Corresponds to eye_spy.content_row_step in settings.
    content_row_step = tonumber(settings:get("eye_spy.content_row_step")) or 18,
}

-- ---------------------------------------------------------------------------
-- Legacy update_interval migration
-- ---------------------------------------------------------------------------
-- Older versions of this mod stored the refresh rate as a plain float (in
-- seconds) in the Minetest settings file.  The current interval system keeps
-- its authoritative value in mod storage as "server_default_interval_ms".
--
-- If the storage key is not yet set (first run after upgrade, or a clean
-- install where the admin copied over an old minetest.conf), and the legacy
-- setting was given a non-zero value, convert it to milliseconds and write it
-- into storage via the public API so the interval system picks it up.
-- ---------------------------------------------------------------------------

if eye_spy.storage:get_string("server_default_interval_ms") == "" then
    local legacy_s = eye_spy.config.update_interval

    -- Only migrate an explicitly configured value: skip the bare default (0.25)
    -- unless it was intentionally set.  We detect "intentionally set" by
    -- checking whether the key actually appears in minetest.settings.
    local raw_setting = settings:get("eye_spy.update_interval")

    if raw_setting ~= nil and tonumber(raw_setting) and tonumber(raw_setting) > 0 then
        local ms = math.floor(legacy_s * 1000 + 0.5)

        minetest.log("action", "[eye_spy] Migrating legacy update_interval setting ("
            .. tostring(legacy_s) .. "s → " .. tostring(ms) .. "ms) to mod storage.")

        eye_spy.set_server_default_interval_ms(ms)
    end
end
