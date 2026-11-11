#!/usr/bin/env bash
set -euo pipefail

EMULATOR_HOST="${EMULATOR_HOST:-android-emulator}"
ADB_PORT="${ADB_PORT:-5555}"

cd /app

echo "Connecting ADB to ${EMULATOR_HOST}:${ADB_PORT} ..."
until adb connect "${EMULATOR_HOST}:${ADB_PORT}" 2>&1 | grep -q "connected to"; do
  sleep 3
done

echo "Waiting for the emulator to finish booting ..."
adb wait-for-device
until [ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ]; do
  sleep 3
done
echo "Emulator booted."

if [ ! -f .env.json ]; then
  echo "Creating .env.json from the example. Point URLs at 10.0.2.2."
  cp .env.json.example .env.json
fi

flutter pub get

DEVICE_SERIAL="$(adb devices | awk 'NR > 1 && $2 == "device" { print $1; exit }')"
echo "Launching FieldLog on ${DEVICE_SERIAL} ..."
exec flutter run --dart-define-from-file=.env.json -d "${DEVICE_SERIAL}"
