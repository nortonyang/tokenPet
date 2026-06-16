# TokenPet 🐾

<p align="center">
  <img src="docs/assets/tokenpet_mockup.jpg" width="500" alt="TokenPet Mockup">
</p>

TokenPet is a lightweight, native macOS desktop pet and AI developer tool companion. Designed as an elegant, non-intrusive background agent, TokenPet keeps you company while automatically monitoring the activity, token consumption, and rate limits of your favorite AI command-line interfaces (including **Gemini/Antigravity**, **Codex**, and **Claude Code**).

---

## ✨ Key Features

### 🤖 1. Procedural Vector-Based Desktop Pet ("Token")
* **0MB Assets**: Built entirely using native SwiftUI vector graphics (`Path`, `Shape`) and spring physics animations. Zero external images, GIFs, or sprite sheets required—infinite scalability with zero storage overhead.
* **Non-Disruptive Interaction**: Runs as a borderless, transparent floating panel (`NSPanel`) using `.nonactivatingPanel` masks. You can click and drag Token anywhere on your screen, and it **never steals focus** from your IDE or Terminal.
* **2.5D Mouse Cursor Tracking**: Token's head and eyes dynamically look at and track your mouse cursor across the screen, utilizing soft-clamped spring formulas for a natural, organic depth parallax effect.
* **State Machine & Animations**:
  * **Idle**: Soft floating/breathing animation with random blinking.
  * **Working**: Coding on a mini-laptop with rapid keyboard typing animations and active visor HUD status.
  * **Finished**: Turns eyes to happy smiley faces (`^ _ ^`), spins around, and holds up a green `DONE!` sign.
  * **Warning**: Nervous shivering, sweat drop animations, and an orange `WARN` sign when API quotas are low.
  * **Error**: Visor turns to `× ×` with a rotating dizzy halo when monitoring threads encounter issues.

### 📊 2. Task-Differentiated Visor HUD & Actions
When background AI tasks are running, Token's appearance adapts dynamically to the active tool:
* **Shell & LED Colors**: Adapt to the tool's color theme (Light Blue for Gemini, Codex Purple, Claude Orange, or Cyan/Teal for mixed concurrently running tasks).
* **HUD Visor Eyes**: Dynamically display the initials of the active tool(s):
  * **`G G`** when **Gemini (Antigravity)** is working.
  * **`C C`** when **Codex** is working.
  * **`A A`** when **Claude Code** (Anthropic) is working.
  * **Split Initials (e.g., `G C`, `C A`)** in the left and right eyes if multiple tools are active concurrently.
* **Laptop Screen & Code Lines**: Mini laptop displays code lines themed to match the active tool (purple for Codex, orange/yellow for Claude, cyan/blue for Gemini).
* **Typing Speed**: Typing animation intervals scale dynamically based on the tool's processing speed (e.g., Claude types at a blazing 0.08s, Gemini at 0.12s, and Codex at a steady 0.16s).

### 🔍 3. Automatic Log Parsing & Quota Analysis
TokenPet parses local logs in the background without making redundant network calls:
* **Gemini (Antigravity-CLI)**:
  * Automatically parses OpenTelemetry JSON Lines output (`~/.gemini/telemetry.log`) and HTTP helpers log (`~/.gemini/antigravity-cli/cli.log`).
  * Extracts multi-dimensional Token metrics: Input, Output, Cached, Thoughts, Tool, and Total tokens.
  * Integrates Google OAuth to refresh credentials and request official cloud quota snapshots, tracking 5-hour and 24-hour sliding usage windows.
  * Detects `429 Too Many Requests` limit errors and calculates precise reset countdowns.
* **Codex**:
  * Scans local session logs (`~/.codex/sessions/**/*.jsonl`) using file modification timestamp (mtime) caching.
  * Extracts rate limits, prompt/completion tokens, and cached input tokens to represent local consumption.

### 💬 4. Interactive Status Popover & Menu Bar
* **Status Item**:常驻 macOS 菜单栏 (`🐾` pawprint icon). Left-clicking the icon or the pet displays a sleek translucent popover (`NSPopover`). Right-clicking reveals a menu to quickly show/hide the pet, open settings, or exit.
* **Scrollable Metrics Panel**: Displays detailed 5h/24h/7d quota meters, token breakdown grids, and data source tags. Built with a scrollable container to ensure it never gets clipped on smaller screens.
* **Quota Refresh Countdown**: Displays a countdown (e.g. `⏳ 18s`) inside the Gemini Quota section, marking the exact time remaining until the next background log/telemetry poll.

### ⚙️ 5. Native Preferences Panel
A clean AppKit-style multi-tab preferences window:
* **General**: Adjustable pet sizing scale (0.5x to 2.0x), always-on-top toggle, start at login, and system notification permissions.
* **Monitoring**: Toggle process detection and customize comma-separated keywords for Gemini, Codex, and Claude.
* **Quota Management**: View and modify quota limits, set warn thresholds (percentage of usage), and review historical API statistics.

---

## 🛠 Tech Stack & Architecture

TokenPet is built purely on native macOS API frameworks:
* **Swift 6.0**: Strict concurrency checking fully resolved (`@MainActor` isolation for UI, non-isolated threads for I/O).
* **SwiftUI + AppKit**: Blended interface using `NSPanel` hosting SwiftUI `PetView`.
* **SQLite3**: Lightweight local database (`ai_telemetry.db`) used to query and aggregate usage data over sliding 5-hour, 24-hour, and 7-day intervals.
* **Swift Package Manager**: Dependency-free workspace packaging.

### Directory Structure

```text
TokenPet/
├── Package.swift            # SPM Package manifest
├── build_app.sh             # Production build & assembly script
├── Sources/
│   └── TokenPet/
│       ├── AppDelegate.swift        # Life cycle, status item, windows, gesture listeners
│       ├── PetPanel.swift           # Borderless transparent NSPanel wrapper
│       ├── PetView.swift            # Procedural drawing, timers, animations, eye states
│       ├── PetState.swift           # Central state machine orchestrator
│       ├── ProcessMonitor.swift     # Background process scanner (/bin/ps)
│       ├── QuotaManager.swift       # Quota calculations and window counters
│       ├── SQLiteManager.swift      # Local SQLite database, query aggregations
│       ├── UsageLogParser.swift     # Telemetry & Gemini CLI log parser
│       ├── SessionScanner.swift     # Codex JSONL session file parser
│       ├── CCDataCoordinator.swift  # Coordinates data sync between scanners & UI
│       ├── BubbleView.swift         # Translucent status popover View
│       ├── SettingsView.swift       # Preferences TabView
│       └── ...
└── ...
```

---

## 🚀 How to Build & Run

### Prerequisites
* macOS 14.0 or newer.
* Xcode 16.0 or newer (with Swift 6.0 compiler support).

### Quick Build & Assemble
Run the custom automated build script from the project root. This compiles the project with high optimization (WMO) and bundles it into a standalone macOS App structure:

```bash
chmod +x build_app.sh
./build_app.sh
```

Upon successful completion, you will find `TokenPet.app` in the root folder.

### Run
Double-click `TokenPet.app` in Finder or run the following command in your terminal:

```bash
open TokenPet.app
```

*Note: Since the app runs as a background agent (`LSUIElement = true` in `Info.plist`), it will not appear in your Dock. Look for the Pawprint icon (`🐾`) in the macOS system menu bar.*

---

## 📁 Log Integration Paths

TokenPet scans the following standard paths in user home directory to aggregate usage:
* **Gemini Telemetry**: `~/.gemini/telemetry.log`
* **Gemini CLI Log**: `~/.gemini/antigravity-cli/cli.log`
* **Gemini Settings**: `~/.gemini/settings.json`
* **Codex Sessions**: `~/.codex/sessions/`

To enable detailed Gemini token reporting, make sure `telemetry` is enabled in `~/.gemini/settings.json`:
```json
{
  "telemetry": {
    "enabled": true,
    "target": "local",
    "outfile": ".gemini/telemetry.log"
  }
}
```
*Tip: You can enable telemetry with a single click inside the TokenPet Settings → Gemini panel.*

---

## 📄 License
This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.
