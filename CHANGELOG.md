# RemindMe

## 0.1.0

First release, for WoW Forever (Interface 16001).

- `/remind` reminders in plain language: `at 5pm`, `in 20 minutes`, `1h30m`, `tomorrow`, `friday at 9am`, `tmrw`, `@5pm` and more.
- Location reminders that fire when you arrive: `when I get to Orgrimmar`, `next time I'm in IF`, bare `at Ironforge`, with WoW short names (`org`, `sw`, `brd`, `naxx`...).
- NPC reminders: trainer, weapon master, mailbox, vendor, bank, guild bank, auction house, flight master.
- Repeating reminders: `always`, `every day at 5pm`, `daily`, `every 2h`, `every other day`, `whenever I get to org`.
- Low / Normal / High priority, set with words, `!`, or the shorthands `-L` / `-M` / `-H`, each with its own alerts: chat, raid warning, sound (with LibSharedMedia sounds if available), screen-edge flash and taskbar flash.
- Stable letter codes for `done`, `delete`, `snooze` and `priority`.
- On-screen icon: round, movable, scalable, adjustable opacity, optional always-on, priority-coloured tooltip, animations (pulse, glow, ring, sparkles, comet). Shift-click opens the reminder list, Ctrl-click opens options.
- Reminder list window (Shift-click the icon or /remind list): priority order, triggers, status, priority dropdown, Done / Delete; resizable with adjustable columns.
- Options panel in Esc > Options > AddOns > RemindMe, with sound previews.
- Local or realm clock; reminders missed while offline fire on login.
