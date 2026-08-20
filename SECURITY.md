# Security

AttendX was built as a Final Year Project to explore hardware-bound biometric attendance verification. This document describes the threat model, what the system does and does not protect against, and how to report issues. It intentionally avoids overstating what the design guarantees.

## Reporting a vulnerability

This is an academic project, not a production service handling real institutional data at scale. If you find a security issue, please open a GitHub issue on this repository, or contact the maintainer directly if the issue involves a live deployment (see repository owner profile for contact details). Please avoid publicly disclosing details that could be used to defeat attendance verification on an active deployment until it's been addressed.

## What the system protects against

- **Casual QR sharing / screenshotting**: QR tokens rotate every 5 seconds, and a scan is only accepted if it matches the session's current live token at the moment it's registered with the server. A screenshotted or forwarded QR code is very likely to be expired by the time it's used elsewhere.
- **Marking attendance without the registered device**: Attendance requires an RSA signature produced by a key generated inside the Android Keystore (`PURPOSE_SIGN`, `setUserAuthenticationRequired(true)`). The private key is non-exportable and never leaves the device; signing operations require a fresh biometric check at the OS level.
- **Forged or self-generated signatures**: A request submitted with a fabricated signature (e.g. bypassing the app entirely and calling the API directly with a random key) will always fail verification in `MarkAttendanceView`, since the server checks the signature against the specific public key on file for that student's enrolled device.
- **One account, one device (and vice versa)**: Database-level uniqueness constraints ensure a student can have only one active enrolled device, and a physical device fingerprint can only be actively bound to one student account at a time.
- **Replayed or stale scans**: A scan is validated live against the session's current QR token at registration time (`register-scan/`), which issues a short-lived, signed `scan_token` (max age 180 seconds). That token — not just "is the session still open" — is what's checked again when attendance is actually marked, so a token can't be replayed after it expires or against a different session.
- **Editing attendance after the fact, invisibly**: Manual teacher overrides are flagged (`is_modified`) and visible to students in their history rather than silently overwriting the original record.
- **Credential brute-forcing on login**: `/api/auth/login/` is throttled to 5 requests/minute per IP address (`ScopedRateThrottle`, DRF). This doesn't make password guessing impossible, but it makes scripted dictionary attacks impractically slow.
- **Scripted request flooding against attendance marking**: `/api/attendance/mark/` is throttled to 5 requests/minute per authenticated user. This doesn't (and can't) stop a legitimate account from *attempting* fabricated requests, but it caps how much server work (DB queries, RSA verification attempts) one account can trigger per minute, limiting the endpoint's use as a resource-exhaustion vector.

## Known limitations

- **No self-service or admin UI to release a lost device's binding.** If a student's phone is genuinely lost, broken, or replaced, `DeviceEnrollView` correctly rejects the new device (a different physical device fingerprint than the one on record — see `Device.device_fingerprint`). Re-enrollment on the *same* physical device after a reinstall is safe and self-service (the fingerprint still matches, so the app correctly shows "Re-enroll Device" and the server updates the stored public key). But recovering from an actually lost device currently requires a maintainer to manually deactivate the old `Device` row via Django admin or a DB shell — there's no in-app flow for this yet.
- **Device fingerprinting relies on OS-reported identifiers** (`device_info_plus`, using brand/model/Android ID). These identifiers are not cryptographically attested and are used for enrollment bookkeeping (one device per student) rather than as a security boundary in their own right — see "Planned hardening" below.
- **First-time device enrollment trusts the authenticated session with no additional device attestation.** Any request with valid login credentials and no prior enrolled device can register a public key as that student's device, without proof the key was generated in genuine secure hardware. Once a device is enrolled, re-binding a *different* fingerprint to that account is blocked (see above), so this trust window applies only at initial enrollment.
- **This has not undergone independent security review or penetration testing.** It should be treated as a research/academic prototype, not as a hardened system ready for high-stakes institutional deployment without further hardening.

## Planned hardening

- **Android Key Attestation** on device enrollment, to cryptographically verify that an enrolled public key was genuinely generated inside tamper-resistant hardware (TEE/StrongBox) rather than software, closing the first-enrollment trust gap described above.
- Proximity/liveness verification to reduce reliance on QR possession alone as proof of physical presence.

## Design notes for reviewers

- Signatures are verified using RSA PKCS1v15 with SHA-256 over the exact string `"{session_id}:{qr_token}"`.
- QR token validity is checked live, server-side, at scan-registration time (`register-scan/`) — the request must present the session's current `qr_token` before it's accepted. A successful check issues a signed, time-limited `scan_token` (Django `TimestampSigner`, 180-second max age), which is unsealed and re-checked when attendance is actually marked (`mark/`). The session's live `is_active` state and signature validity are the binding server-side checks at that final step.
- Attendance-count limits (`expected_count`) are enforced with an atomic, conditional `UPDATE ... RETURNING` query to avoid race conditions when many students scan in quick succession.
- Account creation is administrator-provisioned, not self-service, removing open account-creation abuse as a concern.