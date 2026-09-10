# Run and build Base 01

Version 0.6 update: crouch bends backward at the waist without changing model scale; Tab holds a live player scoreboard (town: names/ping; arena: rounds won, round KO and ping). Rankings use rounds won then round KO, with team totals in 2v2. The main menu is Singleplayer / Multiplayer / Settings / Quit; Multiplayer offers Host / Join / WSS Server / Back. Server version 0.6.0 supplies measured ping while keeping protocol 4 compatibility with 0.5. Verify `version: "0.6.0"` at `/health` after updating the existing service.

Client/server version: **0.6.0**. Network protocol: **4**. Use Godot **4.6.1 Standard** with matching Windows export templates and Node.js **22 or newer**. The client uses GDScript and the Compatibility renderer; no .NET SDK or Godot add-ons are required.

## Run and export

Import `game/project.godot` in Godot, allow asset import to finish, then run the project. Single-player works without a server. To host locally, run `npm ci` and `npm start` in `server`, then connect to `ws://127.0.0.1:8787/ws` from clients on the same PC.

For a Windows release, use **Project > Export > Windows Desktop**, architecture `x86_64`, with **Export With Debug** disabled. Export to a new folder outside `game`. Share the entire folder, including a `.pck` if your export creates one, along with the project and dependency licenses. This release uses an embedded pack and is unsigned.

Example PowerShell commands from the source root (replace `godot` with your installed console executable):

```powershell
godot --headless --editor --path .\game --import --quit
New-Item -ItemType Directory -Force -Path .\build\windows | Out-Null
godot --headless --path .\game --export-release "Windows Desktop" ..\build\windows\CoopFoundation.exe
```

The export destination is relative to the game project. Keep the matching 4.6.1 templates. Check output for script/import/export errors and launch the final executable before distribution.

## Local tests

From `server`, `npm test` runs pure combat/match rules and real local WebSocket integration tests. From the source root:

```powershell
.\game\tests\run-smoke.ps1 -Godot "C:\path\to\godot_console.exe" -Render -Width 960 -Height 640
.\game\tests\run-match05.ps1 -Godot "C:\path\to\godot_console.exe" -Node "C:\path\to\node.exe"
```

The smoke runner isolates and verifies restoration of a saved-settings fixture. It tests actual menus/options, controls, Town/NPC/Ready entry, movement and God options. Rendering adds screenshots and pointer/camera checks. The match runner starts a local server and four actual Godot processes, using ordinary network inputs and observing replicated states. Results live under `test-results`.

Focused scripts include `bindings.gd`, `movement05.gd`, `town05.gd`, `match05.gd`, `world05.gd`, `audio.gd` and `audio_samples.py`. GDScript tests must run with a separate process `APPDATA` profile; scripts requiring `--expected-user-root` must receive that absolute profile path. Use absolute log paths and restore the process environment afterward. Do not run them against normal player settings. `match05.gd` advances simulation time deterministically to check all ten default rounds without a 25-minute wait.

`run-lobby.ps1` and `lobby_client.gd` are historical Combat 04/protocol 3 tests. They are retained as reference; use `run-match05.ps1` for this release's Town and match flow. Earlier phase-only online movement tests likewise record their original phase gate, before Town was introduced.

See [VERIFICATION.md](../VERIFICATION.md) for actual results, distinct from these runnable instructions. Local automation cannot establish internet connectivity from separate homes or human audio/control feel. Use [INTERNET-TEST.md](INTERNET-TEST.md) for that test.

## Distribution and deployment

Keep scripts, scenes, original audio assets, project settings, export preset, lockfile, tests and licenses in source control. Exclude `.godot`, `node_modules`, generated builds and test profiles. Deploy the complete `server` folder as one persistent process; friends receive the Windows ZIP.

Base 01 requires a coordinated client/server update to protocol 4. Include the new `match.mjs` as well as `combat.mjs`. Keep the same public service URL and saved settings. See [HOSTING.md](HOSTING.md).
