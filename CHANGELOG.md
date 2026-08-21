# Changelog

All notable changes to AttendX are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Dates reflect actual commit history.

## [2026-08-21]

### Added
- New `DeviceEvent` model (`users` app) — an audit log for device enrollment, re-enrollment, admin enable/disable, and blocked mismatch attempts (fingerprint already taken, student already has a device). Previously these either weren't tracked at all or existed only as a rejected API response that left no trace.
- `DeviceEnrollView` now writes a `DeviceEvent` on every code path (first enrollment, re-enrollment, both mismatch-rejection cases) instead of just returning an error response.
- New web admin dashboard at `/dashboard/` (`dashboard` app, previously empty scaffolding), session-authenticated and gated to `role == 'admin'`:
  - **Overview** — attendance totals, modified-record counts, absent↔present flip counts, signature-verified vs. unsigned counts, device counts, mismatch-attempt counts, recent event feed.
  - **Devices** — searchable/filterable list of every enrolled device joined to its student; a "students with no device enrolled" view; per-device detail page with a single Enable/Disable action (always logged) and full history for that device.
  - **Event Log** — every `DeviceEvent`, filterable by type and searchable by roll number/fingerprint.
- Django admin (`/admin/`) also updated in parallel: registered `Device` (with the same Enable/Disable actions and inline history) and a read-only `DeviceEvent` log, plus an `AttendanceRecord` admin with a linked aggregate stats page.

### Security
- `Device.is_active` is now read-only on the Django admin change form — it can only be changed through the logged Enable/Disable actions (dashboard or admin), never by editing the field directly, closing a gap where the audit log could be silently bypassed.
- Disabled delete permission in Django admin on `Device`, `Class`, `Enrollment`, `Session`, and `AttendanceRecord`. Several of these cascade-delete attendance history if removed (`AttendanceRecord.device` and `Session` both use `on_delete=CASCADE`), so this closes a real risk of an admin misclick destroying attendance records in production.
- No device *deletion* exists anywhere (dashboard or Django admin) — only disable/enable. True deletion would require first migrating `AttendanceRecord.device` to `on_delete=SET_NULL`, which hasn't been done.

### Removed
- Removed the dead "New student? Register here" link from the login screen — it pointed at a `/register` route/screen that no longer exists after self-service registration was removed on 2026-08-19.
- Removed the dead admin-login redirect (`role == 'admin'` branch navigating to `/admin_home`) from the login screen — no `/admin_home` route or screen was ever built; admin management now happens through the `/dashboard/` web app, not the mobile app.

## [2026-08-20]

### Fixed
- Student department not displaying correctly on the student side.
- Removed the device-enroll button from the web view of the app (device enrollment is an Android/iOS Keystore/Keychain-bound flow and doesn't make sense on web — the button was a leftover from the browser-view addition).

## [2026-08-19]

### Changed
- Replaced the `QRTokenHistory`-based validity model with a signed, time-limited `scan_token` (Django `TimestampSigner`): validity is now checked live at scan-register time via a new `register-scan/` endpoint, and the token is verified again at `mark/` time. The `QRTokenHistory` model and its table were deleted.
- Scan time is now captured and checked server-side in real time rather than relying on a client-supplied timestamp reconciled against historical QR windows.
- QR code is now hidden in the UI while it's in a refreshing state, avoiding a visible stale/expired code between rotations.
- Added a server-side QR expiry check as a second guard alongside the live token check.
- Optimized device-enrollment detection logic (two follow-up commits refining the same change).
- Restyled the "expected/total present" input dialog and changed alert box button colors (two passes).

### Removed
- Removed the self-service student registration process entirely — account creation is now admin-provisioned only, matching the documented security model. Cleaned up related unused imports afterward.

### Security
- Added rate limiting on the login endpoint.
- Added standard GitHub community files (README/CONTRIBUTING/SECURITY/LICENSE, etc.).

### Fixed
- `DeviceStatusView` / `getDeviceStatus()` — the device fingerprint was never actually transmitted to the server (accepted as a Flutter parameter but not sent on the `GET` request, and read from an empty `request.data` on a bodyless GET on the backend). Converted the endpoint to `POST` with a JSON body so the fingerprint reaches the server, and added a fallthrough response for the "not yet enrolled, no conflicts" case that previously fell through to an unhandled `None` return.
- Student home screen now correctly distinguishes three device states — enrolled, needs re-enrollment (server has a device on record but the local Keystore key is missing, e.g. after a reinstall), and device mismatch (fingerprint registered to a different student) — instead of collapsing all non-enrolled cases into a single generic "Enroll Device" prompt.

## [2026-08-17]

### Added
- Optional "expected/total present" count on session creation; session now auto-stops once the count is reached.
- Error handling for the case where the same physical device is used by a different student mid-session.

### Fixed
- Fixed a navigation issue that occurred on auto session-stop.
- Fixed issues with QR generation (two follow-up commits).
- Optimized live-count updates by removing a `.count()` database query that was previously run on every successful attendance mark.

## [2026-08-14 – 2026-08-15]

### Added
- Added security headers (multiple passes) and CSRF trusted origins.
- Enforced one active device per student at the database level (`is_active` partial unique constraint).

### Fixed
- Fixed QR code validity window, scan-time handling, teacher authorization checks, and WebSocket authentication.
- Removed a hardcoded fallback `SECRET_KEY`, requiring it to come from the environment.
- Debugged and fixed a live-count WebSocket issue (including a temporary print-statement debugging pass).
- Fixed a `QRTokenHistory` scan-lookup issue (superseded by the Aug 19 removal of the model).

### Removed
- Removed dead code left over from the earlier `previous_qr_token` approach.

## [2026-08-09 – 2026-08-12]

### Added
- `daphne` added to `requirements.txt` for ASGI/WebSocket support in production.
- `pillow` added to `requirements.txt` (required by the `qrcode` image generation).

### Changed
- Prepared and deployed the backend for hosting on Render, then migrated deployment to Railway.
- Fixed the deployed Vercel frontend URL and added it to `CORS_ALLOWED_ORIGINS`.

## [2026-07-23 – 2026-07-30]

### Added
- Live attendance updates and student history over Django Channels WebSockets, replacing HTTP polling.
- Search feature on the teacher's attendance review screen.

### Fixed
- Present/absent student ordering on the attendance review screen.
- An auto-login issue, resolved alongside the WebSocket rollout on the history screen.

## [2026-04-02]

### Fixed
- Hardware-level biometric signing error.
- Scan-time capturing logic.

### Removed
- Removed the grace period for the previous QR token (an early precursor to the later `QRTokenHistory`/scan-token rework).

## [2026-03-29]

### Added
- Splash-screen token check that logs the user out automatically once the stored token passes its 30-day expiry.

## [2026-03-25]

### Security
- Enforced hardware-level biometric authentication for signing, blocking PIN/password fallback so only fingerprint or face unlock can authorize a signature.

## [2026-03-22]

### Added
- Browser (web) view of the app.

## [2026-03-19]

### Changed
- Reduced QR code rotation/expiry time to 5 seconds.

## [2026-03-15]

### Added
- iOS support scaffolding (Keychain-backed signing, `AppDelegate` method channel).
- Device mismatch detection and auto-refreshing attendance history.

### Fixed
- App icons — new "AX" monogram icon applied across all platforms.

## [2026-03-14]

### Added
- Auto-login on app start, using stored token verification (added, then re-verified working in a follow-up commit).

### Fixed
- QR scanning time window fixed to exclude the biometric prompt duration from the countdown.
- Attendance status handling: sessions now show "pending" and "modified" states correctly in history, and attendance only finalizes once the teacher explicitly submits.

## [2026-03-13]

### Added
- Re-enrollment feature with hardware ID (device fingerprint) verification.

### Changed
- Renamed the project to AttendX.
- Switched local backend tunneling to a portmap.io URL.

### Fixed
- QR timer sync/latency issue seen on the real server under slow internet conditions.

## [2026-03-11] — Initial commit

### Added
- Initial commit of the AttendX FYP project (Flutter app + Django backend scaffold).

### Removed
- Removed a one-off `generate_icon.py` utility script no longer needed after icon setup.