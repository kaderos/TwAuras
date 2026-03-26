# Optional Addon Enhancements

TwAuras does not assume `SuperWoW`, `Nampower`, or `UnitXP_SP3` are installed.

If they are present and expose richer APIs, these TwAuras functions are the best candidates for enhancement.

## SuperWoW (Optional)

Potential improvement targets:

- `TwAuras:RecordCombatLog` (`Triggers.lua`)
  - Use structured combat event data if available instead of text-only parsing.
- `TwAuras:TrackPlayerDebuffsFromCombatLog` (`Triggers.lua`)
  - Improve debuff application fidelity from richer source/destination payloads.
- `TwAuras:TrackPlayerBuffsFromCombatLog` (`Triggers.lua`)
  - Improve ownership/source accuracy for buff tracking.
- `TwAuras:GetRangeInfo` (`Triggers.lua`)
  - Prefer direct distance/range APIs (if exposed) over interact/action heuristics.

## Nampower (Optional)

Potential improvement targets:

- `TwAuras:UpdateEstimatedManaForUnit` (`Core.lua`)
  - Replace percent-based estimation with direct target mana values where available.
- `TwAuras:TrackTargetManaEstimateFromCombatLog` (`Triggers.lua`)
  - Reduce dependence on combat-log mana-drain text parsing.
- `TwAuras:GetRealManaTokenData` (`Core.lua`)
  - Prefer exact token values from addon-provided mana data.

## UnitXP_SP3 (Optional)

Potential improvement targets:

- `TwAuras:UpdateEstimatedHealthForUnit` (`Core.lua`)
  - Replace percent+damage estimation with direct max/current health values.
- `TwAuras:TrackTargetHealthEstimateFromCombatLog` (`Triggers.lua`)
  - Reduce combat-log dependency for inferred health tracking.
- `TwAuras:GetRealHealthTokenData` (`Core.lua`)
  - Prefer exact health tokens from addon-provided unit health data.

## Integration Guidance

- Detect optional APIs at runtime and branch safely.
- Keep current fallback behavior as default when optional addons are absent.
- Add dedicated compatibility tests for each optional integration gate.
