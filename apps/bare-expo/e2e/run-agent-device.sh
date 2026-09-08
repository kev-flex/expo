#!/usr/bin/env bash
# Run the agent-device e2e scripts for one platform.
#
#   ./run-agent-device.sh ios "iPhone 17 Pro (26.4)" [artifacts-dir] [script-or-dir...]
#   ./run-agent-device.sh android "Pixel 8a big"
#   ./run-agent-device.sh ios auto            # first booted simulator or emulator
#
# Cross-platform scripts have no `context platform` header. Platform-specific scripts end
# in `.ios.ad` or `.android.ad`. The app id reaches scripts as ${APP_ID}.
set -euo pipefail

platform="${1:?platform (ios|android)}"
device="${2:?device name as listed by 'agent-device devices', or auto}"
artifacts="${3:-$(mktemp -d)/agent-device-artifacts}"
shift 3 2>/dev/null || shift $#

cd "$(dirname "$0")"

case "$platform" in
  ios) app_id="dev.expo.Payments"; other="android"; kind="ios simulator" ;;
  android) app_id="dev.expo.payments"; other="ios"; kind="android emulator" ;;
  *) echo "unknown platform: $platform" >&2; exit 2 ;;
esac

targets=("$@")
if [ ${#targets[@]} -eq 0 ]; then
  targets=(.)
fi
scripts=()
while IFS= read -r file; do
  scripts+=("$file")
done < <(find "${targets[@]}" -name '*.ad' -not -name "*.${other}.ad" -not -path '*/.agent-device/*' | sort)
if [ ${#scripts[@]} -eq 0 ]; then
  echo "no .ad scripts found under: ${targets[*]}" >&2
  exit 2
fi

# A daemon left by an interactive session holds the device lease and makes `test` fail.
agent-device daemon stop --clean >/dev/null 2>&1 || true
pkill -f 'agent-device' >/dev/null 2>&1 || true

if [ "$device" = "auto" ]; then
  # `agent-device devices` prints lines like: iPhone 17 Pro (26.4) (ios simulator target=mobile) booted=true
  device="$(agent-device devices --platform "$platform" 2>/dev/null \
    | grep "($kind " | grep 'booted=true' | head -1 | sed "s/ ($kind .*//")"
  if [ -z "$device" ]; then
    echo "no booted $kind found; boot one or pass a device name" >&2
    exit 2
  fi
fi

mkdir -p "$artifacts"
echo "agent-device test: ${#scripts[@]} script(s) on $platform / $device"
agent-device test "${scripts[@]}" \
  --device "$device" \
  -e "APP_ID=$app_id" \
  --reporter default \
  --reporter "junit:$artifacts/junit.xml" \
  --artifacts-dir "$artifacts" \
  2>&1 | tee "$artifacts/run.log"
