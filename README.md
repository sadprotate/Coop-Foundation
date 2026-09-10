# Co-op Foundation — Combat 06

Version 0.6 keeps the successful 0.5 game flow and adds a backward hip-bend crouch with unchanged proportions, a hold-Tab multiplayer scoreboard, and a four-choice main menu: **Singleplayer, Multiplayer, Settings, Quit**. Multiplayer contains **Host, Join, WSS Server, Back**. The server editor validates and saves the address; Back without Save keeps the previous address.

Hold **Tab** in town for connected players and server-measured ping. In the arena it also shows rounds won and current-round knockouts, ranked by rounds won and then knockouts. Team mode uses shared team totals. Releasing Tab hides it without releasing the cursor. Update the server to **version 0.6.0** for synchronized ping; the wire protocol remains 4, so an older 0.5 server can connect but cannot provide the new ping fields.

A 3D combat sandbox for one to four Windows players. Enter a safe medieval town, meet the Old Man, ready up together and fight across ten rounds in a grass arena. Play free-for-all or Red versus Blue 2v2. Sprinting uses stamina, crouching changes the actual hitbox, and the host can adjust thirty shared gameplay options.

## Play

Extract **CoopFoundation-Combat06-Windows.zip** into a new folder and run **CoopFoundation.exe**. Godot and Node.js are not needed by players. This release is **0.6.0**, using **protocol 4**. Existing saved names, server addresses, keybindings and personal settings carry over on this PC.

**Play single-player** starts an offline town immediately. To play with friends, use the same shared server address; one player creates a room and others join its six-character code. Everyone enters the same town. The room code and team settings are inside Options, also accessible through the Old Man.

The **host** walks to the white-bearded Old Man, presses **F — Talk**, and selects **START BATTLE**. Every player, including the host, must click **READY** before the countdown expires. Nobody teleports early. A missed ready check keeps everyone safely in town.

| Default input | Action |
| --- | --- |
| WASD / arrows | Move relative to the camera |
| Mouse movement / wheel | Turn and orbit / zoom |
| Space | Jump |
| Left Shift | Sprint while moving; consumes stamina |
| Left Ctrl | Crouch; slower movement and lower hitbox |
| Left mouse / hold | Punch / repeat |
| Right mouse / hold | Block toward the direction you face |
| F near the Old Man | Talk |
| Escape | Release the cursor and open Options; Resume returns to play |

Change all ten action bindings in **Options > Gameplay**. Escape cancels a pending remap. Instructions stay inside Options. During play, the interface shows health, stamina while spent or regenerating, other players' names/health, and useful match information. Only damaging hits produce damage numbers; there are no hit/miss counters. Original menu/town music, arena music and action sounds have separate Music and Sound effects volume controls.

## Battles

Default matches have **10 rounds**, **2:30 per round**, and **4 knockouts to win a round**. In free-for-all, individual players score; in 2v2, each team's knockouts combine. Team mode requires exactly two Red and two Blue players. Teammates cannot damage each other. The host chooses the mode and each player chooses a team in town; both stay fixed during a match.

The unique leader wins when time expires. A tie enters overtime until someone takes a unique lead. Players reset between rounds, with a three-second result screen. After the last round, the most round wins determines the match winner. Equal final round-win totals produce joint winners. The winner screen lasts six seconds, then everyone returns to town with scores cleared and town protection restored.

Town always prevents damage, knockouts and knockback, independently of the battle God mode setting. In the arena, defaults are 100 starting health, 10 damage per grounded punch, 20 per airborne punch, and a three-second respawn. Punches can hit only in front of the attacker and must intersect the opponent's current vertical hitbox. A high punch can miss a crouched player; a low punch can still hit them.

**God options are host-only in multiplayer** and editable locally in single-player. Categories cover Player, Movement, Combat, Stamina, Match and World. These include damage immunity, health, attack speed/damage/reach, move/sprint/crouch speed, jump height/speed/count, gravity, falling, stamina, respawn and match rules. Changes replicate to everyone. Personal graphics, audio and keybindings remain each player's choice. See [complete rules and option limits](docs/COMBAT.md).

Single-player has no bots or damage targets. It follows the same ready/round/victory/town loop; the sole participant wins when each round's timer expires, with no invented knockouts. Use shorter host timers to try this loop quickly.

## Server update required

Combat 06 requires its included **protocol 4 server**. Update the existing service with the complete `server` folder, including **combat.mjs** and **match.mjs**, then redeploy. Keep the same server address. `/health` must show `protocol: 4`; Combat 03/04 clients and protocol 3 servers are incompatible with this release. All players should update together. [Hosting/update instructions](docs/HOSTING.md).

Rooms hold four including the host. Joining is allowed in town. A departure during battle returns the remaining group to town; host ownership transfers if needed. A server restart erases rooms. This task builds the update locally; it does not deploy the live service.

## Source and checks

The source ZIP contains the Godot project, Node.js server, tests, documentation and licenses. See [build instructions](docs/BUILD.md), [architecture](docs/ARCHITECTURE.md), and [actual verification results](VERIFICATION.md). Local four-client tests do not establish internet play from separate homes; use [the remote acceptance checklist](docs/INTERNET-TEST.md) after deployment.

The Windows executable is unsigned. Source is MIT licensed; retain engine/dependency notices. Combat 04 archives remain separate rollback builds and need their matching protocol 3 server.
