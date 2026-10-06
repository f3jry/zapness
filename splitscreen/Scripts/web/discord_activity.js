/**
 * @file discord_activity.js
 * @description JavaScript shim bridging Discord Embedded App SDK into Godot 4 web export.
 * Also provides call-wide lobby discovery via lightweight ntfy.sh pub/sub.
 *
 * Exposes window.GodotDiscord
 */

(function () {
  'use strict';

  var _originalConsoleLog = console.log.bind(console);
  console.log = function () {
    var args = Array.prototype.slice.call(arguments);
    args.unshift('[Discord]');
    _originalConsoleLog.apply(console, args);
  };

  var urlParams = new URLSearchParams(window.location.search);
  var initialChannelId = urlParams.get('channel_id') || '';
  var initialInstanceId = urlParams.get('instance_id') || '';
  var initialGuildId = urlParams.get('guild_id') || '';

  function isRunningInDiscord() {
    var hostname = window.location.hostname || '';
    return hostname.indexOf('discordsays.com') !== -1 ||
           hostname.indexOf('discord.com') !== -1 ||
           initialChannelId.length > 0;
  }

  // Active lobbies cache discovered in this channel
  var _activeLobbies = [];
  var _activeLobbiesJson = '[]';
  var _isHostingAnnouncement = false;
  var _hostAnnouncementTimer = null;
  var _hostInfo = null;

  function getDefaultAvatarUrl(name) {
    var hash = 0;
    var str = name || 'player';
    for (var i = 0; i < str.length; i++) {
      hash = (hash * 31 + str.charCodeAt(i)) >>> 0;
    }
    return 'https://cdn.discordapp.com/embed/avatars/' + (hash % 6) + '.png';
  }

  var GodotDiscord = {
    sdk: null,
    ready: initialChannelId.length > 0,
    currentUser: null,
    channelId: initialChannelId,
    guildId: initialGuildId,
    instanceId: initialInstanceId,
    onReady: null,
    onError: null,

    init: async function (clientId) {
      try {
        if (!isRunningInDiscord()) {
          console.log('Not running inside Discord. Skipping SDK init.');
          GodotDiscord.ready = true;
          if (typeof GodotDiscord.onReady === 'function') {
            GodotDiscord.onReady();
          }
          return;
        }

        console.log('Discord Activity detected. Channel:', GodotDiscord.channelId || initialChannelId);

        var SDKClass = null;
        if (typeof window.DiscordSDK === 'function') {
          SDKClass = window.DiscordSDK;
        } else if (window.DiscordModule && typeof window.DiscordModule.DiscordSDK === 'function') {
          SDKClass = window.DiscordModule.DiscordSDK;
        }

        if (SDKClass) {
          try {
            GodotDiscord.sdk = new SDKClass(clientId);
            await GodotDiscord.sdk.ready();
            GodotDiscord.channelId  = GodotDiscord.sdk.channelId  || GodotDiscord.channelId  || initialChannelId;
            GodotDiscord.instanceId = GodotDiscord.sdk.instanceId || GodotDiscord.instanceId || initialInstanceId;
            GodotDiscord.guildId    = GodotDiscord.sdk.guildId    || GodotDiscord.guildId    || initialGuildId;
            console.log('DiscordSDK handshake complete. Channel:', GodotDiscord.channelId);

            // Fetch connected participants if available
            if (GodotDiscord.sdk.commands && typeof GodotDiscord.sdk.commands.getInstanceConnectedParticipants === 'function') {
              try {
                var pData = await GodotDiscord.sdk.commands.getInstanceConnectedParticipants();
                if (pData && pData.participants && pData.participants.length > 0) {
                  var p = pData.participants[0];
                  var avatarUrl = '';
                  if (p.avatar) {
                    avatarUrl = 'https://cdn.discordapp.com/avatars/' + p.id + '/' + p.avatar + '.png?size=128';
                  } else {
                    avatarUrl = getDefaultAvatarUrl(p.username || 'player');
                  }
                  GodotDiscord.currentUser = {
                    id: p.id,
                    username: p.global_name || p.username || 'Player',
                    avatar: avatarUrl
                  };
                  console.log('Identified participant:', GodotDiscord.currentUser.username);
                }
              } catch (pErr) {
                console.log('getInstanceConnectedParticipants info:', pErr && pErr.message ? pErr.message : pErr);
              }
            }
          } catch (sdkErr) {
            console.log('DiscordSDK init non-fatal:', sdkErr && sdkErr.message ? sdkErr.message : sdkErr);
          }
        }

        // Fallback user if not populated
        if (!GodotDiscord.currentUser) {
          var randNum = Math.floor(1000 + Math.random() * 9000);
          var uname = 'Player' + randNum;
          GodotDiscord.currentUser = {
            id: 'local_' + randNum,
            username: uname,
            avatar: getDefaultAvatarUrl(uname)
          };
        }

        GodotDiscord.ready = true;
        if (typeof GodotDiscord.onReady === 'function') {
          GodotDiscord.onReady();
        }
      } catch (err) {
        var message = err && err.message ? err.message : String(err);
        console.error('[GodotDiscord] init error:', message);
        GodotDiscord.ready = true;
        if (typeof GodotDiscord.onReady === 'function') {
          GodotDiscord.onReady();
        }
      }
    },

    getUser: function () {
      if (GodotDiscord.currentUser) {
        try {
          return JSON.stringify(GodotDiscord.currentUser);
        } catch (e) {
          return '{}';
        }
      }
      return '{}';
    },

    getChannelId: function () {
      return GodotDiscord.channelId || '';
    },

    getGuildId: function () {
      return GodotDiscord.guildId || '';
    },

    isReady: function () {
      return GodotDiscord.ready;
    },

    isRunningInDiscord: function () {
      return isRunningInDiscord();
    },

    patchUrlMappings: function () {
      var patchFn = null;
      if (GodotDiscord.sdk && typeof GodotDiscord.sdk.patchUrlMappings === 'function') {
        patchFn = GodotDiscord.sdk.patchUrlMappings.bind(GodotDiscord.sdk);
      } else if (window.DiscordModule && typeof window.DiscordModule.patchUrlMappings === 'function') {
        patchFn = window.DiscordModule.patchUrlMappings;
      }

      if (!patchFn) {
        console.log('patchUrlMappings: not available. Skipping.');
        return;
      }
      try {
        patchFn([{ prefix: '/peer', target: '0.peerjs.com' }]);
        console.log('URL mappings patched for PeerJS proxy (/peer -> 0.peerjs.com).');
      } catch (err) {
        console.error('[GodotDiscord] patchUrlMappings error:', err);
      }
    },

    // -------------------------------------------------------------------------
    // Call-wide Lobby Discovery (via public ntfy.sh topic keyed to channel_id)
    // -------------------------------------------------------------------------
    getChannelTopic: function () {
      var cid = GodotDiscord.channelId || initialChannelId || 'global';
      return 'zapness-lobby-' + cid;
    },

    startHostingAnnouncement: function (hostPeerId, username, avatarUrl) {
      _isHostingAnnouncement = true;
      var uname = username || (GodotDiscord.currentUser ? GodotDiscord.currentUser.username : 'Host');
      var av = avatarUrl || (GodotDiscord.currentUser ? GodotDiscord.currentUser.avatar : getDefaultAvatarUrl(uname));
      _hostInfo = {
        action: 'host',
        host_peer_id: hostPeerId,
        username: uname,
        avatar: av
      };

      var publish = function () {
        if (!_isHostingAnnouncement || !_hostInfo) return;
        var topic = GodotDiscord.getChannelTopic();
        var payload = Object.assign({}, _hostInfo, { timestamp: Date.now() });
        fetch('https://ntfy.sh/' + encodeURIComponent(topic), {
          method: 'POST',
          body: JSON.stringify(payload),
          headers: { 'Content-Type': 'application/json' }
        }).catch(function (e) {
          console.log('[Lobby] Publish heartbeat failed:', e && e.message ? e.message : e);
        });
      };

      publish();
      if (_hostAnnouncementTimer) clearInterval(_hostAnnouncementTimer);
      _hostAnnouncementTimer = setInterval(publish, 5000);
    },

    stopHostingAnnouncement: function () {
      _isHostingAnnouncement = false;
      if (_hostAnnouncementTimer) {
        clearInterval(_hostAnnouncementTimer);
        _hostAnnouncementTimer = null;
      }
      if (_hostInfo) {
        var topic = GodotDiscord.getChannelTopic();
        var payload = Object.assign({}, _hostInfo, { action: 'closed', timestamp: Date.now() });
        fetch('https://ntfy.sh/' + encodeURIComponent(topic), {
          method: 'POST',
          body: JSON.stringify(payload),
          headers: { 'Content-Type': 'application/json' }
        }).catch(function () {});
        _hostInfo = null;
      }
    },

    fetchLobbies: async function () {
      var topic = GodotDiscord.getChannelTopic();
      try {
        var res = await fetch('https://ntfy.sh/' + encodeURIComponent(topic) + '/json?poll=1&since=20s');
        if (!res.ok) {
          _activeLobbies = [];
          _activeLobbiesJson = '[]';
          return '[]';
        }
        var text = await res.text();
        var lines = text.trim().split('\n');
        var lobbiesMap = {};
        var now = Date.now();

        for (var i = 0; i < lines.length; i++) {
          if (!lines[i]) continue;
          try {
            var event = JSON.parse(lines[i]);
            if (event.event === 'message' && event.message) {
              var data = JSON.parse(event.message);
              if (data && data.host_peer_id) {
                if (data.action === 'closed') {
                  delete lobbiesMap[data.host_peer_id];
                } else if (data.timestamp && (now - data.timestamp) < 25000) {
                  // If we are the host of this lobby, don't show it to ourselves
                  if (_isHostingAnnouncement && _hostInfo && _hostInfo.host_peer_id === data.host_peer_id) {
                    continue;
                  }
                  lobbiesMap[data.host_peer_id] = {
                    host_peer_id: data.host_peer_id,
                    username: data.username || 'Host',
                    avatar: data.avatar || getDefaultAvatarUrl(data.username),
                    timestamp: data.timestamp
                  };
                }
              }
            }
          } catch (lineErr) {}
        }

        var list = [];
        for (var k in lobbiesMap) {
          list.push(lobbiesMap[k]);
        }
        _activeLobbies = list;
        _activeLobbiesJson = JSON.stringify(list);
        return _activeLobbiesJson;
      } catch (e) {
        return _activeLobbiesJson;
      }
    },

    getActiveLobbiesJson: function () {
      return _activeLobbiesJson;
    }
  };

  window.GodotDiscord = GodotDiscord;
  console.log('GodotDiscord shim loaded with lobby discovery support.');
})();
