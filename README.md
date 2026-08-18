# 📦 Flutter Packages Monorepo

[![CI Pipeline](https://github.com/dhc-tech/flutter-packages/actions/workflows/ci.yml/badge.svg)](https://github.com/dhc-tech/flutter-packages/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](CONTRIBUTING.md)

A centralized monorepo of production-grade Dart & Flutter packages, plugins, and developer toolkits maintained by **[dhc-tech](https://github.com/dhc-tech)**.

---

## 📚 Available Packages

| Package | Version | Description | Status |
|---|---|---|---|
| **[`white_label_kit`](packages/white_label_kit)** | [![white_label_kit](https://img.shields.io/badge/version-0.0.2-green.svg)](packages/white_label_kit/CHANGELOG.md) | Multi-tenant white-label and flavor management toolkit for Flutter applications. | ✅ Stable |
| **[`dig_cli`](packages/dig_cli)** | [![dig_cli](https://img.shields.io/badge/version-1.8.0-green.svg)](packages/dig_cli/CHANGELOG.md) | CLI utility for Flutter code generation, asset path indexing, and project scaffolding. | ✅ Stable |
| **[`apple_sign_in_plugin`](packages/apple_sign_in_plugin)** | [![apple_sign_in_plugin](https://img.shields.io/badge/version-1.2.6-green.svg)](packages/apple_sign_in_plugin/CHANGELOG.md) | Streamlined Sign in with Apple authentication with JWT decoding and token validation. | ✅ Stable |

---

## 🏛️ Monorepo Architecture

```text
flutter-packages/
├── .github/
│   ├── ISSUE_TEMPLATE/            # 📝 Standardized Bug Report & Feature Request templates
│   ├── workflows/
│   │   ├── ci.yml                 # 🔍 Automated static analysis & test matrix across all packages
│   │   └── release.yml            # 🚀 Automated semantic release and artifact publishing
│   └── pull_request_template.md   # 📋 Quality checklist for all PRs
│
├── packages/                      # 📦 Independent, reusable Dart & Flutter packages
│   ├── white_label_kit/           # 🏷️ Multi-tenant white-label CLI & runtime kit
│   │   ├── bin/
│   │   ├── lib/
│   │   ├── test/
│   │   ├── CHANGELOG.md
│   │   ├── README.md
│   │   └── pubspec.yaml
│   └── ...
│
├── LICENSE                        # ⚖️ MIT License
└── README.md                      # 📖 Monorepo documentation
```

---

## 🛠️ Local Development & Testing

### 1. Test All Packages
Run the automated test suite across all packages:

```bash
for pkg in packages/*; do
  if [ -d "$pkg/test" ]; then
    echo "🧪 Running tests in $pkg..."
    (cd "$pkg" && dart test)
  fi
done
```

### 2. Analyze & Lint All Packages
Run static analysis with zero-warning enforcement:

```bash
for pkg in packages/*; do
  if [ -d "$pkg" ] && [ -f "$pkg/pubspec.yaml" ]; then
    echo "🔍 Analyzing $pkg..."
    (cd "$pkg" && dart analyze --fatal-infos)
  fi
done
```

### 3. Verify Code Formatting
```bash
dart format --output=none --set-exit-if-changed packages/
```

---

## ➕ Adding a New Package

1. Create a new package directory under `packages/`:
   ```bash
   dart create -t package-simple packages/<your_package_name>
   ```
2. Include a comprehensive `README.md`, `CHANGELOG.md`, and complete unit tests under `test/`.
3. The CI/CD pipeline will automatically detect, analyze, and test the new package on pull requests and pushes to `main`.

---

## 🤝 Contributing & Pull Requests

1. Fork the repository and create a feature branch (`feature/your-feature-name`).
2. Ensure `dart format`, `dart analyze --fatal-infos`, and all package tests pass.
3. Submit a Pull Request targeting `main`.

---

## 📄 License

This repository and all its packages are open source and licensed under the [MIT License](LICENSE).
