# Massage Appointment Booking App

A Flutter app (Android, iOS, web) with a Node.js/Express backend for booking massage appointments.

**Features:** register / log in, browse massage services, pick a date and time to book, view your bookings.

## Project layout

```
backend/    Node.js + Express API (JWT auth, in-memory or MongoDB storage)
frontend/   Flutter app
scripts/    One-click Windows launchers + iPhone preview page
```

## Quick start on Windows

Requirements: [Node.js 18+](https://nodejs.org), [Flutter](https://docs.flutter.dev/get-started/install/windows), Android Studio (for the Android emulator), Chrome.

1. `scripts\setup.bat` – one time: installs packages, generates platform folders, runs all tests.
2. `scripts\run_android.bat` – starts the backend, boots the Pixel emulator and runs the app on it.
3. `scripts\run_iphone_preview.bat` – starts the backend and shows the app inside an iPhone-sized frame in your browser.

> Apple's iPhone Simulator only runs on macOS. On Windows, the iPhone preview is the Flutter **web** build shown at real iPhone dimensions; it's good for checking layout and flows but isn't native iOS. On a Mac, `flutter run -d ios` works as normal.

## Backend

```bash
cd backend
npm install
npm test
npm start          # http://localhost:3000
```

With no configuration it uses in-memory storage and a random JWT secret, so it works with nothing else installed. For persistent data, copy `.env.example` to `.env` and set `MONGO_DB_URL` and `JWT_SECRET` (`python generateSecretKey.py` prints one).

| Method | Path            | Auth | Body                          |
|--------|-----------------|------|-------------------------------|
| GET    | `/health`       |      |                               |
| POST   | `/register`     |      | `username`, `email`, `password` |
| POST   | `/login`        |      | `email`, `password`           |
| GET    | `/services`     |      |                               |
| GET    | `/appointments` | ✓    |                               |
| POST   | `/appointments` | ✓    | `serviceId`, `startsAt` (ISO) |

Authenticated routes take `Authorization: Bearer <token>`.

## Frontend

```bash
cd frontend
flutter pub get
flutter test
flutter run                 # pick a device
```

The app talks to `http://10.0.2.2:3000` on the Android emulator (that's the host PC) and `http://localhost:3000` elsewhere. Override with `--dart-define=API_URL=http://<host>:3000`, e.g. when testing on a physical phone on the same Wi‑Fi.
