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

-- A place reminder's window opened while you're already standing there
-- ("tomorrow when I get to IF", and you're in Ironforge at midnight). Ask:
-- keep it for next arrival (the default: Escape / closing keeps it) or cancel
-- it (a periodic one just skips this window). One popup at a time.
local queue = {}
local POPUP = "REMINDME_ALREADY_HERE"

local function showNext()
    local r = table.remove(queue, 1)
    if not r then return end
    local t = r.trigger
    local periodic = type(t.every) == "table" and t.every.unit == "day"
    local dialog = StaticPopupDialogs[POPUP]
    dialog.button1 = periodic and "Skip this time" or "Cancel reminder"
    StaticPopup_Show(POPUP, Notify.Escape(t.name), Notify.Escape(r.text), r)
end

function Notify.AskAlreadyHere(r)
    local name = Notify.Escape(r.trigger.name)
    if not (StaticPopup_Show and StaticPopupDialogs) then
        ns.Print("You're already in " .. name .. ", so I'll remind you to |cffffffff" ..
            Notify.Escape(r.text) .. "|r next time you arrive. |cff999999(/remind delete " ..
            (r.code or "?") .. " cancels it)|r")
        return
    end
    if not StaticPopupDialogs[POPUP] then
        StaticPopupDialogs[POPUP] = {
            text = "RemindMe: you're already in %s.\n\n|cffffffff%s|r\n\nI'll remind you next time you arrive.",
            button1 = "Cancel reminder",
            button2 = "Next arrival",
            OnAccept = function(_, data)
                if not data then return end
                local result = ns.Scheduler.CancelAlreadyHere(data)
                ns.Print((result == "skipped" and "skipped this time: " or "cancelled: ") .. Notify.Escape(data.text))
            end,
            OnHide = function()
                if C_Timer then C_Timer.After(0, showNext) else showNext() end
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
        }
    end
    queue[#queue + 1] = r
    if not (StaticPopup_Visible and StaticPopup_Visible(POPUP)) then showNext() end
end
