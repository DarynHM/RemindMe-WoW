-- Parser.lua
-- Natural-language reminder parser. Pure Lua 5.1: NO WoW API calls here, so it
-- can be unit tested outside the game (see tests/run.lua).
--
-- Parser.Parse(text, ctx) -> result | nil, errorMessage
--   ctx.now  : epoch seconds treated as "now" (already clock-adjusted)
--   ctx.time : function like time()/os.time  (defaults to global time)
--   ctx.date : function like date()/os.date  (defaults to global date)
--   ctx.places : optional { names = { [key] = "Display Name" }, aliases = { [key] = key } }
--                (keys from Parser.PlaceKey); built in game by Places.lua
--   result   : { message = "buy potions", trigger = <trigger>,
--                priority = "low"|"normal"|"high"|nil }
--   trigger  : { type = "time", at = epoch }
--            | { type = "place", kind = "zone", key, name, known = bool }
--            | { type = "place", kind = "npc", npc = "trainer"|"mailbox"|..., name }
--   trigger.every : repeating. Time: { unit = "day"|"sec", n = N } (every N days
--                   / seconds from `at`). Place: true (every arrival), or
--                   { unit = "day", n } (once per window, the window moving on
--                   by n days) or { unit = "sec", n } (at most every n seconds).
--   place window : trigger.after / trigger.before (epoch, either optional):
--                   a place reminder only fires inside it ("tomorrow when I
--                   get to IF", "before 8pm next time I'm at the bank").
--                   trigger.each = true: a periodic place that fires on every
--                   arrival inside its window ("whenever I'm in org after 5pm").
--   ctx.morning / ctx.night : minutes after midnight used for "tomorrow",
--                   "morning" (default 540 = 9am) and "tonight" (1200 = 8pm).

local _, ns = ...
ns = ns or {}

local Parser = {}
ns.Parser = Parser

local unpack = unpack or table.unpack
local date = date or (os and os.date)   -- WoW globals, or plain Lua outside the game
local time = time or (os and os.time)

local WEEKDAYS_FULL = {
    sunday = 1, monday = 2, tuesday = 3, wednesday = 4,
    thursday = 5, friday = 6, saturday = 7,
}
-- Short forms are only accepted after "on"/"next" (e.g. "sat" alone is too ambiguous).
local WEEKDAYS_SHORT = {
    sun = 1, mon = 2, tue = 3, tues = 3, wed = 4,
    thu = 5, thur = 5, thurs = 5, fri = 6, sat = 7,
}

local UNITS = {
    s = 1, sec = 1, secs = 1, second = 1, seconds = 1,
    m = 60, min = 60, mins = 60, minute = 60, minutes = 60,
    h = 3600, hr = 3600, hrs = 3600, hour = 3600, hours = 3600,
    d = 86400, day = 86400, days = 86400,
    w = 604800, wk = 604800, wks = 604800, week = 604800, weeks = 604800,
}

local DEFAULT_MORNING = 9 * 60   -- "tomorrow" with no time -> 9am (Slack does the same)
local DEFAULT_NIGHT = 20 * 60    -- "tonight" -> 8pm

---------------------------------------------------------------------------
-- Durations: "10m", "1 hour 30 minutes", "an hour", "half an hour"
---------------------------------------------------------------------------

-- Strict: the whole string must be a duration. Returns seconds or nil.
function Parser.ParseDuration(str)
    if not str then return nil end
    local s = str:lower():gsub("^%s+", ""):gsub("%s+$", "")
    s = s:gsub("^for%s+", "")
    if s == "" then return nil end

    if s:match("^half%s+an?%s+hour$") then return 1800 end

    local total, found = 0, false
    while s ~= "" do
        local n, unit, rest = s:match("^(%d+)%s*(%a+)%s*(.*)$")
        if not n then
            unit, rest = s:match("^an?%s+(%a+)%s*(.*)$")
            n = unit and 1
        end
        if not n or not UNITS[unit] then return nil end
        total = total + tonumber(n) * UNITS[unit]
        found = true
        s = rest:gsub("^and%s+", "")
    end
    return found and total or nil
end

---------------------------------------------------------------------------
-- Span bookkeeping: matched phrases are "claimed" so they don't match twice
-- and can be cut out of the message afterwards.
---------------------------------------------------------------------------

local function newSpans()
    local spans = {}
    local function isFree(s, e)
        for _, sp in ipairs(spans) do
            if s <= sp[2] and e >= sp[1] then return false end
        end
        return true
    end
    local function claim(s, e)
        spans[#spans + 1] = { s, e }
    end
    return spans, isFree, claim
end

-- Find the first free match of `pattern` in `l`; `accept` may veto a match.
-- Returns { s, e, captures... } or nil.
local function findFree(l, pattern, isFree, accept)
    local init = 1
    while true do
        local res = { l:find(pattern, init) }
        local s, e = res[1], res[2]
        if not s then return nil end
        if isFree(s, e) and (not accept or accept(unpack(res))) then
            return res
        end
        init = s + 1
    end
end

-- Extend a span backwards over a leading preposition ("at 5pm", "on monday").
local function extendPrefix(l, s, words)
    local before = l:sub(1, s - 1)
    for _, w in ipairs(words) do
        local p = before:find("%f[%w]" .. w .. "%s+$")
        if p then return p end
    end
    return s
end

-- Like extendPrefix, but each entry is { pattern, mode } and the mode of the
-- matched word is returned too: "after 5pm" -> "after", "by friday" -> "by".
local function prefixed(l, s, entries)
    local before = l:sub(1, s - 1)
    for _, w in ipairs(entries) do
        local p = before:find("%f[%w]" .. w[1] .. "%s+$")
        if p then return p, w[2] end
    end
    return s, nil
end

-- Window words: "after"/"from"/"starting" open a place reminder's window,
-- "before"/"by"/"until" close it. Without a place they just set the time.
local CLOCK_PREFIX = {
    { "starting%s+at", "after" }, { "starting%s+from", "after" }, { "starting", "after" },
    { "after", "after" }, { "from", "after" },
    { "before", "before" }, { "until", "by" }, { "till", "by" }, { "by", "by" },
    { "at" }, { "around" },
}
local DAY_PREFIX = {
    { "starting%s+on", "after" }, { "starting%s+from", "after" }, { "starting", "after" },
    { "from", "after" },
    { "before", "before" }, { "until", "by" }, { "till", "by" }, { "by", "by" },
}

---------------------------------------------------------------------------
-- Extraction
---------------------------------------------------------------------------

-- Consume a run of duration chunks starting exactly at `pos`:
-- "1h30m", "1h 30m", "1 hour 30 minutes", "2 hours and 15 minutes".
-- compactOnly: number and unit must touch ("10m", not "10 m").
-- Returns endPos, seconds or nil.
local function scanDuration(l, pos, compactOnly)
    local chunk = compactOnly and "^(%d+)(%a+)%f[%A]" or "^(%d+)%s*(%a+)%f[%A]"
    local total, lastEnd = 0, nil
    local p = pos
    while true do
        local s, e, n, unit = l:find(chunk, p)
        if not s or not UNITS[unit] then break end
        total = total + tonumber(n) * UNITS[unit]
        lastEnd = e

        -- optional separator ("", " ", " and ") before another chunk
        local nextP = e + 1
        local _, andEnd = l:find("^%s+and%s+", nextP)
        if andEnd then
            nextP = andEnd + 1
        else
            local _, wsEnd = l:find("^%s*", nextP)
            nextP = wsEnd + 1
        end
        if not l:find("^%d", nextP) then break end
        p = nextP
    end
    -- a duration must end on a word boundary ("10mins" ok, "10minsx" not)
    if lastEnd and not l:sub(lastEnd + 1, lastEnd + 1):find("^%w") then
        return lastEnd, total
    end
    return nil
end

local function extractRelative(l, isFree, claim)
    local r = findFree(l, "%f[%w]in%s+half%s+an?%s+hour%f[%W]", isFree)
    if r then claim(r[1], r[2]); return 1800 end

    -- "in 10 minutes", "in 1h30m", "in 2 hours and 15 minutes"
    local init = 1
    while true do
        local s, numStart = l:match("()%f[%w]in%s+()%d", init)
        if not s then break end
        local e, secs = scanDuration(l, numStart, false)
        if e and isFree(s, e) then claim(s, e); return secs end
        init = numStart
    end

    r = findFree(l, "%f[%w]in%s+an?%s+(%a+)%f[%W]", isFree,
        function(_, _, unit) return UNITS[unit] ~= nil end)
    if r then claim(r[1], r[2]); return UNITS[r[3]] end

    -- Bare shorthand anywhere: "1min", "10m", "1h30m", "2d", "1w"
    init = 1
    while true do
        local s = l:find("%f[%w]%d+%a", init)
        if not s then break end
        local e, secs = scanDuration(l, s, true)
        if e and isFree(s, e) then claim(s, e); return secs end
        init = s + 1
    end

    return nil
end

-- Returns { candidates = { {h, m}, ... }, ambiguous = bool,
-- mode = "after"|"before"|"by"|nil } or nil.
local function extractClock(l, isFree, claim)
    local mode
    local function take(r)
        local s
        s, mode = prefixed(l, r[1], CLOCK_PREFIX)
        claim(s, r[2])
    end
    local function h12(h, mer)
        h = tonumber(h)
        if h < 1 or h > 12 then return nil end
        if mer == "a" then return h % 12 end
        return h % 12 + 12
    end

    -- 12:30pm / 12:30 p.m.
    local r = findFree(l, "%f[%d](%d%d?):(%d%d)%s*([ap])%.?m%.?%f[%W]", isFree,
        function(_, _, h, m) return h12(h, "a") and tonumber(m) < 60 end)
    if r then
        take(r)
        return { candidates = { { h12(r[3], r[5]), tonumber(r[4]) } }, mode = mode }
    end

    -- 12pm / 3 am
    r = findFree(l, "%f[%d](%d%d?)%s*([ap])%.?m%.?%f[%W]", isFree,
        function(_, _, h) return h12(h, "a") ~= nil end)
    if r then
        take(r)
        return { candidates = { { h12(r[3], r[4]), 0 } }, mode = mode }
    end

    -- 14:00 / 9:30 (9:30 is ambiguous: am or pm)
    r = findFree(l, "%f[%d](%d%d?):(%d%d)%f[%D]", isFree,
        function(_, _, h, m) return tonumber(h) < 24 and tonumber(m) < 60 end)
    if r then
        take(r)
        local h, m = tonumber(r[3]), tonumber(r[4])
        if h >= 1 and h <= 12 and r[3]:sub(1, 1) ~= "0" then
            return { candidates = { { h % 12, m }, { h % 12 + 12, m } }, ambiguous = true, mode = mode }
        end
        return { candidates = { { h, m } }, mode = mode }
    end

    r = findFree(l, "%f[%w]noon%f[%W]", isFree)
    if r then take(r); return { candidates = { { 12, 0 } }, mode = mode } end

    r = findFree(l, "%f[%w]midnight%f[%W]", isFree)
    if r then take(r); return { candidates = { { 0, 0 } }, mode = mode } end

    -- Bare hour needs a preposition so "buy 20 potions" isn't a time: "at 5"
    r = findFree(l, "%f[%w]at%s+(%d%d?)%f[%W]", isFree,
        function(_, e, h)
            h = tonumber(h)
            return h >= 1 and h <= 12 and l:sub(e + 1, e + 1) ~= ":"
        end)
    if r then
        local s
        s, mode = prefixed(l, r[1], CLOCK_PREFIX)
        claim(s, r[2])
        local h = tonumber(r[3])
        return { candidates = { { h % 12, 0 }, { h % 12 + 12, 0 } }, ambiguous = true, mode = mode }
    end

    return nil
end

-- Priority words. Matched anywhere in the text (longest/most specific first).
local PRIORITY_PHRASES = {
    { "low%s+priority", "low" }, { "low%-priority", "low" },
    { "quietly", "low" }, { "silently", "low" },
    { "high%s+priority", "high" }, { "high%-priority", "high" },
    { "loudly", "high" }, { "urgently", "high" }, { "urgent", "high" },
    { "important", "high" }, { "asap", "high" },
    { "normal%s+priority", "normal" },
}
-- Plain adjectives only count as the first word (after "remind me") or the
-- last word, so "find a quiet spot" keeps its text.
local EDGE_WORDS = { quiet = "low", silent = "low", loud = "high" }

-- Shorthand flags: "-L", "-M", "-H" (and -N / long forms), any case. Also
-- used by "/remind priority <code> <word>" via Parser.PriorityWord.
local PRIORITY_FLAGS = {
    l = "low", low = "low",
    m = "normal", n = "normal", med = "normal", medium = "normal", normal = "normal",
    h = "high", high = "high",
}

-- "h", "-H", "med"... -> "low"|"normal"|"high", or nil.
function Parser.PriorityWord(word)
    if type(word) ~= "string" then return nil end
    return PRIORITY_FLAGS[word:lower():gsub("^%-", "")]
end

-- Returns "low"|"normal"|"high" or nil.
local function extractPriority(l, isFree, claim)
    -- Flags first: a standalone "-word" (start of text or after a space, then
    -- the end, a space or punctuation), so "e-mail" and "low-priority" are text.
    local init = 1
    while true do
        local s, word, e = l:match("()%-(%a+)()", init)
        if not s then break end
        local before = (s == 1) or l:sub(s - 1, s - 1):find("%s")
        local after = l:sub(e, e)
        local ends = (after == "") or after:find("[%s%p]") and after ~= "-"
        if before and ends and PRIORITY_FLAGS[word] and isFree(s, e - 1) then
            claim(s, e - 1)
            return PRIORITY_FLAGS[word]
        end
        init = s + 1
    end

    for _, p in ipairs(PRIORITY_PHRASES) do
        local r = findFree(l, "%f[%w]" .. p[1] .. "%f[%W]", isFree)
        if r then claim(r[1], r[2]); return p[2] end
    end

    -- First word, optionally after "remind me"
    local s, word, e = l:match("^%s*remind%s+me%s+()(%a+)()")
    if not s then s, word, e = l:match("^%s*()(%a+)()") end
    if s and EDGE_WORDS[word] and isFree(s, e - 1) then
        claim(s, e - 1)
        return EDGE_WORDS[word]
    end

    -- Last word (trailing punctuation allowed)
    s, word, e = l:match("%f[%a]()(%a+)()[%s%p]*$")
    if s and EDGE_WORDS[word] and isFree(s, e - 1) then
        claim(s, e - 1)
        return EDGE_WORDS[word]
    end

    -- "!" shorthand: standalone token, or leading the message ("!at 5pm raid").
    local init = 1
    while true do
        local bs, be = l:find("!+", init)
        if not bs then break end
        local before = l:sub(1, bs - 1)
        local after = l:sub(be + 1, be + 1)
        local standalone = (bs == 1 or before:sub(-1):find("%s")) and (after == "" or after:find("%s"))
        local leading = before:find("^%s*$")
        if (standalone or leading) and isFree(bs, be) then
            claim(bs, be)
            return "high"
        end
        init = be + 1
    end

    return nil
end

-- Returns { kind = "today"|"tonight"|"tomorrow"|"weekday", wday = n,
-- part = "morning"|"night"|nil, roll = bool, mode = "after"|"before"|"by"|nil }
-- or nil. part: "tomorrow morning", "friday night". roll: "in the morning"
-- means tomorrow once this morning has passed.
local function extractDay(l, isFree, claim)
    -- "tomorrow morning", "friday night": extend the span over the part word.
    local function withPart(day, s, e)
        if day.kind ~= "tonight" then
            local ps, pe, w = l:find("^%s+(%a+)%f[%W]", e + 1)
            local part = (w == "morning") and "morning" or (w == "night" or w == "evening") and "night" or nil
            if part and isFree(ps, pe) then
                day.part = part
                e = pe
            end
        end
        local st
        st, day.mode = prefixed(l, s, DAY_PREFIX)
        claim(st, e)
        return day
    end

    local phrases = {
        { "this%s+morning", "today", "morning" }, { "in%s+the%s+morning", "today", "morning", true },
        { "this%s+evening", "tonight", "night" }, { "in%s+the%s+evening", "tonight", "night" },
    }
    for _, entry in ipairs(phrases) do
        local r = findFree(l, "%f[%w]" .. entry[1] .. "%f[%W]", isFree)
        if r then
            local st, mode = prefixed(l, r[1], DAY_PREFIX)
            claim(st, r[2])
            return { kind = entry[2], part = entry[3], roll = entry[4], mode = mode }
        end
    end

    local simple = {
        { "today", "today" }, { "tonight", "tonight" },
        { "tomorrow", "tomorrow" }, { "tmrw", "tomorrow" }, { "tmr", "tomorrow" },
        { "tmrrw", "tomorrow" }, { "2moro", "tomorrow" }, { "2morrow", "tomorrow" },
        { "tomoz", "tomorrow" }, { "tonite", "tonight" }, { "2nite", "tonight" },
        { "2night", "tonight" },
    }
    for _, entry in ipairs(simple) do
        local r = findFree(l, "%f[%w]" .. entry[1] .. "%f[%W]", isFree)
        if r then
            return withPart({ kind = entry[2] }, r[1], r[2])
        end
    end

    local init = 1
    while true do
        local s, e, word = l:find("%f[%w](%a+)%f[%W]", init)
        if not s then return nil end
        if isFree(s, e) then
            local ps = extendPrefix(l, s, { "on", "next", "this" })
            local gs = prefixed(l, ps, DAY_PREFIX)
            local wday = WEEKDAYS_FULL[word] or (gs ~= s and WEEKDAYS_SHORT[word])
            if wday then
                return withPart({ kind = "weekday", wday = wday }, ps, e)
            end
        end
        init = e + 1
    end
end

---------------------------------------------------------------------------
-- Repeats: "always", "every day", "every friday", "every 2h", "daily"
---------------------------------------------------------------------------

-- Seconds -> repeat spec. Whole days/weeks step by calendar day so "9am"
-- stays 9am across daylight-saving changes.
local function everySeconds(secs)
    if secs % 86400 == 0 then return { unit = "day", n = secs / 86400 } end
    return { unit = "sec", n = secs }
end

-- Returns nil, or { generic = true } for a bare "always", or a spec
-- { unit = "day"|"sec", n = N, day = <day hint for resolveTime>|nil }.
local function extractRepeat(l, isFree, claim)
    local rep
    local r = findFree(l, "%f[%w]always%f[%W]", isFree)
    if r then claim(r[1], r[2]); rep = { generic = true } end

    local function found(spec)
        if rep then spec.generic = nil end
        return spec
    end

    -- "every 2h", "every 30 minutes", "every 2 days"
    local init = 1
    while true do
        local s, numStart = l:match("()%f[%w]every%s+()%d", init)
        if not s then break end
        local e, secs = scanDuration(l, numStart, false)
        if e and isFree(s, e) and secs > 0 then claim(s, e); return found(everySeconds(secs)) end
        init = numStart
    end

    r = findFree(l, "%f[%w]every%s+other%s+day%f[%W]", isFree)
    if r then claim(r[1], r[2]); return found({ unit = "day", n = 2 }) end
    r = findFree(l, "%f[%w]every%s+other%s+week%f[%W]", isFree)
    if r then claim(r[1], r[2]); return found({ unit = "day", n = 14 }) end

    -- "every day", "every morning", "every night", "every hour", "every friday"
    r = findFree(l, "%f[%w]every%s+(%a+)%f[%W]", isFree, function(_, _, w)
        return w == "day" or w == "morning" or w == "night" or w == "evening" or w == "week"
            or w ~= "time" and (UNITS[w] ~= nil or WEEKDAYS_FULL[w] ~= nil or WEEKDAYS_SHORT[w] ~= nil)
    end)
    if r then
        claim(r[1], r[2])
        local w = r[3]
        if w == "day" then return found({ unit = "day", n = 1 }) end
        if w == "morning" then return found({ unit = "day", n = 1, day = { kind = "today", part = "morning" } }) end
        if w == "night" or w == "evening" then return found({ unit = "day", n = 1, day = { kind = "tonight" } }) end
        if w == "week" then return found({ unit = "day", n = 7 }) end
        local wday = WEEKDAYS_FULL[w] or WEEKDAYS_SHORT[w]
        if wday then return found({ unit = "day", n = 7, day = { kind = "weekday", wday = wday } }) end
        return found(everySeconds(UNITS[w]))
    end

    local words = {
        { "everyday", { unit = "day", n = 1 } }, { "daily", { unit = "day", n = 1 } },
        { "nightly", { unit = "day", n = 1, day = { kind = "tonight" } } },
        { "weekly", { unit = "day", n = 7 } }, { "hourly", { unit = "sec", n = 3600 } },
    }
    for _, w in ipairs(words) do
        r = findFree(l, "%f[%w]" .. w[1] .. "%f[%W]", isFree)
        if r then claim(r[1], r[2]); return found(w[2]) end
    end
    return rep
end

---------------------------------------------------------------------------
-- Places: "when I get to Orgrimmar", "next time I'm at a trainer"
---------------------------------------------------------------------------

-- Normalised lookup key for a place name: lower case, apostrophes dropped,
-- other punctuation as spaces, leading "the " removed.
-- "The Crossroads" -> "crossroads", "Un'Goro Crater" -> "ungoro crater".
function Parser.PlaceKey(name)
    local k = name:lower():gsub("'", ""):gsub("[%p]", " "):gsub("%s+", " ")
    k = k:gsub("^%s+", ""):gsub("%s+$", ""):gsub("^the ", "")
    return k
end

-- NPC windows. Display names are used in confirmations ("at a trainer").
local NPC_NAMES = {
    trainer = "a trainer", mailbox = "a mailbox", vendor = "a vendor",
    bank = "the bank", ah = "the auction house", flight = "a flight master",
    gbank = "the guild bank",
}
local NPC_WORDS2 = {
    ["weapon master"] = "trainer", ["weapon trainer"] = "trainer", ["class trainer"] = "trainer",
    ["auction house"] = "ah", ["flight master"] = "flight", ["flight path"] = "flight",
    ["repair vendor"] = "vendor", ["guild bank"] = "gbank",
}
local NPC_WORDS1 = {
    trainer = "trainer", trainers = "trainer", wm = "trainer",
    mailbox = "mailbox", mail = "mailbox", mbox = "mailbox",
    vendor = "vendor", merchant = "vendor", merch = "vendor",
    bank = "bank", banker = "bank", gbank = "gbank", gb = "gbank",
    ah = "ah", auctioneer = "ah", fp = "flight", fm = "flight",
}

-- "when i get to " and friends. Built as (prefix x verb) combinations.
-- Entries are { pattern, repeats }: "whenever"/"every time" make it repeat.
local LEAD_PATTERNS = {}
do
    local prefixes = {
        { "whenever", true }, { "every%s*time", true }, { "each%s+time", true },
        { "when", false }, { "next%s+time", false }, { "the%s+next%s+time", false }, { "once", false },
    }
    local verbs = {
        "i%s+get%s+back%s+to", "i%s+get%s+to", "i%s+get%s+into", "i%s+reach",
        "i%s+arrive%s+in", "i%s+arrive%s+at", "i'?m%s+back%s+in", "i'?m%s+in", "i'?m%s+at",
        "i%s+am%s+in", "i%s+am%s+at", "i%s+visit", "i%s+go%s+to",
        "in", "at",   -- "when in org", "next time at the bank"
    }
    for _, p in ipairs(prefixes) do
        for _, v in ipairs(verbs) do
            LEAD_PATTERNS[#LEAD_PATTERNS + 1] = { "%f[%w]" .. p[1] .. "%s+" .. v .. "%s+", p[2] }
        end
    end
end

-- Words starting at `pos`, stopping at punctuation: { {s, e, word}, ... }
local function wordsFrom(l, pos, max)
    local words = {}
    local p = pos
    while #words < max do
        local s, e = l:find("^[%w'%-]+", p)
        if not s then break end
        words[#words + 1] = { s, e, l:sub(s, e) }
        local _, ws = l:find("^ +", e + 1)
        if not ws then break end
        p = ws + 1
    end
    return words
end

local ARTICLES = { a = true, an = true, the = true }

local function matchNpc(words)
    local i = (words[1] and ARTICLES[words[1][3]]) and 2 or 1
    local w1, w2 = words[i], words[i + 1]
    if w1 and w2 and NPC_WORDS2[w1[3] .. " " .. w2[3]] then
        return NPC_WORDS2[w1[3] .. " " .. w2[3]], w2[2]
    end
    if w1 and NPC_WORDS1[w1[3]] then return NPC_WORDS1[w1[3]], w1[2] end
    return nil
end

-- Longest known name (or alias, if allowed) at the start of `words`.
-- allowAliases: true, false, or function(aliasKey, startPos, endPos) -> bool.
-- Returns key, endPos.
local function matchKnown(words, places, allowAliases)
    if not places then return nil end
    for n = math.min(#words, 6), 1, -1 do
        local parts = {}
        for i = 1, n do parts[i] = words[i][3] end
        local key = Parser.PlaceKey(table.concat(parts, " "))
        if key ~= "" then
            if places.names[key] then return key, words[n][2] end
            local alias = places.aliases and places.aliases[key]
            local ok = allowAliases == true
                or (type(allowAliases) == "function" and allowAliases(key, words[1][1], words[n][2]))
            if alias and ok and places.names[alias] then return alias, words[n][2] end
        end
    end
    return nil
end

local STOP_WORDS = { remind = true, ["and"] = true, to = true }
local CONNECTORS = { of = true, the = true }

-- A name we don't know: a run of Capitalised words (allowing "of"/"the"
-- between them), or else a single word. A leading article is skipped.
-- Returns endPos, displayName.
local function matchUnknown(words, text)
    if words[1] and ARTICLES[words[1][3]] and words[2] then
        words = { unpack(words, 2) }
    end
    local first = words[1]
    if not first or STOP_WORDS[first[3]] or first[3]:find("^%d") then return nil end
    local function isCap(w) return text:sub(w[1], w[1]):find("%u") ~= nil end
    local last = 1
    local tail = words[#words]
    if not isCap(first) and #words <= 4 and text:sub(tail[2] + 1, tail[2] + 1) == "," then
        -- lowercase, but closed off by a comma: "when I'm in razor hill, buy food"
        last = #words
    elseif isCap(first) then
        local i = 2
        while words[i] do
            if isCap(words[i]) then
                last = i
            elseif not (CONNECTORS[words[i][3]] and words[i + 1] and isCap(words[i + 1])) then
                break
            end
            i = i + 1
        end
    end
    return words[last][2], text:sub(first[1], words[last][2])
end

local function npcTrigger(kind)
    return { type = "place", kind = "npc", npc = kind, name = NPC_NAMES[kind] }
end

local function zoneTrigger(key, places)
    return { type = "place", kind = "zone", key = key, name = places.names[key], known = true }
end

-- Explicit form: "<lead phrase> <place>". Returns a trigger or nil.
-- Returns trigger, repeats (true for "whenever ..." / "every time ...").
local function extractPlace(l, text, isFree, claim, places)
    for _, lead in ipairs(LEAD_PATTERNS) do
        local r = findFree(l, lead[1], isFree)
        if r then
            local words = wordsFrom(l, r[2] + 1, 7)
            local npc, npcEnd = matchNpc(words)
            local key, keyEnd = matchKnown(words, places, true)
            if npc and (not key or npcEnd >= keyEnd) then
                claim(r[1], npcEnd)
                return npcTrigger(npc), lead[2]
            elseif key then
                claim(r[1], keyEnd)
                return zoneTrigger(key, places), lead[2]
            end
            local e, name = matchUnknown(words, text)
            if e then
                claim(r[1], e)
                return { type = "place", kind = "zone", key = Parser.PlaceKey(name), name = name, known = false },
                    lead[2]
            end
        end
    end
    return nil
end

-- Bare aliases that are also everyday words.
local COMMON_WORDS = { stocks = true, lights = true, winter = true, needles = true, gadget = true }

-- Bare form, only used when there's no time: "at Orgrimmar buy wine",
-- "at the mailbox send mats", "in org", "at IF". Aliases count bare when
-- they're 3+ letters and not everyday words, or typed in capitals ("IF",
-- "SW"), so "in if I fail" stays text. Straight after "remind me" any alias
-- counts ("remind me in if to ...").
local function extractBarePlace(l, text, isFree, claim, places)
    for _, prep in ipairs({ "at", "in" }) do
        local init = 1
        while true do
            local s, e = l:find("%f[%w]" .. prep .. "%s+", init)
            if not s then break end
            if isFree(s, e) then
                local words = wordsFrom(l, e + 1, 7)
                local before = l:sub(1, s - 1)
                local afterRemindMe = before:find("remind%s+me%s+$") ~= nil or before:find("^%s*me%s+$") ~= nil
                local key, keyEnd = matchKnown(words, places, afterRemindMe or function(alias, as, ae)
                    if #alias >= 3 then return not COMMON_WORDS[alias] end
                    return text:sub(as, ae):find("^%u+$") ~= nil
                end)
                if key and #key >= 2 then
                    claim(s, keyEnd)
                    return zoneTrigger(key, places)
                end
                if prep == "at" then
                    local npc, npcEnd = matchNpc(words)
                    if npc and words[1] and ARTICLES[words[1][3]] then
                        claim(s, npcEnd)
                        return npcTrigger(npc)
                    end
                end
            end
            init = e + 1
        end
    end
    return nil
end

local function editDistance(a, b)
    if math.abs(#a - #b) > 2 then return 99 end
    local prev = {}
    for j = 0, #b do prev[j] = j end
    for i = 1, #a do
        local cur = { [0] = i }
        for j = 1, #b do
            local cost = (a:sub(i, i) == b:sub(j, j)) and 0 or 1
            cur[j] = math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
        end
        prev = cur
    end
    return prev[#b]
end

-- "Did you mean" for an unknown place key: up to 3 display names, closest first.
function Parser.Suggest(key, places)
    if not places or not key or key == "" then return {} end
    local found = {}
    for k, display in pairs(places.names) do
        local d = editDistance(key, k)
        if d > 2 and #key >= 3 and k:sub(1, #key) == key then d = 2.5 end
        if d <= 2.5 then found[#found + 1] = { d, display } end
    end
    table.sort(found, function(x, y)
        if x[1] ~= y[1] then return x[1] < y[1] end
        return x[2] < y[2]
    end)
    local out = {}
    for i = 1, math.min(3, #found) do out[i] = found[i][2] end
    return out
end

---------------------------------------------------------------------------
-- Message cleanup
---------------------------------------------------------------------------

-- "me ..." covers typing "/remind me to ..." (the slash command eats "remind").
local FILLERS = { "remind me to ", "remind me about ", "remind me that ", "remind me ",
    "me to ", "me about ", "me that ", "me ", "to " }

local function cleanMessage(text, spans)
    table.sort(spans, function(a, b) return a[1] > b[1] end)
    for _, sp in ipairs(spans) do
        text = text:sub(1, sp[1] - 1) .. " " .. text:sub(sp[2] + 1)
    end

    local function trim(s)
        s = s:gsub("%s+", " ")
        s = s:gsub("^[%s,;:%.%-]+", ""):gsub("[%s,;:%-]+$", "")
        -- drop a lone trailing period, but keep "..." / "!" / "?"
        s = s:gsub("([^%.])%.$", "%1")
        return s
    end

    text = trim(text)
    local lower = text:lower()
    for _, f in ipairs(FILLERS) do
        if lower:sub(1, #f) == f then
            text = trim(text:sub(#f + 1))
            break
        end
    end
    -- Bare trailing "remind me" from e.g. "buy potions, remind me"
    text = trim(text:gsub("[,%s]+[Rr]emind me$", ""))
    if text:lower() == "remind me" or text:lower() == "me" then text = "" end
    -- Fragments left between a removed span and a comma, e.g. "remind me ," → handled by trim
    return text
end

---------------------------------------------------------------------------
-- Resolution: turn extracted pieces into an epoch timestamp
---------------------------------------------------------------------------

-- rolling: a repeating reminder, so "today 9am" that's already passed means
-- tomorrow instead of an error.
local function resolveTime(ctx, clock, day, rolling)
    local timeFn = ctx.time or time
    local dateFn = ctx.date or date
    local now = ctx.now
    local t = dateFn("*t", now)

    local function at(dayOffset, h, m)
        return timeFn({
            year = t.year, month = t.month, day = t.day + dayOffset,
            hour = h, min = m, sec = 0,
        })
    end

    local isNight = day and (day.kind == "tonight" or day.part == "night")
    local isMorning = day and day.part == "morning"

    local candidates
    if clock then
        candidates = clock.candidates
        if clock.ambiguous and isNight then
            candidates = { candidates[2] } -- pm
        elseif clock.ambiguous and isMorning then
            candidates = { candidates[1] } -- am
        elseif clock.ambiguous and day and day.kind ~= "today" then
            -- Future day, no "next occurrence" to go by: prefer daytime hours.
            -- 7..11 -> am, 12 and 1..6 -> pm.
            local am = candidates[1][1]
            candidates = { (am >= 7 and am <= 11) and candidates[1] or candidates[2] }
        end
    else
        local mins = isNight and (ctx.night or DEFAULT_NIGHT) or (ctx.morning or DEFAULT_MORNING)
        candidates = { { math.floor(mins / 60), mins % 60 } }
    end

    local offsets
    if not day then
        offsets = { 0, 1 }
    elseif day.kind == "today" or day.kind == "tonight" then
        offsets = (rolling or day.roll) and { 0, 1 } or { 0 }
    elseif day.kind == "tomorrow" then
        offsets = { 1 }
    else -- weekday
        local off = (day.wday - t.wday) % 7
        offsets = { off, off + 7 }
    end

    local best
    for _, off in ipairs(offsets) do
        for _, c in ipairs(candidates) do
            local ts = at(off, c[1], c[2])
            if ts > now and (not best or ts < best) then best = ts end
        end
        if best then break end
    end

    if not best then
        return nil, "That time has already passed today."
    end
    return best
end

---------------------------------------------------------------------------
-- Place windows: "tomorrow when I get to IF", "before 8pm at the bank"
---------------------------------------------------------------------------

-- Midnight `days` after the day containing `base`, plus `mins` minutes.
-- Calendar arithmetic, so it's right across daylight-saving changes.
local function dayPlus(ctx, base, days, mins)
    local t = (ctx.date or date)("*t", base)
    return (ctx.time or time)({
        year = t.year, month = t.month, day = t.day + days,
        hour = math.floor(mins / 60), min = mins % 60, sec = 0,
    })
end

-- Minutes after midnight for a clock on the day starting at `base`.
local function clockMinutes(ctx, clock, day, base)
    local c = clock.candidates
    if #c == 1 then return c[1][1] * 60 + c[1][2] end
    local pick
    if day and (day.kind == "tonight" or day.part == "night") then
        pick = c[2]
    elseif day and day.part == "morning" then
        pick = c[1]
    elseif day and day.kind ~= "today" then
        pick = (c[1][1] >= 7 and c[1][1] <= 11) and c[1] or c[2]   -- daytime hours
    else
        -- today: the next one still ahead ("after 9" at 10am means 9pm)
        pick = c[2]
        for _, cand in ipairs(c) do
            if dayPlus(ctx, base, 0, cand[1] * 60 + cand[2]) > ctx.now then pick = cand; break end
        end
    end
    return pick[1] * 60 + pick[2]
end

-- The window for a place reminder with a time. Returns { after, before }
-- (either may be nil) or nil, error. A day lasts only that day.
-- rolling: periodic, so a window that has already closed is fine (the
-- scheduler moves it on).
local function placeWindow(ctx, clock, day, rolling)
    local now = ctx.now
    local t = (ctx.date or date)("*t", now)
    local off = 0
    local partMins
    if day then
        if day.kind == "tonight" or day.part == "night" then partMins = ctx.night or DEFAULT_NIGHT
        elseif day.part == "morning" then partMins = ctx.morning or DEFAULT_MORNING end
        if day.kind == "tomorrow" then
            off = 1
        elseif day.kind == "weekday" then
            off = (day.wday - t.wday) % 7
        elseif day.roll and dayPlus(ctx, now, 0, partMins) <= now then
            off = 1   -- "in the morning", said after this morning
        end
    end
    local base = dayPlus(ctx, now, off, 0)
    local dayEnd = dayPlus(ctx, base, 1, 0)
    local cmode, dmode = clock and clock.mode, day and day.mode

    local w
    if cmode == "before" or cmode == "by" then
        -- "before 8pm", "friday before 8pm" (open from the start of friday)
        w = { before = dayPlus(ctx, base, 0, clockMinutes(ctx, clock, day, base)) }
        if day and not dmode then w.after = dayPlus(ctx, base, 0, partMins or 0) end
    elseif dmode == "before" or dmode == "by" then
        -- "by friday" (end of friday), "before friday" (start), "by tonight"
        local mins = clock and clockMinutes(ctx, clock, day, base) or partMins
        if mins then
            w = { before = dayPlus(ctx, base, 0, mins) }
        else
            w = { before = (dmode == "by") and dayEnd or base }
        end
    else
        -- "tomorrow", "after 5pm", "tonight": from then until the end of that day
        local mins = clock and clockMinutes(ctx, clock, day, base) or partMins or 0
        w = { after = dayPlus(ctx, base, 0, mins), before = dayEnd }
    end
    if not rolling and w.before <= now then
        return nil, "That time has already passed today."
    end
    return w
end

-- Turn a place trigger plus any time / repeat into the final trigger.
-- each: "whenever" / "always" (every arrival).
local function placeTrigger(ctx, place, each, rep, rel, clock, day)
    local spec = rep and not rep.generic and rep or nil
    if spec and spec.unit == "sec" then
        -- "every 2h when I'm in org": at most once every 2h
        place.every = { unit = "sec", n = spec.n }
        if rel then
            place.after = ctx.now + rel
        elseif clock or day then
            local w, err = placeWindow(ctx, clock, day, false)
            if not w then return nil, err end
            place.after = w.after
        end
    elseif spec or (each and (clock or day)) then
        -- "every day when I get to org", "whenever I'm in org after 5pm"
        local d = day or (spec and spec.day) or { kind = "today" }
        local n = spec and spec.n or ((d.kind == "weekday") and 7 or 1)
        local w = placeWindow(ctx, clock, d, true)
        place.after, place.before = w.after, w.before
        place.every = { unit = "day", n = n }
        if each then place.each = true end
    elseif rel then
        place.after = ctx.now + rel        -- "in 2h when I get to org"
        if each then place.every = true end
    elseif clock or day then
        local w, err = placeWindow(ctx, clock, day, false)
        if not w then return nil, err end
        place.after, place.before = w.after, w.before
    elseif each then
        place.every = true
    end
    return place
end

---------------------------------------------------------------------------
-- Public entry point
---------------------------------------------------------------------------

function Parser.Parse(text, ctx)
    if not text or text:match("^%s*$") then
        return nil, "What should I remind you about?"
    end
    ctx = ctx or {}
    ctx.now = ctx.now or (ctx.time or time)()
    -- "@5pm" / "@ 17:30" -> "at 5pm"
    text = text:gsub("@%s*(%d)", "at %1")

    local l = text:lower()
    local spans, isFree, claim = newSpans()

    local priority = extractPriority(l, isFree, claim)
    local rep = extractRepeat(l, isFree, claim)
    local place, placeRepeats = extractPlace(l, text, isFree, claim, ctx.places)

    local rel = extractRelative(l, isFree, claim)
    local clock, day
    if not rel then
        clock = extractClock(l, isFree, claim)
        day = extractDay(l, isFree, claim)
    end

    local trigger
    if place then
        -- "tomorrow when I get to IF": the place fires, the time is its window
        local err
        trigger, err = placeTrigger(ctx, place, placeRepeats or (rep and rep.generic), rep, rel, clock, day)
        if not trigger then return nil, err end
    elseif rel then
        trigger = { type = "time", at = ctx.now + rel }
        if rep and rep.generic then rep = everySeconds(rel) end   -- "always in 2h" = every 2h
    else
        if rep and not rep.generic then
            day = day or rep.day
            if not clock and not day and rep.unit == "day" then day = { kind = "today" } end
        end
        if clock or day then
            local at, err = resolveTime(ctx, clock, day, rep ~= nil)
            if not at then return nil, err end
            trigger = { type = "time", at = at }
            if rep and rep.generic then
                rep = (day and day.kind == "weekday") and { unit = "day", n = 7 } or { unit = "day", n = 1 }
            end
        elseif rep and rep.unit == "sec" then
            trigger = { type = "time", at = ctx.now + rep.n }       -- "every 2h": first in 2h
        end
    end

    if not trigger then
        -- Bare places ("at IF") only when there's no time, so they don't guess.
        local bare = extractBarePlace(l, text, isFree, claim, ctx.places)
        if bare then trigger = placeTrigger(ctx, bare, rep and rep.generic, nil, nil, nil, nil) end
    elseif trigger.type == "time" and rep then
        trigger.every = { unit = rep.unit, n = rep.n }
    end

    if not trigger and rep then
        return nil, "Always when? Try 'always at 9am', 'every friday at 7pm', 'every 2h' or " ..
            "'whenever I get to Orgrimmar'."
    end

    if not trigger then
        -- "in Orgrimmer" with a typo: offer the nearest place names
        for _, prep in ipairs({ "in", "at" }) do
            local init = 1
            while ctx.places do
                local s, e = l:find("%f[%w]" .. prep .. "%s+", init)
                if not s then break end
                local words = wordsFrom(l, e + 1, 3)
                for n = #words, 1, -1 do
                    local parts = {}
                    for i = 1, n do parts[i] = words[i][3] end
                    local sug = Parser.Suggest(Parser.PlaceKey(table.concat(parts, " ")), ctx.places)
                    if sug[1] then
                        return nil, "I couldn't find a time or place in that. Did you mean '" .. prep .. " " ..
                            sug[1] .. "'? Or say 'when I get to ...' for a place I don't know."
                    end
                end
                init = e + 1
            end
        end
        return nil, "I couldn't find a time or place in that. Try 'at 12pm', 'in 30 minutes', " ..
            "'tomorrow at 9am' or 'when I get to Orgrimmar'."
    end

    local message = cleanMessage(text, spans)
    if message == "" then
        return nil, "What should I remind you about?"
    end

    return { message = message, trigger = trigger, priority = priority }
end

return Parser
