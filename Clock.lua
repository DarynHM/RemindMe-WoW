-- Clock.lua
-- Abstracts "what time is it" so reminders can follow either the local PC clock
-- or the realm (server) clock. Reminders are always STORED as real epoch
-- seconds (time()); the server offset only affects parsing and display.

local _, ns = ...

local Clock = {}
ns.Clock = Clock

local WEEKDAY_NAMES = { "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday" }

function Clock.Now()
    return time()
end

function Clock.Mode()
    return (ns.settings and ns.settings.clock) or "local"
end

-- Seconds to ADD to local wall-clock time to get realm wall-clock time.
-- Derived from GetGameTime() (realm hour/minute), rounded to 15 minutes to
-- absorb the minute boundary drift between the two clocks.
function Clock.Offset()
    if Clock.Mode() ~= "server" or not GetGameTime then return 0 end
    local sh, sm = GetGameTime()
    local lt = date("*t")
    local diff = (sh * 60 + sm) - (lt.hour * 60 + lt.min)
    diff = (diff + 720) % 1440 - 720         -- normalise to [-12h, +12h)
    diff = math.floor(diff / 15 + 0.5) * 15  -- nearest quarter hour
    return diff * 60
end

-- Context handed to the pure Parser. "now" is shifted into the chosen clock;
-- results must be shifted back with Clock.ToReal().
-- morning / night: minutes after midnight for "tomorrow" / "morning" and
-- "tonight" / "night" (options panel, Times).
function Clock.ParserContext()
    local s = ns.settings or {}
    return { now = time() + Clock.Offset(), time = time, date = date, morning = s.morning, night = s.night }
end

function Clock.ToReal(virtualTs)
    return virtualTs - Clock.Offset()
end

local function formatTime(t)
    local s = date("%I:%M %p", t):gsub("^0", "")
    return s
end

-- Day part of a real epoch timestamp in the current clock mode: "today",
-- "tomorrow", "yesterday", "Friday" (within a week) or "Dec 03".
function Clock.DescribeDay(ts)
    local off = Clock.Offset()
    local v, vnow = ts + off, time() + off
    local d, n = date("*t", v), date("*t", vnow)

    -- Whole-day difference using local midnights (DST-safe enough for reminders)
    local function midnight(tt)
        return time({ year = tt.year, month = tt.month, day = tt.day, hour = 12 })
    end
    local days = math.floor((midnight(d) - midnight(n)) / 86400 + 0.5)

    if days == 0 then return "today"
    elseif days == 1 then return "tomorrow"
    elseif days == -1 then return "yesterday"
    elseif days > 1 and days < 7 then return WEEKDAY_NAMES[d.wday]
    end
    return date("%b %d", v)
end

-- "5:00 PM" (plus " (server)" on the realm clock).
function Clock.DescribeTime(ts)
    local suffix = (Clock.Mode() == "server") and " (server)" or ""
    return formatTime(ts + Clock.Offset()) .. suffix
end

-- Minutes after midnight in the current clock mode (0 = midnight).
function Clock.MinuteOfDay(ts)
    local t = date("*t", ts + Clock.Offset())
    return t.hour * 60 + t.min
end

-- "Friday"
function Clock.Weekday(ts)
    return WEEKDAY_NAMES[date("*t", ts + Clock.Offset()).wday]
end

-- Human description of a real epoch timestamp in the current clock mode,
-- e.g. "today 12:00 PM", "tomorrow 9:00 AM", "Friday 6:30 PM", "Dec 03 9:00 AM".
function Clock.Describe(ts)
    return Clock.DescribeDay(ts) .. " " .. Clock.DescribeTime(ts)
end
