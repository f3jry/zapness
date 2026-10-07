# Zapness — Discord Activity server (WebSocket relay)

Replaces the old PeerJS/WebRTC networking, which **cannot work inside a Discord
Activity** (Discord's proxy blocks WebRTC; only WebSockets pass through — see
https://docs.discord.com/developers/activities/development-guides/networking).

This folder contains a small Node.js server that:

1. serves the exported Godot web build from `./public`
2. relays Godot's `WebSocketMultiplayerPeer` traffic between the two players
   (it implements the *server side* of Godot's WebSocket multiplayer protocol,
   so the game keeps using its normal high-level multiplayer API / RPCs).

## 1. Build & deploy the game

```sh
# export the Godot web build into game-server/public/
# (Godot editor → Project → Export → Web; preset: splitscreen)
```

Then run everything from one place:

```sh
npm install
npm start           # http://localhost:8920, ws://localhost:8920/ws
```

For production, put this behind TLS (Discord requires HTTPS) — e.g. behind
nginx/Caddy, or deploy the folder as-is to Render/Fly.io/Railway.

## 2. Discord Developer Portal setup

1. Create the application, note the **client id**.
2. Set `client_id` in `splitscreen/project.godot` under `[discord]`.
3. **URL Mappings** for the activity (portal → Activities → URL mappings):
   | Prefix | Target |
   |--------|--------|
   | `/`    | your server origin (e.g. `https://zapness.example.com`) |
   | `/ws`  | same target — the game's WebSocket endpoint |
   If the game files are hosted on the same Node server that runs this relay,
   a single root mapping is enough; both static files and `/ws` share one origin.
4. Set the Activity's **target URL** to `https://<clientId>.discordsays.com/`.
5. In-iframe, the game connects to `wss://<host>/ws?role=host|join&room=<CODE>`
   (same-origin, see `NetworkManager._get_relay_url()`).

## 3. Local testing (browser, no Discord)

```sh
cd game-server
npm start
# open http://localhost:8920 in two tabs
# host: Host  -> shares a code; client: Join -> enter the code
```

Desktop (native) builds are unaffected: `NetworkManager` only auto-connects to
the relay on the web platform.

## 4. Protocol notes (for debugging)

`server.js` implements the server half of Godot's `WebSocketMultiplayerPeer`
(see the header comment in `server.js` for the byte-level protocol). The relay
acts as "peer 1" (the transport-level server) but contains **no game logic**:
the first client to join a room becomes the game host (id `2`), matching
`NetworkManager.GAME_HOST_PEER_ID`. Plain frames addressed to peer 1 are
dropped and logged — if you see `dropped plain frame to peer 1` in the server
log, some code is still doing `rpc_id(1, ...)` and should target the game host
instead (`GameManager_score.gd` was fixed accordingly).

Run the protocol test suite:

```sh
npm test
```
