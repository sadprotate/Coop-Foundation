# Combat 06 controls and rules

Version 0.6 update: crouch bends backward at the waist without changing model scale; Tab holds a live player scoreboard (town: names/ping; arena: rounds won, round KO and ping). Rankings use rounds won then round KO, with team totals in 2v2. The main menu is Singleplayer / Multiplayer / Settings / Quit; Multiplayer offers Host / Join / WSS Server / Back. Server version 0.6.0 supplies measured ping while keeping protocol 4 compatibility with 0.5. Verify `version: "0.6.0"` at `/health` after updating the existing service.

Enter a safe medieval town in single-player or multiplayer. The host invites everyone to a battle through the Old Man. The grass arena supports free-for-all or two teams, Red and Blue, with ten-round matches. Single-player contains only your character; there are no bots, weapons, equipment or progression yet.

## Controls and presentation

| Default input | Action |
| --- | --- |
| WASD / arrows | Camera-relative movement |
| Mouse movement | Orbit camera and turn the character; adjust pitch |
| Mouse wheel | Camera distance |
| Space | Jump |
| Left Shift | Sprint while moving |
| Left Ctrl | Crouch |
| Left mouse / hold | Punch / repeat at configured attack speed |
| Right mouse / hold | Block toward the direction you face |
| F near the Old Man | Talk |
| Escape | Options and free cursor; Resume/Escape returns to play |

In **Options > Gameplay**, remap forward, back, left, right, jump, punch, block, sprint, crouch and talk. Attack/block accept keys or mouse buttons; other actions use keys. Duplicate inputs are rejected without losing the current binding. Escape cancels capture and stays reserved for menus; mouse wheel stays reserved for zoom. Tab holds the multiplayer scoreboard and stays reserved for it. Reset controls restores defaults. Older saved bindings are preserved; a free fallback is chosen if an old custom binding already uses Shift, Ctrl or F. The displayed control labels and talk prompt reflect the saved assignments.

The cursor is captured when playing. Opening Options, a ready/result dialog or losing focus stops local movement and held actions. Online matches continue while Options is open. Forced ready/result dialogs show the cursor until the phase finishes; Escape closes the Old Man's ordinary dialog.

Health is shown at the lower left. The narrow stamina bar beneath it becomes visible when stamina is spent, regenerating or being used, and fades when full. Other players have names and health above their heads. Positive damage shows a floating number without hit/miss text or counters. The arena also shows round number, clock and knockout scores. Movement instructions and room details stay inside Options and the Old Man's dialog.

Original music changes between menu/town and arena. Sounds cover menu actions, jump, landing, swing, impact, block, defeat and respawn. **Options > Audio** has Master, Music and Sound effects controls. Personal graphics, audio, sensitivity and bindings save on this PC; shared match rules reset for a new room.

## Town, teams and readiness

Town is always safe: no damage, fall knockout or damaging knockback. The battle God mode choice is retained separately and resumes in the arena. The Old Man stands near the central banners; approach within three metres and press the displayed Talk input.

Only the host sees **START BATTLE**. The host chooses FFA or 2v2 in Gameplay options, and every player can choose Red or Blue while in town. 2v2 requires all four players with exactly two on each side. FFA supports one to four players and ignores team selection. Mode/team changes are locked during ready checks and battles.

Starting opens a fresh ready check for everyone, including the host. All players begin NOT READY and a visible countdown runs. Only unanimous readiness teleports the group. Timeout, host cancellation or a roster change cancels the pending start in town. Host departure transfers ownership to a remaining player. A player leaving during battle returns the group to town. The remaining players can start another ready check through the Old Man.

## Movement, attacks and health

Default normal movement is 5.5 m/s, sprint is 9 m/s, and crouch/block movement is 2.5 m/s. Sprint spends 25 stamina/s from a maximum of 100. Regeneration begins after a one-second delay and restores 20/s. At zero stamina, sprint ends and normal movement resumes. Release sprint before sprinting again; regeneration still works while exhausted. Crouching takes priority over sprinting and reduces the actual body height from 1.8 to 0.95 metres.

Default health is 100. A grounded punch deals 10 damage and an airborne punch deals 20. Airborne criticals depend on actual jump state; there is no random critical chance. Punches have a half-second cooldown, select at most one eligible target, and require range within 2.2 metres and a 120-degree forward cone. Targets behind the attacker cannot be hit.

The attack also has a real vertical interval: standing punches occupy 1.15–1.75 metres above the attacker's feet, while crouched punches occupy 0.45–0.9 metres. The interval must overlap the target's body at its current feet height. A standing or jumping punch can pass above a crouched target; a low punch can still hit them. Crouching is not invulnerability. Jumping can move either player into or out of the attack interval.

Blocking stops attacks from the defender's forward 120-degree arc. Hits from outside that arc deal normal damage. Release block to punch. Teammates are ineligible targets in 2v2. Zero-damage/protected hits do not apply damaging knockback. The server decides valid hits, health, positions and scoring.

At zero health, movement/actions stop until respawn (three seconds by default). Respawn uses the configured starting health, capped by maximum health, and grants one second of protection. Punching ends your own protection. Fall damage is off by default; when enabled, excess fall distance above the safe threshold is multiplied by damage per metre. A fall/self defeat does not award another player a knockout.

## Rounds and winning

Defaults are ten rounds, 150 seconds per round and four knockouts to win. FFA uses individual knockout scores; Red/Blue combine their members' scores. Reaching the target ends the round. When the timer expires, the unique leading player/team wins; a tie enters overtime until a unique lead exists. Defeats are credited once, only to valid opposing attackers.

The round winner earns one round win. A three-second result screen freezes players, then health, stamina, actions and positions reset for the next round. The match continues through all configured rounds. The most round wins wins the match; a final tie produces joint winners. A six-second WINNER screen precedes a shared return to safe town, with all match scores cleared.

The host can restart the entire active match or return everyone to town from Options. Changing round duration adjusts the current remaining time by the duration difference, preserving elapsed time. Ready-check duration changes behave likewise. KO targets and total-round changes are applied by the match controller; finished winners are not rewritten. These are live testing controls, so agree on rule changes with your group.

Single-player follows this same loop without imaginary opponents or knockouts. The sole player is the unique leader at timer expiry. Shorten the timer and round count in God options to try the winner/town sequence quickly.

## Host / God options

Only the multiplayer host can edit shared rules. Guests can view them and retain full control of their personal settings. New rooms start with defaults. **Battle God mode** switches all arena damage off; town protection stays on independently. Reset God options restores all shared defaults.

| Category | Setting | Default | Allowed range |
| --- | --- | --- | --- |
| Player | Maximum health | 100 | 10–1000 |
| Player | Starting / respawn health | 100 | 1–1000, capped by maximum |
| Movement | Normal speed | 5.5 m/s | 1–20 |
| Movement | Sprint speed | 9 m/s | 1–30 |
| Movement | Crouch speed | 2.5 m/s | 0.1–15 |
| Movement | Jump strength / height | 1.225 m | 0.25–10 |
| Movement | Jump speed / airtime | 1× | 0.25–3× |
| Movement | Jumps before landing | 1 | 1–10 |
| Movement | Blocking movement multiplier | 2.5 / 5.5× | 0–1× |
| Combat | Attack speed | 2/s | 0.2–10/s |
| Combat | Base attack damage | 10 | 0–100 |
| Combat | Player damage multiplier | 1× | 0–10× |
| Combat | Punch reach | 2.2 m | 0.5–5 |
| Combat | Airborne critical damage | 2× | 1–5× |
| Combat | Knockback strength | 2 m/s | 0–15 |
| Combat | Respawn time | 3 s | 0.5–10 |
| Stamina | Maximum | 100 | 1–1000 |
| Stamina | Sprint drain | 25/s | 0–200 |
| Stamina | Regeneration | 20/s | 0–200 |
| Stamina | Regeneration delay | 1 s | 0–10 |
| Match | Round duration | 150 s | 10–1800 |
| Match | Knockouts to win round | 4 | 1–50 |
| Match | Number of rounds | 10 | 1–50 |
| Match | Ready-check timer | 15 s | 3–120 |
| World | Gravity | 20 m/s² | 1–80 |
| World | Maximum fall speed | 30 m/s | 1–100 |
| World | Fall damage | Off | On/off |
| World | Safe fall distance | 4 m | 0–50 |
| World | Damage per extra fall metre | 10 HP/m | 0–100 |

Jump speed changes the duration without changing the configured fresh-jump height. Health/start-health changes do not create opponents or grant knockout credit. Restart the match to reset all players immediately under the current rules.
