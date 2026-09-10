# Base 01 architecture

Version 0.6 update: crouch bends backward at the waist without changing model scale; Tab holds a live player scoreboard (town: names/ping; arena: rounds won, round KO and ping). Rankings use rounds won then round KO, with team totals in 2v2. The main menu is Singleplayer / Multiplayer / Settings / Quit; Multiplayer offers Host / Join / WSS Server / Back. Server version 0.6.0 supplies measured ping while keeping protocol 4 compatibility with 0.5. Verify `version: "0.6.0"` at `/health` after updating the existing service.

Godot 4.6.1 client and Node.js server are version 0.6.0, wire protocol 4. The client presents the world and inputs; the online server owns movement, combat, health, readiness and scores.

## Client modules

| Module | Responsibility |
| --- | --- |
| `main.gd` | Menus, connection forms, input routing, options, host permissions, scene composition |
| `session_ui.gd` | Old Man prompt/dialog, ready roster/countdown, match clock/scores, result/victory dialogs |
| `health_hud.gd` | Health, damage trail, protection and conditional stamina bar |
| `network.gd` | WebSocket transport, snapshots, action inputs and local practice movement/combat feedback |
| `practice_match.gd` | Offline Town/ready/round/victory transitions and live match options |
| `gameplay_options.gd` | Categorized player-facing shared option labels, defaults and limits |
| `combat_arena.gd` | Characters, snapshot interpolation, hip-pivot crouch animation, overhead health/names, numeric damage, camera |
| `scoreboard.gd` | Derived roster/score rows, ranking, server ping and hold-Tab presentation; no independent scoring state |
| `world_builder.gd` | Separate Town and grass-field scenery; Old Man model |
| `settings.gd` | Saved preferences, InputMap actions, legacy-binding migration |
| `controls_settings.gd` | Rebinding capture, conflict/cancel/reset feedback and help inside Options |
| `audio.gd` / `assets/audio` | Original music/effects, buses and playback |

`Prefs`, `Net` and `Sound` are autoloads. Preferences remain in `user://settings.cfg`, normally `%APPDATA%\Godot\app_userdata\Co-op Foundation\settings.cfg`, preserving previous releases' settings. Ten actions are installed: four movement directions, jump, punch, block, sprint, crouch and interact. Existing custom bindings are preserved and new conflicting defaults receive available fallbacks. Escape, Tab and the mouse wheel remain reserved.

The full-window world persists behind Options. Modal dialogs and loss of focus release controls; forced match dialogs resume play when their phase finishes. Scenery switches only when the zone changes. A new `round_id` clears transient feedback and snaps actors/camera to fresh positions while keeping the presentation architecture intact.

Town scenery is a flat central plaza with castle walls/buildings outside the bounded play area. The Old Man is at `(0,0,-5)` with a three-metre interaction radius checked by the authoritative controller. Characters can pass through each other; there is no obstacle navigation system yet. Both maps use bounded X/Z movement and Y for feet height.

## Server modules and phases

`server.mjs` owns connections, rooms, host authority, fixed-step scheduling and action validation. `combat.mjs` implements movement, stamina, jumps, crouch hitboxes, damage, block and respawn. `match.mjs` implements ready checks, score aggregation, round timers/overtime, round wins and final winners. One service instance owns all in-memory rooms; no external datastore is needed.

`room.phase` is `lobby`, `ready_check` or `playing`. `zone` is `town` or `arena`; `safe_zone` identifies Town. The nested `match.phase` is `town`, `ready_check`, `round`, `overtime`, `round_end` or `victory`. Keeping transport membership separate from match subphases allows round transitions without tearing down the room.

Match snapshots include round number/count, remaining round/ready/transition times, round knockout totals, round wins, round winner, final winner IDs/names and display score entries. FFA keys scores by player ID; teams use `red`/`blue`. Combat defeat events are credited once to a valid opposing attacker. Falls, self-defeats and friendly targets do not award KOs. Result/victory phases freeze actions and physics. New rounds reset players; after victory the group returns to Town with scores cleared.

Town applies an effective damage-immunity override rather than mutating the saved battle God setting. Only the host changes shared rules or mode; players choose their own team in Town. Start requires the host near the NPC. Every ready check clears readiness, including the host's. Timeout/cancel/membership changes cancel it; only unanimous readiness begins battle. A battle departure returns the remaining group to Town, transferring host ownership if needed.

The server runs nominal 50 ms steps with bounded catch-up and broadcasts at 20 Hz. Inputs older than 250 ms stop movement and held actions. Movement intent and sequenced jump/punch requests are validated; client health/targets/damage fields have no authority. There is no lag compensation or automatic reconnect. See `server/README.md` for protocol fields and [COMBAT.md](COMBAT.md) for rule values.

Single-player mirrors the movement and match controller locally. It has one participant and no invented enemies/KO credit; timer expiry gives that participant a round win. Rule defaults/ranges stay aligned across network, server and option catalog. Tests check default ten-round progression as well as live changes.

## Extension and verification

Keep future NPCs, equipment, maps and persistence in separate modules. Maintain authoritative damage/scoring and the Town safety override when extending combat. Current tests cover pure rules, real WebSockets, deterministic practice, actual UI controls and four Godot clients. Four local clients prove synchronization on this PC, not remote latency or different-home connectivity. See [VERIFICATION.md](../VERIFICATION.md).
