# FirePing Progress

## Thu 7 Aug 2025

### Completed

#### Infrastructure

- Phoenix 1.7 + LiveView 1.1 + PostGIS docker setup
- Makefile for development workflow
- UUIDv4 primary keys

#### Authentication

- User model with OTP authentication
- Email validation and verification flow
- `live_session` auth with `on_mount` hooks
- Auto-dismissing flash messages
- Complete unit test coverage

#### UI Components

- Login page with email input
- OTP verification page
- Dashboard with user info
- Dashboard restyled with Tailwind (clean top nav; logout icon on right)
- Simplified stats (removed Verified/Member Since cards); removed Next Steps panel
- Session management

#### Locations

- Location model with PostGIS geometry + spatial queries
- `within_radius/3` for fire proximity detection
- Complete validation + test coverage
- Interactive map with location markers, radius circles, and geolocation API
- Fixed map loading issues and zoom behavior
- TDD: Inline edit for locations (create/update/delete flows covered by tests)
- Map data now refreshes after add/edit/delete (locations + nearby fires)

#### Fire Data Integration

- Fire model for NASA VIIRS satellite data with PostGIS geometry
- Optimized spatial queries with bounding box pre-filtering + composite indexes.
- Fire visualization on map with intensity-based sizing and confidence color coding
- FireFetch service (NASA API integration) with Oban cron job

#### Testing & DX

- Added `lazy_html` test dep for LiveView tests
- Refactored LiveView to DRY reload of locations + fires

#### Admin & Monitoring

- Admin user management with mix tasks + Makefile commands
- LiveDashboard at `/admin/dashboard` (system metrics, processes, Ecto)
- Oban + Oban Web integration at `/admin/oban` (job monitoring)
- Admin authentication with `require_admin` hook

### Pending

- FireFetch service (NASA API integration)
- FireNotify service (user alerts)
