# E2E test: real Godot instances over the relay

This test runs two actual Godot processes (host + client) against the Node.js
relay and verifies the full path that the game uses:

- `WebSocketMultiplayerPeer` transport handshake (int32 LE peer id)
- `SceneMultiplayer` ADD_PEER handling (peers appear via `multiplayer.peer_connected`)
- targeted RPCs (`rpc_id`) and broadcasts (`rpc()`) in both directions,
  including correct `multiplayer.get_remote_sender_id()` attribution
- the `SYS_COMMAND_RELAY` routing that `GameManager_score.gd` depends on

## Run

```sh
./run_e2e.sh
```

The script starts `game-server/server.js` on a test port, launches two Godot
instances with `--role=host` / `--role=client`, and checks both report
`E2E_PASS`. Exit code 0 = pass.

Requires a `godot` binary (4.x, headless capable) on PATH or at `$GODOT_BIN`.
