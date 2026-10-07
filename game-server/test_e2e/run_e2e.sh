#!/usr/bin/env bash
# E2E: two real Godot instances (host + client) talking through the relay.
# Usage: GODOT_BIN=/path/to/godot ./run_e2e.sh
set -u

DIR="$(cd "$(dirname "$0")" && pwd)"
PORT="${E2E_PORT:-8922}"
GODOT="${GODOT_BIN:-godot}"

cd "$DIR"
export RELAY_PORT="$PORT"
PORT="$RELAY_PORT" node ../server.js >relay.log 2>&1 &
SRV=$!
sleep 0.5

"$GODOT" --headless --path "$DIR" -- --role=host >host.log 2>&1 &
HPID=$!
sleep 2   # host must create the room before the client joins
"$GODOT" --headless --path "$DIR" -- --role=client >client.log 2>&1 &
CPID=$!

wait "$HPID"; HEXIT=$?
wait "$CPID"; CEXIT=$?

kill "$SRV" 2>/dev/null
wait "$SRV" 2>/dev/null

echo "--- host log ---";   grep -E "peer_connected|got|PASS|FAIL" host.log
echo "--- client log ---"; grep -E "peer_connected|got |PASS|FAIL" client.log

if [ "$HEXIT" -eq 0 ] && [ "$CEXIT" -eq 0 ]; then
	echo "E2E TEST OK"
	exit 0
else
	echo "E2E TEST FAILED"
	exit 1
fi
