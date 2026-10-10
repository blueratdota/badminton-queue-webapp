# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Shuttle Queue: an iPad SwiftUI app (iOS 17+, Swift 5 mode, no third-party dependencies) plus a React web app (hosted on Netlify, tuned for the iPad Mini and phones) for running badminton club nights: a fair player queue, singles/doubles matchmaking across courts, Elo-style ratings, standings, and a double-elimination tournament mode. **[RULES.md](RULES.md) is the spec** of how the app behaves, written for organisers. When you change behaviour or a tunable constant, update RULES.md to match (§13 lists the tunable numbers).

## Build and run

Single target/scheme `ShuttleQueue`; no test target.

```sh
# Build for an iPad simulator
xcodebuild -project ShuttleQueue.xcodeproj -scheme ShuttleQueue -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M5)' -derivedDataPath build/sim build

# Install and launch (stdout in the terminal)
xcrun simctl boot 'iPad Pro 11-inch (M5)'
xcrun simctl install booted build/sim/Build/Products/Debug-iphonesimulator/ShuttleQueue.app
xcrun simctl launch --console booted com.automastery.ShuttleQueue

# Install on the iPad: always the optimized Release build (Debug is 4-5x slower at matchmaking)
xcodebuild -project ShuttleQueue.xcodeproj -scheme ShuttleQueue -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath build/dev -allowProvisioningUpdates build
xcrun devicectl device install app --device <iPad UDID> build/dev/Build/Products/Release-iphoneos/ShuttleQueue.app
```

Release builds skip the DEBUG self-checks, so run a Debug build in the simulator after every change.

**Renewing the iPad copy:** it's signed with a free developer account, so each signing profile lasts 7 days (the app shows the countdown under ⚙︎ → This iPad copy). Rebuilding reuses the cached profile until it expires; to renew early, move the profile named by the app's `embedded.mobileprovision` UUID out of `~/Library/Developer/Xcode/UserData/Provisioning Profiles/`, then `clean build` the Release command above with `-allowProvisioningUpdates` and reinstall. Saved data on the iPad is kept.

- **Benchmark:** launching a DEBUG build with `-bench` writes `Documents/bench.txt`: the cost of one screen update and one shuffle with the saved players. Add `SWIFT_OPTIMIZATION_LEVEL=-O` to the build for numbers close to Release.

### Checks (instead of unit tests)

- **Web version:** the engine (`src/engine.js`) holds its rules; `npm run check` runs its self-checks. `npm run sim -- <sessions.json> --courts 3 [--pairs "A,B;C,D"] [--runs N]` simulates nights through the engine's own matching in seconds. Its matching is identical to the iPad's: `--parity [--draws draws.json]` and the iPad's `-parity` play the same night and should print identical lines (games and ratings). `npm run scan -- <sessions.json> [--courts N] [--pairs ...] [--late "Name:25,..."]` counts odd queue behaviour per night (straight-back calls, someone 2+ games behind left waiting, waits over 30, repeats, wide or lopsided games) with examples. The tools are in `tools/` (CommonJS) and load the engine through `tools/load-page.js`.

- `SessionState.selfCheck()` (and `Tournament.selfCheck()`, called from it) are `assert`-based checks that run in `ShuttleQueueApp.init()` on every DEBUG launch. A failing assert crashes the app at launch. Add new checks there, next to the related ones.
- **Simulation:** launching a DEBUG build with `-simulate` (append it to the `simctl launch` command above) replays 30 virtual nights through the real matching code and writes `Documents/sim-report.md` (also printed). Input is `Documents/sim-input.json` (a `Store` JSON), or the saved `sessions.json` if that's missing. Find the Documents folder with `xcrun simctl get_app_container booted com.automastery.ShuttleQueue data`. Use this to judge matchmaking changes (skill spread, repeats, waits, latecomers).

## Web app

React 19 + Vite, Tailwind v4, shadcn/ui (JSX, `components.json`; components in `src/components/ui`, which import `cn` from the `cn` package), Framer Motion, lucide-react. Deployed to Netlify (`netlify.toml`) as a static site. No backend: everything is saved in the browser's localStorage.

```sh
npm install
npm run dev     # http://localhost:5173. DEV runs the engine self-checks (look for "Assertion failed" in the console)
npm run build   # runs the self-checks, then builds to dist/
```

- **`src/engine.js`** is the iPad app's rules ported to JS: matching, ratings, standings, tournaments. All logic reads and mutates the module-level session `S` (set with `setS`), just as the Swift methods mutate `SessionState`. Keep it plain JS with no imports, because the node tools eval it. Port rule changes from the Swift code here and check `--parity`.
- **`src/store.js`**: sessions, saving, the open sheet (`ui.modal`) and confirmation (`ui.confirm`), and the theme. `act(fn)` runs a change and then `save()`s. `useStore()` re-renders on every `bump()`. `App` runs the matching once per change inside `withMatching` and passes each court's next game down, so the preview is always what Start begins.
- **UI:** `App.jsx` (toolbar, layout), `Courts.jsx`, `Queue.jsx` (Up Next, the queue with its long-press menu, tournament tables), `Sheets.jsx` (every sheet), `bits.jsx` (dots, list sections, segmented control, confirmation). Layout: under 640px, tabs (phones); 640–1023px, courts above the queue (iPad Mini portrait); 1024px and up, side by side.
- **Saving:** all sessions are one JSON value under localStorage key `shuttle-queue-v2` (`{ currentId, sessions }`), rewritten on every change. Each device and browser has its own data. If saving fails (storage full, private browsing), the app says so once. Another tab's saves reload this tab's data, so an old tab can't overwrite them. Old data must keep loading, so add new stored fields as optional, as the iPad app does.
- **Backups and moving devices:** Options → Export / Import Data saves and loads the same `{ currentId, sessions }` JSON (the old artifact's shape too). Importing adds sessions, replacing any with the same id.

## Architecture (iPad app)

Three source files in `ShuttleQueue/`:

- **ShuttleQueueApp.swift**: app entry, all models, persistence, and all game logic, plus the DEBUG self-checks and `Simulation`.
- **Tournament.swift**: the `Tournament` model (round robin, then double-elimination bracket), a `SessionState` extension for tournament play, and its views.
- **ContentView.swift**: all other UI. Views take `@Binding var s: SessionState` and call its mutating methods directly. There are no view models.

Key points that span files:

- **`SessionState` is the whole model**: a `Codable` value type holding players, courts, results and an optional tournament (`nil` = queue mode). All logic lives on it as methods. Derived state (`queue`, `gamesCounted`, `eligible`, `upNext`) is recomputed on every access; nothing is cached.
- **Persistence:** `Store { current, past }` is saved as one JSON file (`Documents/sessions.json`) on every change through `.onChange(of: store)`. Old data must keep decoding, so **add new stored fields as optionals** (as with `first`, `since`, `credit`, `plan`, `changes`). `Store.load()` also migrates the v1 `session.json`.
- **One source of truth for "who plays next":** `queueUpNext` builds a game for every open court (and a guess for busy ones) without booking anyone twice. `nextPairing(for:)`, the court previews and Start all read from it, so the preview is always what Start begins. Matching runs `pick` → `pickSingles` / `pickDoubles` → `bestFour` / `fairSplits`, with the 40-minute wait cap applied in `pick`.
- **Hand-set lineups and shuffles** are stored on the `Court` (`plan` and `shuffles`). Shuffles are deterministic: `SeededRandom` is seeded from the shuffle count so previews don't change when the view redraws. Shuffling one court pins every other open court's lineup as a `plan`.
- **Time:** matching code uses `SessionState.now` instead of `Date()`, so that `Simulation` can drive a virtual clock in DEBUG builds. Keep that in any new time-dependent logic.
- **Ratings:** each `GameResult` stores the rating change actually applied (`changes`) so deleting a game can reverse it exactly. Don't recompute ratings from history.

## Conventions

- Tunable rule values are `static let` constants on `SessionState` (`similarSpread`, `widerSpread`, `fairGap`, `singlesRange`, `repeatLimit`, `waitCap`, `ratingK`, `ratingSpread`, …). Many are marked with `// ponytail:` comments that name the deliberate simplification and when to revisit it. Keep that convention when cutting a corner on purpose.
