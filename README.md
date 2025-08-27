# FirePing 🔥🛰️

**Open Source Fire Intelligence Platform**

Get instant alerts when fires threaten places you care about. Monitor any location worldwide with satellite-powered detection and customizable notifications.

## Features ✨

- **🔐 Simple Authentication**: Email-based login with magic links
- **📍 Location Monitoring**: Add locations with custom radius (home, vacation property, etc.)
- **🗺️ Interactive Map**: Real-time fire visualization with NASA satellite data
- **🔔 Smart Notifications**: Web push, email, and webhook alerts
- **🔥 Fire Intelligence**: Automated clustering and incident tracking
- **⚡ Global Coverage**: Monitor anywhere satellites can see

### Tech Stack 🧰

- 💧 **Elixir + Phoenix LiveView** (app + frontend)
- 🗄️ **PostgreSQL + PostGIS** (primary + spatial data)
- 🐳 **Docker + docker-compose** (full containerized development)
- 📊 **Prometheus + Grafana** (monitoring)

## Quick Start 🚀

**Prerequisites:**

- Docker and docker-compose
- NASA FIRMS API key ([get one here](https://firms.modaps.eosdis.nasa.gov/api/area/))

**1. Clone and setup:**

```bash
git clone https://github.com/LightningK0ala/FirePing.git
cd FirePing
cp .env.example .env
# Edit .env with your NASA FIRMS API key
```

**2. Run:**

```bash
make build
# Visit http://localhost:4000
```

**3. Test:**

```bash
make test
```

## Common Commands 🧰

```bash
make help        # Show all available commands
make up          # Start services
make down        # Stop services
make logs        # View logs
make dev         # Start with live reload
make shell       # Interactive shell
make iex         # Elixir console
make format      # Format code
```

## Fire Data Commands 🔥

```bash
make fire-fetch           # Fetch latest fires from NASA
make fire-fetch days=3    # Fetch last 3 days
make fire-count          # Show fire statistics
make import-fires        # Import sample data
```

## Development 🛠️

The app uses Docker for consistent development. All services run in containers with hot reloading enabled.

**Key directories:**

- `app/` - Phoenix application
- `spec/` - Documentation
- `scripts/` - Utility scripts

## License 📄

Apache-2.0
