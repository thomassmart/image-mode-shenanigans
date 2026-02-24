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

URL="${KIOSK_URL:-http://127.0.0.1/}"
WAIT_FOR_HTTP_URL="${KIOSK_WAIT_FOR_HTTP_URL:-0}"

exec >>"${LOG_FILE}" 2>&1

export HOME="${HOME_DIR}"
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-${HOME_DIR}/.config}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-${HOME_DIR}/.cache}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-${HOME_DIR}/.local/share}"

if [ -f /etc/environment ]; then
  set -a
  # shellcheck disable=SC1091
  . /etc/environment
  set +a
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

if [[ "${WAIT_FOR_HTTP_URL}" == "1" && "${URL}" =~ ^https?:// ]]; then
  for _ in {1..15}; do
    if curl -fsS "${URL}" >/dev/null 2>&1; then
      break
    fi
    sleep 1
  done
fi

while true; do
  "${BROWSER_BIN}" \
    --user-data-dir="${PROFILE_DIR}" \
    --ozone-platform-hint=auto \
    --no-first-run \
    --no-default-browser-check \
    --disable-session-crashed-bubble \
    --disable-infobars \
    --password-store=basic \
    --kiosk-printing \
    --use-fake-ui-for-media-stream \
    --autoplay-policy=no-user-gesture-required \
    --kiosk \
    "${URL}" || true
  sleep 1
done
