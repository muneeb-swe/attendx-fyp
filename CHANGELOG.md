# Changelog

All notable changes to AttendX are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Dates below are placeholders — update them to match your actual commit/release dates before publishing.

## [Unreleased]

### Fixed
- `DeviceStatusView` / `getDeviceStatus()` — the device fingerprint was never actually transmitted to the server (accepted as a Flutter parameter but not sent on the `GET` request, and read from an empty `request.data` on a bodyless GET on the backend). Converted the endpoint to `POST` with a JSON body so the fingerprint reaches the server, and added a fallthrough response for the "not yet enrolled, no conflicts" case that previously fell through to an unhandled `None` return.
- Student home screen now correctly distinguishes three device states — enrolled, needs re-enrollment (server has a device on record but the local Keystore key is missing, e.g. after a reinstall), and device mismatch (fingerprint registered to a different student) — instead of collapsing all non-enrolled cases into a single generic "Enroll Device" prompt.

## [Recorded history]

Reconstructed from development notes; consolidate into dated releases as appropriate.

### Backend (`attendance_system`)
- Added `QRTokenHistory` model to track each rotated QR token's validity window, replacing an earlier `previous_qr_token`-based approach, to prevent replay of expired tokens.
- Implemented hardware-signature verification for attendance marking (RSA PKCS1v15 + SHA-256), supporting both PEM (for manual/Postman testing) and DER (Android Keystore) public key formats.
- Added atomic, conditional `present_count` increments (`UPDATE ... WHERE ... RETURNING`) to safely enforce `expected_count` caps under concurrent scans, with automatic session stop when the cap is reached.
- Added device enrollment constraints: one active device per student, one active student per device fingerprint, with a defined re-enrollment path when the same student re-registers the same physical device.
- Added real-time attendance updates and history notifications over Django Channels (WebSocket group sends on mark, submit, and discard).
- Added manual attendance override by teachers (`EditAttendanceView`), with modification flagged and visible to students rather than silently overwritten.
- Added session lifecycle handling: stop (auto-marks unmarked enrolled students absent), submit (locks the session), discard (removes an unsubmitted session and notifies affected students).

### Mobile app (`attendance_app`)
- Implemented Android Keystore-backed key generation and signing via a native `MethodChannel`, keeping private keys off the Dart/application layer entirely.
- Implemented QR scanning flow with live biometric prompt integrated into the signing step.
- Added splash-screen auto-login via stored token verification.
- Added device enrollment screen and student home screen device-status handling (enrolled / needs re-enrollment / mismatch).
- Added attendance history and session review screens for students and teachers respectively.
- Scaffolded iOS support (Keychain helper, `AppDelegate` method channel) alongside the primary Android implementation.
- Configured backend tunneling for local development/testing via portmap.io prior to production deployment.

### Infrastructure
- Deployed backend to Railway with ASGI (Daphne) for WebSocket support.
