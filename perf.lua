-- eye_spy/perf.lua
-- Performance metrics collection module for the eye_spy mod.
-- Extracted from functions.lua; loaded after functions.lua and config.lua.
--
-- Exposes:
--   eye_spy.perf                  (table)  live metrics state
--   eye_spy.perf_set_enabled(b)   enable/disable + persist to storage
--   eye_spy.perf_reset()          clear all samples and counters
--   eye_spy.perf_inc_counter(k,d) increment a named event counter
--   eye_spy.perf_record(k,us)     record a timed sample in microseconds
--   eye_spy.perf_report()         return a formatted report string
--
-- All public functions are no-ops when eye_spy.perf.enabled == false.

-- ---------------------------------------------------------------------------
-- Internal constants
-- ---------------------------------------------------------------------------

-- Maximum number of rolling samples kept per metric.
-- Older samples are overwritten once the ring buffer is full.
local PERF_SAMPLE_CAP = 200

-- ---------------------------------------------------------------------------
-- Initialise eye_spy.perf state
-- ---------------------------------------------------------------------------
-- eye_spy and eye_spy.config are guaranteed to exist at this point.
-- Restore the persisted enabled-flag from mod storage if present;
-- otherwise fall back to the minetest.conf value read in config.lua.

do
    local persisted = eye_spy.storage:get_string("perf_metrics_enabled")
    local enabled

    if persisted == "true" then
        enabled = true
    elseif persisted == "false" then
        enabled = false
    else
        -- No persisted override — use the value from minetest.conf.
        enabled = eye_spy.config.perf_metrics_enabled
    end

    -- Preserve any table that was already created (e.g. by a /lua reload).
    eye_spy.perf          = eye_spy.perf or {}
    eye_spy.perf.enabled  = enabled
    eye_spy.perf.metrics  = eye_spy.perf.metrics or {}
    eye_spy.perf.counters = eye_spy.perf.counters or {}
end

-- ---------------------------------------------------------------------------
-- Local helpers
-- ---------------------------------------------------------------------------

--- Compute the 95th-percentile sample value for a metric.
-- Uses only the samples that have actually been filled so far.
-- @param metric  A metric entry from eye_spy.perf.metrics.
-- @return        The p95 value in microseconds, or 0 if no samples.
local function metric_p95(metric)
    local n = metric and metric.sample_filled or 0

    if n <= 0 then
        return 0
    end

    -- Copy filled samples into a temporary table for sorting.
    local values = {}
    for i = 1, n do
        values[i] = metric.samples[i] or 0
    end

    table.sort(values)

    local idx = math.max(1, math.ceil(n * 0.95))
    return values[idx] or 0
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

--- Enable or disable performance metrics collection and persist the choice.
-- When disabled all other perf functions become no-ops on the next call.
-- @param enabled  boolean — true to enable, false/nil to disable.
function eye_spy.perf_set_enabled(enabled)
    local value = (enabled == true)
    eye_spy.perf.enabled = value
    eye_spy.storage:set_string("perf_metrics_enabled", value and "true" or "false")
end

--- Reset all collected metrics and event counters.
-- Useful before starting a fresh measurement session.
function eye_spy.perf_reset()
    eye_spy.perf.metrics  = {}
    eye_spy.perf.counters = {}
end

--- Increment a named event counter by delta (default 1).
-- Silently ignored when metrics are disabled or the key is empty.
-- @param counter_name  string  Name of the counter to increment.
-- @param delta         number  Amount to add (default 1; may be negative).
function eye_spy.perf_inc_counter(counter_name, delta)
    if not eye_spy.perf.enabled then
        return
    end

    local key = tostring(counter_name or "")
    if key == "" then
        return
    end

    local step = tonumber(delta) or 1
    if step == 0 then
        return
    end

    local counters = eye_spy.perf.counters
    counters[key] = (counters[key] or 0) + step
end

--- Record a timing sample for a named metric.
-- Samples are stored in a fixed-size ring buffer (PERF_SAMPLE_CAP entries).
-- Silently ignored when metrics are disabled or duration is negative.
-- @param metric_name  string  Name of the metric (e.g. "update_player").
-- @param duration_us  number  Elapsed time for this sample, in microseconds.
function eye_spy.perf_record(metric_name, duration_us)
    if not eye_spy.perf.enabled then
        return
    end

    local us = tonumber(duration_us) or 0
    if us < 0 then
        return
    end

    local metrics = eye_spy.perf.metrics
    local metric  = metrics[metric_name]

    -- Lazily create the metric entry on first use.
    if not metric then
        metric = {
            count         = 0, -- total number of samples recorded
            total_us      = 0, -- cumulative sum of all sample durations
            max_us        = 0, -- single worst-case duration seen
            samples       = {}, -- ring buffer of recent raw durations
            sample_index  = 1, -- write head for the ring buffer (1-based)
            sample_filled = 0, -- how many slots are populated (<= PERF_SAMPLE_CAP)
        }
        metrics[metric_name] = metric
    end

    -- Update aggregate statistics.
    metric.count                        = metric.count + 1
    metric.total_us                     = metric.total_us + us
    metric.max_us                       = math.max(metric.max_us, us)

    -- Write into ring buffer and advance the write head.
    metric.samples[metric.sample_index] = us
    metric.sample_index                 = metric.sample_index + 1

    if metric.sample_index > PERF_SAMPLE_CAP then
        metric.sample_index = 1
    end

    if metric.sample_filled < PERF_SAMPLE_CAP then
        metric.sample_filled = metric.sample_filled + 1
    end
end

--- Build and return a human-readable performance report string.
-- Lists every metric that has at least one sample, sorted alphabetically,
-- followed by every non-zero event counter.
-- Returns a short placeholder message if no data has been collected yet.
-- @return  string  Multi-line report.
function eye_spy.perf_report()
    -- Collect metric keys that have real data.
    local keys = {}
    for key, metric in pairs(eye_spy.perf.metrics) do
        if metric and metric.count > 0 then
            keys[#keys + 1] = key
        end
    end
    table.sort(keys)

    -- Collect counter keys that are non-zero.
    local counter_keys = {}
    for key, value in pairs(eye_spy.perf.counters or {}) do
        if (tonumber(value) or 0) ~= 0 then
            counter_keys[#counter_keys + 1] = key
        end
    end
    table.sort(counter_keys)

    if #keys == 0 and #counter_keys == 0 then
        return "No Eye Spy perf samples yet"
    end

    local lines = { "Eye Spy perf (avg/p95/max in ms):" }

    for _, key in ipairs(keys) do
        local metric = eye_spy.perf.metrics[key]
        local avg_ms = (metric.total_us / math.max(metric.count, 1)) / 1000
        local p95_ms = metric_p95(metric) / 1000
        local max_ms = metric.max_us / 1000

        lines[#lines + 1] = string.format(
            "%s: avg=%.3f  p95=%.3f  max=%.3f  n=%d",
            key, avg_ms, p95_ms, max_ms, metric.count
        )
    end

    if #counter_keys > 0 then
        lines[#lines + 1] = "Eye Spy perf counters:"

        for _, key in ipairs(counter_keys) do
            lines[#lines + 1] = string.format(
                "%s: n=%d",
                key, eye_spy.perf.counters[key] or 0
            )
        end
    end

    return table.concat(lines, "\n")
end
