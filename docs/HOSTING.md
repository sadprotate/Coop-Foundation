# Update the shared server for Base 01

Version 0.6 update: crouch bends backward at the waist without changing model scale; Tab holds a live player scoreboard (town: names/ping; arena: rounds won, round KO and ping). Rankings use rounds won then round KO, with team totals in 2v2. The main menu is Singleplayer / Multiplayer / Settings / Quit; Multiplayer offers Host / Join / WSS Server / Back. Server version 0.6.0 supplies measured ping while keeping protocol 4 compatibility with 0.5. Verify `version: "0.6.0"` at `/health` after updating the existing service.

Base 01 requires **protocol 4**. Update the existing shared service; keep its server address and current hosting arrangement. This local build does not deploy or modify the live service.

## Update an existing service

1. Replace the deployed server source with this release's complete `server` folder: `server.mjs`, **`combat.mjs`**, **`match.mjs`**, `package.json`, `package-lock.json` and the updated `Dockerfile` if used. Do not upload `node_modules` or local test profiles.
2. Keep the service root pointed to that folder. The build command remains `npm ci`; the start command remains `npm start`. Use Node.js 22 or newer. The server honors the hosting platform's `PORT` and listens on `0.0.0.0`.
3. Deploy between play sessions. Replacing the process ends existing rooms; create a new room afterward.
4. Open `https://YOUR-EXISTING-SERVICE/health`. Verify `"ok": true` and **`"protocol": 4`**. A protocol 3 response is the previous server.
5. Give every player **CoopFoundation-Base01-Windows.zip** and use the same `wss://YOUR-EXISTING-SERVICE/ws` address. Update everyone together; earlier client versions are incompatible.

No new dependency, database, account system, paid feature or second service is required by the game update. Your hosting provider's existing plan, availability and usage limits still apply. Check the provider's dashboard before changing any paid plan. For Render, consult its [service documentation](https://render.com/docs/web-services), [WebSocket documentation](https://render.com/docs/websocket), [free-service limitations](https://render.com/docs/free) and [current pricing](https://render.com/pricing).

## Hosting requirements

Use one persistent Node.js process/service instance, with HTTPS/TLS and WebSocket upgrade forwarding. Rooms live in memory and are not shared across multiple instances. A static-only host cannot run this server. The reverse proxy/provider supplies public TLS; Node handles HTTP internally. Both `/ws` and `/` accept WebSockets, and `/health` provides readiness/protocol information.

If the service has been sleeping, open its `/health` page and wait for a response before connecting. All players use the same public `wss://` address. Room codes are shared invitations, not accounts. Server restarts erase rooms; settings remain local to each Windows user.

For a new Render service, connect the repository, choose the server folder as Root Directory, use `npm ci` / `npm start`, and configure the health path `/health`. Choose the desired plan in your own account. Existing deployments should be updated in place instead of creating another service.

## Local development

With Node.js 22 or newer, run from the server folder:

```powershell
npm ci
npm start
```

Use `ws://127.0.0.1:8787/ws` from games on that PC. `127.0.0.1` always means the player's own PC; it is not an internet address for friends. `/health` is at `http://127.0.0.1:8787/health` locally. `npm test` runs the local rule/network suite.

The supplied Dockerfile uses the same modules. Build with `docker build -t coop-foundation-server .` and run with `docker run --rm -p 8787:8787 coop-foundation-server`. Public TLS still belongs to the hosting platform/proxy.

After deployment, use [the four-PC acceptance checklist](INTERNET-TEST.md). Local tests completed during development do not establish separate-home connectivity.
