# Shuttle Queue 🏸

Run a badminton club night without juggling a paper queue. Shuttle Queue manages courts, player turns, balanced matches, ratings, and tournaments on iPad and the web.

[Open the web app](https://hampashers.netlify.app) · [Native iPad source](https://github.com/blueratdota/badminton-queue-app) · [Full playing rules](RULES.md) · [MIT license](LICENSE)

## Screenshots

Actual app screens using a fictional demo roster. The web app adapts to phones and tablets; the native app is designed for iPad.

| Native iPad app | Web courts | Queue matching settings |
| --- | --- | --- |
| <img src="docs/screenshots/ipad-home.png" width="320" alt="Shuttle Queue on iPad showing session creation, All Players, and a live three-court demo session"> | <img src="docs/screenshots/web-courts.jpg" width="260" alt="Web dashboard showing three doubles games in progress with demo players"> | <img src="docs/screenshots/web-matching.jpg" width="260" alt="Web settings with Auto, Equal Skill, and Balanced Skill matching choices"> |

## Features

- **Multiple courts:** run singles and doubles together, start ready courts, and see each court's next game without booking a player twice.
- **Fair player rotation:** counted games and rest order guide selection, with support for arrivals, sitting out, returning players, and organiser adjustments.
- **Three matching modes:** choose Auto, Equal Skill, or Balanced Skill for each session; copied sessions retain their setting.
- **Control when you need it:** shuffle a lineup, keep one side, replace a player, select a manual lineup, or lock regular teammates together.
- **Scheduled matches:** reserve exact teams after their first game, with court assignment, postponement, cancellation, and queue-priority protections.
- **Ratings and standings:** Elo-style rating changes, temporary win/loss streak adjustments, match history, result corrections, and standings.
- **Tournament play:** round robin followed by a double-elimination bracket, for singles or doubles.
- **Session management:** create, end, reopen, and revisit sessions; maintain a player registry across nights.
- **Local data:** the iPad saves on-device; the hosted web app saves in the current browser and supports JSON export/import.
- **Adaptive interface:** phone navigation, tablet layouts, light/dark appearance, and court rally animations that respect Reduce Motion.

## Queue matching

Choose **Settings → Queue matching** while in queue mode.

| Mode | How it selects games |
| --- | --- |
| **Auto — default** | Uses the original queue logic: prefer a 1.0-point skill range, then 1.5, then mixed balanced teams, with game-count and rest protections. Older saves default to Auto. |
| **Equal Skill** | Keeps automatic games within **1.0 matching rating point** from lowest to highest. If a losing-streak penalty leaves a player without a compatible group in the active roster, use their current saved rating instead. A court waits when no legal group fits. |
| **Balanced Skill** | Prioritizes queue turns and balances teams, allowing mixed skill levels without preferring a narrow rating range. |

Matching ratings are capped at **5.0**. The losing-streak fallback applies only to Equal Skill; it changes neither saved ratings nor streak history. Game-count, rest, teammate-lock, and rematch protections still apply. Manual lineups and exact scheduled games retain their overrides. Strict matching does not guarantee a maximum wait. See [RULES.md](RULES.md) for the complete behavior and tunable values.

## Use the app

### Web

Open **[hampashers.netlify.app](https://hampashers.netlify.app)** in a current browser. Choose courts, add players, select a matching mode, and start ready games. Finish each game to record its winner and return players to the queue.

Use **Settings → Export Data** to back up a browser's sessions. **Import Data** adds exported sessions and replaces sessions with the same ID. Each browser and device has its own data; iPad and web do not sync automatically. The iPad's JSON export can be imported into the hosted web app.

### Run the React app locally

Requires Node.js 22 or later and npm. Built with React, Vite, Tailwind CSS, Radix/shadcn UI, Framer Motion, and lucide-react. Netlify runs the same production build and publishes `dist/`.

```sh
npm ci
npm run dev
# Open the localhost URL printed by Vite.

npm run check
npm run build
npm run preview
```

### Native iPad app

Requires **iPadOS 17 or later**, macOS, and an Xcode installation with an appropriate iOS SDK. The app uses SwiftUI, Swift 5 language mode, and no third-party dependencies.

1. Clone the [native iPad repository](https://github.com/blueratdota/badminton-queue-app) and open `ShuttleQueue.xcodeproj`.
2. Select the **ShuttleQueue** scheme and your simulator or iPad.
3. For a physical device, select your development team under Signing & Capabilities.
4. Build and run. Use an optimized **Release** build for club nights; Debug builds include extensive self-checks and are slower at matching.

```sh
# Replace the destination name with an installed iPad simulator.
xcodebuild -project ShuttleQueue.xcodeproj -scheme ShuttleQueue \
  -configuration Debug -destination 'platform=iOS Simulator,name=iPad mini (A17 Pro)' \
  -derivedDataPath build/sim build

# Signed Release build for a physical iPad.
xcodebuild -project ShuttleQueue.xcodeproj -scheme ShuttleQueue \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath build/dev -allowProvisioningUpdates build
```

Free Apple development signing expires after seven days. The app shows its signing expiry in **Settings → This iPad copy**; reinstall a freshly signed build to renew it. Updating the same app preserves its saved sessions.

## Development and checks

| Location | Purpose |
| --- | --- |
| `src/engine.js` | Native-compatible matching, ratings, tournament logic, and self-checks |
| `src/store.js` | Browser storage, import/export, session switching, and theme |
| `src/App.jsx` | Dashboard, toolbar, and queue matching selector |
| `src/Courts.jsx`, `src/Queue.jsx`, `src/Sheets.jsx` | Courts, player queue, and organiser dialogs |
| `tools/` | Engine checks, deterministic replays, and simulation diagnostics |
| `RULES.md` | Organiser-facing specification and tunable rules |

```sh
# Engine, frontend, scheduling, and queue regression checks.
npm run check

# Keep real player exports outside version control.
npm run sim -- /path/to/session.json --courts 3 --minutes 180 \
  --runs 30 --queue-matching equalSkill

# Deterministic replay; compare with the native -parity launch.
npm run sim -- /path/to/session.json --parity --courts 3 \
  --queue-matching equalSkill
```

The native simulator accepts `-parity -courts 3 -queue-matching equalSkill`. Both engines share the same matching behavior; keep `RULES.md` and both ports consistent when changing a rule. Development builds run the engine's assertions; production builds run the checks before bundling.

The checked-in `ShuttleQueue/` sources mirror the native app, whose canonical project is the separate iPad repository. Do not commit player exports, device backups, signing material, or build output.

## License

[MIT](LICENSE) © 2026 blueratdota. Third-party dependencies retain their own licenses.
