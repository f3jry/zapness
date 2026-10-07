/**
 * Standalone WebRTC Relay Bridge for Zapness Godot Game
 * Uses PythonAnywhere SQLite REST relay for signaling (no third-party PeerJS dependencies)
 */

window.GodotWebRTC = {
    pc: null,
    dc: null,
    role: null,
    code: null,
    onCodeReady: null,
    onConnected: null,
    onData: null,
    onError: null,

    config: {
        iceServers: [
            { urls: "stun:stun.l.google.com:19302" },
            { urls: "stun:stun1.l.google.com:19302" },
            { urls: "stun:stun2.l.google.com:19302" },
            { urls: "stun:stun3.l.google.com:19302" },
            { urls: "stun:stun4.l.google.com:19302" },
            { urls: "stun:stun.cloudflare.com:3478" }
        ],
        iceCandidatePoolSize: 10
    },

    _waitForIce: function (pc) {
        return new Promise(function (resolve) {
            if (pc.iceGatheringState === "complete") {
                return resolve();
            }
            var onCandidate = function (e) {
                if (!e.candidate || e.candidate.type === "srflx" || pc.iceGatheringState === "complete") {
                    // ICE gathering progressing
                }
            };
            var onStateChange = function () {
                if (pc.iceGatheringState === "complete") {
                    cleanup();
                    resolve();
                }
            };
            var timer = setTimeout(function () {
                cleanup();
                resolve();
            }, 1800);

            var cleanup = function () {
                clearTimeout(timer);
                pc.removeEventListener("icecandidate", onCandidate);
                pc.removeEventListener("icegatheringstatechange", onStateChange);
            };

            pc.addEventListener("icecandidate", onCandidate);
            pc.addEventListener("icegatheringstatechange", onStateChange);
        });
    },

    hostRoom: async function () {
        try {
            this.disconnect();
            this.role = "host";
            this.pc = new RTCPeerConnection(this.config);
            this.dc = this.pc.createDataChannel("game", { ordered: true });
            this._setupDataChannel(this.dc);

            var offer = await this.pc.createOffer();
            await this.pc.setLocalDescription(offer);

            // Wait for ICE candidate gathering
            await this._waitForIce(this.pc);

            var finalSdp = (this.pc.localDescription.sdp || offer.sdp)
                .replace(/\r\n/g, "\n").replace(/\n/g, "\r\n").trim() + "\r\n";

            var resp = await fetch("https://ironinblood.pythonanywhere.com/zap/webrtc/host", {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({ offer: finalSdp, candidates: [] })
            });
            var data = await resp.json();
            if (!resp.ok) {
                var errMessage = (data && data.error) ? data.error : "Failed to register room on relay server";
                throw new Error(errMessage);
            }
            this.code = data.code;
            console.log("[WebRTC] Host registered code:", this.code);
            if (this.onCodeReady) this.onCodeReady(this.code);

            this._pollForAnswer();
            return this.code;
        } catch (e) {
            console.error("[WebRTC] Host error:", e);
            if (this.onError) this.onError(e.message || "Failed to host room");
        }
    },

    _pollForAnswer: function () {
        var attempts = 0;
        var maxAttempts = 120; // 60 seconds
        var self = this;
        var iv = setInterval(async function () {
            if (!self.pc || self.pc.signalingState === "closed" || self.pc.signalingState === "stable") {
                clearInterval(iv);
                return;
            }
            attempts++;
            if (attempts > maxAttempts) {
                clearInterval(iv);
                console.warn("[WebRTC] Host poll timed out waiting for client");
                return;
            }
            try {
                var resp = await fetch("https://ironinblood.pythonanywhere.com/zap/webrtc/poll/" + self.code);
                if (resp.status === 200) {
                    var data = await resp.json();
                    if (data.answer && self.pc && self.pc.signalingState === "have-local-offer") {
                        clearInterval(iv);
                        console.log("[WebRTC] Host received client answer!");
                        var sdpStr = data.answer.replace(/\r\n/g, "\n").replace(/\n/g, "\r\n").trim() + "\r\n";
                        await self.pc.setRemoteDescription(new RTCSessionDescription({ type: "answer", sdp: sdpStr }));
                    }
                }
            } catch (e) {
                // Ignore poll collision when already connected
            }
        }, 500);
    },

    joinRoom: async function (code) {
        try {
            this.disconnect();
            this.role = "client";
            this.code = String(code || "").toUpperCase().trim();
            if (!this.code || this.code.length < 3) {
                throw new Error("Please enter a valid 4-letter room code");
            }
            this.pc = new RTCPeerConnection(this.config);
            var self = this;
            this.pc.ondatachannel = function (e) {
                console.log("[WebRTC] Client got DataChannel from Host!");
                self.dc = e.channel;
                self._setupDataChannel(self.dc);
            };

            var resp = await fetch("https://ironinblood.pythonanywhere.com/zap/webrtc/join/" + this.code);
            var data = await resp.json();
            if (!resp.ok) {
                var errMessage = (data && data.error) ? data.error : "Room code not found or expired";
                throw new Error(errMessage);
            }
            if (!data || !data.offer) {
                throw new Error("Invalid room session data");
            }
            console.log("[WebRTC] Client retrieved host offer for:", this.code);

            var offerSdp = data.offer.replace(/\r\n/g, "\n").replace(/\n/g, "\r\n").trim() + "\r\n";
            await this.pc.setRemoteDescription(new RTCSessionDescription({ type: "offer", sdp: offerSdp }));
            var answer = await this.pc.createAnswer();
            await this.pc.setLocalDescription(answer);

            // Wait for ICE candidate gathering
            await this._waitForIce(this.pc);

            var finalAnswerSdp = (this.pc.localDescription.sdp || answer.sdp)
                .replace(/\r\n/g, "\n").replace(/\n/g, "\r\n").trim() + "\r\n";

            await fetch("https://ironinblood.pythonanywhere.com/zap/webrtc/answer/" + this.code, {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({ answer: finalAnswerSdp, candidates: [] })
            });
            console.log("[WebRTC] Client posted answer to relay!");
        } catch (e) {
            console.error("[WebRTC] Join error:", e);
            if (this.onError) this.onError(e.message || "Failed to join room");
        }
    },

    _setupDataChannel: function (dc) {
        var self = this;
        dc.onopen = function () {
            console.log("[WebRTC] Direct DataChannel OPENED for role:", self.role);
            if (self.onConnected) self.onConnected(self.role);
        };
        dc.onmessage = function (e) {
            if (self.onData) self.onData(e.data);
        };
        dc.onclose = function () {
            console.log("[WebRTC] DataChannel closed");
        };
        dc.onerror = function (err) {
            console.error("[WebRTC] DataChannel error:", err);
            if (self.onError) self.onError("DataChannel connection error");
        };
    },

    sendData: function (data) {
        if (this.dc && this.dc.readyState === "open") {
            var str = typeof data === "string" ? data : JSON.stringify(data);
            this.dc.send(str);
            return true;
        }
        return false;
    },

    disconnect: function () {
        if (this.dc) { try { this.dc.close(); } catch (e) {} this.dc = null; }
        if (this.pc) { try { this.pc.close(); } catch (e) {} this.pc = null; }
        this.role = null;
        this.code = null;
    }
};

console.log("[WebRTC] Standalone bridge ready");
