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
  // Detect whether the page is actually running inside Discord
  // ---------------------------------------------------------------------------
  /**
   * Returns true if the page appears to be hosted inside Discord's iframe
   * (i.e., the hostname contains "discordsays.com" or "discord.com").
   * @returns {boolean}
   */
  function isRunningInDiscord() {
    var hostname = window.location.hostname || '';
    return hostname.indexOf('discordsays.com') !== -1 ||
           hostname.indexOf('discord.com') !== -1;
  }

  // ---------------------------------------------------------------------------
  // GodotDiscord namespace
  // ---------------------------------------------------------------------------
  var GodotDiscord = {
    /** @type {DiscordSDK|null} The DiscordSDK instance, set after init(). */
    sdk: null,

    /** @type {boolean} True once the SDK has completed initialization. */
    ready: false,

    /** @type {Object|null} The authenticated Discord user object. */
    currentUser: null,

    /** @type {string|null} The Discord channel ID for this activity instance. */
    channelId: null,

    /** @type {string|null} The Discord guild (server) ID, if applicable. */
    guildId: null,

    /** @type {string|null} The Discord activity instance ID. */
    instanceId: null,

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
     *
     * Steps:
     *  1. Load the SDK script from CDN.
     *  2. If NOT running inside Discord, skip SDK setup and mark ready.
     *  3. Create DiscordSDK instance and await sdk.ready().
     *  4. Authorise with the 'identify' scope.
     *  5. Exchange the authorization code for an access token via /api/token.
     *  6. Authenticate the SDK with the token.
     *  7. Fetch the current user via REST.
     *  8. Populate channelId, guildId, instanceId.
     *  9. Fire onReady callback.
     *
     * @param {string} clientId - Your Discord application client ID.
     * @returns {Promise<void>}
     */
    init: async function (clientId) {
      try {
        // Step 1 — load the SDK script
        await loadSDKScript();

        // Step 2 — bail out gracefully when running outside Discord
        if (!isRunningInDiscord()) {
          console.log(
            'Not running inside Discord (hostname: ' +
              window.location.hostname +
              '). Skipping SDK init.'
          );
          GodotDiscord.ready = true;
          if (typeof GodotDiscord.onReady === 'function') {
            GodotDiscord.onReady();
          }
          return;
        }

        // Step 3 — create SDK instance and wait for the Discord client handshake
        // The UMD build exposes DiscordSDK on window after the script loads.
        GodotDiscord.sdk = new window.DiscordSDK(clientId);
        console.log('DiscordSDK instance created for client:', clientId);

        await GodotDiscord.sdk.ready();
        console.log('DiscordSDK handshake complete.');

        // Capture instance-level identifiers provided by the SDK
        GodotDiscord.instanceId = GodotDiscord.sdk.instanceId || null;
        GodotDiscord.channelId  = GodotDiscord.sdk.channelId  || null;
        GodotDiscord.guildId    = GodotDiscord.sdk.guildId    || null;

        // Step 4-7 — optional OAuth2 flow (if a token exchange backend is deployed)
        try {
          var authorizeResult = await GodotDiscord.sdk.commands.authorize({
            client_id: clientId,
            response_type: 'code',
            state: '',
            prompt: 'none',
            scope: ['identify'],
          });

          var code = authorizeResult.code;
          console.log('Authorisation code received.');

          var tokenResponse = await fetch('/api/token', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ code: code }),
          });

          if (tokenResponse.ok) {
            var tokenData = await tokenResponse.json();
            var accessToken = tokenData.access_token;
            if (accessToken) {
              var authResult = await GodotDiscord.sdk.commands.authenticate({
                access_token: accessToken,
              });
              var userResponse = await fetch('https://discord.com/api/users/@me', {
                headers: { Authorization: 'Bearer ' + accessToken },
              });
              if (userResponse.ok) {
                GodotDiscord.currentUser = await userResponse.json();
                console.log('Fetched current user:', GodotDiscord.currentUser.username);
              } else {
                GodotDiscord.currentUser = authResult.user || null;
              }
            }
          } else {
            console.log('No /api/token backend found (static host) — running Activity without user token.');
          }
        } catch (authErr) {
          console.log('OAuth2 skipped or non-fatal error (static hosting):', authErr.message || authErr);
        }

        // Step 8 — update channelId / guildId in case they weren't set earlier
        GodotDiscord.channelId  = GodotDiscord.sdk.channelId  || GodotDiscord.channelId;
        GodotDiscord.guildId    = GodotDiscord.sdk.guildId    || GodotDiscord.guildId;
        GodotDiscord.instanceId = GodotDiscord.sdk.instanceId || GodotDiscord.instanceId;

        // Step 9 — mark ready and notify GDScript
        GodotDiscord.ready = true;
        console.log('GodotDiscord ready. Channel:', GodotDiscord.channelId, 'Instance:', GodotDiscord.instanceId);

        if (typeof GodotDiscord.onReady === 'function') {
          GodotDiscord.onReady();
        }
      } catch (err) {
        var message = err && err.message ? err.message : String(err);
        console.error('[GodotDiscord] init error:', message);
        if (typeof GodotDiscord.onError === 'function') {
          GodotDiscord.onError(message);
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
