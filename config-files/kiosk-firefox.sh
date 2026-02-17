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

PROFILE_DIR="${HOME_DIR}/.mozilla/kiosk-profile"
if ! install -d -m 700 "${PROFILE_DIR}" 2>/dev/null; then
  PROFILE_DIR="/tmp/kiosk-firefox-profile-${UID_NUM}"
  install -d -m 700 "${PROFILE_DIR}"
fi

for i in {1..60}; do
  if curl -fsS "$URL" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

while true; do
  rm -f "${PROFILE_DIR}/lock" "${PROFILE_DIR}/.parentlock" || true
  firefox \
    --no-remote \
    --new-instance \
    --profile "${PROFILE_DIR}" \
    --kiosk \
    "$URL" || true
  sleep 1
done
