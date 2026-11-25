-- Scheduler.lua
-- Owns the reminder list and fires time reminders when they come due.
--
-- Reminder record (RemindMeCharDB.reminders[i]):
--   { id, code = "a"|"b"|..., text, created,
--     priority = "low"|"normal"|"high"|nil (nil = default),
--     trigger = { type = "time", at = epoch }
--             | { type = "place", kind = "zone", key, name, known, armed }
--             | { type = "place", kind = "npc", npc, name },
--     trigger.every = { unit = "day"|"sec", n } (time) or true (place): repeating.
--     Place window (optional): trigger.after / trigger.before (epoch). A place
--     reminder only fires inside it; `opened` marks that the window's opening
--     has been handled. A place `every` can also be { unit = "day", n } (once
--     per window, moving on n days; `each` = every arrival inside it) or
--     { unit = "sec", n } (at most every n seconds).
--     snoozedUntil = epoch|nil, fired = bool, firedAt = epoch|nil }
-- A fired reminder stays in the list (marked "fired") until it is completed,
-- deleted or snoozed, the same way Slack keeps it until you act on it.
--
-- Repeating reminders (trigger.every) re-arm themselves when they fire: a
-- time one moves `at` to its next occurrence, a zone one waits until you
-- leave. They still show as fired (icon, list) until dismissed with "done",
-- which keeps them; only "delete" stops them.
--
-- `code` is the short handle used by commands (/remind done b). It is the
-- lowest letter code not in use when the reminder is created, never changes
-- while the reminder exists, and is freed (reused) once it's removed.

local _, ns = ...

local Scheduler = {}
ns.Scheduler = Scheduler

local date, time = date or os.date, time or os.time

local TICK_SECONDS = 5
local MISSED_GRACE = 120   -- fired more than 2 minutes late means "missed"

local function reminders()
    return ns.charDB.reminders
end

-- Single notification point for anything that shows reminder state (indicator).
local function changed()
    if ns.OnRemindersChanged then ns.OnRemindersChanged() end
end

-- 1 -> "a", 26 -> "z", 27 -> "aa", 28 -> "ab", ...
function Scheduler.CodeFor(n)
    local s = ""
    while n > 0 do
        local rem = (n - 1) % 26
        s = string.char(97 + rem) .. s
        n = math.floor((n - 1) / 26)
    end
    return s
end

local function nextFreeCode()
    local used = {}
    for _, r in ipairs(reminders()) do
        if r.code then used[r.code] = true end
    end
    local n = 1
    while used[Scheduler.CodeFor(n)] do n = n + 1 end
    return Scheduler.CodeFor(n)
end

-- Give a code to any reminder saved without one (oldest first).
function Scheduler.AssignMissingCodes()
    local list = {}
    for _, r in ipairs(reminders()) do
        if not r.code then list[#list + 1] = r end
    end
    table.sort(list, function(a, b) return a.id < b.id end)
    for _, r in ipairs(list) do r.code = nextFreeCode() end
end

function Scheduler.ByCode(code)
    code = code and code:lower()
    for _, r in ipairs(reminders()) do
        if r.code == code then return r end
    end
    return nil
end

function Scheduler.DueTime(r)
    return r.snoozedUntil or (r.trigger and r.trigger.at)
end

function Scheduler.Add(text, trigger, priority)
    local db = ns.charDB
    local r = {
        id = db.nextId,
        code = nextFreeCode(),
        text = text,
        priority = priority,
        created = ns.Clock.Now(),
        trigger = trigger,
        fired = false,
    }
    db.nextId = db.nextId + 1
    table.insert(db.reminders, r)
    changed()
    return r
end

-- Stable display order: pending timed ones by due time, then pending place
-- ones, then fired ones.
function Scheduler.Sorted()
    local list = {}
    for _, r in ipairs(reminders()) do list[#list + 1] = r end
    local HUGE = math.huge
    table.sort(list, function(a, b)
        if a.fired ~= b.fired then return not a.fired end
        local da, db = Scheduler.DueTime(a) or HUGE, Scheduler.DueTime(b) or HUGE
        if da ~= db then return da < db end
        return a.id < b.id
    end)
    return list
end

-- "when you get to Orgrimmar", "every time you're at a trainer"; nil for
-- timed reminders.
function Scheduler.PlaceText(r)
    local t = r.trigger
    if not t or t.type ~= "place" then return nil end
    local every = t.every == true or t.each
    if t.kind == "npc" then
        return (every and "every time you're at " or "at ") .. t.name
    end
    return (every and "every time you get to " or "when you get to ") .. t.name
end

-- 5400 -> "1h30m"
local function shortDuration(secs)
    local parts = {}
    local h, m, s = math.floor(secs / 3600), math.floor(secs % 3600 / 60), secs % 60
    if h > 0 then parts[#parts + 1] = h .. "h" end
    if m > 0 then parts[#parts + 1] = m .. "m" end
    if s > 0 then parts[#parts + 1] = s .. "s" end
    return table.concat(parts)
end

local WEEKDAY = { "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday" }

-- "every day", "every Friday", "every 2h"; nil if it doesn't repeat (or is a place).
function Scheduler.EveryText(r)
    local e = r.trigger and r.trigger.every
    if type(e) ~= "table" then return nil end
    if e.unit == "sec" then return "every " .. shortDuration(e.n) end
    if e.n == 1 then return "every day" end
    if e.n == 7 then return "every " .. WEEKDAY[date("*t", r.trigger.at).wday] end
    if e.n % 7 == 0 then return "every " .. (e.n / 7) .. " weeks" end
    return "every " .. e.n .. " days"
end

local HOUR = 3600

-- A place reminder's window: "tomorrow", "today after 5:00 PM",
-- "before 8:00 PM today", "by the end of Friday", "once a day", "every Friday".
-- nil when it has none.
function Scheduler.WindowText(t)
    local C = ns.Clock
    local a, b, e = t.after, t.before, t.every
    local function isMidnight(ts) return C.MinuteOfDay(ts) == 0 end
    local wholeDay = a and b and isMidnight(a) and isMidnight(b) and b - a >= 23 * HOUR and b - a <= 25 * HOUR
    local dayEnds = a and b and isMidnight(b) and b - a <= 25 * HOUR

    if type(e) == "table" and e.unit == "sec" then
        return "at most every " .. shortDuration(e.n)
    end
    if type(e) == "table" then
        local period
        if e.n == 1 then period = t.each and "each day" or "once a day"
        elseif e.n == 7 then period = "every " .. C.Weekday(a or b)
        else period = "every " .. e.n .. " days" end
        if wholeDay or not (a or b) then return period end
        if dayEnds then return period .. ", after " .. C.DescribeTime(a) end
        if a and not isMidnight(a) then period = period .. ", after " .. C.DescribeTime(a) end
        if b then period = period .. ", before " .. C.DescribeTime(b) end
        return period
    end

    if wholeDay then return C.DescribeDay(a) end
    if dayEnds then return C.DescribeDay(a) .. " after " .. C.DescribeTime(a) end
    if b then
        local by = isMidnight(b) and ("by the end of " .. C.DescribeDay(b - 1))
            or ("before " .. C.DescribeTime(b) .. " " .. C.DescribeDay(b))
        if a and isMidnight(a) and b - a < 24 * HOUR then
            return C.DescribeDay(a) .. " before " .. C.DescribeTime(b)   -- "Friday before 8:00 PM"
        elseif a and a > C.Now() then
            return "from " .. C.Describe(a) .. ", " .. by
        end
        return by
    end
    if a then return "from " .. C.Describe(a) end
    return nil
end

-- Where / when it triggers (chat list, window "Triggers" column):
-- "today 5:00 PM, every day", "when you get to Orgrimmar (after you leave)",
-- "when you get to Ironforge, tomorrow".
function Scheduler.TriggerText(r)
    local where = Scheduler.PlaceText(r)
    if where then
        local window = Scheduler.WindowText(r.trigger)
        if window then where = where .. ", " .. window end
        if r.trigger.armed == false then where = where .. " (after you leave)" end
        return where
    end
    local every = Scheduler.EveryText(r)
    local at = r.trigger and r.trigger.at
    return (at and ns.Clock.Describe(at) or "?") .. (every and (", " .. every) or "")
end

-- Window "Status" column: "fired 5:02 PM", "snoozed until 5:30 PM", "waiting".
function Scheduler.StatusText(r)
    if r.fired then
        local at = r.firedAt or Scheduler.DueTime(r)
        return "fired" .. (at and (" " .. ns.Clock.Describe(at)) or "")
    elseif r.snoozedUntil then
        return "snoozed until " .. ns.Clock.Describe(r.snoozedUntil)
    end
    local t = r.trigger
    if t and t.type == "place" and t.after and t.after > ns.Clock.Now() then
        return "starts " .. ns.Clock.Describe(t.after)
    end
    return "waiting"
end

-- Window order: High, Normal, Low; within a priority fired first, then the
-- soonest due, then place reminders (no due time).
function Scheduler.ByPriority()
    local list = {}
    for _, r in ipairs(reminders()) do list[#list + 1] = r end
    local rank, HUGE = ns.PRIORITY_RANK, math.huge
    table.sort(list, function(a, b)
        local pa, pb = rank[ns.PriorityOf(a)] or 2, rank[ns.PriorityOf(b)] or 2
        if pa ~= pb then return pa > pb end
        local fa, fb = a.fired and true or false, b.fired and true or false
        if fa ~= fb then return fa end
        local da, db = Scheduler.DueTime(a) or HUGE, Scheduler.DueTime(b) or HUGE
        if da ~= db then return da < db end
        return a.id < b.id
    end)
    return list
end

-- Next occurrence of a repeating time trigger strictly after `now`.
function Scheduler.NextAt(t, now)
    local at, e = t.at, t.every
    if e.unit == "sec" then
        if at <= now then at = at + e.n * (math.floor((now - at) / e.n) + 1) end
        return at
    end
    for _ = 1, 5000 do
        if at > now then break end
        local tt = date("*t", at)
        tt.day = tt.day + e.n
        tt.isdst = nil   -- keep the wall-clock time across DST changes
        at = time(tt)
    end
    return at
end

-- "done": a one-off is removed; a repeating one is just dismissed (it stays
-- scheduled). Returns true if it was removed.
function Scheduler.Complete(r)
    if r.trigger and r.trigger.every then
        r.fired = false
        r.firedAt = nil
        changed()
        return false
    end
    return Scheduler.Remove(r)
end

-- Fired reminders, highest priority first, then newest first.
function Scheduler.Fired()
    local list = {}
    for _, r in ipairs(reminders()) do
        if r.fired then list[#list + 1] = r end
    end
    local rank = ns.PRIORITY_RANK
    table.sort(list, function(a, b)
        local pa, pb = rank[ns.PriorityOf(a)], rank[ns.PriorityOf(b)]
        if pa ~= pb then return pa > pb end
        if (a.firedAt or 0) ~= (b.firedAt or 0) then return (a.firedAt or 0) > (b.firedAt or 0) end
        return a.id > b.id
    end)
    return list
end

-- Highest priority among fired reminders, or nil if none.
function Scheduler.HighestFired()
    local top = Scheduler.Fired()[1]
    return top and ns.PriorityOf(top)
end

function Scheduler.MostRecentFired()
    return Scheduler.Fired()[1]
end

function Scheduler.Remove(target)
    local list = reminders()
    for i = #list, 1, -1 do
        if list[i] == target then
            table.remove(list, i)
            changed()
            return true
        end
    end
    return false
end

-- Removes fired one-offs and dismisses fired repeating ones.
function Scheduler.ClearFired()
    local list, removed = reminders(), 0
    for i = #list, 1, -1 do
        local r = list[i]
        if r.fired then
            if r.trigger and r.trigger.every then
                r.fired, r.firedAt = false, nil
            else
                table.remove(list, i)
            end
            removed = removed + 1
        end
    end
    if removed > 0 then changed() end
    return removed
end

-- Fired reminders come back `seconds` from now; reminders that haven't fired
-- yet are pushed back by `seconds` from when they were due.
function Scheduler.Snooze(r, seconds)
    local from = ns.Clock.Now()
    local due = Scheduler.DueTime(r)
    if not r.fired and due and due > from then from = due end
    r.snoozedUntil = from + seconds
    r.fired = false
    r.firedAt = nil
    changed()
end

local function addDays(ts, n)
    local tt = date("*t", ts)
    tt.day = tt.day + n
    tt.isdst = nil   -- keep the wall-clock time across DST changes
    return time(tt)
end

-- Is a place reminder's window (after / before) open at `now`?
local function windowOpen(t, now)
    return (not t.after or now >= t.after) and (not t.before or now < t.before)
end
Scheduler.WindowOpen = windowOpen

-- Periodic place window ({ unit = "day", n }): move it on by n days at a time
-- until it hasn't closed yet.
local function advanceWindow(t, now)
    local e = t.every
    if type(e) ~= "table" or e.unit ~= "day" or not (t.after or t.before) then return end
    for _ = 1, 5000 do
        if t.after then t.after = addDays(t.after, e.n) end
        if t.before then t.before = addDays(t.before, e.n) end
        if (t.before or t.after) > now then break end
    end
    t.opened = nil
end

local function fire(r, note)
    r.fired = true
    r.firedAt = ns.Clock.Now()
    ns.Notify.Fire(r, note)
    local t = r.trigger
    if t.type == "place" then t.opened = true end
    if t.every then
        r.snoozedUntil = nil
        if t.type == "time" then
            t.at = Scheduler.NextAt(t, r.firedAt)
        else
            if type(t.every) == "table" then
                if t.every.unit == "sec" then
                    t.after = r.firedAt + t.every.n      -- at most every n seconds
                elseif not t.each then
                    advanceWindow(t, r.firedAt)          -- once per window
                end
            end
            if t.kind == "zone" then
                t.armed = false   -- you're there now: next time is after you leave
            end
        end
    end
end

-- "Cancel" on the already-here popup: a periodic reminder skips this window,
-- anything else is deleted. Returns "skipped" or "removed".
function Scheduler.CancelAlreadyHere(r)
    local t = r.trigger
    if type(t.every) == "table" and t.every.unit == "day" then
        advanceWindow(t, ns.Clock.Now())
        changed()
        return "skipped"
    end
    Scheduler.Remove(r)
    return "removed"
end

-- Can this reminder fire now? One-offs fire once; repeating ones fire again
-- even if the last alert wasn't dismissed.
local function canFire(r)
    return not r.fired or (r.trigger and r.trigger.every)
end

-- Place windows opening and closing (called from the ticker). Returns true
-- if anything changed.
local function checkWindow(r, now)
    local t = r.trigger
    if t.before and now >= t.before then
        if type(t.every) == "table" then
            advanceWindow(t, now)             -- periodic: on to the next one, no alert
            return true
        elseif not r.fired then
            fire(r, "(missed: you didn't get to " .. t.name .. " in time)")
            return true
        end
        return false
    end
    if t.after and not t.opened and now >= t.after then
        t.opened = true
        -- Already standing there when it opens: ask (next arrival / cancel).
        if t.kind == "zone" and canFire(r) and ns.Places and ns.Places.IsHere(t.key) then
            t.armed = false
            if ns.Notify.AskAlreadyHere then ns.Notify.AskAlreadyHere(r) end
        end
        return true
    end
    return false
end

-- Timed reminders, and place reminders that were snoozed (snoozing is always
-- time-based, so they have a snoozedUntil).
function Scheduler.Check()
    local now = ns.Clock.Now()
    local anyFired = false
    for _, r in ipairs(Scheduler.Sorted()) do
        local due = Scheduler.DueTime(r)
        if canFire(r) and due and now >= due then
            local note
            if now - due > MISSED_GRACE then
                note = "(missed, was due " .. ns.Clock.Describe(due) .. ")"
            end
            fire(r, note)
            anyFired = true
        end
        local t = r.trigger
        if t and t.type == "place" and not r.snoozedUntil and checkWindow(r, now) then
            anyFired = true
        end
    end
    if anyFired then changed() end
end

-- `set` is Places.CurrentSet(). Zone reminders fire on arrival: one made while
-- you're already there is unarmed, and arms once you've left.
function Scheduler.CheckPlaces(set)
    local any = false
    local now = ns.Clock.Now()
    for _, r in ipairs(Scheduler.Sorted()) do
        local t = r.trigger
        if canFire(r) and not r.snoozedUntil and t.type == "place" and t.kind == "zone" then
            if set[t.key] then
                if t.armed and windowOpen(t, now) then
                    fire(r, "(you've arrived in " .. t.name .. ")")
                    any = true
                end
            elseif not t.armed then
                t.armed = true
                any = true
            end
        end
    end
    if any then changed() end
end

-- An NPC window of `kind` ("trainer", "mailbox", ...) just opened.
function Scheduler.CheckNpc(kind)
    local any = false
    local now = ns.Clock.Now()
    for _, r in ipairs(Scheduler.Sorted()) do
        local t = r.trigger
        if canFire(r) and not r.snoozedUntil and t.type == "place" and t.kind == "npc" and t.npc == kind
            and windowOpen(t, now) then
            fire(r)
            any = true
        end
    end
    if any then changed() end
end

function Scheduler.Start()
    if Scheduler.ticker then return end
    Scheduler.ticker = C_Timer.NewTicker(TICK_SECONDS, Scheduler.Check)
end
