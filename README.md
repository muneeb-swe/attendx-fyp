# AttendX

AttendX is a biometric-secured, QR-based attendance system built as a Final Year Project. It pairs a Flutter mobile app with a Django REST backend to make attendance fraud (buddy punching, screenshotted QR codes, replayed scans) significantly harder than a plain QR or roll-call system.

## How it works

1. A teacher starts a session for a class. The server generates a QR code encoding `session_id:qr_token`.
2. The QR code **rotates every 5 seconds** — a scan is only accepted if it matches the session's current live token, checked server-side at the moment of scanning.
3. A student scans the QR with the app. The app immediately registers the scan with the server, which validates the token is still current and returns a short-lived, signed `scan_token`.
4. The student then completes a biometric prompt (fingerprint/face) tied to a hardware-backed key pair stored in the **Android Keystore** — the private key never leaves the device. The app signs `session_id:qr_token` with that hardware key.
5. The app sends the `scan_token` and signature to the server. The server verifies the signature against the student's registered public key, confirms the scan token hasn't expired, confirms the student is enrolled in the class, and marks attendance.
6. Teachers see attendance update in real time over WebSockets (Django Channels), can manually override individual records, and finally submit/lock the session.

## Why hardware-bound keys

Each student may only register **one active device**, and each physical device may only be bound to **one active student account** (enforced via database constraints). Because the private signing key is generated inside the Android Keystore and requires a live biometric prompt to use, a signature can't be produced without the registered phone being physically present and its owner authenticating in that moment. This is meant to raise the cost of proxy attendance, not to claim it's mathematically impossible — see [SECURITY.md](SECURITY.md) for the honest limitations.

## Tech stack

**Backend** (`attendance_system/`)
- Django 5.2 + Django REST Framework
- Django Channels + Daphne (WebSockets, ASGI)
- SimpleJWT (access/refresh token auth)
- PostgreSQL in production (`psycopg2-binary`, `dj-database-url`), SQLite for local dev
- `cryptography` for RSA signature verification (PKCS1v15 + SHA-256)
- `qrcode` + `pillow` for QR image generation

**Mobile app** (`attendance_app/`)
- Flutter
- `mobile_scanner` — QR scanning
- `local_auth` — biometric prompts
- `device_info_plus` — device fingerprinting
- `flutter_secure_storage` — token storage
- `web_socket_channel` — live session updates
- Native Android Keystore integration via `MethodChannel` for RSA key generation and signing (private key never touches Dart/application code)

## Admin dashboard

A separate web dashboard lives at `/dashboard/` (the `dashboard` app), gated to accounts with `role == 'admin'` and authenticated via Django sessions — independent from the Flutter app's JWT auth and from Django's built-in `/admin/`.

- **Overview** — attendance totals, modified-record counts, absent↔present flip counts, and a "present but no signature" count (records currently marked present with no backing signature — meaning they were set that way by a teacher's manual edit, not a real scan).
- **Classes → Sessions → per-student records** — the main transparency tool. Pick a class, pick a day/session, and see every student's *original* status (what their device actually reported), their signature if one exists (expandable — this is the cryptographic proof they scanned), and their *current* status with a flag if a teacher changed it afterward. This is what answers a dispute like "I marked attendance and the teacher changed it to absent" — the original signed record stays visible regardless of the current status.
- **Devices** — every enrolled device joined to its student, searchable/filterable, plus a "students with no device enrolled" view. Enable/disable a device from its detail page (always logged, never a silent field edit).
- **Event Log** — every device enrollment, re-enrollment, admin enable/disable, and blocked mismatch attempt (e.g. someone trying to enroll a fingerprint already bound to another student), backed by a `DeviceEvent` audit model.

Device *deletion* is intentionally not exposed anywhere (dashboard or Django admin) — `AttendanceRecord.device` uses `on_delete=CASCADE`, so deleting a `Device` row would delete the attendance history signed with it. Disable/enable is the only lifecycle action available.

## Project structure

```
attendx-fyp/
├── attendance_system/       # Django backend
│   ├── attendance/          # Sessions, QR tokens, attendance records
│   ├── users/                # Auth, students, teachers, device enrollment, device event log
│   ├── dashboard/            # Admin web dashboard (session-authenticated, role == 'admin')
│   └── attendance_system/    # Project settings, ASGI/WSGI, routing
└── attendance_app/           # Flutter app
    ├── lib/screens/           # UI screens (login, QR display, scan, history, enrollment)
    └── lib/services/          # API client, Keystore/crypto bridge
```

## API overview

Base path: `/api/`

**Auth & devices** (`/api/auth/`)
| Endpoint | Method | Description |
|---|---|---|
| `login/` | POST | Authenticate, returns JWT pair |
| `device/enroll/` | POST | Register (or re-register) a device's public key |
| `device/status/` | POST | Check enrollment status / mismatch for this device |
| `verify/` | GET | Validate an access token |

**Attendance** (`/api/attendance/`)
| Endpoint | Method | Description |
|---|---|---|
| `generate-qr/` | POST | Teacher starts a session, gets first QR |
| `session/<id>/refresh-qr/` | POST | Rotates the QR token (called every 5s) |
| `register-scan/` | POST | Student registers a scan against the current QR token, receives a short-lived signed scan token |
| `session/<id>/stop/` | POST | Stops the session, marks remaining students absent |
| `session/<id>/attendance/` | GET | Live roster for a session |
| `record/<id>/edit/` | PATCH | Teacher manual override of a record |
| `session/<id>/submit/` | POST | Locks attendance for the session |
| `mark/` | POST | Student submits signed scan token + signature to mark present |
| `teacher/classes/` | GET | Classes owned by the logged-in teacher |
| `student/history/` | GET | Logged-in student's attendance history |
| `session/<id>/discard/` | DELETE | Discards an unsubmitted session |

> Accounts are admin-provisioned, not self-service — there is no public registration endpoint.

## Getting started

### Backend

```bash
cd attendance_system
python -m venv venv
source venv/bin/activate      # Windows: venv\Scripts\activate
pip install -r requirements.txt
python manage.py migrate
python manage.py runserver
```

For local development, `DATABASE_URL` and other environment variables are read via `dj-database-url` / standard Django settings — configure a `.env` or export them before running. WebSocket support requires an ASGI server (`daphne`), which is already listed in `requirements.txt`.

### Running tests

```bash
cd attendance_system
DEBUG=True SECRET_KEY="any-value-for-testing" python manage.py test \
  users attendance dashboard \
  --settings=attendance_system.test_local_settings
```

80 tests across `users/`, `attendance/`, and `dashboard/` — the `attendance` suite runs the full generate-QR → scan → sign → mark flow with real RSA signing, not mocked.

### Mobile app

```bash
cd attendance_app
flutter pub get
flutter run
```

Update the `baseUrl` constant in `lib/services/api_service.dart` to point at your backend before running.

> Android Keystore signing requires a physical Android device or an emulator with a secure lock screen configured — biometric/keystore APIs will not behave correctly on unsupported emulators.

## Status

This project was developed as a Final Year Project and is under active iteration. See [CHANGELOG.md](CHANGELOG.md) for recent changes and [SECURITY.md](SECURITY.md) for known limitations and how to report issues.

## License

See [LICENSE](LICENSE).