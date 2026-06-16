# UpturtleMon

A lightweight macOS menu bar companion for the [Upturtle](https://github.com/Z3nto/upturtle) self-hosted uptime monitor.

UpturtleMon lives in your menu bar, polls your Upturtle server on each monitor's own configured interval, and shows status, uptime, and recent response-time history in a compact popup. Click any monitor to expand a live response-time chart with hover details.

## Features

- **Per-monitor polling** — each monitor refreshes at its server-configured interval (clamped to a 5-second floor); no fixed global tick.
- **Bulk reconciliation** — `GET /api/monitors` is hit every 5 minutes (and on demand) to pick up new/removed monitors, re-sync history, and recover from per-monitor failures.
- **Grouped popup** — monitor list grouped by their server-side group, with the group order resolved from `GET /api/groups` rather than alphabetical.
- **History strip** — last 20 checks per monitor as colored bars. Hover any bar to see the exact timestamp and outcome in a custom blur-style tooltip.
- **Click-to-expand chart** — clicking a row drops down a Swift Charts response-time graph for that monitor, with avg / min / max stats, red failure dots, and a cursor-tracking tooltip showing time, latency, and status.
- **Outage alert in the menu bar** — when any selected monitor goes down, the menu bar icon turns red. It returns to the standard tinted template the moment everything is up again.
- **Clickable HTTP targets** — for HTTP/HTTPS monitors, the target URL is rendered as a real link and opens in your default browser.
- **Monitor activation** — choose which monitors appear in the popup; activations persist across launches. New monitors on the server land in the **Available** column until you opt them in.
- **Settings window** — server URL, API token, language, and a one-click "Start on Login" toggle (uses `SMAppService`). Window pops to front when the gear button is clicked, even from the menu bar agent.
- **Dock icon on demand** — the app runs as a menu bar agent (`LSUIElement`), but the moment the Settings window opens, a Dock icon appears so you can find or Cmd-Tab back to the window. The icon disappears again when Settings closes.
- **Refresh on settings change** — saving a new server URL or token in **General** triggers an immediate bulk refresh.

## Requirements

- macOS 15.6 (Sequoia) or later
- An Upturtle server you can reach over the network (HTTP/S)
- An API token from your Upturtle server (generate one in your user profile under API keys)

## Setup

1. Build and run from Xcode, or install the notarized `.app` from a release.
2. Click the menu bar icon → ⚙️ → **General**
3. Paste your **Server URL** (e.g. `https://upturtle.example.com`) and **API Token**.
4. Switch to **Monitors** and activate the monitors you want to see in the popup. New monitors added on the server later default to **Available** — you opt them in.

The first successful fetch automatically activates every monitor on the server. From then on, you control the selection.

## How polling works

- On launch and every 5 minutes thereafter, UpturtleMon hits `GET /api/monitors` (and `GET /api/groups` in parallel) to reconcile the monitor list, group names, group order, and authoritative history.
- For each monitor returned, a per-monitor task is scheduled at that monitor's own `config.interval`. Each tick calls `GET /api/monitors/{id}` and appends one history bar locally if the server's `last_checked` advanced.
- Bulk failures surface in the popup footer; per-monitor failures stay silent — the next bulk refresh resolves them.

## API endpoints used

| Endpoint | Auth | Purpose |
| --- | --- | --- |
| `GET /api/monitors` | bearer | Bulk list of all monitor snapshots with history |
| `GET /api/monitors/{id}` | bearer | Single-monitor live snapshot (status + last_checked + last_latency) |
| `GET /api/groups` | bearer | Group names + order (used to sort groups in the popup and resolve group_id → name) |

All requests send `Authorization: Bearer <api-token>` when a token is set.

## Project layout

```
UpturtleMon/
├── UpturtleMon/
│   ├── UpturtleMonApp.swift       # MenuBarExtra + Settings Window scenes; red/normal menu bar icon
│   ├── ContentView.swift          # Popup view
│   ├── Monitor.swift              # Monitor / MonitorGroup / HistoryEntry models
│   ├── MonitorRowView.swift       # Single monitor row, history bars + hover tooltip
│   ├── MonitorChartView.swift     # Expanded Swift Charts graph + cursor-tracking tooltip
│   ├── MonitorStore.swift         # @Observable store; per-monitor polling + bulk reconcile
│   ├── UpturtleClient.swift       # Async REST client + Codable wire models
│   ├── SettingsView.swift         # General / Monitors / About tabs; toggles dock icon
│   ├── AppIcon.icon/              # App icon (Xcode 16 App Icon Composer format)
│   └── Assets.xcassets/
└── UpturtleMon.entitlements        # App sandbox + network.client
```

## Building

```bash
xcodebuild -project UpturtleMon.xcodeproj -scheme UpturtleMon -configuration Debug -destination 'platform=macOS' build
```

Or just open `UpturtleMon.xcodeproj` in Xcode and hit Run.

## Credits

- Built on top of the [Upturtle](https://github.com/Z3nto/upturtle) server by Z3nto.
## License

MIT.
