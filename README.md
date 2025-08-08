## FirePing 🔥🛰️

FirePing is a simple, accessible Phoenix LiveView app that delivers instant fire notifications for user-defined geographic areas using NASA FIRMS data.

### Highlights ✨

- **Authentication** 🔐: Email-based OTP (6-digit). Auto-registers unrecognized emails
- **Locations** 📍: Per-user saved locations (GPS) with custom radius (meters)
- **Notifications** 📣: Web Push (VAPID), Email, SMS, Webhook
- **Preferences** ⚙️: Notification frequency and lifecycle controls
- **Services** 🧩:
  - **FireFetch** 📡: Pulls recent fires from NASA FIRMS
  - **FireNotify** 📬: Sends notifications to users with matching locations

### Tech Stack 🧰

- 💧 **Elixir + Phoenix LiveView** (app + frontend)
- 🗄️ **PostgreSQL + PostGIS** (primary + spatial data)
- 🐳 **Docker + docker-compose** (database container)
- 📊 **Phoenix LiveDashboard + AppSignal** (monitoring)

## Quick Start 🚀

Prerequisites 📋:

- Elixir/OTP (recommended: Elixir 1.18.x, OTP 27)
- Docker and docker-compose
- Node.js (for Phoenix asset tooling, if you plan to modify assets)
- mdBook (optional, for `spec` docs): install from `https://rust-lang.github.io/mdBook/`

1. Clone and configure environment 🧩

```bash
git clone https://github.com/LightningK0ala/FirePing.git
cd FirePing
cp .env.example .env
# Edit .env with any required secrets (e.g., VAPID keys, email/SMS provider configs)
```

2. Start the database 🐘

```bash
make db-up
```

3. App setup (deps, create DB, migrate) 🛠️

```bash
make setup
```

4. Run the app (dev) ▶️

```bash
make app-dev
# Visit http://localhost:4000
```

5. Run tests ✅

```bash
make test
```

## Common Tasks (Makefile) 🧰

The project provides convenient targets. Below is a practical subset; run `make help` for the full list.

### Setup & Development 🧑‍💻

- **Install deps, create and migrate DB**:

  ```bash
  make setup
  ```

- **Run Phoenix with IEx**:

  ```bash
  make app-dev
  ```

- **Format & checks**:
  ```bash
  make format
  make check   # format --check + credo
  ```

### Database 🗃️

- **Start DB**:

  ```bash
  make db-up
  ```

- **Wait for DB readiness** (also runs `db-up`):

  ```bash
  make db-ready
  ```

- **Reset databases (dev + test)**:

  ```bash
  make db-reset
  ```

- **Seed data**:
  ```bash
  make db-seed
  ```

### Tests ✅

- **Run once**:

  ```bash
  make test
  ```

- **Watch mode**:
  ```bash
  make test-watch
  ```

### Fire data utilities 🔥

- **Import sample NASA FIRMS fires (CSV)**:

  ```bash
  make import-fires
  ```

- **Manually trigger FireFetch job** (optional `days=N`):

  ```bash
  make fire-fetch           # default lookback
  make fire-fetch days=3    # last 3 days
  ```

- **Debug FIRMS API response** (optional `days=N`):

  ```bash
  make fire-debug
  make fire-debug days=3
  ```

- **Show fire DB statistics**:

  ```bash
  make fire-count
  ```

- **Test FireFetch logic synchronously** (verbose):
  ```bash
  make fire-test
  ```

### Admin (Users) 🛡️

- **Grant admin**:

  ```bash
  make admin-grant user@example.com
  ```

- **Revoke admin**:

  ```bash
  make admin-revoke user@example.com
  ```

- **List admins**:
  ```bash
  make admin-list
  ```

### Spec documentation (optional) 📚

- **Serve the `spec` book**:
  ```bash
  make spec-dev
  # mdBook serves at http://localhost:3000 by default unless configured otherwise
  ```

## Notes 📝

- The DB runs via docker-compose. App connects using standard Phoenix `dev.exs`/`test.exs` settings.
- If you change environment variables, restart the app process.
- For Web Push (VAPID), Email, SMS, and Webhook delivery, ensure the related credentials are configured in `.env` and mapped into your runtime configuration.

## Troubleshooting 🧯

- DB not ready: run `make db-ready` or inspect logs with `docker-compose logs postgres`.
- Port conflicts: stop other services on ports used by Phoenix (default 4000) or Postgres.
- Missing tools: ensure Elixir/OTP, Docker, and (optionally) mdBook are installed and on PATH.

## License 📄

Apache-2.0 (or update to your preferred license).
