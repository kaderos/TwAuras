# TwAuras QA Test Harness

This repository includes a deterministic local harness for validating TwAuras logic against WoW 1.12 and Turtle WoW API assumptions, without requiring a live server session.

## Quick Start

1. Install Lua 5.1 or LuaJIT.
2. From the repository root, run:

```powershell
.\tests\run.ps1
```

3. Review console output and the saved artifact:

- `tests/output/latest-run.txt`

## What This Harness Validates

- trigger logic correctness for TwAuras trigger families
- combat-log driven tracking and timer behavior
- config normalization and migration safety
- debug/throttle behavior under repeated updates
- compatibility fallbacks for older/missing API surfaces
- replay-style event sequences for ordering and volume behavior

## Turtle WoW API Compatibility Strategy

- Tests run against `tests/wow_stub.lua`, a controlled WoW API stub.
- Compatibility coverage focuses on fallback behavior when APIs are absent or limited.
- Negative tests intentionally remove selected APIs and assert non-crashing behavior.
- See Turtle WoW API reference:
  [Turtle WoW API Functions](https://turtle-wow.fandom.com/wiki/API_Functions)

## Incorporated Lessons (GCDTimer + JankyPlates)

- Event ordering / race conditions:
  replay tests validate cast/apply ordering resilience.
- Stale state cleanup:
  tracked aura fade/expiry tests ensure state does not leak.
- Throttling under event volume:
  combat-log ring-buffer and debug-throttle tests prevent runaway churn.
- Compatibility fallbacks:
  tests simulate missing APIs and verify graceful degradation.

## Additional QA Documents

- [Test Matrix](tests/TEST_MATRIX.md)
- [Risk Register](tests/RISK_REGISTER.md)
- [Optional Addon Enhancements](tests/OPTIONAL_ADDON_IMPROVEMENTS.md)

## Notes

- This harness validates addon logic deterministically.
- In-game rendering and full client integration still need targeted manual smoke passes.
