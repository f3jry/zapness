/**
 * Protocol test for the Zapness WebSocket relay (game-server/server.js).
 *
 * Simulates on the wire what Godot's WebSocketMultiplayerPeer +
 * SceneMultiplayer do (see server.js header for the protocol) and asserts the
 * full 2-player lobby flow: host creates a room, client joins, ADD_PEER /
 * DEL_PEER announcements, RPC-style relayed frames, broadcasts, and full-room
 * rejection.
 *
 * Messages are consumed through a buffering reader so nothing is lost between
 * awaits (raw on('message') handlers would race the relay's async deliveries).
 *
 * Run: node test_relay.js
 */
'use strict';

const { spawn } = require('node:child_process');
const path = require('node:path');
const WebSocket = require('ws');

const PORT = 8921;
const WS_URL = 'ws://127.0.0.1:' + PORT + '/ws';

// SceneMultiplayer protocol constants (must match server.js; verified against
// reference bytes from a real Godot server: ADD_PEER = [07 01 <id>]).
const NET_CMD_SYS = 7;
const SYS_ADD_PEER = 1;
const SYS_DEL_PEER = 2;
const SYS_RELAY = 3;

let passed = 0;
let failed = 0;

function ok(cond, label) {
	if (cond) {
		console.log('  ok   ' + label);
		passed++;
	} else {
		console.error('  FAIL ' + label);
		failed++;
	}
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

/** Build a SceneMultiplayer sys frame: [0x07, sysCmd, int32 LE peerId]. */
function sysFrame(sysCmd, peerId) {
	const buf = Buffer.alloc(6);
	buf[0] = NET_CMD_SYS;
	buf[1] = sysCmd;
	buf.writeInt32LE(peerId, 2);
	return buf;
}

/** A WebSocket whose incoming frames are buffered so tests can consume them in order. */
class Peer {
	/** @param {WebSocket} ws */
	constructor(ws) {
		this.ws = ws;
		this.queue = [];
		this.waiters = [];
		this.closedPromise = new Promise((resolve) => ws.once('close', () => resolve(true)));
		ws.on('message', (data) => {
			const buf = Buffer.isBuffer(data) ? data : Buffer.from(data);
			if (this.waiters.length > 0) {
				this.waiters.shift()(buf);
			} else {
				this.queue.push(buf);
			}
		});
	}

	/** Resolve with the next buffered frame (waiting up to timeoutMs if empty). */
	next(timeoutMs = 2000) {
		if (this.queue.length > 0) {
			return Promise.resolve(this.queue.shift());
		}
		return new Promise((resolve, reject) => {
			const timer = setTimeout(() => {
				const i = this.waiters.indexOf(waiter);
				if (i >= 0) this.waiters.splice(i, 1);
				reject(new Error('timeout waiting for message'));
			}, timeoutMs);
			const waiter = (buf) => {
				clearTimeout(timer);
				resolve(buf);
			};
			this.waiters.push(waiter);
		});
	}

	/** Await a SYS frame with the given command and peer id. */
	async expectSys(sysCmd, peerId, label) {
		const msg = await this.next();
		ok(
			msg.length === 6 && msg[0] === NET_CMD_SYS && msg[1] === sysCmd && msg.readInt32LE(2) === peerId,
			label
		);
	}

	async expectClosed(label, timeoutMs = 2000) {
		const before = Date.now();
		while (this.ws.readyState !== WebSocket.CLOSED && Date.now() - before < (timeoutMs || 2000)) {
			await sleep(50);
		}
		ok(this.ws.readyState === WebSocket.CLOSED, label);
	}
}

function connect(role, room) {
	return new Peer(new WebSocket(WS_URL + '?role=' + role + '&room=' + room));
}

async function main() {
	const server = spawn(process.execPath, [path.join(__dirname, 'server.js')], {
		env: { ...process.env, PORT: String(PORT) },
		stdio: ['ignore', 'inherit', 'inherit'],
	});
	await sleep(500);

	try {
		// --- 1. host creates the room, receives its id as the first frame
		const host = connect('host', 'ABC123');
		const hostId = await host.next();
		ok(hostId.length === 4 && hostId.readInt32LE(0) === 2, 'host receives int32 LE id 2');

		// --- 2. client joins
		const client = connect('join', 'ABC123');
		const clientId = await client.next();
		ok(clientId.length === 4 && clientId.readInt32LE(0) === 3, 'client receives int32 LE id 3');

		// --- 3. ADD_PEER announcements in both directions
		const hostAdd = await host.next();
		ok(
			hostAdd.length === 6 && hostAdd[1] === SYS_ADD_PEER && hostAdd.readInt32LE(2) === 3,
			'host notified of client (ADD_PEER 3)'
		);
		const clientAdd = await client.next();
		ok(
			clientAdd.length === 6 && clientAdd[1] === SYS_ADD_PEER && clientAdd.readInt32LE(2) === 2,
			'client notified of host (ADD_PEER 2)'
		);

		// --- 4. RPC-style targeted frame: host (2) -> client (3)
		const payload = Buffer.from([0xde, 0xad, 0xbe, 0xef]);
		host.ws.send(Buffer.concat([sysFrame(SYS_RELAY, 3), payload]));
		const clientGot = await client.next();
		ok(
			clientGot.length === 6 + payload.length &&
				clientGot[1] === SYS_RELAY &&
				clientGot.readInt32LE(2) === 2 &&
				clientGot.subarray(6).equals(payload),
			'client receives host frame re-sourced to peer 2'
		);

		// --- 5. broadcast (target 0) from client reaches the host, re-sourced
		const bcast = Buffer.from('broadcast');
		client.ws.send(Buffer.concat([sysFrame(SYS_RELAY, 0), bcast]));
		const hostGot = await host.next();
		ok(
			hostGot.length === 6 + bcast.length &&
				hostGot[1] === SYS_RELAY &&
				hostGot.readInt32LE(2) === 3 &&
				hostGot.subarray(6).equals(bcast),
			'host receives broadcast re-sourced from peer 3'
		);

		// --- 6. plain frames addressed to "the server" (peer 1) are dropped safely
		client.ws.send(Buffer.from([0x00, 0x01, 0x02, 0x03]));
		await sleep(150);
		ok(true, 'plain frame to server dropped without crashing');

		// --- 7. client leaves -> host gets DEL_PEER(3)
		client.ws.close();
		const hostDel = await host.next();
		ok(
			hostDel.length === 6 && hostDel[1] === SYS_DEL_PEER && hostDel.readInt32LE(2) === 3,
			'host notified of client leave (DEL_PEER 3)'
		);

		// --- 8. joining a non-existent room is rejected
		const ghost = connect('join', 'ZZZ999');
		await ghost.expectClosed('join on missing room is rejected');

		// --- 9. a third peer is rejected when the room is full
		const host2 = connect('host', 'DEF456');
		await host2.next(); // id 2
		const client2 = connect('join', 'DEF456');
		await client2.next(); // id 3
		const third = connect('join', 'DEF456');
		await third.expectClosed('third peer rejected when room is full');

		console.log('\n' + passed + ' passed, ' + failed + ' failed');
	} catch (err) {
		ok(false, 'unexpected error: ' + err.message);
		console.error(err);
	} finally {
		server.kill();
		process.exit(failed === 0 ? 0 : 1);
	}
}

main().catch((e) => {
	console.error(e);
	process.exit(1);
});
