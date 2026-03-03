#!/usr/bin/env bash
set -euo pipefail

export PYTHONPYCACHEPREFIX="${PWD}/.pycache"

echo "[qa] verifying required files"
test -f Containerfile
test -f .github/workflows/image-build.yml
test -f index.html
test -f config-files/kiosk-pos-agent.py
test -f config-files/flightctl/config.yaml

echo "[qa] validating build label placeholder"
rg -q "__BUILD_VERSION__" index.html

echo "[qa] validating flightctl integration wiring"
rg -q "flightctl-agent" Containerfile
rg -q "COPY config-files/flightctl/config.yaml /etc/flightctl/config.yaml" Containerfile
rg -q "systemctl enable flightctl-agent.service" Containerfile

echo "[qa] shell syntax checks"
bash -n config-files/kiosk-chromium.sh
bash -n config-files/gnome-kiosk-script
bash -n config-files/kiosk-install-zebra.sh

echo "[qa] python syntax checks"
python3 -m py_compile config-files/kiosk-pos-agent.py

echo "[qa] unit tests"
python3 -m unittest discover -s tests -p "test_*.py" -v

echo "[qa] done"
