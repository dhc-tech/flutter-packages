# Copilot Instructions

Follow [AGENTS.md](../AGENTS.md) for layout, commands and rules, and
[CONTRIBUTING.md](../CONTRIBUTING.md) for the contribution process.

Key points:

- This is a pub workspace: run `flutter pub get` at the repo root, never add
  `dependency_overrides`.
- `dart analyze --fatal-infos` must report zero issues.
- Public API needs `///` docs; new behavior needs tests under `test/`.
- Package changes need a version bump and `CHANGELOG.md` entry.
- Never hardcode credentials or proprietary names; use neutral identifiers.
