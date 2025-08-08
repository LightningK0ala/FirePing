## FirePing 🔥🛰️

FirePing is a Phoenix LiveView web application that provides fire monitoring and visualization for user-defined geographic areas using NASA FIRMS satellite data.

### Current Features ✨

- **Authentication** 🔐: Email-based OTP (6-digit code). Auto-registers new emails
- **Interactive Map** 🗺️: View fire locations with intensity-based sizing and confidence color coding
- **Location Management** 📍: Add/edit/delete locations with custom radius settings (GPS coordinates)
- **Fire Visualization** 🔥: Real-time fire data from NASA VIIRS satellites with spatial queries
- **Admin Panel** 🛠️: LiveDashboard (system metrics) and Oban Web (job monitoring)
- **Data Integration** 📡: **FireFetch** service pulls recent fires from NASA FIRMS API via scheduled jobs

### Planned Features 🚧

- **Notifications** 📣: Web Push (VAPID), Email, SMS, Webhook alerts
- **FireNotify Service** 📬: Automated user notifications for fires within location radius
- **Notification Preferences** ⚙️: Frequency and lifecycle controls

### Tech Stack 🧰

- 💧 **Elixir + Phoenix LiveView** (app + frontend)
- 🗄️ **PostgreSQL + PostGIS** (primary + spatial data)
- 🐳 **Docker + docker-compose** (full containerized development)
- 📊 **Phoenix LiveDashboard + AppSignal** (monitoring)

## Quick Start 🚀

Prerequisites 📋:

- Docker and docker-compose
- NASA FIRMS API key (MAP_KEY) 🔑 — request it via the widget at the bottom of the FIRMS Area API page. Quota: 5000 transactions per 10-minute interval; larger requests (e.g., multi-day range) may count as multiple. See [FIRMS Area API](https://firms.modaps.eosdis.nasa.gov/api/area/).

1. Clone and configure environment 🧩

```bash
git clone https://github.com/LightningK0ala/FirePing.git
cd FirePing
cp .env.example .env
# Edit .env with your NASA FIRMS API key and other secrets
# Example:
# NASA_FIRMS_API_KEY=your_api_key_here
```

2. Start the application 🚀

```bash
make docker-build
# Visit http://localhost:4000
```

That's it! The app and database will start automatically in Docker containers.

3. Run tests ✅

```bash
make docker-test
```

## Alternative: Local Development (without Docker)

If you prefer running Elixir locally:

Prerequisites: Elixir/OTP (1.15.x, OTP 26), Node.js, Docker (for database only)

```bash
make db-up      # Start database only
make setup      # Install deps, create DB, migrate
make app-dev    # Start Phoenix with IEx
make test       # Run tests locally
```

## Common Tasks (Makefile) 🧰

The project provides convenient targets. Below is a practical subset; run `make help` for the full list.

### Docker Development 🐳 (Recommended)

- **Start all services**:

  ```bash
  make docker-up
  ```

- **Build and start all services**:

  ```bash
  make docker-build
  ```

- **Stop all services**:

  ```bash
  make docker-down
  ```

- **View logs**:

  ```bash
  make docker-logs
  ```

- **Run tests in container**:

  ```bash
  make docker-test
  ```

- **Start Phoenix with Docker**:

  ```bash
  make app-docker
  ```

### Local Development 💻

- **Install deps, create and migrate DB**:

  ```bash
  make setup
  ```

- **Run Phoenix with IEx (local)**:

  ```bash
  make app-dev
  ```

- **Format & checks**:
  ```bash
  make format
  make check   # format --check + credo
  ```

### Database 🗃️

- **Start DB only**:

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

- **Run tests (Docker)**:

  ```bash
  make docker-test
  ```

- **Run tests (local)**:

  ```bash
  make test
  ```

- **Watch mode (local)**:
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

## Deployment 🚀

For VPS deployment:

```bash
git clone https://github.com/LightningK0ala/FirePing.git
cd FirePing
cp .env.example .env
# Edit .env with production secrets and NASA API key
make docker-build
```

Your production environment will run the same tested containers from CI.

## Notes 📝

- **Docker-first development**: The entire stack (app + database) runs in containers for consistency.
- **Environment variables**: Edit `.env` file and restart containers with `make docker-down && make docker-up`.
- **CI/CD**: GitHub Actions automatically tests with the same Docker setup.
- For Web Push (VAPID), Email, SMS, and Webhook delivery, ensure the related credentials are configured in `.env`.

## Troubleshooting 🧯

- **Services won't start**: Run `make docker-logs` to see container logs.
- **Port conflicts**: Stop other services on ports 4000 (Phoenix) or 5432 (Postgres).
- **Database issues**: Run `make docker-down && make docker-build` to reset.
- **Missing Docker**: Install Docker and docker-compose from [docker.com](https://docker.com).

## License 📄

Apache-2.0 (or update to your preferred license).
