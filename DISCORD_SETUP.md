# Discord Activity Setup Guide — Zapness

This guide walks through everything needed to make Zapness launchable as a
**Discord Activity** (embedded game inside a Discord voice channel).

---

## Overview of the architecture

```
Discord client (iframe)
  └── discordsays.com proxy
        └── GitHub Pages  ──►  index.html (Godot web export)
                                  ├── discord_activity.js  (Discord Embedded App SDK shim)
                                  └── peerjs_bridge.js     (WebRTC via Discord proxy)
```

---

## Step 1 — Create a Discord Application

1. Go to **[discord.com/developers/applications](https://discord.com/developers/applications)**
2. Click **New Application** → name it `Zapness`
3. Note the **Application ID** (also called Client ID) — you'll need this in two places

---

## Step 2 — Enable the Embedded App SDK (Activities)

1. In your app, go to **Activities** in the left sidebar
2. Click **Enable Activities**
3. Under **URL Mappings**, add a mapping:
   - **Prefix:** `/`
   - **Target:** your GitHub Pages URL (e.g. `https://yourusername.github.io/zapness`)
4. Under **URL Mappings**, also add the PeerJS proxy mapping:
   - **Prefix:** `/peer`
   - **Target:** `0.peerjs.com`

> [!IMPORTANT]
> The URL mappings tell Discord which external URLs to proxy through `discordsays.com`.
> Without the PeerJS mapping, WebRTC signaling will fail inside the Activity.

---

## Step 3 — OAuth2 Configuration

1. Go to **OAuth2 → General**
2. Under **Redirects**, add:
   - `https://<your-app-id>.discordsays.com/`
   - `https://yourusername.github.io/zapness/`
3. Note the **Client Secret** (needed only if you add a token-exchange backend later)

For the current minimal setup (no OAuth2 login), you only need the Client ID.

---

## Step 4 — Plug in your Client ID

In two places:

### 4a — GDScript Autoload
Open [`splitscreen/Scripts/environment/DiscordManager.gd`](splitscreen/Scripts/environment/DiscordManager.gd)
and replace line:
```gdscript
const DISCORD_CLIENT_ID := "YOUR_DISCORD_CLIENT_ID_HERE"
```
with your actual ID, e.g.:
```gdscript
const DISCORD_CLIENT_ID := "1234567890123456789"
```

### 4b — JavaScript shim
Open [`splitscreen/Scripts/web/discord_activity.js`](splitscreen/Scripts/web/discord_activity.js)
and replace:
```js
const CLIENT_ID = 'YOUR_DISCORD_CLIENT_ID_HERE';
```
with your actual ID.

---

## Step 5 — Add DiscordManager as an Autoload

1. Open Godot → **Project → Project Settings → Autoload**
2. Add `res://Scripts/environment/DiscordManager.gd` with name `DiscordManager`
3. Ensure it loads **before** `NetworkManager` (drag to reorder if needed)

---

## Step 6 — Update `export_presets.cfg` (head_include)

The Discord SDK script must be loaded **before** the Godot engine starts.
In Godot → **Project → Export → Web preset → HTML → Head Include**, replace the current
content with:

```html
<!-- Discord Embedded App SDK -->
<script src="https://unpkg.com/@discord/embedded-app-sdk@1.5.0/output/discord-embedded-app-sdk.umd.js"></script>
<!-- Discord Activity bridge -->
<script src="Scripts/web/discord_activity.js"></script>
<!-- PeerJS Library for WebRTC signaling -->
<script src="https://unpkg.com/peerjs@1.5.5/dist/peerjs.min.js"></script>
<!-- PeerJS Bridge for Godot -->
<script src="Scripts/web/peerjs_bridge.js"></script>
```

> [!NOTE]
> Order matters: Discord SDK → Discord bridge → PeerJS → PeerJS bridge.

---

## Step 7 — Set up GitHub repository + Pages

1. Create a new **GitHub repository** (e.g. `zapness`)
2. Push the project:
   ```bash
   git init
   git remote add origin https://github.com/YOURUSER/zapness.git
   git add .
   git commit -m "Initial commit"
   git push -u origin main
   ```
3. In GitHub → **Settings → Pages**:
   - Source: **GitHub Actions**
4. The [`deploy.yml`](.github/workflows/deploy.yml) workflow will auto-run on push and
   publish the Godot web export to Pages

> [!TIP]
> The workflow uses `barichello/godot-ci:4.3` Docker image which has Godot 4.3 pre-installed.
> You may need to place export templates in the repo if the CI can't download them — the workflow
> already tries to copy them from `splitscreen/Detected_profile_templates/`.

---

## Step 8 — Test the Activity (Developer Mode)

1. In Discord, enable **Developer Mode** (User Settings → Advanced → Developer Mode)
2. In your app's Developer Portal → **Activities → Test Activity**
3. Join a voice channel → click the rocket icon → search `Zapness` → launch

> [!WARNING]
> Activities are restricted during development. Only you and up to 25 allowlisted users
> can test it. To go public, apply to Discord's [Embedded App submission process](https://discord.com/developers/docs/activities/overview).

---

## File Map

| File | Purpose |
|---|---|
| [`Scripts/web/discord_activity.js`](splitscreen/Scripts/web/discord_activity.js) | Discord SDK shim (JS) |
| [`Scripts/environment/DiscordManager.gd`](splitscreen/Scripts/environment/DiscordManager.gd) | GDScript autoload wrapper |
| [`Scripts/web/peerjs_bridge.js`](splitscreen/Scripts/web/peerjs_bridge.js) | WebRTC PeerJS bridge (existing) |
| [`Scripts/environment/NetworkManager.gd`](splitscreen/Scripts/environment/NetworkManager.gd) | Game networking (existing) |
| [`.github/workflows/deploy.yml`](.github/workflows/deploy.yml) | GitHub Pages auto-deploy |

---

## PeerJS + Discord Proxy

When running inside Discord, PeerJS must route its signaling through Discord's proxy.
`DiscordManager.patch_peerjs_url_mappings()` does this — call it from `NetworkManager`
before initialising PeerJS:

```gdscript
# In NetworkManager._ready() or host_game() / join_game():
if DiscordManager.is_ready:
    DiscordManager.patch_peerjs_url_mappings()
```

---

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| Blank iframe in Discord | GitHub Pages URL not set in Activities URL Mappings |
| PeerJS connection fails | `/.proxy/peer` mapping missing in Developer Portal |
| `GodotDiscord is not defined` | Script load order wrong — Discord SDK must load first |
| `CrossOriginEmbedderPolicy` error | COOP/COEP headers missing — check the `_headers` file |
| Activity not showing in Discord | App not allowlisted — add your Discord account in the Portal |
