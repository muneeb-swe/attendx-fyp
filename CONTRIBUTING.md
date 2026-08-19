# Contributing

AttendX started as a Final Year Project, developed by a small team. It isn't currently set up as a large open-source project with a formal review process, but contributions, bug reports, and suggestions are welcome.

## Reporting bugs / suggesting features

Please open a GitHub issue with:
- What you expected to happen vs. what actually happened
- Steps to reproduce (for bugs)
- Whether the issue is in the Flutter app (`attendance_app/`) or the Django backend (`attendance_system/`)

For security-related issues, please see [SECURITY.md](SECURITY.md) instead of opening a public issue.

## Development setup

See the "Getting started" section in [README.md](README.md) for backend and mobile app setup instructions.

## Pull requests

1. Fork the repo and create a branch from `main` (e.g. `fix/device-status-endpoint`).
2. Keep changes focused — one logical fix or feature per PR.
3. For backend changes, include/update Django migrations if models change (`python manage.py makemigrations`).
4. For Flutter changes, run `flutter analyze` before opening the PR.
5. Describe what changed and why in the PR description; reference any related issue.

## Code style

- Python: follow standard Django/PEP 8 conventions used elsewhere in `attendance_system/`.
- Dart/Flutter: follow the lint rules already configured in `analysis_options.yaml`.

No formal CI is currently configured — please test changes manually against both the backend and the app before submitting.
