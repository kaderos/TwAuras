# TwAuras Risk Register

## Active Risks

| ID | Risk | Severity | Current Mitigation | Next Test Recommendation |
|---|---|---|---|---|
| R-01 | Combat log text variance across locales and custom client strings can miss trigger patterns | High | Partial-match combat-log triggers and replay tests | Add localized replay fixtures for common Turtle WoW locales |
| R-02 | 1.12 API surface differences can break assumptions when APIs are absent | High | Fallback tests for item count, threat, range, player aura scan | Expand negative tests for additional optional/missing APIs |
| R-03 | State leak across rapid target swaps and aura fades | Medium | Existing fade cleanup and runtime reset tests | Add replay fixture with target swaps + repeated debuff applications |
| R-04 | UI-only behaviors may regress without detection in logic harness | Medium | Manual smoke checklist in `TESTING.md` | Add scripted in-game smoke protocol for icon/bar/text/unitframe checks |
| R-05 | High event volume can cause noisy debugging/perf churn | Medium | Debug throttling + combat-log ring-buffer tests | Add stress replay benchmark with timing budget assertions |

## Recommended Next Tests (Priority Order)

1. Localized combat-log replay suite (`enUS` plus common Turtle localized patterns).
2. Target-swap stale-state replay suite (A -> B -> A rapid transitions).
3. Raid-size unitframe replay with party/raid join-leave churn.
4. Manual in-game smoke runbook with fixed sample aura pack and expected screenshots.
