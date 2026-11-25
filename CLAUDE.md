# RemindMe (formerly Nudge): project instructions and context

RemindMe (renamed from Nudge before its first public release) is a World of Warcraft addon: Slack-style natural-language reminders typed as slash commands, such as `/remind at 12pm today buy potions` or `/remind when I get to Orgrimmar, upgrade my weapon skill`. The author is Daryn (GitHub `DarynHM`, formerly `Ki-ches`; repo `DarynHM/RemindMe-WoW`). It is MIT licensed.

## Working rules (from the user, always follow)

- **Edit the repo, then copy to the game.** The source of truth is `B:\_Projects\WoW\Nudge` (a git repo with the addon files at its root; the local folder keeps its old name). After every change, copy only `*.lua`, `RemindMe.toc` and `RemindMe_Forever.toc` to `G:\Games\World of Warcraft\_forever_\Interface\AddOns\RemindMe`. Never edit the game folder directly.
- **Commit locally; don't push** to GitHub unless asked.
- **Run the tests before deploying:** `luajit tests/run.lua` (LuaJIT is installed via scoop). Compile-check every file with `luajit -b <file> /dev/null`.
- **Restart or reload:** a `/reload` is enough unless a file was added to the .toc. Then the game must be restarted; say so.
- **Don't touch the old project:** `B:\_Projects\WoW\FlexibleReminderAddon` is the old pre-rename copy, kept as a backup. Leave it alone.
- **Plan first:** the user likes plan mode for features (questions first, then a plan to approve) and short, direct summaries afterwards.

## Target client: "WoW Forever"

- Build 1.60.1 (71037), `## Interface: 16001`. It's a "modern classic" client running **Mainline-style Blizzard UI code**, so modern APIs exist even though the content is Classic.
- **Verified in game:**
  - `Settings.RegisterCanvasLayoutCategory` / `Settings.RegisterAddOnCategory` / `Settings.OpenToCategory(category:GetID())` exist.
  - `WowStyle1DropdownTemplate`, `OptionsSliderTemplate`, `UICheckButtonTemplate` and `UIDropDownMenu_Initialize` exist.
  - `MiniMapMailFrame` is **nil**. Mail lives at `MinimapCluster.IndicatorFrame.MailFrame`, and the indicator anchors to `MinimapCluster.IndicatorFrame`.
- **Not yet verified:**
  - `C_Map.GetBestMapForUnit`, `C_Map.GetMapInfo`, `C_Map.GetAreaInfo`.
  - The `Interface\FullScreenTextures\LowHealth` texture, `FlashClientIcon`, and the server clock (`GetGameTime`).
  - `GUILDBANKFRAME_OPENED`.
  - All of these are guarded or fall back.
- Plain Lua 5.1 sandbox, no libraries required. LibSharedMedia sounds are used only if another addon has loaded LSM.

## Files (TOC load order)

| File | Role |
|---|---|
| `Parser.lua` | Pure-Lua natural-language parser. **No WoW API calls** (unit tested). `Parser.Parse(text, ctx)`, `ParseDuration`, `PlaceKey`, `Suggest` |
| `Clock.lua` | Local or server clock (`Now`, `Offset`, `ToReal`, `Describe`, `ParserContext`) |
| `Places.lua` | Place dictionary (built-in names + C_Map + `ALIASES`), `CurrentSet()` of place keys where the player stands, zone/NPC events, `Describe` for `/remind where` |
| `Media.lua` | Icons and sounds (built-in SOUNDKITs + optional LSM) |
| `Flash.lua` | Screen-edge flash and taskbar flash |
| `Notify.lua` | `Fire(reminder, note)` runs the channels of the reminder's priority profile |
| `Scheduler.lua` | Reminder list, letter codes, `Check` (time ticker every 5 s), `CheckPlaces`, `CheckNpc`, `Snooze`, `Sorted`, `Fired` |
| `Indicator.lua` | Movable mail-style icon: tooltip, left-click done, right-click snooze, shift-click list, animations |
| `Options.lua` | Panel in Esc > Options > AddOns: per-priority alert grid, indicator settings, clock |
| `Commands.lua` | `/remind` (the only slash command). Anything that isn't a management command becomes a new reminder |
| `Core.lua` | `ns.Print`, `ns.Debug`, priority tables, saved-variable defaults, login startup |

Saved variables: `RemindMeDB` (account settings) and `RemindMeCharDB` (per-character reminders).

## Design decisions already made (don't re-litigate)

**Priorities**
- Low, Normal and High; Normal is the default.
- Set them with words: quietly / low priority, urgent / important / loudly / high priority / asap. `!` alone, or leading the text, means High.
- quiet / loud / silent only count as the first or last word.
- Each priority has its own profile: chat, raid warning, sound, icon animation, edge flash, taskbar flash.

**Letter codes**
- Each reminder gets the lowest free code (`a`..`z`, `aa`...) when it's created.
- The code never changes while the reminder exists and is reused once it's freed.
- `done`, `delete`, `snooze` and `priority` take a code.

**Time parsing**
- Shorthand: `10m`, `1h30m`, `2d`, `1w`. Clock times: `12pm`, `17:30`, noon, midnight. Days: today, tonight, tomorrow, weekdays.
- Abbreviations: tmrw / 2moro / 2nite / tonite, and `@5pm`.
- A day with no time means 9am; tonight means 8pm. A time already passed today is an error.

**Place triggers**
- Phrases: `when I get to X`, `next time I'm in X`, `when in X`, `once I'm at X`, and so on.
- Bare forms (`at Orgrimmar`, `buy wine in org`) are only tried when there's no time trigger.
- Bare aliases need 3+ letters (and not an everyday word), or capitals for 2-letter ones (`at IF`). Straight after "remind me" or "me", any alias counts.
- Zone reminders fire on **arrival**. One made while you're already there is `armed = false` until you leave.
- Unknown names are accepted with a "did you mean" warning and matched exactly.
- NPC triggers: trainer / weapon master / wm, mailbox / mbox, vendor / merch / repair vendor, bank, guild bank / gbank, ah / auction house, fp / fm / flight master.
- "inn" was dropped: there's no clean innkeeper event.
- `DM` is deliberately not an alias (Deadmines or Dire Maul?).

**Repeating reminders**
- Triggered by `always` (anywhere in the text), `every <duration / unit / weekday>`, `every other day`, `daily` / `nightly` / `weekly` / `hourly`. For places: `whenever` / `every time` / `each time` phrases, or `always` + a place.
- Stored as `trigger.every`: `{ unit = "day"|"sec", n }` for time, `true` for a place.
  - Day steps add calendar days, so 9am stays 9am across DST.
  - Whole-day durations (`every 2d`) become day steps. With no clock time, day steps use the 9am default and roll to tomorrow if 9am has passed.
- `always` with a time and no day means daily; `always` with a weekday means weekly; `always in 2h` means every 2h.
- `every day when I get to org` is an error: places repeat per arrival.
- **On fire:** it notifies, shows as fired, then re-arms immediately. A time reminder moves `at` to its next occurrence; a zone reminder sets `armed = false` until you leave. It fires again even if the previous alert wasn't dismissed.
- **Commands:** `done` (`Scheduler.Complete`) dismisses and keeps it; `delete` removes it; `clear` dismisses repeating ones and removes fired one-offs. Snoozing works once, then it goes back to its schedule.

**Other rules**
- **Snooze is always time-based**, including for place reminders.
- **Time + place together is not supported yet** and gives an error. It's on the roadmap.
- **A fired reminder stays in the list** (Slack-style) until it's done, deleted or snoozed. Reminders that came due while offline fire on login, marked "missed".

## Gotchas learned the hard way

- **Never put a raw `|` in chat text.** `|n` is a newline code and `|c`/`|r` are colour codes. Write alternatives as `a / b`, and escape user text with `ns.Notify.Escape`.
- **No space-padded columns in chat:** the chat font is proportional. Use one short "command - description" line each.
- `/remind me ...` arrives as "me ...", so the parser strips leading "me", "me to", and so on.
- **Parser positions:** `l = text:lower()` must keep the same length as `text`, because spans index both. Normalise text (e.g. `@`) *before* lowercasing.
- Keep the parser free of WoW calls; WoW data comes in through `ctx` (e.g. `ctx.places`).

## Testing and debugging

- `tests/run.lua` covers the parser, letter codes, place arming, NPC firing and abbreviations (399 checks at the time of writing).
- Smoke harnesses with stubbed WoW globals have been used to run the real `/remind` handler offline. Recreate one if needed: stub `SlashCmdList`, `CreateFrame`, the `Get*ZoneText` functions and `print`, then load the addon files with `loadfile(f)("RemindMe", ns)`.
- **In game:**
  - `/remind debug` shows parses, zone changes and NPC events.
  - `/remind where` shows the current place keys.
  - `/console scriptErrors 1` turns on Lua error popups.

## Releasing (WowUp Hub)

- **Two identical TOCs:** `RemindMe_Forever.toc` is how WowUp Hub recognises WoW Forever, and `RemindMe.toc` is the fallback if the client ignores the suffix. Edit both together; `tests/run.lua` fails if they differ.
- **Version:** the TOCs say `## Version: @project-version@`, which the BigWigs packager replaces with the tag. Locally the AddOns list shows the raw token; that's expected.
- **To release:**
  1. Add a section to `CHANGELOG.md`.
  2. Commit, then make an annotated tag: `git tag -a vX.Y.Z -m "RemindMe X.Y.Z"`.
  3. Push `main` and the tag (only when the user says so).
  4. `.github/workflows/release.yml` runs the packager and creates the GitHub release; WowUp Hub picks it up.
- **What the packager leaves out** is set by `.pkgmeta`: `tests`, the docs, `.previews` and `.github`.
- **Hub extras:**
  - Category comes from the repo topics (`miscellaneous`).
  - The icon is the GitHub social preview image.
  - Screenshots go in `.previews/`.

## Roadmap / not started

- Time + place together ("tomorrow when I get to IF").
- A reminder list window.
- In-game verification of: the options panel, indicator, priorities and flashes, server clock, missed reminders, place triggers, C_Map availability.
