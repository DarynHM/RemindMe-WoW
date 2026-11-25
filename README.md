# RemindMe

Natural-language `/remind` reminders for World of Warcraft, with priority-based alerts and an on-screen reminder icon.

Type a reminder the way you'd say it in Slack, and RemindMe works out when to remind you:

```
/remind At 12pm today, remind me to buy potions
/remind repair in 30 minutes
/remind 1h30m check the auction house
/remind ! tomorrow at 7pm raid
/remind quietly in 10m stretch
/remind When I get to Orgrimmar, remind me to upgrade my weapon skill
/remind next time I'm at a trainer learn swords
/remind me always at 9am stretch
/remind whenever I get to org, repair
```

Built for **WoW Forever** (Interface 16001).

## Install

- **WowUp**: search for **RemindMe** in WowUp's Get Addons tab (WowUp Hub) with your WoW Forever install selected.
- **Manually**: download the RemindMe zip from [Releases](https://github.com/DarynHM/RemindMe-WoW/releases) and extract it into `World of Warcraft\_forever_\Interface\AddOns`, so you end up with `AddOns\RemindMe\RemindMe.toc`.

## Features

- **Natural-language times, anywhere in the sentence**: `at 5pm`, `12:30 pm`, `19:30`, `noon`, `midnight`, `in 20 minutes`, `in an hour`, shorthand like `10m`, `2h`, `1d`, `1w`, `1h30m`, and days like `today`, `tonight`, `tomorrow`, `friday at 9am`.
- **Location reminders**: `when I get to Orgrimmar`, `next time I'm in org`, `when I reach Light's Hope Chapel`, or bare `at Ironforge`. Zones, subzones, cities and dungeons are recognised, plus short names (`org`, `sw`, `if`, `uc`, `tb`, `xroads`, `brd`…). They fire when you *arrive*; one made while you're already there waits until you leave and come back. Unknown names are still accepted (with a "did you mean") and matched exactly.
- **WoW abbreviations**: `org`, `sw`, `if`, `uc`, `tb`, `xr`, `stv`, `epl`, `brd`, `ubrs`, `strat`, `sm lib`, `zg`, `mc`, `bwl`, `aq40`, `naxx`, `wsg`, `ab`, `av`… and `ah`, `fp`, `fm`, `mbox`, `gbank` for NPCs. Times accept `2moro`, `tmrw`, `2nite`, `tonite` and `@5pm`. Short names count anywhere when they're 3+ letters (`buy wine in org`); 2-letter ones need capitals (`repair at IF`) or a phrase (`when I get to if`).
- **NPC reminders**: `next time I'm at a trainer` / `weapon master`, `mailbox`, `vendor`, `bank`, `auction house`, `flight master`. They fire when that window opens.
- **Repeating reminders**: `always at 9am`, `every day at 5pm`, `daily`, `every friday at 7pm`, `every 2h`, `every other day`, `every night`, and for places `always when I get to org` / `whenever I'm at a trainer` / `every time I'm in IF`. A repeating reminder schedules itself again when it fires; `/remind done` dismisses the current alert and `/remind delete` stops it.
- **Priorities**: Low / Normal / High. Set them with words (`quietly`, `low priority`, `urgent`, `important`, `loudly`, `high priority`) or `!` for high. Each priority has its own alerts.
- **Configurable alerts per priority**: chat message, raid-warning text, sound (built-in sounds plus any from LibSharedMedia if another addon provides it), screen edge flash, and taskbar flash when the game is in the background.
- **On-screen reminder icon**: a round icon that sits beside the minimap mail icon by default, or can be dragged anywhere. Hover to see what's due (coloured by priority); left-click for done, right-click to snooze 10 minutes, shift-click to list everything, ctrl-click for options. Choice of icon, size, opacity, whether it shows only while something is due, and an animation per priority (pulse, glow, ring, sparkles, comet).
- **Sound picker with preview**: each sound in the list has a play button, and long lists (LibSharedMedia) scroll.
- **Local or realm clock**: "at 12pm" can follow your PC clock or server time.
- **Missed reminders**: anything that came due while you were offline fires when you log in, marked as missed.
- **Options panel** in *Esc → Options → AddOns → RemindMe*.

## Commands

| Command | What it does |
|---|---|
| `/remind <what> <when>` | Add a reminder |
| `/remind list` | Show reminders, each with a short letter code (`a`, `b`, `c`…) |
| `/remind done <code>` | Complete a reminder, e.g. `/remind done b` (a repeating one is just dismissed until next time) |
| `/remind delete <code>` | Delete a reminder (stops a repeating one) |
| `/remind snooze [code] [time]` | Snooze (default: most important due reminder, 10 minutes). Snoozing a place reminder turns it into a timed one |
| `/remind priority <code> low\|normal\|high` | Change a reminder's priority |
| `/remind clear` | Remove all fired reminders |
| `/remind clock local\|server` | Which clock times use |
| `/remind options` | Open the options panel |
| `/remind where` | Show the place names RemindMe sees where you're standing |
| `/remind debug` | Toggle debug output (parses, zone changes, NPC windows) |

A reminder keeps its letter code until it's completed or deleted, so `/remind done b` always means the same reminder even after others are added or fire. Freed letters are reused for new reminders.

## Roadmap

- Time and place together: "tomorrow when I get to Ironforge"
- A reminder list window

## Development

The addon is plain Lua 5.1 with no dependencies. The natural-language parser (`Parser.lua`) doesn't call any WoW API, so it can be tested outside the game:

```
luajit tests/run.lua
```

In game, `/remind debug` prints what each reminder was parsed into and every zone change / NPC window RemindMe sees. For Lua errors, turn on the game's error popups with `/console scriptErrors 1` (or install BugSack + BugGrabber).

## License

[MIT](LICENSE)
