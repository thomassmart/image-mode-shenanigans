#!/usr/bin/env bash
set -euo pipefail

exec >>/home/kiosk/kiosk-session.log 2>&1

URL="http://127.0.0.1:8080/"

for i in {1..60}; do
  if curl -fsS "$URL" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

while true; do
  firefox --new-instance --kiosk "$URL" || true
  sleep 1
done
