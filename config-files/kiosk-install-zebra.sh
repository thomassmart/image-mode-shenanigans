#!/usr/bin/env bash
set -euo pipefail

CFG_FILE="/etc/kiosk-zebra.conf"
STATE_DIR="/var/lib/kiosk-pos"
STATE_FILE="${STATE_DIR}/zebra-install.state"

mkdir -p "${STATE_DIR}"

if [ -f "${STATE_FILE}" ]; then
  echo "[zebra-install] state exists, skipping"
  exit 0
fi

if [ -f "${CFG_FILE}" ]; then
  set -a
  # shellcheck disable=SC1090
  . "${CFG_FILE}"
  set +a
fi

INSTALL_MODE="${INSTALL_MODE:-rpm}"
SDK_LOCAL_DIR="${SDK_LOCAL_DIR:-/usr/local/share/zebra}"
SDK_FILE="${SDK_FILE:-}"
SDK_SHA256="${SDK_SHA256:-}"
ENABLE_CLU="${ENABLE_CLU:-true}"

if [ "${INSTALL_MODE}" != "rpm" ]; then
  echo "[zebra-install] only INSTALL_MODE=rpm is implemented"
  exit 1
fi

if [ -n "${SDK_FILE}" ] && [ ! -f "${SDK_FILE}" ]; then
  echo "[zebra-install] SDK_FILE not found: ${SDK_FILE}"
  exit 1
fi

if [ -n "${SDK_SHA256}" ] && [ -n "${SDK_FILE}" ]; then
  echo "${SDK_SHA256}  ${SDK_FILE}" | sha256sum -c -
fi

CORE_RPM=""
if compgen -G "${SDK_LOCAL_DIR}/zebra-scanner-corescanner-*.rpm" >/dev/null 2>&1; then
  CORE_RPM="$(ls -1 ${SDK_LOCAL_DIR}/zebra-scanner-corescanner-*.rpm | head -n1)"
fi

if [ -z "${CORE_RPM}" ]; then
  echo "[zebra-install] missing CoreScanner RPM under ${SDK_LOCAL_DIR}"
  exit 1
fi

echo "[zebra-install] installing CoreScanner from ${CORE_RPM}"
dnf -y install "${CORE_RPM}"

if compgen -G "${SDK_LOCAL_DIR}/zebra-scanner-javapos-*.rpm" >/dev/null 2>&1; then
  JAVAPOS_RPM="$(ls -1 ${SDK_LOCAL_DIR}/zebra-scanner-javapos-*.rpm | head -n1)"
  echo "[zebra-install] installing JavaPOS optional package ${JAVAPOS_RPM}"
  dnf -y install "${JAVAPOS_RPM}" || true
fi

if [ "${ENABLE_CLU}" = "true" ]; then
  echo "[zebra-install] CLU enabled by config"
fi

for unit in cscore.service corescanner.service; do
  if systemctl list-unit-files | grep -q "^${unit}"; then
    echo "[zebra-install] enabling ${unit}"
    systemctl enable --now "${unit}" || true
    break
  fi
done

{
  echo "installed_at=$(date -Is)"
  echo "core_rpm=${CORE_RPM}"
  echo "local_dir=${SDK_LOCAL_DIR}"
} > "${STATE_FILE}"

echo "[zebra-install] complete"
