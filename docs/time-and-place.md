# Time + place reminders (design notes)

Dev-only notes; `docs/` is excluded from the package by `.pkgmeta`.

Goal: allow a time and a place in one reminder, e.g. "tomorrow when I get to Ironforge, buy reagents".

## How it works today

- `Parser.Parse` parses the place (`extractPlace`) and the time (`extractRelative`, or `extractClock` + `extractDay` → `resolveTime`) separately.
- If it finds both, it gives up with "I can't do a time and a place together yet" (`Parser.lua`, the check after the time block).
- A trigger is either a time trigger (`{ type = "time", at }`) or a place trigger (`{ type = "place", kind = "zone" | "npc", ... }`). They can't be combined.
- Place reminders fire from events:
  - `Scheduler.CheckPlaces(set)` fires zone reminders on arrival, using the `armed` flag;
  - `Scheduler.CheckNpc(kind)` fires NPC reminders when that window opens.
- Time reminders fire from the 5-second `Scheduler.Check` ticker, via `DueTime` (`snoozedUntil` or `trigger.at`).
- `Commands.lua` converts `trigger.at` from parser time to real time with `Clock.ToReal`, for the server clock.

## What the combination should mean

There are two readings. They behave differently, so pick deliberately.

**A. The place triggers, the time is a gate (recommended first).**
"Tomorrow when I get to IF" means: fire on arrival in Ironforge, but not before tomorrow. This covers most real use: "next time I'm in town after the reset", "after 5pm at the AH".

**B. The time triggers, the place is a condition.**
"At 5pm if I'm in Org" means: fire at 5pm, but only if you're in Orgrimmar then. That's rarer, needs a rule for when you're not there (skip, wait, or fire anyway?), and reads oddly. Leave it out for now.

The rest of these notes are about A.

## Phrases to support

| Text | Gate opens | Gate closes |
|---|---|---|
| `tomorrow when I get to IF` | tomorrow 00:00 | see the expiry decision |
| `when I get to org tomorrow` | same (order shouldn't matter) | |
| `friday next time I'm at the bank` | Friday 00:00 | |
| `after 5pm when I'm in org` | today 5pm | |
| `tonight when I get to SW` | today 18:00? (decide) | |
| `in 2h when I get to org` | now + 2h | |
| `at 5pm when I get to org` | 5pm (treat "at" as "from") | |
| `before 8pm when I get to org` / `by friday` | now | 8pm / Friday end (deadline, optional) |
| `every day when I get to org` | daily, first arrival each day | currently an error; see repeating |

New words to claim so they don't end up in the reminder text: `after`, `from`, `starting`, and later `before`, `by`, `until`.

## Data model

Keep it a place trigger, so `CheckPlaces` and `CheckNpc` still own it, and add optional fields:

```lua
trigger = {
    type = "place", kind = "zone", key = "ironforge", name = "Ironforge", known = true, armed = true,
    after = 1764115200,   -- don't fire before this (real time, after Clock.ToReal)
    before = nil,         -- optional: stop/expire after this
    every = nil,          -- see repeating
}
```

- Old saved reminders have no `after`, so they behave exactly as now. No migration needed.
- `Commands.lua` must run `after` / `before` through `Clock.ToReal`, the same way it does `at`.

## Parser changes

1. Replace the "time and place together" error: when both are present and the trigger is a time, move the time into `place.after` and use the place as the trigger.
2. **Day-only gates start at midnight, not 9am.** `resolveTime` applies `DEFAULT_DAY_HOUR` (9am) when there's a day and no clock. For a gate, "tomorrow" should mean the start of tomorrow. Add a flag to `resolveTime` (or a small sibling function) that uses 00:00.
3. The "already passed today" error shouldn't apply to a gate: "after 5pm" at 6pm just means "now". Clamp to `ctx.now`.
4. Bare places (`at IF`) are only tried when there's no time trigger (`extractBarePlace`). Keep that, so "at 5pm at IF" doesn't guess. Only phrase places (`when I get to ...`) combine with a time.
5. Claim the gate words (`after`, `from`) next to a clock or day.

## Scheduler changes

- A shared helper, e.g. `local function gateOpen(t, now) return not t.after or now >= t.after end`, used by `CheckPlaces` and `CheckNpc` before firing.
- **Arrival vs already there.** If you're already in Ironforge when the gate opens, should it fire?
  - Arrival-only is consistent with today's rule ("fires on arrival").
  - But "tomorrow when I'm in IF" while standing in IF at midnight probably should fire.
  - Suggestion: when the gate opens, fire if the player is in the place, else wait for arrival. That needs a check in the `Check` ticker: when `after` has just passed, look at `ns.Places.CurrentSet()`.
  - Make sure arming still works. A reminder created inside the zone starts `armed = false`, and leaving before the gate opens should arm it as normal.
- **NPC triggers** need nothing extra: the gate just blocks `CheckNpc` until `after`.
- **Expiry (`before`)**, if supported: once past, drop the reminder or show it as "missed / expired" in the list. Decide which. A reminder you never acted on probably shouldn't vanish silently.
- **Offline:** the gate can open while you're offline, which is fine since it's still waiting for arrival. An expiry that passed offline should show as missed on login, like missed time reminders.
- **Snooze:** unchanged. Snoozing is time-based and sets `snoozedUntil`.

## Repeating

- "Every day when I get to org" errors today ("Places repeat every time you arrive").
- With gates it could mean: at most once per period, on the first arrival.
  - After it fires, set `after` to the start of the next period (next day / next Friday), reusing `Scheduler.NextAt`-style calendar stepping.
  - `trigger.every` for places is currently `true`. A periodic place reminder would need `{ unit = "day", n }` instead, so `fire()` must tell the two apart.
- `whenever` / `always` + place (every arrival) stays as it is.
- Probably a second step, after one-off gates work.

## Display

- `Scheduler.TriggerText`: "when you get to Ironforge, from tomorrow 12:00 AM" (and ", until Fri 8:00 PM").
- `Scheduler.StatusText`: "waiting (from tomorrow)" before the gate opens, "waiting" after.
- `Scheduler.ByPriority`: gated place reminders could sort by `after`, ahead of ungated place reminders.
- `/remind debug` should print the gate.
- Check that the list window's Triggers column width still looks fine with the longer text.

## Tests (`tests/run.lua`)

- Parses:
  - `tomorrow when I get to IF x`: place trigger, `after` = tomorrow 00:00, text "x".
  - Reversed order.
  - `after 5pm` before and after 5pm.
  - `in 2h` + place.
  - NPC + day.
- Bare place + time still doesn't combine.
- Gate:
  - `CheckPlaces` / `CheckNpc` don't fire before `after` and do fire after.
  - Arming across the gate.
  - Already there when the gate opens (whatever rule is chosen).
- `TriggerText` / `StatusText` strings.
- Server clock: `after` converted with `Clock.ToReal`.

## Open decisions

1. Fire when the gate opens if you're already there, or arrival only?
2. Does a day-only gate expire at the end of that day ("tomorrow" = only tomorrow), or stay open?
3. What does "tonight" open at: 18:00, or 20:00 like the time default?
4. Support deadlines (`before` / `by` / `until`) in the first version, or later?
5. Periodic place reminders (`every day when I get to org`): now, or later?

## Docs to update when shipping

README (drop it from "Coming next", add examples), CHANGELOG, CLAUDE.md (remove the "not supported yet" rule and the roadmap line), `tests/ingame-checklist.txt`.
