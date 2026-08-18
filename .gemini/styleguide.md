# DHC Tech Packages Engineering & Style Guide

## Introduction

This style guide outlines the engineering conventions and quality standards for contributions across all packages in this repository.

## Best Practices

- **Strict Type Safety:** Code must pass `dart analyze --fatal-infos` / `flutter analyze --fatal-infos` with zero warnings.
- **Tested Code:** Every feature or bugfix must be accompanied by comprehensive tests under `test/`.
- **Zero Proprietary Data:** Never hardcode sensitive brand names, private bundle identifiers, or credentials. Always use neutral test values (`com.example.acme`, `Acme App`).
- **Pub.dev Standards:** Packages must achieve maximum Pana points (160/160).

## Review Agent Guidelines

When providing a code review summary, the review agent must adhere to the following principles:
- **Be Objective:** Focus on a neutral, descriptive summary of the changes without subjective fluff.
- **Use Code as the Source of Truth:** Base all summaries strictly on the code diff.
- **Be Concise:** Generate summaries that are brief, precise, and easily actionable.
