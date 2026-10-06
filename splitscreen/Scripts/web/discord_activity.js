/**
 * @file discord_activity.js
 * @description JavaScript shim that bridges a Godot 4 web export (nothreads WASM build)
 * running as a Discord Activity inside Discord's iframe.
 *
 * Loaded via a plain <script> tag in Godot's HTML export template.
 * Uses UMD-compatible code — no ES module syntax.
 *
 * Exposes a single global: window.GodotDiscord
 * GDScript communicates with it through JavaScriptBridge.
 */

(function () {
  'use strict';

  // ---------------------------------------------------------------------------
  // Patch console.log to prefix SDK-related output for easier debugging
  // ---------------------------------------------------------------------------
  var _originalConsoleLog = console.log.bind(console);
  console.log = function () {
    var args = Array.prototype.slice.call(arguments);
    args.unshift('[Discord]');
    _originalConsoleLog.apply(console, args);
  };

  // ---------------------------------------------------------------------------
  // Load the Discord Embedded App SDK from CDN (UMD build)
  // ---------------------------------------------------------------------------
  var SDK_CDN_URL =
    'https://unpkg.com/@discord/embedded-app-sdk@1.5.0/output/discord-embedded-app-sdk.umd.js';

  /**
   * Dynamically injects the Discord SDK <script> tag and resolves when loaded.
   * @returns {Promise<void>}
   */
  function loadSDKScript() {
    return new Promise(function (resolve, reject) {
      if (typeof DiscordSDK !== 'undefined') {
        // Already loaded (e.g. injected by the Discord client itself)
        resolve();
        return;
      }
      var script = document.createElement('script');
      script.src = SDK_CDN_URL;
      script.onload = function () {
        console.log('Discord Embedded App SDK script loaded.');
        resolve();
      };
      script.onerror = function (err) {
        reject(new Error('Failed to load Discord Embedded App SDK from CDN: ' + SDK_CDN_URL));
      };
      document.head.appendChild(script);
    });
  }

  // ---------------------------------------------------------------------------
  // Parse URL parameters immediately upon script evaluation
  // ---------------------------------------------------------------------------
  var urlParams = new URLSearchParams(window.location.search);
  var initialChannelId = urlParams.get('channel_id') || '';
  var initialInstanceId = urlParams.get('instance_id') || '';
  var initialGuildId = urlParams.get('guild_id') || '';

  // ---------------------------------------------------------------------------
  // Detect whether the page is actually running inside Discord
  // ---------------------------------------------------------------------------
  /**
   * Returns true if the page appears to be hosted inside Discord's iframe
   * (i.e., hostname contains "discordsays.com" or "discord.com", or channel_id is present).
   * @returns {boolean}
   */
  function isRunningInDiscord() {
    var hostname = window.location.hostname || '';
    return hostname.indexOf('discordsays.com') !== -1 ||
           hostname.indexOf('discord.com') !== -1 ||
           initialChannelId.length > 0;
  }

  // ---------------------------------------------------------------------------
  // GodotDiscord namespace
  // ---------------------------------------------------------------------------
  var GodotDiscord = {
    /** @type {DiscordSDK|null} The DiscordSDK instance, set after init(). */
    sdk: null,

    /** @type {boolean} True once initialized or channelId is known. */
    ready: initialChannelId.length > 0,

    /** @type {Object|null} The authenticated Discord user object. */
    currentUser: null,

    /** @type {string} The Discord channel ID for this activity instance. */
    channelId: initialChannelId,

    /** @type {string} The Discord guild (server) ID, if applicable. */
    guildId: initialGuildId,

    /** @type {string} The Discord activity instance ID. */
    instanceId: initialInstanceId,

    /**
     * Callback invoked (by GDScript via JavaScriptBridge) when the SDK is ready.
     * Set this before calling init().
     * @type {Function|null}
     */
    onReady: null,

    /**
     * Callback invoked (by GDScript via JavaScriptBridge) on any SDK error.
     * Receives a single string message argument.
     * @type {Function|null}
     */
    onError: null,

    // -------------------------------------------------------------------------
    // init
    // -------------------------------------------------------------------------
    /**
     * Initialises the Discord Embedded App SDK.
     * @param {string} clientId - Your Discord application client ID.
     * @returns {Promise<void>}
     */
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

        try {
          await loadSDKScript();
          if (typeof window.DiscordSDK === 'function') {
            GodotDiscord.sdk = new window.DiscordSDK(clientId);
            await GodotDiscord.sdk.ready();
            GodotDiscord.channelId  = GodotDiscord.sdk.channelId  || GodotDiscord.channelId  || initialChannelId;
            GodotDiscord.instanceId = GodotDiscord.sdk.instanceId || GodotDiscord.instanceId || initialInstanceId;
            GodotDiscord.guildId    = GodotDiscord.sdk.guildId    || GodotDiscord.guildId    || initialGuildId;
            console.log('DiscordSDK handshake complete. Channel:', GodotDiscord.channelId);
          }
        } catch (sdkErr) {
          console.log('DiscordSDK init non-fatal:', sdkErr && sdkErr.message ? sdkErr.message : sdkErr);
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


    // -------------------------------------------------------------------------
    // getUser
    // -------------------------------------------------------------------------
    /**
     * Returns the current Discord user as a JSON string.
     * Returns '{}' if no user is available yet.
     * @returns {string}
     */
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

    // -------------------------------------------------------------------------
    // getChannelId
    // -------------------------------------------------------------------------
    /**
     * Returns the Discord channel ID string for this activity instance.
     * Returns '' if not yet available.
     * @returns {string}
     */
    getChannelId: function () {
      return GodotDiscord.channelId || '';
    },

    // -------------------------------------------------------------------------
    // getGuildId
    // -------------------------------------------------------------------------
    /**
     * Returns the Discord guild (server) ID string for this activity instance.
     * Returns '' if not applicable (e.g. DM channel) or not yet available.
     * @returns {string}
     */
    getGuildId: function () {
      return GodotDiscord.guildId || '';
    },

    // -------------------------------------------------------------------------
    // isReady
    // -------------------------------------------------------------------------
    /**
     * Returns true once the SDK (or the local fallback) has finished initialising.
     * Poll this from GDScript before calling other methods.
     * @returns {boolean}
     */
    isReady: function () {
      return GodotDiscord.ready;
    },

    /**
     * Check if currently executing inside a Discord Activity iframe.
     * @returns {boolean}
     */
    isRunningInDiscord: function () {
      return isRunningInDiscord();
    },

    // -------------------------------------------------------------------------
    // patchUrlMappings
    // -------------------------------------------------------------------------
    /**
     * Patches Discord's URL proxy mappings so that PeerJS traffic is correctly
     * routed through Discord's /.proxy/peer endpoint.
     *
     * Call this after init() has resolved (i.e., after onReady fires).
     *
     * @returns {void}
     */
    patchUrlMappings: function () {
      if (!GodotDiscord.sdk) {
        console.log(
          'patchUrlMappings: SDK not initialised (likely running outside Discord). Skipping.'
        );
        return;
      }
      try {
        GodotDiscord.sdk.patchUrlMappings([
          { prefix: '/peer', target: '0.peerjs.com' },
        ]);
        console.log('URL mappings patched for PeerJS proxy (/peer -> 0.peerjs.com).');
      } catch (err) {
        var message = err && err.message ? err.message : String(err);
        console.error('[GodotDiscord] patchUrlMappings error:', message);
        if (typeof GodotDiscord.onError === 'function') {
          GodotDiscord.onError(message);
        }
      }
    },
  };

  // ---------------------------------------------------------------------------
  // Expose the namespace globally so GDScript can reach it via JavaScriptBridge
  // ---------------------------------------------------------------------------
  window.GodotDiscord = GodotDiscord;

  console.log('GodotDiscord shim loaded. Call GodotDiscord.init(clientId) to begin.');
})();
