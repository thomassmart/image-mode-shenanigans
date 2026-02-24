#!/usr/bin/env bash
set -euo pipefail

CFG_FILE="/etc/kiosk-zebra.conf"
STATE_DIR="/var/lib/kiosk-pos"
STATE_FILE="${STATE_DIR}/zebra-install.state"
BUILD_TIME="${BUILD_TIME:-0}"

mkdir -p "${STATE_DIR}"

if [ "${BUILD_TIME}" != "1" ] && [ -f "${STATE_FILE}" ]; then
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
ALLOW_LEGACY_RPM="${ALLOW_LEGACY_RPM:-true}"

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
if ! dnf -y install "${CORE_RPM}"; then
  if [ "${ALLOW_LEGACY_RPM}" = "true" ]; then
    echo "[zebra-install] dnf install failed; retrying with legacy rpm flags (--nodigest --nosignature)"
    rpm -Uvh --nodigest --nosignature "${CORE_RPM}"
  else
    echo "[zebra-install] dnf install failed and ALLOW_LEGACY_RPM=false"
    exit 1
  fi
fi

if compgen -G "${SDK_LOCAL_DIR}/zebra-scanner-javapos-*.rpm" >/dev/null 2>&1; then
  JAVAPOS_RPM="$(ls -1 ${SDK_LOCAL_DIR}/zebra-scanner-javapos-*.rpm | head -n1)"
  echo "[zebra-install] installing JavaPOS optional package ${JAVAPOS_RPM}"
  if ! dnf -y install "${JAVAPOS_RPM}"; then
    if [ "${ALLOW_LEGACY_RPM}" = "true" ]; then
      rpm -Uvh --nodigest --nosignature "${JAVAPOS_RPM}" || true
    fi
  fi
fi

if [ "${ENABLE_CLU}" = "true" ]; then
  echo "[zebra-install] CLU enabled by config"
fi

if [ "${BUILD_TIME}" != "1" ]; then
  for unit in cscore.service corescanner.service; do
    if systemctl list-unit-files | grep -q "^${unit}"; then
      echo "[zebra-install] enabling ${unit}"
      systemctl enable --now "${unit}" || true
      break
    fi
  done
fi

if [ "${BUILD_TIME}" != "1" ]; then
  {
    echo "installed_at=$(date -Is)"
    echo "core_rpm=${CORE_RPM}"
    echo "local_dir=${SDK_LOCAL_DIR}"
  } > "${STATE_FILE}"
fi

echo "[zebra-install] complete"
