# TwAuras

Addon Version: `0.1.41`  
Readme Version: `0.1.26`

TwAuras is a lightweight WeakAuras-style addon for TurtleWoW / WoW 1.12 focused on building configurable icons, bars, text trackers, and party/raid frame overlays in game.

The project goal is to recreate the core aura-building workflow of WeakAuras without import/export or user-authored custom code. Users should be able to create and manage auras entirely through the in-game UI.

## Getting Started

Type `/twa` in game to open the main TwAuras configuration window.

From there, users can:

- create a new aura
- edit existing auras
- use the built-in wizard presets
- configure triggers, display, conditions, load rules, and position

## What TwAuras Can Do

- Create aura displays as `icon`, `bar`, `text`, or `party / raid frame` overlays
- Build auras with multiple triggers
- Combine triggers with `all`, `any`, or `priority`
- Track buffs, debuffs, cooldowns, spell casts, resources, combo points, health, combat state, target state, zones, forms, energy ticks, and the mana five-second rule
- Show dynamic text such as remaining time, stack count, current value, and percentages
- Customize icon color, bar color, background color, alpha, font size, outline, and text anchors
- Add conditions that can change colors, alpha, desaturation, and glow when thresholds are met
- Play configured WoW sound files when an aura starts, while it stays active, or when it stops
- Save aura definitions between reloads and logins

## Current Trigger Types

TwAuras currently supports these built-in trigger families:

- `buff`
- `debuff`
- `power`
- `combo`
- `health`
- `energytick`
- `manaregen`
- `combat`
- `targetexists`
- `targethostile`
- `combatlog`
- `spellcast`
- `cooldown`
- `spellusable`
- `internalcooldown`
- `itemcooldown`
- `form`
- `casting`
- `pet`
- `zone`
- `spellknown`
- `actionusable`
- `weaponenchant`
- `itemequipped`
- `itemcount`
- `range`
- `threat`
- `playerstate`
- `groupstate`
- `always`

The `combatlog` trigger supports partial text matching, which is useful for raid boss ability warnings, environmental events, and other combat-log lines that are easier to match by phrase than by exact full message.

## Notable Debuff Tracking Support

TwAuras includes a runtime debuff timer system for player-applied target debuffs.

This is especially useful on TurtleWoW / 1.12 because the old API does not reliably expose exact debuff durations the way later WoW clients do.

Current debuff timer support includes:

- saved runtime timers started from combat-log application events
- combo-point snapshotting for finisher-style debuffs
- optional `Cast By Player` source filtering
- timer display through `%time` and bar/icon timer output

TwAuras also supports internal cooldown tracking for item procs and similar effects:

- start an ICD from a player buff gain
- or start it from a partial combat log match
- show the aura while the ICD is cooling down or only when it becomes ready again

## In-Game Workflow

1. Install the addon and run `/twa`
2. Create a new aura or use the `Wizard` button
3. Configure one or more triggers in the `Trigger` tab
4. Configure `icon`, `bar`, or `text` output in the `Display` tab
5. Add optional visual rules in the `Conditions` tab
   - including one-shot start sounds, repeating active sounds, and one-shot stop sounds
6. Add optional restrictions in the `Load` tab
7. Place the aura in the `Position` tab or unlock and drag it
8. Click `Apply`

The main editor shows a human-readable summary of the selected aura to make saved setups easier to scan and maintain.

## Wizard Presets

The main config window currently includes starter presets for:

- `Buff Tracker`
- `Target Debuff`
- `Cooldown Ready`

These create a new aura with sensible defaults so the user can finish setup faster.

## Display Features

TwAuras currently supports:

- icon picker with search and paging
- sound picker with search, scrolling, and test playback
- icon path override
- icon desaturation
- icon hue picker with live preview
- icon cooldown swipe overlay
- icon cooldown dark overlay
- configurable timer formatting (`smart`, `mm:ss`, `seconds`, `decimal`)
- low-time text and bar color transitions
- sound path or sound id support for condition lifecycle audio
- inactive desaturation
- main color tint
- background color
- text color
- alpha
- width and height
- font size
- font outline
- text anchors
- dynamic text tokens

Supported text tokens include:

- `%name`
- `%label`
- `%time`
- `%value`
- `%max`
- `%percent`
- `%stacks`
- `%realhp`
- `%realmaxhp`
- `%realhpdeficit`
- `%realmana`
- `%realmaxmana`
- `%realmanadeficit`

The `realhp` and `realmana` tokens prefer exact unit values when the client exposes them. If the client only exposes percentage-style target values, TwAuras falls back to a combat-log-based estimate and only tracks that estimate when at least one aura actually uses those tokens.

## Conditions

The `Conditions` tab allows users to override visual output when state thresholds are met.

Current condition checks support values such as:

- active
- remaining time
- stacks
- value
- percent

Current condition actions support:

- alpha override
- main color override
- text color override
- background color override
- icon desaturation
- glow

## Notes On 1.12 Compatibility

Some trigger families are best-effort because TurtleWoW / 1.12 exposes less combat and unit state than later clients.

Examples:

- target threat uses the best aggro signal available to the client
- focus-related unit selectors are only useful if the client exposes a valid `focus` unit
- mounted detection depends on client API availability

## Persistence and Backups

Aura definitions are saved in `TwAurasDB`.

Saved aura configuration persists across:

- UI reloads
- relogs
- client restarts

TwAuras stores aura definitions in a compartmentalized aura store so individual auras are easier to identify and back up later.

Persistent data includes:

- aura name and metadata
- triggers
- display settings
- load settings
- conditions
- position

Runtime-only data is intentionally not persisted. This includes:

- active timer countdowns
- recent combat log lines
- temporary target debuff runtime tracking

## TurtleWoW / 1.12 Limitations

TwAuras is designed around the 1.12 client, so some modern WeakAuras behavior is intentionally out of scope or not possible with perfect accuracy.

Known limitations include:

- no import/export
- no custom code in the in-game editor
- no dynamic groups or clone-style grouped displays yet
- no full modern combat-log payloads
- some target debuff timing depends on combat-log text tracking instead of native duration APIs
- glow is currently the only animation-style visual effect

## Local Testing

TwAuras includes a local Lua 5.1 logic harness in the `tests` folder.

Use it for:

- config normalization checks
- trigger logic checks
- saved debuff timer behavior
- summary generation checks

Run it from the project root with:

```powershell
.\TwAuras\tests\run.ps1
```

See `TESTING.md` for more detail.

## Project Structure

- `TwAuras.lua`: addon bootstrap, events, slash entry point, runtime state
- `Core.lua`: data normalization, aura store, refresh pipeline, summaries, conditions
- `Triggers.lua`: trigger registry, trigger descriptors, trigger handlers
- `Regions.lua`: region registry, display creation, visual state application
- `Config.lua`: in-game editor, selectors, icon picker, wizard UI
- `IconList.lua`: searchable icon manifest
- `TESTING.md`: test guidance

## Maintenance Note

This README should be updated whenever major functionality is added, removed, or changed.

At minimum, keep these values current:

- `Addon Version`
- supported trigger list
- major UI workflow changes
- important limitations
- testing instructions
