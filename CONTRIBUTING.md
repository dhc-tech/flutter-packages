# Contributing to Flutter Packages

We welcome contributions to Flutter Packages!

## Getting Started

1. **Fork the repository** on GitHub.
2. **Clone your fork** locally:
   ```bash
   git clone https://github.com/<your-username>/flutter-packages.git
   cd flutter-packages
   ```
3. **Bootstrap the workspace with Melos**:
   ```bash
   dart pub global activate melos
   melos bootstrap
   ```

## Development Workflow

### 1. Code Formatting
All Dart files must be formatted with the official Dart formatter:
```bash
melos run format:fix
```

### 2. Static Analysis
All code must pass static analysis with zero warnings and fatal infos enforced:
```bash
melos run analyze
```

### 3. Automated Tests
Every feature or bug fix must include comprehensive unit/widget tests:
```bash
melos run test
```

### 4. Pub.dev Pana Health Check
Verify that the package maintains maximum Pub.dev points (160/160):
```bash
melos run pana
```

## Pull Request Guidelines

1. **Clear Title & Description:** Use semantic commit messages (e.g. `feat(white_label_kit): add new config option` or `fix(apple_sign_in_plugin): resolve web token issue`).
2. **Package Labeling:** Pull requests are automatically categorized by package paths (`p: white_label_kit`, `p: dig_cli`, `p: apple_sign_in_plugin`).
3. **Automated Merging:** Add the `autosubmit` label once your PR is ready, approved, and CI checks are green.
4. **AI Review:** Google Gemini AI automatically performs initial review on your PR diff to assist the maintainers.
