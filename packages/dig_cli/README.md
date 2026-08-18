# 🚀 DIG CLI - The Ultimate Flutter Companion

[![pub package](https://img.shields.io/pub/v/dig_cli.svg)](https://pub.dev/packages/dig_cli)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![GitHub](https://img.shields.io/badge/github-repo-181717?logo=github)](https://github.com/Digvijaysinh2204/dig_cli)

**DIG CLI** (`dg`) is a premium, enterprise-grade command-line tool designed for Flutter developers. It automates your daily workflows with an intuitive **Interactive Dashboard** and a powerful set of low-level commands. From rebuilding your entire architecture to generating robust boilerplate code, `dg` is the absolute authority on Flutter project management.

---

## 📑 Table of Contents
1. [📦 Installation & Setup](#1--installation--setup)
2. [⚡ CLI Alias configuration](#-cli-alias-configuration-tips)
3. [💻 MacOS Professional Setup](#-professional-environment-setup-macos)
4. [🪟 Windows Setup](#-windows-setup-powershell)
5. [🐧 Ubuntu / Linux Setup](#-ubuntu--linux-setup-bash)
6. [🖥️ The Interactive Dashboard](#3--the-interactive-dashboard-ui)
7. [🛠️ Full Command Reference](#4--full-command-reference)
8. [🔍 Feature Deep Dive](#5--feature-deep-dive)
9. [🏗️ Architecture Standards](#6--architecture-standards)

---

## 1. 📦 Installation & Setup

### **Requirements:**
- **Dart SDK**: `>=3.0.0`
- **Flutter**: Ensure `flutter` is perfectly configured in your system `PATH`.

### **Standard Installation (Stable)**
To globally activate the stable version of the CLI using Dart:
```bash
dart pub global activate dig_cli
```

### **Bleeding-Edge Installation (GitHub Source)**
If you want direct access to the latest, unreleased features, you can install directly from the GitHub repository source path:
```bash
dart pub global activate -sgit https://github.com/Digvijaysinh2204/dig_cli.git
```

### **Executable Alias (`dg`)**
The `dig_cli` package registers a global alias named **`dg`**. Ensure your global pub cache is embedded in your system's `PATH`. Run this to verify the installation:
```bash
dg --version
```

---

To maximize your speed, we highly recommend adding custom aliases to your shell profile (`~/.zshrc`, `~/.zshenv` or `~/.bash_profile`):

```bash
# Set 'dig' as a main command alias
alias dig='dg'

# Common shortcuts
alias dgm="dg create-module"
alias dgp="dg create-project"
alias dgapk="dg create apk"
alias dgcb="dg clean"
alias dga="dg asset build"
```
After saving, simply run `source ~/.zshrc`. Now you can instantly scaffold a feature by just typing `dgm -n auth`!

---

## 💻 Professional Environment Setup (MacOS)

For a seamless enterprise experience on Mac (M1/M2/M3), ensure your shell environment is strictly configured. We recommend adding these to your `~/.zshenv`:

```bash
# Locale settings
export LANG=en_US.UTF-8
export LANGUAGE=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# Homebrew & Pub Cache
eval "$(/opt/homebrew/bin/brew shellenv)"
export PATH="$PATH:$HOME/.pub-cache/bin"

# Android Studio & Java (Crucial for builds)
export PATH="$PATH:/Applications/Android Studio.app/Contents/MacOS"
export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
export PATH="$JAVA_HOME/bin:$PATH"

# FVM (If using Flutter Version Manager)
export PATH="$PATH:$HOME/fvm/default/bin"
```

---

## 🪟 Windows Setup (PowerShell)

To use `dg` and custom aliases on Windows, add these to your Microsoft.PowerShell_profile.ps1:

```powershell
# Set path for Global Pub Cache
$env:Path += ";$env:USERPROFILE\.pub-cache\bin"

# Custom Aliases
function dgm { dg create-module @args }
function dgp { dg create-project @args }
function dga { dg asset build @args }
```

---

## 🐧 Ubuntu / Linux Setup (Bash)

Add these to your `~/.bashrc`:

```bash
# Path for Global Pub Cache
export PATH="$PATH":"$HOME/.pub-cache/bin"

# Custom Aliases
alias dig='dg'
alias dgm='dg create-module'
alias dgp='dg create-project'
alias dga='dg asset build'
```
Run `source ~/.bashrc` to apply.

---

## 3. 🖥️ The Interactive Dashboard UI

The easiest way to use Dig CLI is to simply launch the visual dashboard setup. Forget writing complex arguments; just type:
```bash
dg
```

**Inside the Dashboard:**
- **`[1] Build & Release`**: Auto-generate APKs, App Bundles, and iOS IPAs with smart timestamping.
- **`[2] Clean & Repair`**: Safely wipe CocoaPods, Xcode caches, Gradle, and `pub-cache`.
- **`[3] Signing & Keys`**: Seamlessly generate SHA1/SHA256 data or automate JKS File setups.
- **`[4] Configuration`**: Fast Asset and Font scaffolding setup.
- **`[5] Project Management`**: Download GetX boilerplates directly from GitHub or rebrand an existing app.

---

## 4. 🛠️ Full Command Reference

If you prefer scripting or CI/CD pipelines, use the headless terminal commands:

| Command Area | Syntax | Description |
|---|---|---|
| **Build System** | `dg create apk` | Compile a Release APK. Optional `-o` (dir) and `-n` (name). |
| | `dg create bundle` | Compile an Android App Bundle (AAB). |
| | `dg ios` | Complete iOS IPA build pipeline. |
| **Maintenance** | `dg clean` | Full framework reset (CocoaPods, Xcode, builds). |
| | `dg pub-cache` | Runs intensive `flutter pub cache repair`. |
| **Keys/Security** | `dg create-jks` | Generate & hook a secure Android keystore cleanly. |
| | `dg sha-keys` | Display your Gradle SHA1/SHA256 outputs cleanly. |
| | `dg hash-key` | Fast Facebook/Google Hash Key generator. |
| **Scaffolding**| `dg create-project` | Clones our enterprise template mapped directly from GitHub. |
| | `dg create-module` | Fully scaffolds a modular GetX setup. |
| **Asset Engine** | `dg asset build` | Generates strict type-safe assets matching `dig.yaml`. |
| | `dg asset watch` | Real-time Daemon analyzing asset injections. |
| **System** | `dg rename` | Renames Android/iOS Display Name & Global Bundle IDs. |
| | `dg zip` | Compress project without garbage files (`.gitignore` safe). |

---

## 5. 🔍 Feature Deep Dive

### **Scaffold an Entire Project**
`dg create-project`
*This command pulls the absolute latest production template from `https://github.com/Digvijaysinh2204/dig_template`, overrides standard Flutter configurations, generates Secure ENV keys natively, handles Android Keystore linking immediately, and integrates GetX logic out of the box.*

### **Scaffold a GetX Module**
```bash
dg create-module --name auth_screen
```
*Creates `AuthScreenView`, `AuthScreenController`, `AuthScreenBinding`, registers them natively into `AppRoute.authScreen`, and auto-exports the module. We parse all internal casing dynamically!*

### **Asset Safety Engine**
```bash
dg asset build
```
*Parses all localized PNG/SVG/TTF graphics and outputs generated paths. You can instantly start writing `SvgPicture.asset(BottomBarSvg.home);` without any fear of naming typos.*

---

## 6. 🏗️ Architecture Standards

By using DIG CLI, you automatically adopt industry-leading architectural norms:
- **Feature-First**: All screens operate inside dedicated `module/` bundles entirely abstracted from external logic.
- **Dependency Injections**: Automated `Binding` linking via routes prevents memory leaks and manages GetX lifetimes natively.
- **Secure Handling**: Debug logic separates `key.properties` from Git environments automatically.

---

## 👨‍💻 Author & License

- **Author**: [Digvijaysinh Chauhan](https://github.com/Digvijaysinh2204)
- **License**: [MIT](LICENSE)

> *"Efficiency through Automation."*

