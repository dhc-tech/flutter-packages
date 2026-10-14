#!/usr/bin/env bash
# Creates or updates every label in .github/labels.json (name, color,
# description). Labels not listed there are left untouched.
# Requires an authenticated `gh` (GH_TOKEN) and jq.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

jq -c '.[]' .github/labels.json | while read -r label; do
  name="$(jq -r .name <<<"$label")"
  gh label create "$name" \
    --color "$(jq -r .color <<<"$label")" \
    --description "$(jq -r .description <<<"$label")" \
    --force
done
