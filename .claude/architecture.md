# Natural Language Reminders architecture (for AI-assisted development)

How the addon works inside, for an AI agent (or a person) about to change it. `CLAUDE.md` holds the working rules and the design decisions; this file explains the moving parts and how to change them safely.

## The big picture

```
/remind text
   │
   ▼
Commands.addReminder ──► Parser.Parse(text, ctx) ──► { message, trigger, priority }
   │                        (pure Lua, no WoW API)
   │  converts times to real epoch (Clock.ToReal), sets armed / opened
   ▼
Scheduler.Add ──► NaturalLanguageRemindersCharDB.reminders  (saved per character)
   │
   │  Something can fire it:
   │    5 s ticker ─────────► Scheduler.Check        (time reminders, snoozes, place windows)
   │    zone events ────────► Scheduler.CheckPlaces  (Places.CurrentSet())
   │    NPC window events ──► Scheduler.CheckNpc     (TRAINER_SHOW, MAIL_SHOW, ...)
   ▼
fire(r) ──► Notify.Fire (chat, raid warning, sound, flashes, by priority profile)
   │
   ▼
ns.OnRemindersChanged() ──► Indicator.Refresh + ListWindow.Refresh
```

Everything shares one namespace table, `ns`. Each file gets it via `local _, ns = ...` and adds its module (`ns.Parser`, `ns.Scheduler`, ...). Files run in TOC order. A module may call later modules only at runtime (inside functions), never while the file is loading.

## Modules

| File | Owns | Talks to |
|---|---|---|
| `Parser.lua` | Turning text into a trigger. **No WoW API**; WoW data comes in via `ctx` | nothing |
| `Clock.lua` | Now, local / server clock offset, display strings (`Describe`, `DescribeDay`, `DescribeTime`), the parser context | settings |
| `Places.lua` | Place dictionary (built-in names, `ALIASES`, C_Map when present), where the player is (`CurrentSet`), zone and NPC events | Scheduler |
| `Scheduler.lua` | The reminder list, letter codes, firing rules, place windows, text for list / chat (`TriggerText`, `StatusText`) | Notify, Clock, Places |
| `Notify.lua` | How a fired reminder is shown; the "already here" popup | Media, Flash |
| `Media.lua`, `Flash.lua` | Icons and sounds; screen-edge and taskbar flash | |
| `Indicator.lua` | Round minimap-style icon, tooltip, clicks, animations | Scheduler, ListWindow, Options |
| `Options.lua` | Esc > Options > AddOns panel. Small widget helpers: `checkbox`, `dropdown`, `slider`, `button` | settings |
| `ListWindow.lua` | `/remind list` window | Scheduler |
| `Commands.lua` | `/remind` slash command: management commands, otherwise a new reminder | everything |
| `Core.lua` | Print / Debug, priority tables, saved-variable defaults, startup (`ADDON_LOADED`, then `PLAYER_LOGIN`, then the first check after a delay) | everything |

## Data model

A reminder (`NaturalLanguageRemindersCharDB.reminders[i]`):

```lua
{
  id = 12, code = "c",                 -- code: stable handle for /remind done c
  text = "buy reagents",
  priority = "high" | "normal" | "low" | nil,   -- nil = default priority setting
  created = epoch, fired = bool, firedAt = epoch | nil, snoozedUntil = epoch | nil,
  trigger = <see below>,
}
```

Triggers:

```lua
-- time
{ type = "time", at = epoch, every = nil | { unit = "day" | "sec", n } }

-- zone / subzone / city
{ type = "place", kind = "zone", key = "ironforge", name = "Ironforge", known = true,
  armed = bool,                    -- false while you're inside; arms when you leave
  after = epoch?, before = epoch?, -- optional window (time + place)
  opened = bool?,                  -- the window's opening has been handled
  every = nil | true | { unit = "day", n } | { unit = "sec", n },
  each = bool? }                   -- periodic window that fires on every arrival

-- NPC window
{ type = "place", kind = "npc", npc = "trainer" | "mailbox" | "vendor" | "bank" | "gbank" | "ah" | "flight",
  name = "a trainer", after?, before?, opened?, every?, each? }
```

What `every` means:
- **Time:** `{day, n}` steps by calendar days (DST-safe); `{sec, n}` steps by seconds.
- **Place:**
  - `true`: every arrival;
  - `{day, n}`: once per window, the window moving n days at a time;
  - `{sec, n}`: a cooldown (`after = firedAt + n`).

**Times are stored as real epoch seconds.** The parser works in "virtual" time, shifted by the server-clock offset when the realm clock is selected. `Commands.addReminder` converts `at`, `after` and `before` with `Clock.ToReal` before saving. Any new time field must be converted there too.

Settings live in `NaturalLanguageRemindersDB`. Defaults are in `Core.InitDB` (`applyDefaults`), which only fills missing keys, so adding a setting is safe. Rename or remove one by migrating it in `InitDB` (see the animation migration there).

## Parser

`Parser.Parse(text, ctx)`:
- **`ctx` fields:**
  - `now`, `time`, `date`;
  - `places = { names, aliases }` (from `Places.ParserContext()`);
  - `morning` / `night` (minutes after midnight).
- **Returns** `{ message, trigger, priority }`, or `nil, "error for the user"`.

**How it works: claimed spans.**
- `l = text:lower()` must keep the same length as `text`, because spans index both. Normalise things like `@5pm` *before* lowercasing.
- Each extractor finds a phrase that isn't claimed yet (`findFree`), claims its span and returns structured data.
- `cleanMessage` cuts every claimed span out of the text, then strips fillers ("remind me to", "me", ...). Whatever is left is the message.
- **Order matters:** the earlier an extractor runs, the higher its priority.

Steps in `Parse`:
1. `extractPriority`: `-H` / `-low` flags first, then words (`urgent`, `quietly`), first/last-word adjectives, `!`.
2. `extractRepeat`: `always`, `every 2h`, `every friday`, `daily`, ...
3. `extractPlace`: phrase places (`LEAD_PATTERNS`: "when I get to", "next time I'm at", "whenever ...") followed by an NPC word, a known name / alias, or an unknown name.
4. `extractRelative`: `in 10 minutes`, `1h30m`.
5. If there's no relative time: `extractClock` (`5pm`, `17:30`, `noon`, `at 5`) and `extractDay` (`today`, `tomorrow`, weekdays, `tonight`, `tomorrow morning`, `friday night`).
6. **Combine:**
   - **Phrase place present:** `placeTrigger` turns the time into a window (`placeWindow`) or a periodic / cooldown spec.
   - **Otherwise time:** `resolveTime` picks the next matching moment.
   - **Neither:** `extractBarePlace` (`at IF`, `in org`). It's tried only when there's no time, so bare names don't guess.

Clock and day extractors also record a **mode** from the word before them (`prefixed` with `CLOCK_PREFIX` / `DAY_PREFIX`):
- `after` / `from` / `starting` mean "after";
- `before` means "before";
- `by` / `until` / `till` mean "by".

Modes only matter for place windows. For time reminders the word is simply claimed.

**Parser rules:**
- No WoW API calls in `Parser.lua`. New WoW data goes in through `ctx`, filled by `Clock.ParserContext` / `Places.ParserContext`.
- Errors are user-facing sentences, shown in red in chat.
- Every new phrase needs tests that it parses, **and** tests that ordinary text containing those words stays text ("drop by the bank", "find a quiet spot").

## Scheduler firing rules

`canFire(r)`: not fired yet, or repeating (repeating reminders fire again even if the last alert wasn't dismissed).

- **`Check`** (every 5 s, and once at login):
  - fires anything whose `DueTime` (`snoozedUntil` or `trigger.at`) has passed; more than 2 minutes late means "missed";
  - then runs `checkWindow` for place reminders:
    - **when a window closes unfired:** a one-off fires as missed; a periodic window moves on silently;
    - **when a window opens while you're in the zone:** it disarms the reminder and calls `Notify.AskAlreadyHere`.
- **`CheckPlaces(set)`:** a zone reminder fires when its key is in the set, it's `armed`, and its window is open. Not in the set means armed.
- **`CheckNpc(kind)`:** fires matching NPC reminders whose window is open.
- **`fire(r)`:** sets fired, then notifies. For repeating reminders:
  - time: `at` moves on (`NextAt`);
  - place: zones disarm, periodic windows move on (unless `each`), cooldowns set `after`.
- **Commands:**
  - `Complete` (done): removes a one-off, or dismisses a repeating one;
  - `Remove` (delete);
  - `Snooze`: always time-based, even for place reminders;
  - `ClearFired`.

**After changing reminder state outside these functions, call `changed()` (inside Scheduler) or `ns.OnRemindersChanged()`** so the icon and list window update.

## UI conventions

- **Feature-detect everything.** The target client (WoW Forever, Interface 16001) runs Mainline-style UI code, but not every API exists.
  - Check templates with `C_XMLUtil.GetTemplateInfo`.
  - Guard globals (`if StaticPopup_Show then`).
  - Keep a fallback: classic `UIDropDownMenu`, a chat line instead of a popup, and so on.
  - The lists of verified and unverified APIs are in `CLAUDE.md`.
- **Chat text:**
  - never contains a raw `|` (escape user text with `ns.Notify.Escape`);
  - no space-padded columns (the chat font is proportional);
  - one short "command - description" line each.
- **Colours:** priority colours come from `ns.PRIORITY_COLOR` / `ns.Colorize`. Otherwise use the default Blizzard look.
- **Options panel:** use the existing helpers in `Options.lua`. The page sits in a scroll child, so raise `content:SetHeight` when adding rows.

## Common changes

**Add an NPC trigger** (e.g. a stable master):
1. `Parser.lua`: add words to `NPC_WORDS1` / `NPC_WORDS2` and a display name to `NPC_NAMES`.
2. `Places.lua`: map the opening event to the kind in `NPC_EVENTS`. Registration is wrapped in `pcall`, so unknown events are skipped.
3. Add tests (parse and fire), and update the README and the `/remind` help lines in `Commands.showHelp`.

**Add a time word:** extend `extractDay`, `extractClock` or `extractRepeat`, and add tests for both the new phrase and nearby normal text. If it needs a configurable value, pass it through `ctx` (as `morning` / `night` are).

**Add a setting:**
1. Default in `Core.InitDB`.
2. Control in `Options.buildPanel`.
3. Read it where it's needed. For the parser, read it via `Clock.ParserContext`.

**Add a field to reminders:** saved data persists between versions. Make code treat a missing field as the old behaviour, or migrate in `Core.InitDB` (`CHAR_VERSION`).

**Add a Lua file:** list it in **both** `NaturalLanguageReminders.toc` and `NaturalLanguageReminders_Forever.toc` (the tests fail if they differ). A new file needs a full game restart, not just `/reload`.

## Testing

- `luajit tests/run.lua` runs the unit tests: parser, letter codes, scheduler (stubbed `ns`), window text, TOC checks. Run it before every commit. Compile-check every file with `luajit -b file.lua /dev/null`.
- **Scheduler tests** build a fake `ns`:
  - `charDB`, `Clock` with a controllable `now`;
  - `Notify.Fire` / `AskAlreadyHere` recorders;
  - `Places.IsHere`.
  - Then they load `Scheduler.lua` with `loadfile("Scheduler.lua")("NaturalLanguageReminders", sns)`.
- **Whole-addon smoke test:** stub the WoW globals (`CreateFrame` returning permissive mocks, `SlashCmdList`, the `Get*ZoneText` functions, `print`, `C_Timer`), load every file in TOC order, fire `ADDON_LOADED` and `PLAYER_LOGIN` on the frames, then call `SlashCmdList.NATURALLANGUAGEREMINDERS("...")` and read the captured chat output.
- **In game:**
  - `/remind debug` shows each parse, zone change and NPC event;
  - `/remind where` shows the current place keys;
  - `/console scriptErrors 1` turns on Lua error popups;
  - `tests/ingame-checklist.txt` lists the manual checks.

## Further reading

- `CLAUDE.md`: working rules, target client facts, design decisions, gotchas, release steps.
- `docs/time-and-place.md`: the full rules for time + place windows.
- `README.md`: the player-facing feature list.
