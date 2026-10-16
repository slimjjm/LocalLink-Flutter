#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WEB_DIR="$ROOT_DIR/build/web"

cd "$ROOT_DIR"
flutter build web --release

required_files=(
  ".well-known/apple-app-site-association"
  ".well-known/assetlinks.json"
  "_headers"
  "_redirects"
  "download/index.html"
  "download/download.css"
  "download/download.js"
  "download/locallink-icon.png"
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

# Cloudflare Pages treats a `functions/` directory in the current working
# directory as Pages Functions. LocalLink's repo-root `functions/` directory is
# Firebase Functions, so deploy from the static Flutter output directory.
npx wrangler pages deploy . --project-name=locallink --cwd "$WEB_DIR"
