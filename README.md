# the20sspa

**A Roaring Twenties day spa: book your indulgence.**

the20sspa is a Flutter app (Android, iOS, web) with a Node.js/Express booking API. It's styled in black and gold Art Deco: sunbursts, fan emblems, chamfered gold frames, and Limelight, Poiret One and Josefin Sans type.

## What guests can do

- **Become a member / log in**: email and password, with validation and clear errors.
- **Browse the treatment menu**: four house signatures, each with a description, duration and price.

  | Signature | Treatment | Length | Price |
  |---|---|---|---|
  | The Gatsby | Swedish Massage | 60 min | $80 |
  | The Speakeasy | Deep Tissue Massage | 60 min | $95 |
  | The Jazz Age | Hot Stone Massage | 90 min | $120 |
  | The Charleston | Sports Massage | 45 min | $70 |

- **Reserve**: pick a date from the next three weeks and an hourly slot between 10 AM and 7 PM. Past slots are struck through. You get a summary card with the total before confirming.
- **Reservations**: every booking appears as an admission-style ticket.

## Project layout

```
backend/    Node.js + Express API (JWT auth, in-memory or MongoDB storage)
frontend/   Flutter app (package: the20sspa)
branding/   Android launcher icons
scripts/    One-click Windows launchers, branding, iPhone preview page
```

## Quick start on Windows

1. `scripts\SETUP_WINDOWS_TOOLS.bat`: first time only. Installs Git, JDK 17, Flutter, the Android SDK and a Pixel emulator (no admin needed).
2. `scripts\setup.bat`: installs packages, generates platform folders, applies branding, runs tests.
3. `scripts\run_android.bat`: starts the server, boots the emulator and runs the app.
4. `scripts\run_iphone_preview.bat`: shows the web build inside an iPhone frame.
5. `scripts\update.bat`: pulls the latest code, re-applies branding and runs all tests.

> Apple's iOS Simulator only runs on macOS. On Windows, the iPhone preview is the Flutter **web** build at real iPhone dimensions. On a Mac, `flutter run -d ios` works as normal.

## Backend

```bash
cd backend
npm install
npm test
npm start          # http://localhost:3000
```

With no configuration the API uses in-memory storage and a random JWT secret, so nothing else is required. For persistent data, copy `.env.example` to `.env` and set `MONGO_DB_URL` and `JWT_SECRET` (`python generateSecretKey.py` prints one).

| Method | Path            | Auth | Body                            |
|--------|-----------------|------|---------------------------------|
| GET    | `/health`       |      |                                 |
| POST   | `/register`     |      | `username`, `email`, `password` |
| POST   | `/login`        |      | `email`, `password`             |
| GET    | `/services`     |      |                                 |
| GET    | `/appointments` | ✓    |                                 |
| POST   | `/appointments` | ✓    | `serviceId`, `startsAt` (ISO)   |

Authenticated routes take `Authorization: Bearer <token>`.

## Frontend

```bash
cd frontend
flutter pub get
flutter test
flutter run
```

The app talks to `http://10.0.2.2:3000` on the Android emulator (the host PC) and `http://localhost:3000` elsewhere. Override with `--dart-define=API_URL=http://<host>:3000`.

Fonts (Limelight, Poiret One, Josefin Sans) are bundled under `frontend/assets/fonts` under the SIL Open Font License.
