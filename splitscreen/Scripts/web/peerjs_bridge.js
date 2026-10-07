/**
 * PeerJS Bridge for Godot
 * This file provides a bridge between PeerJS and Godot's JavaScriptBridge.
 * It must be loaded after the PeerJS library.
 */

// Global state
window.GodotPeerJS = {
    peer: null,
    connections: {},
    myPeerId: null,
    isHost: false,

    // Callbacks that Godot will set
    onPeerOpen: null,
    onPeerConnected: null,
    onDataReceived: null,
    onPeerDisconnected: null,
    onError: null,

    /**
     * Initialize a new PeerJS connection
     * @param {string} customId - Optional custom peer ID
     * @returns {boolean} Success status
     */
    initialize: function (customId) {
        try {
            // Clean up existing peer if any
            if (this.peer) {
                this.peer.destroy();
            }

            // Create new peer with optional custom ID
            const peerOptions = {
                debug: 2, // Show warnings and errors
                config: {
                    iceServers: [
                        { urls: 'stun:stun.l.google.com:19302' },
                        { urls: 'stun:stun1.l.google.com:19302' }
                    ]
                }
            };

            if (customId && customId.length > 0) {
                this.peer = new Peer(customId, peerOptions);
            } else {
                this.peer = new Peer(peerOptions);
            }

            // Set up event handlers
            this.peer.on('open', (id) => {
                console.log('[PeerJS] Peer opened with ID:', id);
                this.myPeerId = id;
                if (this.onPeerOpen) {
                    this.onPeerOpen(id);
                }
            });

            this.peer.on('connection', (conn) => {
                console.log('[PeerJS] Incoming connection from:', conn.peer);
                this._setupConnection(conn);
            });

            this.peer.on('error', (err) => {
                console.error('[PeerJS] Error:', err.type, err.message);
                if (this.onError) {
                    this.onError(err.type + ': ' + err.message);
                }
            });

            this.peer.on('disconnected', () => {
                console.log('[PeerJS] Disconnected from signaling server');
                // Try to reconnect
                if (this.peer && !this.peer.destroyed) {
                    this.peer.reconnect();
                }
            });

            return true;
        } catch (e) {
            console.error('[PeerJS] Initialize error:', e);
            if (this.onError) {
                this.onError('Initialize failed: ' + e.message);
            }
            return false;
        }
    },

    /**
     * Connect to another peer
     * @param {string} peerId - The peer ID to connect to
     * @returns {boolean} Success status
     */
    connectToPeer: function (peerId) {
        try {
            if (!this.peer || this.peer.destroyed) {
                console.error('[PeerJS] Peer not initialized');
                return false;
            }

            console.log('[PeerJS] Connecting to peer:', peerId);
            const conn = this.peer.connect(peerId, {
                reliable: true,
                serialization: 'json'
            });

            this._setupConnection(conn);
            return true;
        } catch (e) {
            console.error('[PeerJS] Connect error:', e);
            if (this.onError) {
                this.onError('Connect failed: ' + e.message);
            }
            return false;
        }
    },

    /**
     * Set up connection event handlers
     * @param {DataConnection} conn - PeerJS DataConnection object
     */
    _setupConnection: function (conn) {
        this.connections[conn.peer] = conn;

        conn.on('open', () => {
            console.log('[PeerJS] Connection opened with:', conn.peer);
            if (this.onPeerConnected) {
                this.onPeerConnected(conn.peer);
            }
        });

        conn.on('data', (data) => {
            console.log('[PeerJS] Data received from', conn.peer, ':', data);
            if (this.onDataReceived) {
                // Convert to JSON string for Godot
                const jsonData = typeof data === 'string' ? data : JSON.stringify(data);
                this.onDataReceived(conn.peer, jsonData);
            }
        });

        conn.on('close', () => {
            console.log('[PeerJS] Connection closed with:', conn.peer);
            delete this.connections[conn.peer];
            if (this.onPeerDisconnected) {
                this.onPeerDisconnected(conn.peer);
            }
        });

        conn.on('error', (err) => {
            console.error('[PeerJS] Connection error with', conn.peer, ':', err);
            if (this.onError) {
                this.onError('Connection error: ' + err.message);
            }
        });
    },

    /**
     * Send data to a specific peer
     * @param {string} peerId - Target peer ID
     * @param {string} data - JSON string data to send
     * @returns {boolean} Success status
     */
    sendToPeer: function (peerId, data) {
        try {
            const conn = this.connections[peerId];
            if (!conn || !conn.open) {
                console.error('[PeerJS] No open connection to peer:', peerId);
                return false;
            }

            // Parse JSON string back to object for PeerJS
            const parsedData = JSON.parse(data);
            conn.send(parsedData);
            return true;
        } catch (e) {
            console.error('[PeerJS] Send error:', e);
            return false;
        }
    },

    /**
     * Send data to all connected peers
     * @param {string} data - JSON string data to send
     * @returns {number} Number of peers data was sent to
     */
    broadcast: function (data) {
        let count = 0;
        for (const peerId in this.connections) {
            if (this.sendToPeer(peerId, data)) {
                count++;
            }
        }
        return count;
    },

    /**
     * Get the local peer ID
     * @returns {string} Local peer ID or empty string
     */
    getMyPeerId: function () {
        return this.myPeerId || '';
    },

    /**
     * Get list of connected peer IDs
     * @returns {string} JSON array of peer IDs
     */
    getConnectedPeers: function () {
        return JSON.stringify(Object.keys(this.connections));
    },

    /**
     * Check if connected to a specific peer
     * @param {string} peerId - Peer ID to check
     * @returns {boolean} Connection status
     */
    isConnectedTo: function (peerId) {
        const conn = this.connections[peerId];
        return conn && conn.open;
    },

    /**
     * Disconnect from a specific peer
     * @param {string} peerId - Peer ID to disconnect from
     */
    disconnectFrom: function (peerId) {
        const conn = this.connections[peerId];
        if (conn) {
            conn.close();
            delete this.connections[peerId];
        }
    },

    /**
     * Disconnect from all peers and destroy the peer object
     */
    disconnect: function () {
        // Close all connections
        for (const peerId in this.connections) {
            this.connections[peerId].close();
        }
        this.connections = {};

        // Destroy peer
        if (this.peer) {
            this.peer.destroy();
            this.peer = null;
        }

        this.myPeerId = null;
        this.isHost = false;
        console.log('[PeerJS] Disconnected and cleaned up');
    },

    /**
     * Check if PeerJS is initialized and connected to signaling server
     * @returns {boolean} Ready status
     */
    isReady: function () {
        return this.peer && !this.peer.destroyed && this.myPeerId !== null;
    }
};

console.log('[PeerJS] Bridge loaded successfully');
