# Overview

## Project Summary

FirePing is a simple, accessible web application that provides instant fire notifications for user-defined geographic areas. The application leverages NASA's fire detection data to alert users when fires are detected within their specified radius around locations of interest.

## Tech

- Elixir + Phoenix Liveview for services + frontend
- Docker + docker compose for containerization of database
- Database Postgres + PostGIS for application + spatial data
- Phoenix LiveDashboard + AppSignal for monitoring

## Authentication

- Email authentication using OTP (auto-register if email is not registered).
- OTP is a 6-digit numeric code.

## Location Management

- Users can create and manage locations with custom radius settings.
- Locations use GPS coordinates with radius specified in meters.

## Notification Delivery

- Web Push (VAPID)
- Email
- SMS
- Webhook

## Notification Preferences

- Frequency.
- Lifecycle.

## Services

- FireFetch: Fetch fire data from NASA FIRMS API.
- FireNotify: Notify users of fires in locations they have.
