#!/usr/bin/env sh
set -eu

PROJECT_ROOT="${SRCROOT}/.."
STRIPE_CONFIG="${SRCROOT}/Flutter/StripeLive.xcconfig"
FLUTTER_BACKEND="${FLUTTER_ROOT}/packages/flutter_tools/bin/xcode_backend.sh"

trim() {
  printf "%s" "$1" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

read_xcconfig_value() {
  key="$1"
  if [ ! -f "$STRIPE_CONFIG" ]; then
    printf ""
    return
  fi

  grep -E "^[[:space:]]*${key}[[:space:]]*=" "$STRIPE_CONFIG" \
    | tail -n 1 \
    | sed "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*//;s/[[:space:]]*$//"
}

encode_define() {
  printf "%s" "$1" | base64 | tr -d '\n'
}

contains_encoded_key() {
  case "${DART_DEFINES:-}" in
    *"U1RSSVBFX1BVQkxJU0hBQkxFX0tFWT0"*) return 0 ;;
    *) return 1 ;;
  esac
}

if ! contains_encoded_key; then
  stripe_publishable_key="$(trim "$(read_xcconfig_value STRIPE_PUBLISHABLE_KEY)")"
  stripe_mode="$(trim "$(read_xcconfig_value STRIPE_MODE)")"

  if [ ! -f "$STRIPE_CONFIG" ]; then
    echo "error: Missing ${STRIPE_CONFIG}. Copy ios/Flutter/StripeLive.xcconfig.example to ios/Flutter/StripeLive.xcconfig and set the existing pk_live publishable key." >&2
    exit 1
  fi

  case "$stripe_publishable_key" in
    sk_*)
      echo "error: Do not put a Stripe secret key in the Flutter app. STRIPE_PUBLISHABLE_KEY must start with pk_live_." >&2
      exit 1
      ;;
    *REPLACE*)
      echo "error: Replace the placeholder in ${STRIPE_CONFIG} with the existing live Stripe publishable key." >&2
      exit 1
      ;;
    pk_live_*) ;;
    *)
      echo "error: STRIPE_PUBLISHABLE_KEY must be the existing live publishable key and start with pk_live_." >&2
      exit 1
      ;;
  esac

  if [ "$stripe_mode" != "live" ]; then
    echo "error: STRIPE_MODE must be live for this LocalLink iOS build." >&2
    exit 1
  fi

  stripe_defines="$(encode_define "STRIPE_PUBLISHABLE_KEY=${stripe_publishable_key}"),$(encode_define "STRIPE_MODE=live")"

  if [ "${CONFIGURATION:-}" = "Debug" ]; then
    stripe_defines="${stripe_defines},$(encode_define "STRIPE_ALLOW_LIVE_IN_DEBUG=true")"
  fi

  if [ -n "${DART_DEFINES:-}" ]; then
    export DART_DEFINES="${DART_DEFINES},${stripe_defines}"
  else
    export DART_DEFINES="${stripe_defines}"
  fi
fi

cd "$PROJECT_ROOT"
/bin/sh "$FLUTTER_BACKEND" build
