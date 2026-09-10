# Combat 06 authoritative server

Version 0.6 update: crouch bends backward at the waist without changing model scale; Tab holds a live player scoreboard (town: names/ping; arena: rounds won, round KO and ping). Rankings use rounds won then round KO, with team totals in 2v2. The main menu is Singleplayer / Multiplayer / Settings / Quit; Multiplayer offers Host / Join / WSS Server / Back. Server version 0.6.0 supplies measured ping while keeping protocol 4 compatibility with 0.5. Verify `version: "0.6.0"` at `/health` after updating the existing service.

Node.js 22+, package version **0.6.0**, protocol **4**. `server.mjs` manages transport/rooms, `combat.mjs` manages movement/damage and `match.mjs` manages Town, readiness, scoring and match transitions. The only package dependency remains pinned `ws` 8.21.0.

## Run, test and deploy

```powershell
npm ci
npm start
```

Local client address: `ws://127.0.0.1:8787/ws`. Health: `http://127.0.0.1:8787/health`. Run `npm test` for pure rules and real WebSocket integration tests.

Update an existing public service using this complete folder, including **combat.mjs and match.mjs**, the lockfile and the updated Dockerfile. Keep its existing root directory, `npm ci` build command, `npm start` command and public URL. Deploy between sessions and confirm `/health` reports `protocol: 4`. All clients must update to Combat 06 together; protocol 3 is incompatible. This source delivery does not deploy the live service. See [HOSTING.md](../docs/HOSTING.md).

One process/instance owns the in-memory rooms. The hosting platform/reverse proxy supplies TLS and forwards HTTP and WebSocket upgrades. Both `/ws` and `/` accept WebSockets. Empty rooms and process restarts discard room state; there is no database or automatic session recovery.

| Environment variable | Default | Purpose |
| --- | --- | --- |
| `PORT` | 8787 | HTTP/WebSocket port; honors platform assignment |
| `HOST` | 0.0.0.0 | Listening interface |
| `MAX_ROOMS` | 100 | Room cap |
| `MAX_CONNECTIONS` | 400 | Total WebSocket cap |
| `MAX_CONNECTIONS_PER_IP` | 128 | Immediate-peer cap |
| `ROOM_IDLE_MINUTES` | 30 | Inactivity timeout |

Behind a proxy, the immediate peer may be that proxy; configure its cap for the intended total. Forwarded-IP headers are not trusted. Public players use `wss://`; local tests use `ws://`.

## Protocol 4

UTF-8 JSON objects use a `type` field. On connection, `welcome` reports `id` and `protocol: 4`. Names are trimmed, control characters removed and limited to 1–24 Unicode characters. Room capacity is four; slots 0–3 remain stable until a player leaves. Team IDs are 0 Red and 1 Blue. Room codes are invitations, without player authentication.

| Client type | Fields | Behavior |
| --- | --- | --- |
| `create` | `name`, `protocol: 4`, optional `mode` | Create Town room, become host |
| `join` | `code`, `name`, `protocol: 4` | Join Town; joining during a ready check cancels that check |
| `set_mode` | `mode: "ffa"` or `"teams"` | Host-only, Town lobby only |
| `set_party` | integer `party: 0` or `1` | Own team choice in Town lobby |
| `god_options` | `options` object or `reset: true` | Host-only shared live settings, validated/clamped |
| `start` | none | Host near Old Man starts a fresh ready check; 2v2 needs balanced four |
| `ready` | boolean `ready` | Ready-check confirmation; unanimous true begins battle |
| `cancel_start` | none | Host cancels pending ready check |
| `input` | numeric `x`, `z`, `yaw`; boolean `block`, `sprint`, `crouch`; integer `seq` | Movement/facing/held actions |
| `jump` / `punch` | positive integer `action_seq` | Request validated action |
| `restart` | none | Host restarts the active match from round one |
| `lobby` | none | Host returns group to Town with scores reset |
| `leave` | none | Leave room without closing socket |
| `ping` | numeric `t` | Receive echoed `pong` |

`input.seq` is a nonnegative safe integer. Jump/punch share a separate positive `action_seq`. Each increases; repeats/older values are ignored. Per-player replay state resets on fresh-round/reset/join, not respawn; clients may continue increasing across rounds. Flush current facing/held input before an action when changing both together. Client health, damage, target and vertical-position fields do not determine simulation outcomes.

Server messages:

- `welcome`: connection ID and protocol.
- `room`: `code`, `host_id`, `phase`, `level`, `round_id`, `mode`, `god_options`, `zone`, `safe_zone`, `match`, and roster `{id,name,slot,party,team,ready}`. An empty code/roster acknowledges leaving.
- `state`: `tick`, the shared phase/zone/match/rule fields above, and simulated player states. Player fields include `{id,slot,party,team,x,y,z,yaw,health,max_health,grounded,jumps_used,block,crouching,body_height,sprinting,stamina,max_stamina,stamina_regen_in,sprint_exhausted,action_seq,vy,punch_t,hurt_t,respawn_in,invulnerable}`. Coordinates use metres; Y is feet height; timers use seconds.
- `combat`: `event_id`, `kind`, `attacker`, `target`, `damage`, `critical`, optionally `source`. Kinds include jump, punch, hit, blocked, miss, defeat and respawn. IDs increase within the room across rounds. Fall damage has an empty attacker and `source: "fall"`. Clients render positive damage numbers and animations/sounds without miss counters.
- `notice`: informational cancellation/departure message; `error`: rejected request or connection problem. Both contain `message`.
- `pong`: echoed `t`.

## Match and safety state

Room phases are `lobby`, `ready_check`, `playing`. Town covers the first two. `zone` is `town` or `arena`; Town sets `safe_zone: true`. The nested match phase is `town`, `ready_check`, `round`, `overtime`, `round_end` or `victory`.

Match fields are `phase`, `round_number`, `total_rounds`, `time_left`, `ready_time_left`, `transition_time_left`, `round_scores`, `round_wins`, `round_winner`, `winner_ids`, `winner_names`, and `score_entries` with `{id,name,party,knockouts,round_wins}`. FFA score keys are player IDs; team keys are `red`/`blue`. Internal credited-event tracking is never serialized.

Town spawns are (-3,2), (3,2), (-3,5), (3,5) in X/Z. Old Man position is (0,0,-5), interaction distance 3 m. Arena spawns are (-4,0), (4,0), (0,-5), (0,5). Both areas bound X/Z to -18..18. Town uses effective God mode without changing the host's battle flag, preventing damage, knockouts and damaging knockback, including falls.

Starting resets every Ready flag, including the host's. Only unanimous readiness transitions to the arena. Timeout, host cancellation or membership changes cancel readiness. A departure resets the remaining group to Town and transfers host ownership if needed. Joining an active battle is refused. Mode/team changes are Town-lobby-only; shared God options remain host-editable live.

Defaults: 10 rounds, 150 seconds each, 4 opposing knockouts to win a round. Team scores combine; only real opposing defeat events receive credit, once each. No fall, self or friendly credit. At time expiry a unique leader wins; a tie enters overtime until a unique lead exists. Round completion records a win and freezes players for 3 seconds, then resets health/stamina/actions/spawns and increments `round_id`. After the configured final round, the highest round-win total wins; equal final totals share victory. A 6-second victory state precedes Town return and cleared scores.

Live duration edits preserve elapsed time by adjusting the remaining time by the duration delta. KO target changes are evaluated by the active match controller; total-round changes affect subsequent transitions. Finalized victory winners remain fixed. Restart discards the current match progress under the current rules.

## Movement and combat

The nominal simulation interval is 50 ms, with 20 Hz snapshots. Measured elapsed time accumulates; bounded two-step catch-up prevents a large teleport after a stall. Movement is normalized and stale inputs stop after 250 ms. Sustained overload may slow simulation. There is no rewind/lag compensation.

Default walk/sprint/crouch speeds are 5.5/9/2.5 m/s. Sprint drains 25/s from 100 stamina; regeneration restores 20/s after a 1-second delay. Exhaustion forces normal speed until sprint is released. Body height is 1.8 standing and 0.95 crouched. Jump speed and gravity preserve configured fresh-jump height, with terminal fall speed and optional excess-height fall damage.

A punch selects at most one eligible target in a 120-degree forward cone within 2.2 m, requiring overlap between its vertical interval and the target's current body. Standing interval is feet+[1.15,1.75], crouched interval feet+[0.45,0.9]. Facing vector is `(-sin(yaw),0,-cos(yaw))`. Behind targets cannot be hit; crouch is not blanket immunity. Default grounded damage is 10, airborne damage 20, cooldown 0.5 s. Defender-forward 120-degree block prevents damage. Teammates are ineligible in teams mode.

Default defeat lasts 3 seconds, then respawn uses starting health capped by max health and grants 1-second protection. Punching ends the attacker's own protection. Damage immunity also prevents damaging knockback. [COMBAT.md](../docs/COMBAT.md) lists all thirty host settings, defaults and bounds. Keep client option catalogs and practice values aligned when changing server defaults.

## Verification and limitations

Tests cover room membership/caps, host transfer, version rejection, input validation/replay/staleness, movement/jumps, damage/block/cone/vertical hitboxes, sprint/crouch sync, options authority, Town safety, fresh readiness and cancellation, valid KO credit, timers/overtime, ten-round progression, result freezes, victory and Town reset. Real WebSocket tests use ordinary messages without test-only damage endpoints. Four actual Godot client tests live in `game/tests/run-match05.ps1`; [VERIFICATION.md](../VERIFICATION.md) records completed results.

Payload, rate, connection and buffer caps are prototype safeguards. There are no accounts, passwords, durable rooms, moderation, automatic reconnect or distributed-room support. Local tests do not establish connectivity/latency from separate homes; run [INTERNET-TEST.md](../docs/INTERNET-TEST.md) after deploying the protocol 4 server.
