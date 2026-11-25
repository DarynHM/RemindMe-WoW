-- Commands.lua
-- /remind. Anything that isn't an exact management command is
-- treated as a new reminder, so "/remind delete the trash at 5pm" still works.

local _, ns = ...

local DEFAULT_SNOOZE = 10 * 60

local function codeTag(r)
    return "|cffffd100" .. r.code .. "|r"
end

local function priorityTag(r)
    local p = ns.PriorityOf(r)
    if p == "normal" then return "" end
    return " " .. ns.Colorize(p, "[" .. p .. "]")
end

-- What's next for a reminder: "today 5:00 PM", "today 9:00 AM, every day",
-- "every time you get to Orgrimmar (after you leave)".
local function upcoming(r)
    local where = ns.Scheduler.PlaceText(r)
    if where then
        if r.trigger.armed == false then where = where .. " (after you leave)" end
        return where
    end
    local every = ns.Scheduler.EveryText(r)
    local at = r.trigger.at
    return (at and ns.Clock.Describe(at) or "?") .. (every and (", " .. every) or "")
end

-- "next today 9:00 AM, every day" / "every time you get to Orgrimmar"
local function nextText(r)
    if r.trigger.type == "place" then return upcoming(r) end
    return "next " .. upcoming(r)
end

local function describeReminder(r)
    local repeating = r.trigger and r.trigger.every
    local text
    if r.fired then
        local at = r.firedAt or ns.Scheduler.DueTime(r)
        text = "|cffff8040fired|r " .. (at and ns.Clock.Describe(at) or "")
        if repeating then text = text .. "; " .. nextText(r) end
        return text
    elseif r.snoozedUntil then
        text = "snoozed until " .. ns.Clock.Describe(r.snoozedUntil)
        if repeating then text = text .. ", then " .. upcoming(r) end
        return text
    end
    return upcoming(r)
end

-- Chat uses a proportional font, so no column padding: one short
-- "command - what it does" line each. Never put a raw "|" in chat text
-- ("|n" is a newline code), so alternatives are written "a / b".
local function showHelp()
    local Y, B, G, R = "|cffffd100", "|cff99ccff", "|cff999999", "|r"
    local function cmd(c, desc) print(Y .. c .. R .. " - " .. desc) end
    local function sub(label, text) print("   " .. G .. label .. ":" .. R .. " " .. text) end
    ns.Print("commands:")
    cmd("/remind <what> <when or where>", "add a reminder")
    sub("when", "at 5pm, 17:30, noon, in 20 min, 10m, 1h30m, tomorrow, friday at 9am")
    sub("where", "when I get to Orgrimmar, next time I'm in org, at a trainer / mailbox / bank / AH")
    sub("repeat", "always at 9am, every friday at 7pm, every 2h, daily, whenever I get to org")
    sub("priority", "-L or quietly (low), -M (normal), -H, urgent or ! (high)")
    sub("e.g.", B .. "/remind me to buy potions at 12pm" .. R)
    sub("e.g.", B .. "/remind when I get to Orgrimmar, upgrade my weapon skill" .. R)
    cmd("/remind list", "your reminders and their letter codes")
    cmd("/remind done <code>", "complete one, e.g. /remind done b (repeating: dismiss this alert)")
    cmd("/remind delete <code>", "delete one (stops a repeating one)")
    cmd("/remind snooze [code] [time]", "snooze (default 10 min)")
    cmd("/remind priority <code> <L / M / H>", "change priority (low / normal / high also work)")
    cmd("/remind clear", "remove fired reminders")
    cmd("/remind clock <local / server>", "which clock times use")
    cmd("/remind options", "open settings")
    cmd("/remind where", "show the place names RemindMe sees where you stand")
    cmd("/remind debug", "toggle debug output")
end

local function showList()
    local list = ns.Scheduler.Sorted()
    if #list == 0 then
        ns.Print("no reminders.")
        return
    end
    ns.Print("reminders:")
    for _, r in ipairs(list) do
        print(("  %s. %s%s |cff999999- %s|r"):format(codeTag(r), ns.Notify.Escape(r.text), priorityTag(r),
            describeReminder(r)))
    end
end

local function withCode(code, fn)
    local r = ns.Scheduler.ByCode(code)
    if not r then
        ns.Print("no reminder '" .. code .. "'. See /remind list for the letter codes.")
        return
    end
    fn(r)
end

local function snooze(rest)
    rest = rest or ""
    local target, seconds

    if rest == "" then
        seconds = DEFAULT_SNOOZE
    else
        -- "snooze 15m" (duration only) or "snooze b" / "snooze b 15m"
        seconds = ns.Parser.ParseDuration(rest)
        if not seconds then
            local code, durStr = rest:match("^(%a+)%s*(.*)$")
            if code then
                target = ns.Scheduler.ByCode(code)
                if not target then
                    ns.Print("no reminder '" .. code .. "'. See /remind list for the letter codes.")
                    return
                end
                seconds = (durStr == "") and DEFAULT_SNOOZE or ns.Parser.ParseDuration(durStr)
            end
        end
    end

    if not seconds then
        ns.Print("couldn't read that snooze time. Try |cff99ccff/remind snooze b 15m|r.")
        return
    end

    target = target or ns.Scheduler.MostRecentFired()
    if not target then
        ns.Print("nothing to snooze. Give a letter code from /remind list.")
        return
    end

    ns.Scheduler.Snooze(target, seconds)
    ns.Print("snoozed |cffffffff" .. ns.Notify.Escape(target.text) .. "|r until " ..
        ns.Clock.Describe(target.snoozedUntil) .. ".")
end

local function addReminder(msg)
    local ctx = ns.Clock.ParserContext()
    ctx.places = ns.Places.ParserContext()
    local result, err = ns.Parser.Parse(msg, ctx)
    if not result then
        ns.Print("|cffff4040" .. err .. "|r")
        return
    end
    local trigger = result.trigger
    do
        local parts = {}
        for k, v in pairs(trigger) do
            if type(v) == "table" then v = (v.n or "?") .. " " .. (v.unit or "?") end
            parts[#parts + 1] = k .. "=" .. tostring(v)
        end
        table.sort(parts)
        ns.Debug("parsed %q -> message %q, priority %s, trigger {%s}", msg, result.message,
            result.priority, table.concat(parts, ", "))
    end
    if trigger.type == "time" then
        trigger.at = ns.Clock.ToReal(trigger.at)
    elseif trigger.kind == "zone" then
        trigger.armed = not ns.Places.IsHere(trigger.key)
    end

    local r = ns.Scheduler.Add(result.message, trigger, result.priority)
    local p = ns.PriorityOf(r)
    local suffix = (p ~= "normal") and (" " .. ns.Colorize(p, "(" .. p .. " priority)")) or ""
    local when = upcoming(r)
    ns.Print("I'll remind you to |cffffffff" .. ns.Notify.Escape(r.text) .. "|r " ..
        ns.Notify.Escape(when) .. suffix .. ". |cff999999(|r" .. codeTag(r) .. "|cff999999)|r")

    if trigger.kind == "zone" and not trigger.known then
        local s = ns.Parser.Suggest(trigger.key, ctx.places)
        ns.Print("|cffffff00I don't know a place called '" .. ns.Notify.Escape(trigger.name) ..
            "'.|r I'll match it exactly against zone and subzone names." ..
            (#s > 0 and (" Did you mean " .. table.concat(s, ", ") .. "?") or ""))
    end
    if trigger.armed == false then
        ns.Print("You're in " .. ns.Notify.Escape(trigger.name) ..
            " now, so I'll remind you next time you arrive.")
    end
end

local function handle(msg)
    msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local lower = msg:lower()

    if lower == "" or lower == "help" or lower == "?" then
        showHelp()
    elseif lower == "list" or lower == "ls" then
        showList()
    elseif lower:match("^done%s+%a+$") or lower:match("^complete%s+%a+$") then
        withCode(lower:match("(%a+)$"), function(r)
            if ns.Scheduler.Complete(r) then
                ns.Print("completed: " .. ns.Notify.Escape(r.text))
            else
                ns.Print("dismissed: " .. ns.Notify.Escape(r.text) .. " |cff999999(repeats: " ..
                    ns.Notify.Escape(nextText(r)) .. ". /remind delete " .. r.code .. " stops it)|r")
            end
        end)
    elseif lower:match("^delete%s+%a+$") or lower:match("^del%s+%a+$") or lower:match("^remove%s+%a+$") then
        withCode(lower:match("(%a+)$"), function(r)
            ns.Scheduler.Remove(r)
            ns.Print("deleted: " .. ns.Notify.Escape(r.text))
        end)
    elseif lower == "snooze" or lower:match("^snooze%s") then
        snooze(lower:match("^snooze%s+(.*)$"))
    elseif lower == "clear" then
        ns.Print(("removed %d fired reminder(s)."):format(ns.Scheduler.ClearFired()))
    elseif lower == "clock" or lower:match("^clock%s+%a+$") then
        local mode = lower:match("^clock%s+(%a+)$")
        if mode == "local" or mode == "server" then
            ns.settings.clock = mode
        elseif mode then
            ns.Print("clock must be 'local' or 'server'.")
            return
        end
        ns.Print("clock: |cffffffff" .. ns.Clock.Mode() .. "|r (now " ..
            ns.Clock.Describe(ns.Clock.Now()) .. ")")
    elseif lower:match("^priority%s+%a+%s+%-?%a+$") or lower:match("^pri%s+%a+%s+%-?%a+$") then
        local code, p = lower:match("^%a+%s+(%a+)%s+(%-?%a+)$")
        if p == "quiet" then p = "low" elseif p == "loud" or p == "urgent" then p = "high" end
        p = ns.Parser.PriorityWord(p) -- low / normal / high, l / m / n / h, -h, med...
        if not p then
            ns.Print("priority must be low / normal / high, or L / M / H.")
            return
        end
        withCode(code, function(r)
            r.priority = p
            ns.OnRemindersChanged()
            ns.Print(ns.Notify.Escape(r.text) .. " is now " .. ns.Colorize(p, p .. " priority") .. ".")
        end)
    elseif lower == "debug" or lower == "debug on" or lower == "debug off" then
        if lower == "debug" then ns.settings.debug = not ns.settings.debug
        else ns.settings.debug = (lower == "debug on") end
        ns.Print("debug " .. (ns.settings.debug and "|cff40ff40on|r: parses, zone changes and NPC windows are printed. "
            .. "For Lua errors also use |cff99ccff/console scriptErrors 1|r." or "|cffff4040off|r."))
    elseif lower == "where" then
        ns.Print("you are in: |cffffffff" .. ns.Notify.Escape(ns.Places.Describe()) .. "|r")
    elseif lower == "options" or lower == "config" or lower == "settings" then
        ns.Options.Open()
    else
        addReminder(msg)
    end
end

ns.Commands = { ShowList = showList }

SlashCmdList["REMINDME"] = function(msg)
    if not ns.ready then
        ns.Print("still loading, try again in a moment.")
        return
    end
    handle(msg)
end
SLASH_REMINDME1 = "/remind"
