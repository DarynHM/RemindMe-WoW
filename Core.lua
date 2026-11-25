-- Core.lua
-- Namespace helpers, SavedVariables init and event wiring. Loaded last.

local AddonName, ns = ...

local SETTINGS_VERSION = 1
local CHAR_VERSION = 1
local FIRST_CHECK_DELAY = 5  -- let chat frames finish loading before firing missed reminders

function ns.Print(msg)
    print("|cff33ff99RemindMe|r: " .. msg)
end

-- Extra output while /remind debug is on. Arguments are string.format style;
-- non-strings are tostring'd first.
function ns.Debug(fmt, ...)
    if not (ns.settings and ns.settings.debug) then return end
    local args = { ... }
    for i = 1, select("#", ...) do
        if type(args[i]) ~= "string" and type(args[i]) ~= "number" then args[i] = tostring(args[i]) end
    end
    print("|cff888888RemindMe debug: " .. fmt:format(unpack(args, 1, select("#", ...))):gsub("|", "||") .. "|r")
end

-- Priorities, lowest to highest. Shared by Notify, Indicator, Commands, Options.
ns.PRIORITY_ORDER = { "low", "normal", "high" }
ns.PRIORITY_RANK = { low = 1, normal = 2, high = 3 }
ns.PRIORITY_LABEL = { low = "Low", normal = "Normal", high = "High" }
ns.PRIORITY_COLOR = {          -- hex for chat strings, rgb for textures/tooltips
    low    = { hex = "ff66b3ff", r = 0.40, g = 0.70, b = 1.00 },   -- light blue (grey was hard to read)
    normal = { hex = "ffffd100", r = 1.00, g = 0.82, b = 0.00 },
    high   = { hex = "ffff5a2a", r = 1.00, g = 0.35, b = 0.16 },
}

-- Effective priority of a reminder (nil means "use the default").
function ns.PriorityOf(r)
    local p = r and r.priority
    if p and ns.PRIORITY_RANK[p] then return p end
    return ns.settings.defaultPriority
end

-- Everything that shows reminder state refreshes from here (Scheduler calls
-- it on every change).
function ns.OnRemindersChanged()
    if ns.Indicator then ns.Indicator.Refresh() end
    if ns.ListWindow then ns.ListWindow.Refresh() end
end

function ns.Colorize(priority, text)
    return "|c" .. ns.PRIORITY_COLOR[priority].hex .. text .. "|r"
end

local PROFILE_DEFAULTS = {
    low = {
        chat = true, raidWarning = false, sound = false, soundKey = "TELL_MESSAGE",
        animation = "none", edgeFlash = false, taskbarFlash = false,
    },
    normal = {
        chat = true, raidWarning = false, sound = true, soundKey = "RAID_WARNING",
        animation = "pulse", edgeFlash = false, taskbarFlash = false,
    },
    high = {
        chat = true, raidWarning = true, sound = true, soundKey = "RAID_WARNING",
        animation = "glow", edgeFlash = true, taskbarFlash = true,
    },
}

-- Fill in missing keys without touching values the user already set.
local function applyDefaults(t, defaults)
    for k, v in pairs(defaults) do
        if t[k] == nil then t[k] = v end
    end
end

local function InitDB()
    RemindMeDB = RemindMeDB or {}
    local s = RemindMeDB

    applyDefaults(s, { clock = "local", defaultPriority = "normal", debug = false,
        morning = 540, night = 1200 })   -- minutes after midnight: 9am, 8pm
    s.profiles = s.profiles or {}
    for _, p in ipairs(ns.PRIORITY_ORDER) do
        s.profiles[p] = s.profiles[p] or {}
        applyDefaults(s.profiles[p], PROFILE_DEFAULTS[p])
        -- Removed animations: "proc" (square art on a round icon), "bounce".
        local anim = s.profiles[p].animation
        if anim == "proc" then s.profiles[p].animation = "ring" end
        if anim == "bounce" then s.profiles[p].animation = "pulse" end
    end
    s.indicator = s.indicator or {}
    applyDefaults(s.indicator, { enabled = true, locked = true, icon = "watch", scale = 1,
        alpha = 1, onlyWhenDue = true })
    s.window = s.window or {}          -- list window: left, top, w, h
    s.window.cols = s.window.cols or {} -- column widths you dragged
    s.version = SETTINGS_VERSION
    ns.settings = s

    RemindMeCharDB = RemindMeCharDB or {}
    local c = RemindMeCharDB
    if (c.version or 0) < CHAR_VERSION then
        c.reminders = c.reminders or {}
        c.nextId = c.nextId or 1
        c.version = CHAR_VERSION
    end
    ns.charDB = c
    ns.Scheduler.AssignMissingCodes()
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == AddonName then
        self:UnregisterEvent("ADDON_LOADED")
        InitDB()
        ns.ready = true
    elseif event == "PLAYER_LOGIN" then
        ns.Options.Build()
        ns.Indicator.Refresh()
        C_Timer.After(FIRST_CHECK_DELAY, function()
            ns.Scheduler.Check()
            ns.Scheduler.Start()
            ns.Places.Start()
        end)
    end
end)
