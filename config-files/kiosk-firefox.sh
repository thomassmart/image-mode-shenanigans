#!/usr/bin/env bash
set -euo pipefail

UID_NUM="$(id -u)"
HOME_DIR="${HOME:-/var/home/kiosk}"
if [ ! -d "${HOME_DIR}" ]; then
  HOME_DIR="/home/kiosk"
fi
if [ ! -d "${HOME_DIR}" ]; then
  HOME_DIR="/tmp/kiosk-home-${UID_NUM}"
  install -d -m 700 "${HOME_DIR}"
fi

LOG_FILE="${HOME_DIR}/kiosk-session.log"
if ! touch "${LOG_FILE}" 2>/dev/null; then
  LOG_FILE="/tmp/kiosk-session-${UID_NUM}.log"
fi

URL="${KIOSK_URL:-http://127.0.0.1:8080/}"

exec >>"${LOG_FILE}" 2>&1

export HOME="${HOME_DIR}"
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-${HOME_DIR}/.config}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-${HOME_DIR}/.cache}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-${HOME_DIR}/.local/share}"

KWRITECONFIG_BIN=""
for candidate in kwriteconfig6 kwriteconfig5 kwriteconfig; do
  if command -v "${candidate}" >/dev/null 2>&1; then
    KWRITECONFIG_BIN="${candidate}"
    break
  fi
done

QDBUS_BIN=""
for candidate in qdbus6 qdbus-qt6 qdbus5 qdbus; do
  if command -v "${candidate}" >/dev/null 2>&1; then
    QDBUS_BIN="${candidate}"
    break
  fi
done

if [ -n "${KWRITECONFIG_BIN}" ]; then
  "${KWRITECONFIG_BIN}" --file "${XDG_CONFIG_HOME}/kscreenlockerrc" --group Daemon --key Autolock false || true
  "${KWRITECONFIG_BIN}" --file "${XDG_CONFIG_HOME}/kscreenlockerrc" --group Daemon --key LockOnResume false || true
  "${KWRITECONFIG_BIN}" --file "${XDG_CONFIG_HOME}/kscreenlockerrc" --group Daemon --key Timeout 0 || true

  for profile in AC Battery LowBattery; do
    "${KWRITECONFIG_BIN}" --file "${XDG_CONFIG_HOME}/powermanagementprofilesrc" --group "${profile}" --group DPMSControl --key idleTime 0 || true
    "${KWRITECONFIG_BIN}" --file "${XDG_CONFIG_HOME}/powermanagementprofilesrc" --group "${profile}" --group DPMSControl --key lockBeforeTurnOff 0 || true
    "${KWRITECONFIG_BIN}" --file "${XDG_CONFIG_HOME}/powermanagementprofilesrc" --group "${profile}" --group DimDisplay --key idleTime 0 || true
  done
fi

xset s off || true
xset -dpms || true
xset s noblank || true

if [ -n "${QDBUS_BIN}" ]; then
  "${QDBUS_BIN}" org.freedesktop.PowerManagement /org/kde/Solid/PowerManagement org.kde.Solid.PowerManagement.refreshStatus || true
fi

BROWSER_BIN=""
for candidate in chromium chromium-browser google-chrome-stable google-chrome; do
  if command -v "${candidate}" >/dev/null 2>&1; then
    BROWSER_BIN="${candidate}"
    break
  fi
done

if [ -z "${BROWSER_BIN}" ]; then
  echo "[$(date -Is)] no chromium-based browser found in PATH"
  exit 1
fi

PROFILE_DIR="/tmp/kiosk-chromium-profile-${UID_NUM}"
install -d -m 700 "${PROFILE_DIR}"

for i in {1..60}; do
  if curl -fsS "$URL" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

while true; do
  "${BROWSER_BIN}" \
    --user-data-dir="${PROFILE_DIR}" \
    --ozone-platform=x11 \
    --no-first-run \
    --no-default-browser-check \
    --disable-session-crashed-bubble \
    --disable-infobars \
    --password-store=basic \
    --kiosk \
    "$URL" || true
  sleep 1
done
