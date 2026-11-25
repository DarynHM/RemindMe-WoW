-- Parser tests. Run from the repo root with any Lua 5.1+ / LuaJIT:
--   lua tests/run.lua
-- No dependencies. Uses a fixed "now": Saturday 2026-11-21 10:00 local time.

local ns = {}
local chunk = assert(loadfile("Parser.lua"))
chunk("RemindMe", ns)
local Parser = ns.Parser

local NOW = os.time({ year = 2026, month = 11, day = 21, hour = 10, min = 0, sec = 0 })

local function ctx()
    return { now = NOW, time = os.time, date = os.date }
end

local function ts(day, hour, min)
    return os.time({ year = 2026, month = 11, day = day, hour = hour, min = min or 0, sec = 0 })
end

local passed, failed = 0, 0

local function check(name, cond, detail)
    if cond then
        passed = passed + 1
    else
        failed = failed + 1
        print("FAIL: " .. name .. (detail and ("\n      " .. detail) or ""))
    end
end

local function fmt(t) return t and os.date("%Y-%m-%d %H:%M", t) or "nil" end

-- Expect a successful parse with the given message, trigger time and priority
-- (priority nil = no priority given).
local function expect(input, message, at, priority)
    local r, err = Parser.Parse(input, ctx())
    if not r then
        check(input, false, "error: " .. tostring(err))
        return
    end
    check(input .. " [message]", r.message == message,
        ("got %q, want %q"):format(r.message, message))
    check(input .. " [time]", r.trigger.at == at,
        ("got %s, want %s"):format(fmt(r.trigger.at), fmt(at)))
    check(input .. " [priority]", r.priority == priority,
        ("got %s, want %s"):format(tostring(r.priority), tostring(priority)))
end

local function expectError(input)
    local r = Parser.Parse(input, ctx())
    check(input .. " [should error]", r == nil, r and ("parsed: " .. r.message .. " @ " .. fmt(r.trigger.at)))
end

-- The examples from the brief
expect("At 12pm today, remind me to buy potions", "buy potions", ts(21, 12))
expect("remind me to buy potions at 12pm", "buy potions", ts(21, 12))
expect("Remind me at 12pm today to buy potions", "buy potions", ts(21, 12))

-- Relative
expect("in 10 minutes repair", "repair", NOW + 600)
expect("remind me in 30 min to check the AH", "check the AH", NOW + 1800)
expect("remind me to log off in an hour", "log off", NOW + 3600)
expect("in half an hour feed pet", "feed pet", NOW + 1800)
expect("in 2h turn in quests", "turn in quests", NOW + 7200)

-- Shorthand / compound durations
expect("1min buy potions", "buy potions", NOW + 60)
expect("buy potions 1h", "buy potions", NOW + 3600)
expect("1d check mail", "check mail", NOW + 86400)
expect("remind me to renew auctions in 2d", "renew auctions", NOW + 2 * 86400)
expect("1w reset raid lockout", "reset raid lockout", NOW + 604800)
expect("10mins repair", "repair", NOW + 600)
expect("2hrs log off", "log off", NOW + 7200)
expect("1h30m raid", "raid", NOW + 5400)
expect("1h 30m raid", "raid", NOW + 5400)
expect("in 1h30m raid", "raid", NOW + 5400)
expect("in 1 hour 30 minutes raid", "raid", NOW + 5400)
expect("in 2 hours and 15 minutes raid", "raid", NOW + 8100)
expect("remind me in 45s to loot", "loot", NOW + 45)
expect("buy 20g of herbs in 5m", "buy 20g of herbs", NOW + 300)  -- "20g" is not a duration
expectError("buy 20 potions")                                     -- spaced bare number isn't a time

-- Absolute times
expect("buy potions at 12:30 pm", "buy potions", ts(21, 12, 30))
expect("buy potions at 3 p.m.", "buy potions", ts(21, 15))
expect("raid at 19:30", "raid", ts(21, 19, 30))
expect("lunch at noon", "lunch", ts(21, 12))
expect("reset at midnight", "reset", ts(22, 0))
expect("at 9am check mail", "check mail", ts(22, 9))      -- 9am already passed -> tomorrow
expect("at 5 do dailies", "do dailies", ts(21, 17))       -- bare hour -> next 5 o'clock
expect("at 9:30 do something", "do something", ts(21, 21, 30))

-- Days
expect("tomorrow at 9am buy reagents", "buy reagents", ts(22, 9))
expect("tomorrow buy reagents", "buy reagents", ts(22, 9))
expect("tonight check the AH", "check the AH", ts(21, 20))
expect("tonight at 8 raid", "raid", ts(21, 20))
expect("on monday at 6pm guild meeting", "guild meeting", ts(23, 18))
expect("friday reset dungeons", "reset dungeons", ts(27, 9))
expect("tomorrow at 5 group up", "group up", ts(22, 17))
expect("tomorrow at 8 farm herbs", "farm herbs", ts(22, 8))
expect("remind me to buy 20 potions tomorrow", "buy 20 potions", ts(22, 9))

-- Keyword-looking words that are NOT triggers stay in the message
expect("remind me to sat down at 3pm", "sat down", ts(21, 15))

-- Priorities
expect("remind me quietly in 1h to stretch", "stretch", NOW + 3600, "low")
expect("urgent: at 5pm raid", "raid", ts(21, 17), "high")
expect("! at 5pm raid", "raid", ts(21, 17), "high")
expect("!at 5pm raid", "raid", ts(21, 17), "high")
expect("raid ! at 5pm", "raid", ts(21, 17), "high")
expect("buy potions! in 5m", "buy potions!", NOW + 300, nil)
expect("find a quiet spot at 5pm", "find a quiet spot", ts(21, 17), nil)
expect("quiet 10m check mail", "check mail", NOW + 600, "low")
expect("remind me loud at 5pm to raid", "raid", ts(21, 17), "high")
expect("raid at 5pm loud", "raid", ts(21, 17), "high")
expect("at 5pm raid high priority", "raid", ts(21, 17), "high")
expect("at 5pm raid, low-priority", "raid", ts(21, 17), "low")
expect("important: renew auctions tomorrow", "renew auctions", ts(22, 9), "high")
expect("normal priority 1h check mail", "check mail", NOW + 3600, "normal")
expect("silently in 30m feed pet", "feed pet", NOW + 1800, "low")
expect("make it loud music at 5pm", "make it loud music", ts(21, 17), nil)

-- Shorthand flags: -L / -M / -N / -H and long forms, any case, standalone only
expect("-h in 10m raid", "raid", NOW + 600, "high")
expect("buy pots tonight -L", "buy pots", ts(21, 20), "low")
expect("raid -M at 5pm", "raid", ts(21, 17), "normal")
expect("-n at 5pm raid", "raid", ts(21, 17), "normal")
expect("-HIGH at 5pm raid", "raid", ts(21, 17), "high")
expect("-medium 1h check mail", "check mail", NOW + 3600, "normal")
expect("at 5pm raid -low.", "raid", ts(21, 17), "low")
expect("check e-mail at 5pm", "check e-mail", ts(21, 17), nil)
expect("raid -x at 5pm", "raid -x", ts(21, 17), nil)
check("PriorityWord h", Parser.PriorityWord("h") == "high")
check("PriorityWord -H", Parser.PriorityWord("-H") == "high")
check("PriorityWord med", Parser.PriorityWord("med") == "normal")
check("PriorityWord L", Parser.PriorityWord("L") == "low")
check("PriorityWord foo", Parser.PriorityWord("foo") == nil)

-- Errors
expectError("buy potions")                  -- no time
expectError("at 12pm today")                -- no message
expectError("at 9am today buy potions")     -- already passed today
expectError("")

-- Durations
check("dur 10m", Parser.ParseDuration("10m") == 600)
check("dur 1 hour 30 minutes", Parser.ParseDuration("1 hour 30 minutes") == 5400)
check("dur for 15 minutes", Parser.ParseDuration("for 15 minutes") == 900)
check("dur an hour", Parser.ParseDuration("an hour") == 3600)
check("dur 2 10m (not a duration)", Parser.ParseDuration("2 10m") == nil)
check("dur 2 (not a duration)", Parser.ParseDuration("2") == nil)
check("dur 1h30m", Parser.ParseDuration("1h30m") == 5400)
check("dur 1w", Parser.ParseDuration("1w") == 604800)

-- Places
local PLACES = { names = {}, aliases = {
    org = "orgrimmar", sw = "stormwind city", ["if"] = "ironforge", xroads = "crossroads",
} }
for _, n in ipairs({ "Orgrimmar", "Stormwind City", "Ironforge", "The Crossroads", "Goldshire",
    "Light's Hope Chapel", "Elwynn Forest" }) do
    PLACES.names[Parser.PlaceKey(n)] = n
end

local function expectPlace(input, message, kind, name, extra)
    local c = ctx()
    c.places = PLACES
    local r, err = Parser.Parse(input, c)
    if not r then
        check(input, false, "error: " .. tostring(err))
        return
    end
    local t = r.trigger
    check(input .. " [message]", r.message == message, ("got %q, want %q"):format(r.message, message))
    check(input .. " [place]", t.type == "place" and t.kind == kind and t.name == name,
        ("got %s/%s/%s"):format(t.type, tostring(t.kind), tostring(t.name)))
    for k, v in pairs(extra or {}) do
        local got = (k == "priority") and r.priority or t[k]
        check(input .. " [" .. k .. "]", got == v, ("got %s, want %s"):format(tostring(got), tostring(v)))
    end
end

local function expectPlaceError(input)
    local c = ctx()
    c.places = PLACES
    local r = Parser.Parse(input, c)
    check(input .. " [should error]", r == nil, r and ("parsed: " .. r.message))
end

check("key crossroads", Parser.PlaceKey("The Crossroads") == "crossroads")
check("key light's hope", Parser.PlaceKey("Light's Hope Chapel") == "lights hope chapel")

expectPlace("When I get to Orgrimmar, remind me to upgrade my weapon skill", "upgrade my weapon skill",
    "zone", "Orgrimmar", { key = "orgrimmar", known = true })
expectPlace("remind me to buy wine when I get to org", "buy wine", "zone", "Orgrimmar")
expectPlace("when i'm in the crossroads repair", "repair", "zone", "The Crossroads")
expectPlace("when im in xroads repair", "repair", "zone", "The Crossroads")
expectPlace("next time I'm in Stormwind City buy a pet", "buy a pet", "zone", "Stormwind City")
expectPlace("next time I'm in stormwind buy a pet", "buy a pet", "zone", "stormwind",
    { known = false })   -- not an alias in this test dictionary
expectPlace("when I reach Light's Hope Chapel turn in quests", "turn in quests", "zone", "Light's Hope Chapel")
expectPlace("next time I'm at a trainer learn swords", "learn swords", "npc", "a trainer", { npc = "trainer" })
expectPlace("when I visit the weapon master learn daggers", "learn daggers", "npc", "a trainer")
expectPlace("when I get to the auction house sell herbs", "sell herbs", "npc", "the auction house",
    { npc = "ah" })
expectPlace("next time I'm at the bank, deposit mats", "deposit mats", "npc", "the bank")
expectPlace("at the mailbox send mats", "send mats", "npc", "a mailbox", { npc = "mailbox" })
expectPlace("at Orgrimmar buy wine", "buy wine", "zone", "Orgrimmar")
expectPlace("buy bread in Goldshire", "buy bread", "zone", "Goldshire")
expectPlace("when I get to Goldshyre sell grey items", "sell grey items", "zone", "Goldshyre",
    { known = false, key = "goldshyre" })
expectPlace("when I get to the Valley of Trials say hi", "say hi", "zone", "Valley of Trials",
    { known = false })
expectPlace("next time I'm in razor hill, buy food", "buy food", "zone", "razor hill", { known = false })
expectPlace("next time I'm in razor hill buy food", "hill buy food", "zone", "razor", { known = false })
expectPlace("! when I get to IF bank stuff", "bank stuff", "zone", "Ironforge", { priority = "high" })
expectPlace("quietly when I get to sw check mail", "check mail", "zone", "Stormwind City", { priority = "low" })
expectPlace("-low when I get to org repair", "repair", "zone", "Orgrimmar", { priority = "low" })
expectPlace("next time I'm at a trainer learn swords -H", "learn swords", "npc", "a trainer", { priority = "high" })
expectPlace("remind me in orgrimmar to buy wine", "buy wine", "zone", "Orgrimmar")
expectPlace("remind me in org to buy wine", "buy wine", "zone", "Orgrimmar")
expectPlace("buy wine when in org", "buy wine", "zone", "Orgrimmar")
expectPlace("next time at the bank deposit mats", "deposit mats", "npc", "the bank")
expectPlace("me transmog when I get to Orgrimmar", "transmog", "zone", "Orgrimmar")  -- typed "/remind me ..."
expectPlace("me in org to buy wine", "buy wine", "zone", "Orgrimmar")
do
    local c = ctx(); c.places = PLACES
    local r, err = Parser.Parse("me transmog in Orgrimmer", c)
    check("typo suggestion", r == nil and err:find("in Orgrimmar", 1, true) ~= nil, tostring(err))
end
expectPlaceError("remind me in orgrimmar")                     -- nothing to remind about
expectPlaceError("meet at if")                                 -- bare aliases don't count

do  -- "if" is not read as Ironforge in a time reminder
    local c = ctx()
    c.places = PLACES
    local r = Parser.Parse("in if I fail at 5pm retry", c)
    check("bare alias ignored [time]", r and r.trigger.type == "time" and r.trigger.at == ts(21, 17))
    r = Parser.Parse("in 1h meet at the bank", c)
    check("time wins over bare place", r and r.trigger.type == "time" and r.message == "meet at the bank")
end

do
    local s = Parser.Suggest("goldshyre", PLACES)
    check("suggest goldshire", s[1] == "Goldshire", tostring(s[1]))
    s = Parser.Suggest("orgri", PLACES)
    check("suggest by prefix", s[1] == "Orgrimmar", tostring(s[1]))
    check("suggest nothing", #Parser.Suggest("zzzzzz", PLACES) == 0)
end

-- WoW abbreviations, using the real dictionary from Places.lua (no C_Map
-- outside the game, so just its built-in names + aliases)
do
    assert(loadfile("Places.lua"))("RemindMe", ns)
    local REAL = ns.Places.ParserContext()
    local function place(input, message, name, extra)
        local c = ctx(); c.places = REAL
        local r, err = Parser.Parse(input, c)
        if not r then check(input, false, "error: " .. tostring(err)); return end
        local t = r.trigger
        check(input .. " [message]", r.message == message, ("got %q, want %q"):format(r.message, message))
        check(input .. " [place]", t.name == name, ("got %s/%s"):format(t.type, tostring(t.name)))
        for k, v in pairs(extra or {}) do
            check(input .. " [" .. k .. "]", t[k] == v, ("got %s, want %s"):format(tostring(t[k]), tostring(v)))
        end
    end
    local function timed(input, message, at)
        local c = ctx(); c.places = REAL
        local r, err = Parser.Parse(input, c)
        check(input, r and r.trigger.type == "time" and r.message == message and r.trigger.at == at,
            r and ("got %q @ %s (%s)"):format(r.message, fmt(r.trigger.at), r.trigger.type) or err)
    end

    place("when I get to brd sell lockboxes", "sell lockboxes", "Blackrock Depths")
    place("next time I'm in ubrs check the key", "check the key", "Blackrock Spire")
    place("when I get to sm lib grab the book", "grab the book", "Scarlet Monastery")
    place("when I get to aq40 bring nature res", "bring nature res", "Ahn'Qiraj")
    place("when i'm in wsg stack bandages", "stack bandages", "Warsong Gulch")
    place("when I get to xr buy water", "buy water", "The Crossroads")
    place("when I get to 1k needles do the race", "do the race", "Thousand Needles")
    place("buy wine in org", "buy wine", "Orgrimmar")                -- 3+ letter alias, bare
    place("repair at IF", "repair", "Ironforge")                     -- capitals, bare
    place("at SW buy a pet", "buy a pet", "Stormwind City")
    place("sell herbs at the ah", "sell herbs", "the auction house", { npc = "ah" })
    place("next time I'm at the fp set hearth", "set hearth", "a flight master", { npc = "flight" })
    place("when I'm at a repair vendor sell greys", "sell greys", "a vendor", { npc = "vendor" })
    place("next time at the gbank deposit mats", "deposit mats", "the guild bank", { npc = "gbank" })
    place("check mbox when I get to the mbox", "check mbox", "a mailbox")

    timed("in if I fail at 5pm retry", "in if I fail retry", ts(21, 17))   -- lowercase "if" stays text
    timed("raid 2moro @ 7pm", "raid", ts(22, 19))
    timed("@5pm buy stocks", "buy stocks", ts(21, 17))
    timed("2nite do dailies", "do dailies", ts(21, 20))
    timed("tonite at 9 raid", "raid", ts(21, 21))
    timed("buy stocks in 1h", "buy stocks", NOW + 3600)
    local c = ctx(); c.places = REAL
    check("bare 2-letter lowercase alias is not a place", Parser.Parse("meet at sw", c) == nil)
    check("bare everyday-word alias is not a place", Parser.Parse("buy wool in winter", c) == nil)
end

-- Repeating reminders
do
    local function rep(input, message, at, unit, n)
        local c = ctx(); c.places = PLACES
        local r, err = Parser.Parse(input, c)
        if not r then check(input, false, "error: " .. tostring(err)); return end
        local e = r.trigger.every
        check(input .. " [message]", r.message == message, ("got %q, want %q"):format(r.message, message))
        check(input .. " [time]", r.trigger.at == at, ("got %s, want %s"):format(fmt(r.trigger.at), fmt(at)))
        check(input .. " [every]", type(e) == "table" and e.unit == unit and e.n == n,
            type(e) == "table" and (e.unit .. " " .. e.n) or tostring(e))
    end
    rep("me always at 9am stretch", "stretch", ts(22, 9), "day", 1)        -- 9am passed -> from tomorrow
    rep("always at 5pm do dailies", "do dailies", ts(21, 17), "day", 1)
    rep("every day at 5pm do dailies", "do dailies", ts(21, 17), "day", 1)
    rep("daily 6pm check AH", "check AH", ts(21, 18), "day", 1)
    rep("every friday at 7pm raid", "raid", ts(27, 19), "day", 7)
    rep("always friday at 7pm raid", "raid", ts(27, 19), "day", 7)
    rep("every 2h drink water", "drink water", NOW + 7200, "sec", 7200)
    rep("every 30 minutes check mail", "check mail", NOW + 1800, "sec", 1800)
    rep("every hour stretch", "stretch", NOW + 3600, "sec", 3600)
    rep("always in 2h stretch", "stretch", NOW + 7200, "sec", 7200)
    rep("every night feed pet", "feed pet", ts(21, 20), "day", 1)
    rep("every day buy reagents", "buy reagents", ts(22, 9), "day", 1)      -- 9am default, rolls
    rep("every other day check AH", "check AH", ts(22, 9), "day", 2)
    rep("every 2d reset", "reset", ts(22, 9), "day", 2)                     -- day steps use 9am default
    rep("weekly on tuesday at 8pm guild meeting", "guild meeting", ts(24, 20), "day", 7)

    expectPlace("me always when I get to org repair", "repair", "zone", "Orgrimmar", { every = true })
    expectPlace("whenever I get to Orgrimmar buy wine", "buy wine", "zone", "Orgrimmar", { every = true })
    expectPlace("every time I'm at a trainer check skills", "check skills", "npc", "a trainer", { every = true })
    expectPlace("everytime im in xroads say hi", "say hi", "zone", "The Crossroads", { every = true })
    expectPlace("when I get to org repair", "repair", "zone", "Orgrimmar", { every = nil })
    expectPlaceError("me always stretch")                       -- always when?
end

-- Repeating in the scheduler
do
    local now = NOW
    local fired = 0
    local sns = {
        charDB = { reminders = {}, nextId = 1 },
        Clock = { Now = function() return now end, Describe = function() return "?" end },
        Notify = { Fire = function() fired = fired + 1 end },
    }
    assert(loadfile("Scheduler.lua"))("RemindMe", sns)
    local S = sns.Scheduler
    local daily = S.Add("stretch", { type = "time", at = ts(21, 17), every = { unit = "day", n = 1 } })
    local hourly = S.Add("water", { type = "time", at = NOW + 3600, every = { unit = "sec", n = 3600 } })
    local zone = S.Add("repair", { type = "place", kind = "zone", key = "orgrimmar", name = "Orgrimmar",
        armed = true, every = true })
    local npc = S.Add("skills", { type = "place", kind = "npc", npc = "trainer", name = "a trainer", every = true })

    now = ts(21, 17) + 1; S.Check()
    check("daily fires", daily.fired)
    check("daily rescheduled to tomorrow", daily.trigger.at == ts(22, 17), fmt(daily.trigger.at))
    check("hourly fired too (was due 11:00)", hourly.fired and fired == 2)
    check("hourly next is after now", hourly.trigger.at == NOW + 8 * 3600, fmt(hourly.trigger.at))
    now = ts(22, 17); S.Check()
    check("daily fires again without dismissing", fired == 4 and daily.trigger.at == ts(23, 17))
    check("done keeps a repeating one", S.Complete(daily) == false and not daily.fired and S.ByCode(daily.code) == daily)

    S.CheckPlaces({ orgrimmar = true })
    check("zone fires and disarms", zone.fired and zone.trigger.armed == false)
    local before = fired
    S.CheckPlaces({ orgrimmar = true })
    check("still inside: no repeat", fired == before)
    S.CheckPlaces({ durotar = true }); S.CheckPlaces({ orgrimmar = true })
    check("leave and return: fires again", fired == before + 1)

    S.CheckNpc("trainer"); S.CheckNpc("trainer")
    check("npc fires every window", fired == before + 3)

    S.Snooze(npc, 600)
    now = now + 601; S.Check()
    check("snoozed repeating fires once and clears snooze", npc.fired and npc.snoozedUntil == nil)
    check("clear dismisses repeating ones", S.ClearFired() > 0 and #sns.charDB.reminders == 4)
    check("every text", S.EveryText(hourly) == "every 1h" and S.EveryText(daily) == "every day")
    check("place text", S.PlaceText(zone) == "every time you get to Orgrimmar")
end

-- Reminder letter codes (Scheduler.lua with stubbed saved data / clock)
do
    local sns = { charDB = { reminders = {}, nextId = 1 }, Clock = { Now = function() return NOW end } }
    assert(loadfile("Scheduler.lua"))("RemindMe", sns)
    local S = sns.Scheduler

    check("code 1", S.CodeFor(1) == "a")
    check("code 26", S.CodeFor(26) == "z")
    check("code 27", S.CodeFor(27) == "aa")
    check("code 28", S.CodeFor(28) == "ab")
    check("code 52", S.CodeFor(52) == "az")
    check("code 53", S.CodeFor(53) == "ba")

    local trig = { type = "time", at = NOW + 60 }
    local a = S.Add("first", trig)
    local b = S.Add("second", trig)
    local c = S.Add("third", trig)
    check("codes assigned in order", a.code == "a" and b.code == "b" and c.code == "c")
    check("ByCode finds b", S.ByCode("b") == b)
    check("ByCode is case-insensitive", S.ByCode("B") == b)
    check("ByCode unknown", S.ByCode("zz") == nil)

    S.Remove(b)
    check("others keep their codes", a.code == "a" and c.code == "c")
    local d = S.Add("fourth", trig)
    check("freed code is reused", d.code == "b")
    local e = S.Add("fifth", trig)
    check("then next unused", e.code == "d")

    -- reminders saved before codes existed get them on load, oldest first
    table.insert(sns.charDB.reminders, { id = 100, text = "old2", trigger = trig })
    table.insert(sns.charDB.reminders, { id = 99, text = "old1", trigger = trig })
    S.AssignMissingCodes()
    local old1, old2
    for _, r in ipairs(sns.charDB.reminders) do
        if r.text == "old1" then old1 = r elseif r.text == "old2" then old2 = r end
    end
    check("backfilled codes", old1.code == "e" and old2.code == "f")
end

-- Place reminders: arming, firing on arrival, NPC windows, time-based snooze
do
    local now = NOW
    local fired = {}
    local sns = {
        charDB = { reminders = {}, nextId = 1 },
        Clock = { Now = function() return now end, Describe = function() return "?" end },
        Notify = { Fire = function(r, note) fired[#fired + 1] = { r = r, note = note } end },
    }
    assert(loadfile("Scheduler.lua"))("RemindMe", sns)
    local S = sns.Scheduler
    local ORG, BARRENS = { orgrimmar = true, durotar = true }, { barrens = true }

    local inside = S.Add("made inside", { type = "place", kind = "zone", key = "orgrimmar", name = "Orgrimmar", armed = false })
    local outside = S.Add("made outside", { type = "place", kind = "zone", key = "orgrimmar", name = "Orgrimmar", armed = true })
    local trainer = S.Add("learn swords", { type = "place", kind = "npc", npc = "trainer", name = "a trainer" })

    S.CheckPlaces(ORG)
    check("armed one fires on arrival", outside.fired and #fired == 1)
    check("arrival note", fired[1] and fired[1].note == "(you've arrived in Orgrimmar)")
    check("unarmed one waits", not inside.fired)
    S.CheckPlaces(BARRENS)
    check("leaving arms it", inside.trigger.armed == true and not inside.fired)
    S.CheckPlaces(ORG)
    check("re-entering fires it", inside.fired and #fired == 2)

    S.CheckNpc("mailbox")
    check("other npc ignored", not trainer.fired)
    S.CheckNpc("trainer")
    check("trainer fires", trainer.fired and #fired == 3)

    check("place reminders sort after timed ones", (function()
        local t = S.Add("timed", { type = "time", at = NOW + 60 })
        local p = S.Add("pending place", { type = "place", kind = "zone", key = "x", name = "X", armed = true })
        local list = S.Sorted()
        local it, ip
        for i, r in ipairs(list) do
            if r == t then it = i elseif r == p then ip = i end
        end
        S.Remove(t); S.Remove(p)
        return it < ip
    end)())

    S.Snooze(inside, 600)
    check("snoozed place is pending", not inside.fired and inside.snoozedUntil == NOW + 600)
    S.CheckPlaces(BARRENS); S.CheckPlaces(ORG)
    check("snoozed place ignores arrival", not inside.fired)
    now = NOW + 601
    S.Check()
    check("snoozed place fires on time", inside.fired)
end

-- List window data: priority order, Triggers and Status text
do
    local now = NOW
    local sns = {
        charDB = { reminders = {}, nextId = 1 },
        Clock = { Now = function() return now end, Describe = function(t) return "T" .. (t - NOW) end },
        PRIORITY_RANK = { low = 1, normal = 2, high = 3 },
        settings = { defaultPriority = "normal" },
    }
    sns.PriorityOf = function(r) return r.priority or sns.settings.defaultPriority end
    assert(loadfile("Scheduler.lua"))("RemindMe", sns)
    local S = sns.Scheduler
    local lowLater  = S.Add("low later", { type = "time", at = NOW + 600 }, "low")
    local normPlace = S.Add("normal place", { type = "place", kind = "zone", key = "orgrimmar", name = "Orgrimmar", armed = false })
    local normSoon  = S.Add("normal soon", { type = "time", at = NOW + 60 })
    local highLater = S.Add("high later", { type = "time", at = NOW + 900 }, "high")
    local highFired = S.Add("high fired", { type = "time", at = NOW + 1200 }, "high")
    highFired.fired, highFired.firedAt = true, NOW + 30
    local daily = S.Add("daily", { type = "time", at = NOW + 300, every = { unit = "day", n = 1 } }, "low")
    local npc = S.Add("swords", { type = "place", kind = "npc", npc = "trainer", name = "a trainer", every = true })
    local snoozed = S.Add("snoozed", { type = "time", at = NOW + 100 })
    snoozed.snoozedUntil = NOW + 400

    local order = {}
    for i, r in ipairs(S.ByPriority()) do order[i] = r.text end
    check("ByPriority order", table.concat(order, ",") ==
        "high fired,high later,normal soon,snoozed,normal place,swords,daily,low later",
        table.concat(order, ","))

    check("TriggerText time", S.TriggerText(normSoon) == "T60")
    check("TriggerText repeating", S.TriggerText(daily) == "T300, every day", S.TriggerText(daily))
    check("TriggerText zone (unarmed)", S.TriggerText(normPlace) == "when you get to Orgrimmar (after you leave)",
        S.TriggerText(normPlace))
    check("TriggerText npc", S.TriggerText(npc) == "every time you're at a trainer", S.TriggerText(npc))
    check("StatusText waiting", S.StatusText(lowLater) == "waiting")
    check("StatusText fired", S.StatusText(highFired) == "fired T30", S.StatusText(highFired))
    check("StatusText snoozed", S.StatusText(snoozed) == "snoozed until T400", S.StatusText(snoozed))
    check("highLater untouched", not highLater.fired)
end

-- Day parts and the morning / night settings (time reminders)
expect("friday night at 9 raid", "raid", ts(27, 21))
expect("tomorrow morning at 8 run", "run", ts(22, 8))
expect("tomorrow morning stretch", "stretch", ts(22, 9))
expect("friday night raid", "raid", ts(27, 20))
expect("friday evening raid", "raid", ts(27, 20))
expect("this evening raid", "raid", ts(21, 20))
expect("in the morning stretch", "stretch", ts(22, 9))     -- 9am passed: tomorrow
expect("tomorrow night at 11 log off", "log off", ts(22, 23))
expectError("this morning stretch")                         -- already passed
do
    local function custom(input, message, at)
        local c = ctx(); c.morning = 7 * 60; c.night = 21 * 60 + 30
        local r, err = Parser.Parse(input, c)
        check(input .. " [custom times]", r and r.message == message and r.trigger.at == at,
            r and ("got %q @ %s"):format(r.message, fmt(r.trigger.at)) or err)
    end
    custom("tomorrow stretch", "stretch", ts(22, 7))
    custom("tonight raid", "raid", ts(21, 21, 30))
    custom("every night feed pet", "feed pet", ts(21, 21, 30))
    custom("friday morning bank", "bank", ts(27, 7))
end

-- Window words without a place just set the time; other uses stay text
expect("call mom after 5pm", "call mom", ts(21, 17))
expect("pay rent by friday", "pay rent", ts(27, 9))
expect("drop by the bank at 5pm", "drop by the bank", ts(21, 17))
expect("buy from vendor tomorrow", "buy from vendor", ts(22, 9))
expect("raid starting at 7pm", "raid", ts(21, 19))

-- Time + place: a place reminder with a window (after / before)
do
    local function win(input, message, name, after, before, extra)
        local c = ctx(); c.places = PLACES
        local r, err = Parser.Parse(input, c)
        if not r then check(input, false, "error: " .. tostring(err)); return end
        local t = r.trigger
        check(input .. " [message]", r.message == message, ("got %q, want %q"):format(r.message, message))
        check(input .. " [place]", t.type == "place" and t.name == name, tostring(t.name))
        check(input .. " [after]", t.after == after, ("got %s, want %s"):format(fmt(t.after), fmt(after)))
        check(input .. " [before]", t.before == before, ("got %s, want %s"):format(fmt(t.before), fmt(before)))
        for k, v in pairs(extra or {}) do
            local got = t[k]
            if type(got) == "table" then got = got.unit .. " " .. got.n end
            check(input .. " [" .. k .. "]", got == v, ("got %s, want %s"):format(tostring(got), tostring(v)))
        end
    end
    win("tomorrow when I get to org buy reagents", "buy reagents", "Orgrimmar", ts(22, 0), ts(23, 0), { every = nil })
    win("when I get to org tomorrow buy reagents", "buy reagents", "Orgrimmar", ts(22, 0), ts(23, 0))
    win("tomorrow morning when I get to IF buy reagents", "buy reagents", "Ironforge", ts(22, 9), ts(23, 0))
    win("tonight when I get to sw check mail", "check mail", "Stormwind City", ts(21, 20), ts(22, 0))
    win("after 5pm when I'm in org buy wine", "buy wine", "Orgrimmar", ts(21, 17), ts(22, 0))
    win("when I get to Orgrimmar at 5pm buy wine", "buy wine", "Orgrimmar", ts(21, 17), ts(22, 0))
    win("in 2h when I get to org repair", "repair", "Orgrimmar", NOW + 7200, nil)
    win("before 8pm when I get to org repair", "repair", "Orgrimmar", nil, ts(21, 20))
    win("friday before 8pm next time I'm at the bank deposit mats", "deposit mats", "the bank", ts(27, 0), ts(27, 20))
    win("by friday when I get to org repair", "repair", "Orgrimmar", nil, ts(28, 0))
    win("by tonight when I get to org repair", "repair", "Orgrimmar", nil, ts(21, 20))
    win("every day when I get to org repair", "repair", "Orgrimmar", ts(21, 0), ts(22, 0), { every = "day 1" })
    win("every friday next time I'm at the ah sell herbs", "sell herbs", "the auction house", ts(27, 0), ts(28, 0),
        { every = "day 7" })
    win("every night when I get to org feed pet", "feed pet", "Orgrimmar", ts(21, 20), ts(22, 0), { every = "day 1" })
    win("every 2h when in org drink", "drink", "Orgrimmar", nil, nil, { every = "sec 7200" })
    win("whenever I'm in org after 5pm buy wine", "buy wine", "Orgrimmar", ts(21, 17), ts(22, 0),
        { every = "day 1", each = true })
    win("whenever I get to org repair", "repair", "Orgrimmar", nil, nil, { every = true })
    expectPlaceError("before 9am when I get to org repair")   -- deadline already passed
    local c = ctx(); c.places = PLACES
    local r = Parser.Parse("at 5pm at Orgrimmar buy wine", c)
    check("bare place + time doesn't combine", r and r.trigger.type == "time" and r.trigger.at == ts(21, 17),
        r and r.message)
end

-- Place windows in the scheduler
do
    local now = NOW
    local fired, asked, here = {}, {}, {}
    local sns = {
        charDB = { reminders = {}, nextId = 1 },
        Clock = {
            Now = function() return now end,
            Describe = function(t) return "T" .. (t - NOW) end,
            DescribeDay = function(t) return "D" .. os.date("%d", t) end,
            DescribeTime = function(t) return os.date("%H:%M", t) end,
            MinuteOfDay = function(t) local d = os.date("*t", t); return d.hour * 60 + d.min end,
            Weekday = function(t) return os.date("%A", t) end,
        },
        Notify = {
            Fire = function(r, note) fired[#fired + 1] = { r = r, note = note } end,
            AskAlreadyHere = function(r) asked[#asked + 1] = r end,
        },
        Places = { IsHere = function(key) return here[key] == true end },
    }
    assert(loadfile("Scheduler.lua"))("RemindMe", sns)
    local S = sns.Scheduler
    local ORG, AWAY = { orgrimmar = true }, { durotar = true }
    local function zone(text, extra)
        local t = { type = "place", kind = "zone", key = "orgrimmar", name = "Orgrimmar", armed = true }
        for k, v in pairs(extra or {}) do t[k] = v end
        return S.Add(text, t)
    end

    -- "tomorrow when I get to org": nothing before the window, fires inside it
    local tmrw = zone("tomorrow", { after = ts(22, 0), before = ts(23, 0) })
    S.CheckPlaces(ORG)
    check("window: no fire before it opens", not tmrw.fired)
    S.CheckPlaces(AWAY)
    now = ts(22, 1); S.Check()
    check("window opens elsewhere: no popup", tmrw.trigger.opened and #asked == 0)
    S.CheckPlaces(ORG)
    check("window: fires on arrival inside it", tmrw.fired)

    -- Deadline passes: missed alert, stays fired
    now = NOW
    local dl = zone("deadline", { before = ts(21, 20) })
    now = ts(21, 20); S.Check()
    check("deadline: missed alert", dl.fired and fired[#fired].r == dl
        and fired[#fired].note:find("missed", 1, true) ~= nil, fired[#fired] and fired[#fired].note)
    local n = #fired
    now = ts(21, 21); S.Check()
    check("deadline: alerts once", #fired == n)

    -- Periodic: once a day, moves on when it fires and when it closes
    now = NOW
    local daily = zone("daily", { after = ts(21, 0), before = ts(22, 0), opened = true, every = { unit = "day", n = 1 } })
    S.CheckPlaces(ORG)
    check("daily: fires in today's window", daily.fired)
    check("daily: window moves to tomorrow", daily.trigger.after == ts(22, 0) and daily.trigger.before == ts(23, 0),
        fmt(daily.trigger.after))
    check("daily: disarmed", daily.trigger.armed == false)

    -- Already there when it opens: popup, then skip
    here.orgrimmar = true
    now = ts(22, 0) + 5; S.Check()
    check("already here: asked", asked[#asked] == daily and daily.trigger.armed == false)
    check("skip moves the window", S.CancelAlreadyHere(daily) == "skipped" and daily.trigger.after == ts(23, 0))

    -- Window closes without a visit: moves on silently
    here.orgrimmar = false
    n = #fired
    now = ts(24, 0) + 1; S.Check()
    check("daily: closed window moves on", daily.trigger.after == ts(24, 0) and daily.trigger.before == ts(25, 0),
        fmt(daily.trigger.after) .. " / " .. fmt(daily.trigger.before))
    check("daily: no alert for a missed window", #fired == n)

    -- One-off already here: cancel deletes it
    now = NOW
    here.orgrimmar = true
    local oneoff = zone("oneoff", { after = ts(21, 11), before = ts(22, 0), armed = false })
    now = ts(21, 11); S.Check()
    check("one-off already here: asked", asked[#asked] == oneoff)
    check("cancel removes a one-off", S.CancelAlreadyHere(oneoff) == "removed" and S.ByCode(oneoff.code) == nil)
    here.orgrimmar = false

    -- NPC window and cooldown
    now = NOW
    local npc = S.Add("bank", { type = "place", kind = "npc", npc = "bank", name = "the bank", after = ts(22, 0) })
    S.CheckNpc("bank")
    check("npc: closed window ignored", not npc.fired)
    now = ts(22, 1); S.CheckNpc("bank")
    check("npc: fires in window", npc.fired)
    local cd = S.Add("drink", { type = "place", kind = "npc", npc = "vendor", name = "a vendor",
        every = { unit = "sec", n = 3600 } })
    S.CheckNpc("vendor")
    n = #fired
    S.CheckNpc("vendor")
    check("cooldown: not again within the hour", cd.fired and #fired == n)
    now = now + 3601; S.CheckNpc("vendor")
    check("cooldown: again after it", #fired == n + 1)

    -- Each arrival inside a periodic window ("whenever I'm in org after 5pm")
    now = ts(21, 18)
    local each = zone("each", { after = ts(21, 17), before = ts(22, 0), opened = true, each = true,
        every = { unit = "day", n = 1 } })
    S.CheckPlaces(ORG)
    S.CheckPlaces(AWAY); S.CheckPlaces(ORG)
    check("each: fires every arrival in the window", each.fired and each.trigger.after == ts(21, 17))

    -- Text
    now = NOW
    local function tt(trig) return S.TriggerText({ trigger = trig }) end
    local function z(extra)
        local t = { type = "place", kind = "zone", key = "orgrimmar", name = "Orgrimmar", armed = true }
        for k, v in pairs(extra) do t[k] = v end
        return t
    end
    check("text: whole day", tt(z({ after = ts(22, 0), before = ts(23, 0) })) == "when you get to Orgrimmar, D22",
        tt(z({ after = ts(22, 0), before = ts(23, 0) })))
    check("text: after", tt(z({ after = ts(21, 17), before = ts(22, 0) })) == "when you get to Orgrimmar, D21 after 17:00",
        tt(z({ after = ts(21, 17), before = ts(22, 0) })))
    check("text: before", tt(z({ before = ts(21, 20) })) == "when you get to Orgrimmar, before 20:00 D21",
        tt(z({ before = ts(21, 20) })))
    check("text: by end of day", tt(z({ before = ts(28, 0) })) == "when you get to Orgrimmar, by the end of D27",
        tt(z({ before = ts(28, 0) })))
    check("text: day before time", tt(z({ after = ts(27, 0), before = ts(27, 20) })) == "when you get to Orgrimmar, D27 before 20:00",
        tt(z({ after = ts(27, 0), before = ts(27, 20) })))
    check("text: from", tt(z({ after = NOW + 7200 })) == "when you get to Orgrimmar, from T7200",
        tt(z({ after = NOW + 7200 })))
    check("text: once a day", tt(z({ after = ts(21, 0), before = ts(22, 0), every = { unit = "day", n = 1 } }))
        == "when you get to Orgrimmar, once a day")
    check("text: weekly", tt(z({ after = ts(27, 0), before = ts(28, 0), every = { unit = "day", n = 7 } }))
        == "when you get to Orgrimmar, every Friday")
    check("text: each after", tt(z({ after = ts(21, 17), before = ts(22, 0), each = true, every = { unit = "day", n = 1 } }))
        == "every time you get to Orgrimmar, each day, after 17:00",
        tt(z({ after = ts(21, 17), before = ts(22, 0), each = true, every = { unit = "day", n = 1 } })))
    check("text: cooldown", tt(z({ every = { unit = "sec", n = 3600 } })) == "when you get to Orgrimmar, at most every 1h")
    check("status: starts", S.StatusText({ trigger = z({ after = ts(22, 0), before = ts(23, 0) }) }) == "starts T50400",
        S.StatusText({ trigger = z({ after = ts(22, 0), before = ts(23, 0) }) }))
end

-- Release packaging: RemindMe.toc (fallback) and RemindMe_Forever.toc (WowUp Hub's
-- Forever flavour) must stay identical, and every listed file must exist.
do
    local function read(path)
        local f = io.open(path, "rb")
        if not f then return nil end
        local s = f:read("*a"):gsub("\r", "")
        f:close()
        return s
    end
    local base, forever = read("RemindMe.toc"), read("RemindMe_Forever.toc")
    check("RemindMe.toc exists", base ~= nil)
    check("RemindMe_Forever.toc exists", forever ~= nil)
    check("TOC files are identical", base == forever,
        "edit both RemindMe.toc and RemindMe_Forever.toc together")
    for line in (base or ""):gmatch("[^\n]+") do
        if not line:match("^#") and line:match("%S") then
            local file = line:match("^%s*(.-)%s*$")
            check("TOC file exists: " .. file, read(file) ~= nil)
        end
    end
    check("TOC version is the packager token", (base or ""):match("\n## Version: @project%-version@\n") ~= nil)
end

print(("%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
