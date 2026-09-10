# Verification — Combat 06 (0.6.0 / protocol 4)

Completed September 9, 2026 on Windows with Godot 4.6.1.

| Check | Result |
| --- | --- |
| Full authoritative server regression | 33 tests, 0 failures |
| Rendered menus/settings/singleplayer at 960×640 | 154 checks, 0 failures |
| Movement and backward hip-bend | 55 checks, 0 failures |
| World and rendered crouch | 20 checks, 0 failures |
| Custom controls/migration | 46 checks, 0 failures |
| Solo ten-round match flow | 107 checks, 0 failures |
| Scoreboard ranking and roster derivation | 8 checks, 0 failures |
| Four actual Godot clients | Host 110/110, guests 8/8, 5/5, 4/4 |
| Windows release export | Completed successfully |
| Exported executable startup | Exit 0 |
| Embedded release menu/Town/scoreboard and normal Quit | Exit 0 |

The crouch model retains a constant uniform scale and rotates the torso, head and arms smoothly about a hip pivot. Rendered Town captures were visually inspected. Existing server crouch hitboxes remain 0.95 metres with real vertical punch overlap; high misses, low hits and forward-only attack rules pass the combat suite.

The four-client run holds and releases Tab through Main's ordinary input path in Town and the arena, verifies all connected players and measured ping, identifies the local player, preserves pointer capture, and ranks the actual round winner first. It also completes the existing ten-round loop, team immunity, ready timeout, shared victory, safe Town reset, another ready check and host transfer.

Separate server tests delay WebSocket pong responses to verify that ping changes are server measured and replicated. Forged input ping cannot set it. An unexpected socket termination removes that player from the roster. Scoreboard derivation tests cover joins/leaves, stale snapshots, changed rankings and team totals without a duplicate score store.

Menu tests verify the four front-page choices, Multiplayer's Host/Join/WSS forms, saved-address preservation, invalid-address rejection, secure/local address validation, save/reload, Back navigation and existing personal settings. Every smoke run uses an isolated settings fixture restored byte-for-byte.

One older Town test initially compared a settled position against an approximate movement goal during concurrent rendering. It now compares actual settled positions before/after the safe punch, checking both X and Z for zero knockback. The final full suite passes. An early standalone scoreboard test loaded an autoload-dependent UI script too soon; loading after initialization fixed the test harness. No failing checks remain in the final runs.

Evidence:
- Menus: test-results/smoke-20260909-132508-render-960-640
- Movement/world/controls/solo: test-results/focused06-20260909-132608
- Actual multiplayer and scoreboard captures: test-results/match05-20260909-132631
- Scoreboard derivation: work/scoreboard06.log
- Export/startup/normal Quit: work/combat06-export.log and work/combat06-release-*.log

Audio remains the original tested music/effects from Version 0.5; no assets were replaced. Source tests and local multiplayer checks do not establish connectivity or latency from separate homes. The sandbox's known root-certificate diagnostic remains; final release checks have no script or cleanup errors.

Update the existing server to version 0.6.0 to supply shared ping. Protocol remains 4, so Version 0.5 clients remain compatible, but the new scoreboard/menu/animation require Version 0.6. The live service was not deployed by this local build. The Windows executable is unsigned. Version 0.5 archives remain available as rollback packages.
