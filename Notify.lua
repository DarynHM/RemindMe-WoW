-- Notify.lua
-- How a reminder is presented when it fires. Each priority (low / normal /
-- high) has its own profile of channels, set in the options panel.
-- The on-screen indicator refreshes itself via ns.OnRemindersChanged().

local _, ns = ...

local Notify = {}
ns.Notify = Notify

-- Escape "|" so user text can't create broken UI escape sequences.
function Notify.Escape(text)
    return (text:gsub("|", "||"))
end

function Notify.Fire(reminder, note)
    local priority = ns.PriorityOf(reminder)
    local profile = ns.settings.profiles[priority]
    local text = Notify.Escape(reminder.text)

    if profile.chat then
        local code = reminder.code and (" |cffffd100(" .. reminder.code .. ")|r") or ""
        ns.Print(ns.Colorize(priority, "Reminder:") .. code .. " " .. text ..
            (note and ("  |cff999999" .. note .. "|r") or ""))
    end

    if profile.raidWarning and RaidNotice_AddMessage and RaidWarningFrame then
        local c = ns.PRIORITY_COLOR[priority]
        RaidNotice_AddMessage(RaidWarningFrame, "Reminder: " .. text, { r = c.r, g = c.g, b = c.b })
    end

    if profile.sound then
        ns.Media.PlaySound(profile.soundKey)
    end

    if profile.edgeFlash then
        ns.Flash.Edges(priority)
    end

    if profile.taskbarFlash then
        ns.Flash.Taskbar()
    end
end

-- Used by the options "Test" buttons: fires every channel of that priority
-- and previews the indicator with its animation.
function Notify.Test(priority)
    Notify.Fire({ text = ns.PRIORITY_LABEL[priority] .. " priority test reminder", priority = priority })
    ns.Indicator.Preview(priority)
end
