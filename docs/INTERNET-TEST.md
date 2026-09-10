# Combat 06 four-player internet acceptance test

Version 0.6 update: crouch bends backward at the waist without changing model scale; Tab holds a live player scoreboard (town: names/ping; arena: rounds won, round KO and ping). Rankings use rounds won then round KO, with team totals in 2v2. The main menu is Singleplayer / Multiplayer / Settings / Quit; Multiplayer offers Host / Join / WSS Server / Back. Server version 0.6.0 supplies measured ping while keeping protocol 4 compatibility with 0.5. Verify `version: "0.6.0"` at `/health` after updating the existing service.

Use four Windows PCs running Combat 06 and a deployed protocol 4 server. At least one PC must be on a different internet connection (another home or a phone hotspot with home Wi-Fi disconnected). Four local windows or PCs behind one router are useful checks but do not establish separate-home play.

Open the public HTTPS `/health` page and confirm `ok: true`, `protocol: 4`. All players use the same public `wss://` server address. Record the date, build name, deployed commit/server URL and each PC's Windows/network details without publishing room codes. Leave results unmarked until players actually try them.

| Check | Expected result | Pass / fail / notes |
| --- | --- | --- |
| Host/create and three joins | Four named characters appear in the same castle town; no early arena entry | |
| Wrong code / fifth player | Clear refusal without disrupting the room | |
| Clean HUD and audio | Health, conditional stamina and overhead names/health; no movement instructions or hit/miss counters; menu/town and arena music plus action effects | |
| Custom controls | All ten actions can be rebound; conflicts and Escape cancellation preserve settings; choices survive reopening | |
| Pointer/options | Escape releases cursor and shows settings; Resume restores play; focus loss stops local held actions | |
| Sprint/exhaustion | Other PCs see faster movement; stamina drains, sprint stops at zero, normal speed returns and stamina regenerates | |
| Crouch replication | All PCs see lowered bodies; high punches miss and low overlapping punches can hit | |
| Town safety | Attacks and enabled fall damage cannot hurt, knock out or knock back Town players | |
| Host God controls | Guests can view shared settings but cannot change them; host changes replicate; personal audio/graphics stay individual | |
| Old Man | Talk prompt appears near him with correct custom key; only host has START BATTLE | |
| Withheld ready | Everyone starts NOT READY, visible countdown/roster, no early teleport; timeout keeps all in Town | |
| Unanimous ready | Host and all three guests click READY; everyone enters arena together | |
| Forward hits/block | Front punches land within range/height; behind-target attempts miss; frontal block prevents damage and rear attacks can land | |
| Defeat/respawn | Valid damage shows numbers and synchronized health; defeat freezes then respawns with brief protection | |
| Red/Blue 2v2 | Exactly two per side required; friendly punches do no damage; team KOs combine | |
| FFA scoring | Only valid opposing defeats award one KO; four KOs wins a default round | |
| Timer/overtime | Unique leader wins at 2:30; tied scores enter overtime until a unique lead | |
| Round reset | Three-second result, synchronized next round, fresh positions/health/stamina and reset round KO totals | |
| Complete ten rounds | Round wins accumulate and most wins determines winner; final tied totals share victory | |
| Winner and return | Large matching winner screen for six seconds, then all return to safe Town with scores reset | |
| Second battle | Old Man initiates a fresh all-NOT-READY check; a new match starts normally | |
| Restart / return to Town | Host actions work from Options and replicate; guests cannot invoke them | |
| Leave / host transfer | Battle departure returns group to Town; next host gains NPC/God controls; old host can rejoin in Town | |
| Quit/reopen | Application closes normally and saved personal settings remain | |

Record high latency, disconnects, sound balance and control feel separately from correctness. Use default rules for the final acceptance pass; shortened timers/one-KO targets can speed up an initial trial. Restore defaults afterward. If a check fails, keep logs/screenshots and record which players observed it.
