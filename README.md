# UpturtleMon

A lightweight macOS menu bar companion for the [Upturtle](https://github.com/Z3nto/upturtle) self-hosted uptime monitor.

UpturtleMon lives in your menu bar, polls your Upturtle server on each monitor's own configured interval, and shows status, uptime, and recent response-time history in a compact popup. Click any monitor to expand a live response-time chart with hover details.

## Features

- **Per-monitor polling** — each monitor refreshes at its server-configured interval; no fixed global tick.
- **Status popup** — grouped monitor list with status badge, uptime %, last-checked time, and a 20-bar history strip; bar hover shows the exact timestamp and status.
- **Response-time chart** — click a monitor to expand a Swift Charts line + area graph; cursor-tracking tooltip with timestamp, latency, and status; red dots mark failures.
- **Monitor selection** — choose which monitors appear in the popup; activations persist across launches.
- **Group order** — respects the group order configured on the server (via `/api/groups`).
- **Clickable URLs** — HTTP monitor targets open in your default browser.
- **Settings** — server URL, API token, language, and a one-click "Start on Login" toggle (uses `SMAppService`).
- **Native menu bar app** — runs as a `LSUIElement` (no Dock icon), template menu bar icon, popup window styled with `MenuBarExtra(.window)`.

## Requirements

- macOS 26 (Tahoe) or later
- An Upturtle server you can reach over the network (HTTP/S)
- An API token from your Upturtle server (generate one in your user profile under API keys)

## Setup

1. Build and run from Xcode, or install the notarized `.app` from a release.
2. Click the menu bar icon → ⚙️ → **General**
3. Paste your **Server URL** (e.g. `https://upturtle.example.com`) and **API Token**.
4. Switch to **Monitors** and activate the monitors you want to see in the popup. New monitors added on the server later default to **Available** — you opt them in.

The first successful fetch automatically activates every monitor on the server. From then on, you control the selection.

## How polling works

- On launch and every 5 minutes thereafter, UpturtleMon hits `GET /api/monitors` to reconcile the monitor list, group names, and authoritative history.
- For each monitor returned, a per-monitor task is scheduled at that monitor's own `config.interval` (clamped to a 5-second floor). Each tick calls `GET /api/monitors/{id}` and appends one history bar locally if the server's `last_checked` advanced.
- Bulk failures surface in the popup footer; per-monitor failures stay silent — the next bulk refresh resolves them.

## API endpoints used

| Endpoint | Purpose |
| --- | --- |
| `GET /api/monitors` | Bulk list of all monitor snapshots with history |
| `GET /api/monitors/{id}` | Single-monitor live snapshot (status + last_checked + last_latency) |
| `GET /api/groups` | Group names + order (used to sort groups in the popup) |

All requests send `Authorization: Bearer <api-token>` when the token is set.

## Project layout

```
UpturtleMon/
├── UpturtleMon/
│   ├── UpturtleMonApp.swift       # MenuBarExtra + Settings Window scenes
│   ├── ContentView.swift          # Popup view
│   ├── Monitor.swift              # Monitor / MonitorGroup / HistoryEntry models
│   ├── MonitorRowView.swift       # Single monitor row + history bars w/ hover tooltip
│   ├── MonitorChartView.swift     # Expanded Swift Charts response-time graph
│   ├── MonitorStore.swift         # @Observable store; per-monitor polling
│   ├── UpturtleClient.swift       # Async REST client + Codable wire models
│   ├── SettingsView.swift         # General / Monitors / About tabs
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
- Logo by toepper.rocks.

## License

MIT.
