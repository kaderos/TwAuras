# TwAuras Test Matrix

| Feature | Scenario | Expected Result | Coverage |
|---|---|---|---|
| Debuff tracking | Finisher cast/apply with combo snapshot | Saved timer uses snapped combo points and duration | `rip snapshots combo points at cast start` |
| Debuff tracking | Periodic tick after initial application | Tick does not reset active timer expiration | `tracked debuff ticks do not reset an active timer` |
| Combat log replay | Cast/apply with interleaved unrelated events | Snapshot remains stable through event jitter | `replay keeps finisher snapshot through cast and apply jitter` |
| Combat log replay | High-volume combat messages | Recent log retains only newest 8 entries | `replay keeps only newest combat log lines under heavy volume` |
| API compatibility | Missing legacy player buff API (`GetPlayerBuff`) | Player buff scan still resolves aura state | `player aura scan falls back when legacy player buff api is missing` |
| API compatibility | Missing `GetItemCount` | Item count falls back to bag scan | `bag count falls back to manual scan when GetItemCount is unavailable` |
| API compatibility | Missing threat APIs | Aggro detection falls back to target-target ownership | `threat detection falls back when threat apis are unavailable` |
| API compatibility | Missing interact-distance API | Range evaluation falls back to action-slot range | `range info falls back to action slot when interact api is unavailable` |
| Stale state cleanup | Debuff fade event | Tracked timer entry is removed | `tracked debuff fades clear saved timer` |
| Performance throttle | Debug spam in same area | Duplicate messages are suppressed in throttle window | `debug log is rate limited per aura and area` |
| Conditional safety | Condition/display handler throws | Addon degrades safely and logs only when debug enabled | `condition debug reports evaluation errors when enabled`, `display debug reports apply errors when enabled` |
| UI data load gating | Load restrictions not met | Aura remains hidden and debug reason is available | `load debug reports failure reasons when enabled` |

## Manual Coverage Still Required

- Full in-game frame rendering and anchoring validation
- Client-specific combat log localization text edge cases
- Real raid-scale event pressure during live play
