# TwAuras Testing

## Fast Manual Pass

1. Install the `TwAuras` folder into `Interface\AddOns`.
2. Log in on a rogue or druid and run `/twa`.
3. Verify the default auras render and the config window opens without Lua errors.
4. Use the `Unlock` and `Lock` buttons in the config window, drag both regions, reload, and confirm positions persist.

## Local Logic Harness

Use the local test harness for syntax-adjacent logic before going in game:

1. Install `Lua 5.1` or `LuaJIT`.
2. From the project root, run `.\TwAuras\tests\run.ps1`.
3. Review the `PASS` / `FAIL` output for:
   tracked debuff timers,
   combo-point debuff snapshots,
   saved target debuff trigger state,
   and timed-aura refresh behavior.

The harness uses mocked WoW globals from `tests/wow_stub.lua`, so it is best for pure logic, not for validating real frame behavior or exact TurtleWoW combat-log text.

## Trigger Coverage

Test at least one aura for each supported trigger:

- `buff`: player buff active and inactive
- `debuff`: target debuff active and inactive
- `power`: energy, mana, and rage threshold checks
- `combo`: 0 through 5 combo points
- `health`: absolute and percent modes
- `combat`: out of combat and in combat
- `targetexists`: no target and valid target
- `targethostile`: friendly target and hostile target
- `combatlog`: `/twa debug` output matches configured event and pattern
- `spellcast`: player and target spell match timing
- `cooldown`: ready and active cooldown states
- `itemcooldown`: trinket or weapon slot cooldown
- `form`: active shapeshift or stance
- `casting`: player cast and channel state
- `pet`: pet exists and missing pet
- `zone`: zone and sub-zone matching
- `spellknown`: spellbook known checks
- `actionusable`: usable, missing resource, cooldown, and range states
- `weaponenchant`: main hand or off hand temporary enchant
- `itemcount`: bag item total threshold
- `range`: target in range and out of range
- `threat`: aggro and no-aggro behavior
- `playerstate`: mounted, stealth, and resting
- `groupstate`: solo, party, and raid
- `always`: region remains visible

## Display Coverage

Verify each region type:

- `icon`: icon, timer text, stack text, label text
- `bar`: width/height, label, timer mode, numeric mode, icon visibility
- `text`: timer text and value text

Also verify:

- alpha changes
- color changes
- desaturate inactive
- show/hide icon
- show/hide timer
- show/hide label
- icon cooldown swipe
- icon cooldown overlay

## Load Conditions

Check these combinations:

- enabled and disabled
- only in combat
- require target
- class restricted
- inverted trigger
- missing aura tracking

## Recommended Test Additions

Add these next to make iteration easier:

1. A lightweight `Dev.lua` file loaded only during development with slash commands that force fake states.
2. A small debug panel that shows the last matched trigger result for the selected aura.
3. A test character matrix:
   rogue for energy and combo points,
   warrior for rage,
   caster for mana,
   any class with common buffs and target debuffs.
4. Saved sample aura presets for repeated smoke tests after refactors.
