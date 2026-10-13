# the20sspa

**A Roaring Twenties day spa: book your indulgence.**

the20sspa is a Flutter app (Android, iOS, web) with a Node.js/Express booking API. It's styled in black and gold Art Deco: sunbursts, fan emblems, chamfered gold frames, and Limelight, Poiret One and Josefin Sans type.

## What guests can do

- **Become a member / log in**: email and password. Guests stay signed in between launches, can reset a forgotten password with an emailed code, and confirm their email.
- **Browse the treatment menu**: four house signatures, plus the spa's address, hours and contact details.

  | Signature | Treatment | Length | Price |
  |---|---|---|---|
  | The Gatsby | Swedish Massage | 60 min | $80 |
  | The Speakeasy | Deep Tissue Massage | 60 min | $95 |
  | The Jazz Age | Hot Stone Massage | 90 min | $120 |
  | The Charleston | Sports Massage | 45 min | $70 |

- **Reserve**: choose a therapist (or whoever is free), a day and a time. Only times that are really free are offered, and every treatment fits before closing. Guests can add a pressure preference and health notes (injuries, allergies, pregnancy). If a day is full, they can join its waitlist.
- **Bookings**: upcoming and past visits as admission-style tickets. Cancel or reschedule up to 24 hours before, rate a finished visit, or book the same treatment again.
- **Emails**: confirmation with a calendar invite, reminders 24 hours and 2 hours before, and a note when a waitlisted day frees up.
- **Account**: change name or password, confirm email, sign out, or delete the account and its bookings.

## What staff can do

Staff accounts get a **Staff** tab:

- Every booking for a day, with the guest's name, email, pressure and notes
- Mark visits completed or no-show, or cancel them
- Block out a therapist's time (training, breaks, days off)
- Change prices and hide treatments from the menu

When the server runs without a database (local testing), it creates a staff login and prints it in the server window: `admin@the20sspa.com` / `gatsby-staff-1920`.

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

### Testing without real email

With no `SMTP_URL` set, emails are printed in the server window instead of sent, and the app shows one-time codes on screen ("Testing mode: your code is …"). That way, email confirmation and password resets can be tried without a mail server.

## Backend

```bash
cd backend
npm install
npm test           # API tests, plus MongoDB store tests when MONGO_TEST_URL is set
npm run lint
npm start          # http://localhost:3000
```

With no configuration the API uses in-memory storage and a random JWT secret, so nothing else is required. For persistent data, copy `.env.example` to `.env` and set `MONGO_DB_URL` and `JWT_SECRET` (`python generateSecretKey.py` prints one). `.env.example` lists every setting: time zone, opening hours, cancellation window, staff emails, SMTP, CORS and proxy options.

**Production** (`NODE_ENV=production`) refuses to start without `JWT_SECRET` and `MONGO_DB_URL`. To run the API with MongoDB in Docker:

```bash
JWT_SECRET=... ADMIN_PASSWORD=... docker compose up --build
```

**Time zone.** Opening hours and slot times are in the spa's time zone (`SPA_TIMEZONE`, default: the server computer's), so every guest sees the same times wherever their phone is set.

### API

All routes also work under `/v1` (the app uses `/v1`). Authenticated routes take `Authorization: Bearer <token>`. Access tokens last 15 minutes; swap the refresh token at `/auth/refresh` for a new pair.

| Method | Path | Auth | Notes |
|---|---|---|---|
| GET | `/health` | | |
| GET | `/spa` | | Name, address, hours, time zone, cancellation window |
| POST | `/register` | | `username`, `email`, `password` (8+ characters) |
| POST | `/login` | | `email`, `password` |
| POST | `/auth/refresh` | | `refreshToken` |
| POST | `/logout` | ✓ | Voids all of the user's tokens |
| POST | `/password/forgot` | | `email`; emails a 6-digit code |
| POST | `/password/reset` | | `email`, `code`, `newPassword` |
| GET / PATCH / DELETE | `/me` | ✓ | Profile; `PATCH` takes `username`; `DELETE` takes `password` |
| POST | `/me/password` | ✓ | `currentPassword`, `newPassword` |
| POST | `/me/verify-email` | ✓ | `code` (`/me/verify-email/resend` sends a new one) |
| GET | `/services` | | Active treatments |
| GET | `/therapists?serviceId=` | | |
| GET | `/availability?serviceId=&date=YYYY-MM-DD[&therapistId=]` | | Every start time, with `available` |
| GET | `/availability/days?serviceId=[&therapistId=]` | | The booking window, day by day |
| GET | `/appointments?scope=upcoming\|past&limit=&offset=` | ✓ | |
| POST | `/appointments` | ✓ | `serviceId`, `startsAt` (ISO), optional `therapistId`, `notes`, `pressure` |
| PATCH | `/appointments/:id` | ✓ | Reschedule: `startsAt`, optional `therapistId` |
| DELETE | `/appointments/:id` | ✓ | Cancel |
| POST | `/appointments/:id/review` | ✓ | `rating` 1–5, optional `comment` |
| GET | `/appointments/:id/ics` | ✓ | Calendar file |
| GET / POST / DELETE | `/waitlist` | ✓ | `serviceId`, `date` |
| GET | `/admin/appointments?date=` | staff | |
| PATCH | `/admin/appointments/:id` | staff | `status`: `completed`, `no_show`, `cancelled` |
| POST | `/admin/blocks` | staff | `therapistId`, `date` + `time` (or `startsAt`), `durationMinutes`, `reason` |
| GET / PATCH | `/admin/services[/:id]` | staff | `price`, `active`, `description`, … |

## Frontend

```bash
cd frontend
flutter pub get
flutter test
flutter run
```

The app talks to `http://10.0.2.2:3000` on the Android emulator (the host PC) and `http://localhost:3000` elsewhere. Override with `--dart-define=API_URL=https://<host>`; release builds should always use `https`.

Fonts (Limelight, Poiret One, Josefin Sans) are bundled under `frontend/assets/fonts` under the SIL Open Font License.
