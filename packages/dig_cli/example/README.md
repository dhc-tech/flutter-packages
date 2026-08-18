# DIG CLI Example

This directory contains examples and documentation on how to use the DIG CLI to professionalize your Flutter workflow.

## 🚀 Creating a "Proper" Project

To create a new project with all the best practices baked in:

```bash
dg create-project --name my_awesome_app --app-name "Awesome App" --bundle-id com.company.app
```

## 🎨 Asset Generation

Organize your assets into subfolders and generate type-safe constants:

```bash
# Generate constants once
dg asset build

# Watch for changes and auto-generate
dg asset watch
```

## 🏷️ Multi-Platform Renaming

Rename your app and update bundle IDs across all 6 platforms:

```bash
dg rename --name "New App Name" --bundle-id com.new.bundle.id
```

## 🏗️ GetX Module Scaffolding

Scaffold a complete module with View, Controller, and Binding:

```bash
dg create-module login
```

For more details, please refer to the main [README.md](../README.md).
