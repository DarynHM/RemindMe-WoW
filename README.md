# RemindMe

**Set reminders in WoW by typing them the way you'd say them.** RemindMe works out when (or where) you mean and nudges you at the right moment, with a chat message, a sound, a screen flash and a little icon by the minimap.

```
/remind in 30m repair
/remind at 7pm tomorrow raid
/remind when I get to Orgrimmar, get my weapon skill
/remind next time I'm at a mailbox, send mats to my alt
/remind every day at 9am do the daily quests
```

Built for **WoW Forever**

## Why I made it

Slack's `/remind` works so well that I wanted the same thing in game. Type it once, then stop thinking about it.

## Install

- **WowUp:** search for **RemindMe** in Get Addons with your WoW Forever install selected.
- **Manually:** download the zip from [Releases](https://github.com/DarynHM/RemindMe-WoW/releases) and extract it into `World of Warcraft\_forever_\Interface\AddOns`.

## What it can do

- **Times:** `in 20 minutes`, `1h30m`, `at 5pm`, `noon`, `tomorrow`, `friday at 9am`, `tmrw`, `@5pm`.
- **Places:** `when I get to Ironforge`, `next time I'm in org`, `at IF`. It fires when you arrive. It knows the usual short names too: `sw`, `uc` and so on.
- **NPCs:** next time you open a trainer, mailbox, vendor, bank, guild bank, auction house or flight master.
- **Repeating:** `every day at 5pm`, `daily`, `every 2h`, `always`, `whenever I get to org`.
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

## Coming next

- Time and place together: "tomorrow when I get to Ironforge".

Got an idea or found a bug? [Open an issue](https://github.com/DarynHM/RemindMe-WoW/issues).

## Development

It's plain Lua 5.1 with no dependencies. The parser doesn't touch the WoW API, so you can test it outside the game with `luajit tests/run.lua`.

## License

[MIT](LICENSE)
