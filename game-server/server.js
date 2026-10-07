/**
 * Zapness — Discord Activity WebSocket relay for Godot's WebSocketMultiplayerPeer.
 *
 * Why this exists:
 *   Discord Activities run in a sandboxed iframe where WebRTC is NOT supported
 *   (https://docs.discord.com/developers/activities/development-guides/networking).
 *   Only WebSockets work, routed through the Discord proxy. The game previously used
 *   PeerJS (WebRTC + external signaling), whose connection hung forever at
 *   "peer: connecting.." inside Discord. This relay replaces PeerJS entirely.
 *
 * What it does:
 *   - Serves the exported Godot web build from ./public
 *   - Implements the *server side* of Godot's WebSocketMultiplayerPeer protocol,
 *     so the game's high-level multiplayer API (RPCs, MultiplayerSynchronizer)
 *     works unchanged. The relay takes the role Godot's "server" (peer 1) plays.
 *
 * Wire protocol (mirrors godot 4.3 modules, little-endian ints):
 *   - On WS open, relay -> client: 4-byte int32 LE = assigned unique peer id (>= 2).
 *     The first client in a room gets id 2 — the "game host" in game logic.
 *   - Join/leave announcements use SceneMultiplayer sys frames:
 *       [0x07 NETWORK_COMMAND_SYS, 2 SYS_COMMAND_ADD_PEER, int32 LE peerId]
 *       [0x07 NETWORK_COMMAND_SYS, 3 SYS_COMMAND_DEL_PEER, int32 LE peerId]
 *   - Client-to-client traffic is routed the same way a real Godot host does
 *     (SceneMultiplayer SYS_COMMAND_RELAY, 6-byte header + payload):
 *       client sends: [0x07, 4, int32 LE target, payload...]
 *       relay routes: [0x07, 4, int32 LE source, payload]
 *     target > 0 = specific peer, 0 = broadcast to all other peers,
 *     target < 0 = everyone except (-target).
 *   - Plain (non-sys) frames from a client are packets addressed to "the server"
 *     (peer 1). The relay has no game logic, so those are dropped and logged.
 *
 * Run:  npm install && npm start   (http://localhost:8920, ws://localhost:8920/ws)
 */
'use strict';

const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const WebSocket = require('ws');
const WebSocketServer = WebSocket.Server || WebSocket.WebSocketServer;

const PORT = Number(process.env.PORT || 8920);
const PUBLIC_DIR = path.join(__dirname, 'public');
const MAX_PLAYERS = 2;
const ROOM_CODE_RE = /^[A-Z0-9]{3,16}$/;

// SceneMultiplayer protocol constants (modules/multiplayer/scene_multiplayer.h).
// NOTE: C++ enum, so the first value is 0 (verified against reference wire
// bytes captured from a real Godot server: ADD_PEER frames are [07 01 <id>]).
const NET_CMD_SYS = 7; // NETWORK_COMMAND_SYS (low 3 bits of the first byte)
const SYS_AUTH = 0; // SYS_COMMAND_AUTH
const SYS_ADD_PEER = 1; // SYS_COMMAND_ADD_PEER
const SYS_DEL_PEER = 2; // SYS_COMMAND_DEL_PEER
const SYS_RELAY = 3; // SYS_COMMAND_RELAY

/** rooms: Map<roomCode, { clients: Map<ws, {id}>, nextId }> */
const rooms = new Map();

function log(...args) {
	console.log(new Date().toISOString(), ...args);
}

/** 4-byte int32 LE frame: the transport handshake that assigns a client its id. */
function idFrame(peerId) {
	const buf = Buffer.alloc(4);
	buf.writeInt32LE(peerId, 0);
	return buf;
}

/** 6-byte SceneMultiplayer sys frame: [0x07, sysCmd, int32 LE arg]. */
function sysFrame(sysCmd, peerId) {
	const buf = Buffer.alloc(6);
	buf[0] = NET_CMD_SYS;
	buf[1] = sysCmd;
	buf.writeInt32LE(peerId, 2);
	return buf;
}

/** Wrap a payload in a SYS_COMMAND_RELAY frame attributed to `fromId`. */
function relayFrame(fromId, payload) {
	return Buffer.concat([sysFrame(SYS_RELAY, fromId), payload]);
}

// --------------------------------------------------------------- static ----

const MIME = {
	'.html': 'text/html; charset=utf-8',
	'.js': 'text/javascript',
	'.mjs': 'text/javascript',
	'.wasm': 'application/wasm',
	'.json': 'application/json',
	'.png': 'image/png',
	'.jpg': 'image/jpeg',
	'.svg': 'image/svg+xml',
	'.ico': 'image/x-icon',
	'.wav': 'audio/wav',
	'.ogg': 'audio/ogg',
	'.mp3': 'audio/mpeg',
	'.webmanifest': 'application/manifest+json',
	'.pck': 'application/octet-stream',
};

function getActiveLobbies(channelFilter) {
	const active = [];
	for (const [code, r] of rooms) {
		if (r.clients.size < MAX_PLAYERS) {
			if (!channelFilter || !r.channelId || r.channelId === channelFilter) {
				active.push({
					roomCode: code,
					hostName: r.hostName || 'Host',
					avatar: r.avatar || '',
					channelId: r.channelId || '',
				});
			}
		}
	}
	return active;
}

const lobbyWatchers = new Set();

function broadcastLobbies() {
	for (const watcher of lobbyWatchers) {
		if (watcher.ws.readyState !== WebSocket.OPEN) continue;
		try {
			const active = getActiveLobbies(watcher.channel);
			watcher.ws.send(JSON.stringify({ type: 'lobbies', lobbies: active }));
		} catch (e) {}
	}
}

const httpServer = http.createServer((req, res) => {
	if (req.url === '/health') {
		res.writeHead(200, { 'content-type': 'text/plain' });
		res.end('ok');
		return;
	}
	if (req.url.startsWith('/lobbies')) {
		res.writeHead(200, {
			'content-type': 'application/json',
			'access-control-allow-origin': '*',
			'access-control-allow-methods': 'GET, OPTIONS',
			'access-control-allow-headers': '*',
		});
		if (req.method === 'OPTIONS') {
			res.end();
			return;
		}
		const url = new URL(req.url, 'http://localhost');
		const channelFilter = url.searchParams.get('channel') || '';
		res.end(JSON.stringify(getActiveLobbies(channelFilter)));
		return;
	}
	const urlPath = decodeURIComponent((req.url || '/').split('?')[0]);
	const rel = urlPath === '/' ? 'index.html' : urlPath.replace(/^\/+/, '');
	const file = path.normalize(path.join(PUBLIC_DIR, rel));
	if (!file.startsWith(PUBLIC_DIR)) {
		res.writeHead(403);
		res.end('forbidden');
		return;
	}
	fs.readFile(file, (err, data) => {
		if (err) {
			res.writeHead(404);
			res.end('not found');
			return;
		}
		res.writeHead(200, {
			'content-type': MIME[path.extname(file).toLowerCase()] || 'application/octet-stream',
		});
		res.end(data);
	});
});

// ---------------------------------------------------------------- relay ----

const wss = new WebSocketServer({ noServer: true });

function closeEarly(req, socket, code, reason) {
	socket.destroy();
	log(`connection rejected: ${reason}`);
}

httpServer.on('upgrade', (req, socket, head) => {
	const url = new URL(req.url, 'http://localhost');
	const role = url.searchParams.get('role') || 'join';
	const roomCode = (url.searchParams.get('room') || '').toUpperCase();
	const user = url.searchParams.get('user') || 'Host';
	const avatar = url.searchParams.get('avatar') || '';
	const channel = url.searchParams.get('channel') || '';

	if (role === 'lobbies' || role === 'discovery') {
		wss.handleUpgrade(req, socket, head, (ws) => {
			wss.emit('connection', ws, req, { role: 'lobbies', roomCode: '', user, avatar, channel });
		});
		return;
	}

	if (!ROOM_CODE_RE.test(roomCode)) {
		socket.write('HTTP/1.1 400 Bad Request\r\n\r\n');
		socket.destroy();
		return;
	}
	wss.handleUpgrade(req, socket, head, (ws) => {
		wss.emit('connection', ws, req, { role, roomCode, user, avatar, channel });
	});
});

wss.on('connection', (ws, req, { role, roomCode, user, avatar, channel }) => {
	if (role === 'lobbies') {
		const watcher = { ws, channel };
		lobbyWatchers.add(watcher);
		ws.isAlive = true;
		ws.on('pong', () => { ws.isAlive = true; });
		ws.on('close', () => { lobbyWatchers.delete(watcher); });
		ws.send(JSON.stringify({ type: 'lobbies', lobbies: getActiveLobbies(channel) }));
		return;
	}

	let room = rooms.get(roomCode);

	if (role === 'host') {
		if (room) {
			log(`room ${roomCode}: host rejected (room already exists)`);
			ws.close(4001, 'room already exists');
			return;
		}
		room = { clients: new Map(), nextId: 2, hostName: user, avatar, channelId: channel };
		rooms.set(roomCode, room);
		log(`room ${roomCode}: created by host ${user} (channel=${channel})`);
		broadcastLobbies();
	} else {
		if (!room) {
			ws.close(4004, 'room not found');
			return;
		}
		if (room.clients.size >= MAX_PLAYERS) {
			ws.close(4000, 'room full');
			return;
		}
	}

	const peer = { id: room.nextId++ };
	room.clients.set(ws, peer);
	log(`room ${roomCode}: peer ${peer.id} joined (role=${role}, ${room.clients.size} online)`);
	broadcastLobbies();

	ws.send(idFrame(peer.id));

	// Mirror SceneMultiplayer::_admit_peer(): announce the newcomer to everyone
	// already in the room, and tell the newcomer who is already connected.
	for (const [other, otherPeer] of room.clients) {
		if (other === ws) continue;
		other.send(sysFrame(SYS_ADD_PEER, peer.id));
		ws.send(sysFrame(SYS_ADD_PEER, otherPeer.id));
	}

	ws.isAlive = true;
	ws.on('pong', () => {
		ws.isAlive = true;
	});

	if (process.env.RELAY_DEBUG) {
		ws.on('message', (data) => {
			const b = Buffer.isBuffer(data) ? data : Buffer.from(data);
			log(`room ${roomCode} RX peer ${peer.id} (${b.length}B):`, b.subarray(0, 24).toString("hex"));
		});
	}

	ws.on('message', (data, isBinary) => {
		if (isBinary === false) return;
		const buf = Buffer.isBuffer(data) ? data : Buffer.from(data);
		if (buf.length < 2) return;

		const cmd = buf[0] & 0x07; // low 3 bits = NETWORK_COMMAND_*
		if (cmd === NET_CMD_SYS && buf[1] === SYS_RELAY && buf.length >= 6) {
			// Client -> client routing, exactly like SceneMultiplayer's server:
			// [0x07, 4, int32 LE target, payload...] -> re-source and forward.
			const target = buf.readInt32LE(2);
			const payload = buf.subarray(6);
			const frame = relayFrame(peer.id, payload);
			for (const [other, otherPeer] of room.clients) {
				if (other === ws) continue;
				if (target > 0 && otherPeer.id !== target) continue;
				if (target < 0 && otherPeer.id === -target) continue;
				other.send(frame);
			}
		} else if (cmd === NET_CMD_SYS && buf[1] === SYS_AUTH && buf.length === 2) {
			// SYS_COMMAND_AUTH (empty) — complete the auth handshake symmetrically.
			ws.send(Buffer.from([NET_CMD_SYS, SYS_AUTH]));
		} else {
			// Plain frames are addressed to "the server" (peer 1). The relay has no
			// game logic, so they would vanish silently — log them loudly instead.
			log(
				`room ${roomCode}: dropped plain frame to peer 1 from ${peer.id} (${buf.length} B): ` +
					[...buf.subarray(0, Math.min(8, buf.length))].map((b) => b.toString(16).padStart(2, "0")).join(" "),
			);
		}
	});

	ws.on('close', () => {
		const r = rooms.get(roomCode);
		if (!r || !r.clients.delete(ws)) return;
		const leave = sysFrame(SYS_DEL_PEER, peer.id);
		for (const other of r.clients.keys()) {
			other.send(leave);
		}
		log(`room ${roomCode}: peer ${peer.id} left (${r.clients.size} left)`);
		if (r.clients.size === 0) {
			rooms.delete(roomCode);
			log(`room ${roomCode}: deleted (empty)`);
		}
		broadcastLobbies();
	});

	ws.on('error', (err) => log(`room ${roomCode}: peer ${peer.id} error: ${err.message}`));
});

// Ping/pong to reap dead connections (proxies drop idle sockets).
const heartbeat = setInterval(() => {
	for (const [roomCode, room] of rooms) {
		for (const [ws, peer] of room.clients) {
			if (ws.isAlive === false) {
				log(`room ${roomCode}: peer ${peer.id} timed out`);
				ws.terminate();
				continue;
			}
			ws.isAlive = false;
			ws.ping();
		}
	}
	for (const watcher of lobbyWatchers) {
		if (watcher.ws.isAlive === false) {
			watcher.ws.terminate();
			lobbyWatchers.delete(watcher);
			continue;
		}
		watcher.ws.isAlive = false;
		watcher.ws.ping();
	}
}, 30000);

wss.on('close', () => clearInterval(heartbeat));

httpServer.listen(PORT, () => {
	log(`Zapness relay listening on :${PORT}`);
	log('  static: ./public   ws: /ws?role=host|join&room=<CODE>');
});

// Optional keep-alive for free tiers that sleep after idle (e.g. Render free
// plan spins down after 15 min without inbound traffic; cold start ~1 min).
// Set KEEP_ALIVE_URL to this service's own public URL (e.g.
// KEEP_ALIVE_URL=https://zapness-relay.onrender.com/health) to have it ping
// itself every 10 minutes and stay awake. Empty/disabled by default.
const KEEP_ALIVE_URL = process.env.KEEP_ALIVE_URL || '';
const KEEP_ALIVE_INTERVAL_MS = 10 * 60 * 1000;
if (KEEP_ALIVE_URL) {
	log(`keep-alive enabled -> ${KEEP_ALIVE_URL}`);
	setInterval(() => {
		fetch(KEEP_ALIVE_URL).catch(() => {});
	}, 10 * 60 * 1000);
}
