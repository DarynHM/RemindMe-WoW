# Natural Language Reminders

**Set reminders in WoW by typing them the way you'd say them.** Natural Language Reminders works out when (or where) you mean and nudges you at the right moment, with a chat message, a sound, a screen flash and a little icon by the minimap.

```
/remind in 30m repair
/remind at 7pm tomorrow raid
/remind when I get to Orgrimmar, get my weapon skill
/remind next time I'm at a mailbox, send mats to my alt
/remind tomorrow when I get to Ironforge, buy reagents
/remind every day at 9am do the daily quests
```

Built for **WoW Forever**. (It used to be called RemindMe.)

## Why I made it

I wanted a quick way to set reminders without leaving the game. Type it once, then stop thinking about it.

## Install

- **WowUp:** search for **Natural Language Reminders** in Get Addons with your WoW Forever install selected.
- **Manually:** download the zip from [Releases](https://github.com/DarynHM/NaturalLanguageReminders-WoW/releases) and extract it into `World of Warcraft\_forever_\Interface\AddOns`.

## What it can do

- **Times:** `in 20 minutes`, `1h30m`, `at 5pm`, `noon`, `tomorrow`, `tomorrow morning`, `friday night`, `tmrw`, `@5pm`. You can choose what time "morning" and "night" mean in the options.
- **Places:** `when I get to Ironforge`, `next time I'm in org`, `at IF`. It fires when you arrive. It knows the usual short names too: `sw`, `uc` and so on.
- **NPCs:** next time you open a trainer, mailbox, vendor, bank, guild bank, auction house or flight master.
- **Time and place together:** `tomorrow when I get to IF`, `after 5pm when I'm in org`, `before 8pm next time I'm at the bank`. If the day ends and you never got there, it tells you that you missed it. If you're already there when the time comes, it asks whether to wait for your next arrival.
- **Repeating:** `every day at 5pm`, `daily`, `every 2h`, `always`, `whenever I get to org`, `every day when I get to org` (once a day).
- **Priority:** add `-L`, `-M` or `-H` (or say `quietly` / `urgent`, or start with `!`). Each priority gets its own alerts, which you set up in the options.
- **Reminder list:** Shift-click the icon or type `/remind list` to see everything. You can mark reminders done, delete them or change their priority there.
- **Missed reminders:** anything that came due while you were offline pops up when you log in.

## Commands

Each reminder gets a letter code (`a`, `b`, `c`…) that stays the same until you finish or delete it.

| Command | What it does |
|---|---|
| `/remind <what> <when>` | Add a reminder |
| `/remind list` | Open the reminder list (`list chat` prints it in chat instead) |
| `/remind done <code>` | Mark it done |
| `/remind delete <code>` | Delete it |
| `/remind snooze [code] [time]` | Snooze it (10 minutes by default) |
| `/remind priority <code> l\|m\|h` | Change its priority |
| `/remind clear` | Clear everything that has fired |
| `/remind options` | Open the options |

There are also `/remind clock local|server`, `/remind where` (the place names it sees where you're standing) and `/remind debug`.

Got an idea or found a bug? [Open an issue](https://github.com/DarynHM/NaturalLanguageReminders-WoW/issues).

## Development

It's plain Lua 5.1 with no dependencies. The parser doesn't touch the WoW API, so you can test it outside the game with `luajit tests/run.lua`.

## License

[MIT](LICENSE)
