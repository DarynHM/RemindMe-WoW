# Time + place reminders (design notes)

Dev-only notes; `docs/` is excluded from the package by `.pkgmeta`.

A reminder can have a place and a time together: "tomorrow when I get to Ironforge, buy reagents". The place fires the reminder. The time is a **window** it must fire inside.

## Phrases

| Text | Window opens (`after`) | Window closes (`before`) |
|---|---|---|
| `tomorrow when I get to IF` | tomorrow 00:00 | end of tomorrow |
| `when I get to IF tomorrow` | same (word order doesn't matter) | |
| `tomorrow morning when I get to IF` | tomorrow, morning time | end of tomorrow |
| `tonight when I get to SW` | today, night time | end of today |
| `after 5pm when I'm in org` / `at 5pm when...` | today 5pm | end of today |
| `in 2h when I get to org` | now + 2h | none |
| `before 8pm when I get to org` | none | today 8pm |
| `friday before 8pm next time I'm at the bank` | Friday 00:00 | Friday 8pm |
| `by friday when I get to IF` | none | end of Friday |
| `by tonight when I get to IF` | none | today, night time |
| `every day when I get to org` | today 00:00, then daily | end of each day |
| `every friday next time I'm at the ah` | Friday 00:00, then weekly | end of each Friday |
| `every night when I get to org` | night time each day | end of each day |
| `every 2h when in org` | not again until 2h after it fired | none |
| `whenever I'm in org after 5pm` | 5pm each day, every arrival | end of each day |

**Rules:**
- **Only phrase places combine with a time.** Phrases are `when I get to`, `next time I'm at`, and so on. Bare places (`at IF`) are only tried when there's no time, so "at 5pm at IF" stays a time reminder.
- **Window words:** `after` / `from` / `starting` open the window, and `before` / `by` / `until` / `till` close it. Each is claimed only straight before a clock time or day.
  - Without a place they just set the reminder time: "pay rent by friday" means Friday at the morning time.
  - Anywhere else they stay in the text: "drop by the bank".
- **A day lasts only that day.**
- **A deadline that has already passed** is an error for a one-off ("That time has already passed today."). A periodic window that has closed just moves on.

## Data

Place triggers get optional fields:
- `after` / `before`: real epoch; Commands converts them with `Clock.ToReal`.
- `opened`: the window's opening has been handled.
- `every`:
  - `true`: every arrival (unchanged);
  - `{ unit = "day", n }`: once per window, the window moving n days at a time;
  - `{ unit = "sec", n }`: a cooldown (`after = firedAt + n`).
- `each = true`: a periodic window that fires on every arrival inside it ("whenever" / "always" plus a time).

Old saved reminders have none of these, so they behave as before.

## Scheduler

- `windowOpen(t, now)` gates `CheckPlaces` and `CheckNpc`.
- **The ticker (`Check`) handles windows** through `checkWindow`:
  - **When the window closes:** a periodic reminder moves on silently (`advanceWindow`). An unfired one-off fires with the note "(missed: you didn't get to X in time)" and stays in the list.
  - **When the window opens while you're in the zone:** it sets `armed = false` and calls `Notify.AskAlreadyHere`.
- **The popup** (`StaticPopupDialogs.NATURALLANGUAGEREMINDERS_ALREADY_HERE`):
  - "Cancel reminder" deletes a one-off; for a periodic one the button reads "Skip this time" and moves to the next window (`Scheduler.CancelAlreadyHere`).
  - "Next arrival", Escape or closing it keeps the reminder.
  - Popups are queued, one at a time.
  - Without StaticPopup it prints a chat line instead.
- **`fire()` for places:**
  - sets `opened`;
  - a periodic day window moves on unless `each` is set;
  - a cooldown sets `after`;
  - zones disarm.
- **Adding a reminder** (Commands): `opened` is set when the window is already open. The "You're in X now" message only shows then; otherwise the popup decides when the window opens.

## Morning / night

- `NaturalLanguageRemindersDB.morning` / `night` (minutes, default 540 / 1200) reach the parser as `ctx.morning` / `ctx.night` through `Clock.ParserContext`.
- **Options > Times** has two dropdowns, every 30 minutes:
  - Morning: 5:00 AM to 12:00 PM.
  - Night: 5:00 PM to 11:30 PM.
- **Day parts:**
  - `tomorrow morning`, `friday night`, `friday evening`, `this morning`, `this evening`, `in the evening`;
  - `in the morning`, which means tomorrow once this morning has passed.
- **A part also settles an ambiguous clock:** "friday night at 9" means 9pm.
- Changing a setting only affects new reminders.
