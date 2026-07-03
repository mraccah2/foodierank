# Contributing to FoodieRank

Thanks for your interest in improving FoodieRank! This guide covers how to get
set up, the conventions we follow, and how to submit changes.

## Getting set up

1. Install the [Flutter SDK](https://docs.flutter.dev/get-started/install) and
   run `flutter doctor` until it's happy.
2. Fork and clone the repo, then `flutter pub get`.
3. Configure your Google Maps / Places API keys — see the
   [README "Configure the app" section](README.md#3-configure-the-app).
4. Install the pre-commit secret scanner (see [Secrets](#secrets) below).

## Development workflow

- Create a branch off `main`: `git checkout -b feature/short-description`.
- Keep changes focused; one logical change per pull request.
- Run the checks below before opening a PR.

### Checks

```bash
flutter analyze          # static analysis (lints in analysis_options.yaml)
dart format .            # formatting
flutter test             # unit/widget tests
```

Please add or update tests under `test/` for behavior changes.

## Coding style

- Follow the lints configured in `analysis_options.yaml`
  (based on `flutter_lints`).
- Format with `dart format` before committing.
- Match the surrounding code — naming, structure, and comment density.
- Keep configuration and secrets out of source: read them through
  `lib/config.dart` (`--dart-define`), never hardcode.

## Secrets

**Never commit API keys, tokens, keystores, or service-account files.**

This repo uses [gitleaks](https://github.com/gitleaks/gitleaks) to catch
secrets both locally and in CI:

```bash
# One-time: install pre-commit and the hook
pip install pre-commit        # or: brew install pre-commit
pre-commit install
```

- Local commits are scanned by the `.pre-commit-config.yaml` hook.
- Every push / PR is scanned by `.github/workflows/secret-scan.yml`.
- Public-by-design client identifiers (e.g. bundle IDs) are allowlisted in
  `.gitleaks.toml`. If you believe a finding is a false positive, discuss it in
  the PR rather than silently allowlisting it.

Runtime keys are injected at build time — see the
[configuration reference](README.md#configuration-reference).

## Commit messages & pull requests

- Write clear, imperative commit messages
  (e.g. `Add cuisine filter chips to list screen`).
- Reference related issues in the PR description.
- Describe what changed and how you tested it. Include screenshots for UI
  changes.
- Make sure CI (analyze, tests, secret-scan) passes.

## Reporting bugs & requesting features

Open a GitHub issue with clear reproduction steps (for bugs) or a description of
the use case (for features). Include your platform, Flutter version
(`flutter --version`), and any relevant logs.

## License

By contributing, you agree that your contributions will be licensed under the
[MIT License](LICENSE).
