#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WEB_DIR="$ROOT_DIR/build/web"

cd "$ROOT_DIR"
flutter build web

required_files=(
  ".well-known/apple-app-site-association"
  ".well-known/assetlinks.json"
  "_headers"
  "_redirects"
  "privacy/index.html"
  "terms/index.html"
  "contact/index.html"
  "delete-account/index.html"
  "index.html"
)

for file in "${required_files[@]}"; do
  if [[ ! -f "$WEB_DIR/$file" ]]; then
    echo "Missing required web deploy file: $WEB_DIR/$file" >&2
    exit 1
  fi
done

cd "$WEB_DIR"
npx wrangler pages deploy . --project-name locallink
