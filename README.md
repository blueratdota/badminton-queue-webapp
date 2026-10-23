# Shuttle Queue webapp

React frontend with the iPad app's current matchmaking, ratings and tournament rules in `src/engine.js`. See `RULES.md` for organizer-facing behavior.

- `npm run dev`: local frontend.
- `npm run check`: engine regression self-checks.
- `npm run build`: self-checks and production build into `dist/`.
- `npm run sim -- <session.json> --parity --courts 4 --locks "Gocs,Bianca;Rica,Joseph"`: deterministic replay to compare with the iPad app.
- `npm run scan -- <session.json> --courts 4`: queue diagnostics.

All data stays in this browser's localStorage (`shuttle-queue-v2`); export before moving to another device. Existing sessions keep loading. Old `partner` requests remain in saved data but no longer affect matching: configure ongoing pairs under **Locked Teammates**. New locks carry into a new session with the same players.

Netlify builds with `npm run build` and publishes `dist/`. Frontend components and the engine are separate so design work can continue independently.
