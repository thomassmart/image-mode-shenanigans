# Test and QA Guide

This guide defines a holistic verification strategy for `image-mode-shenanigans`, from source changes through installed kiosk behavior on real hardware.

## 1. Objectives

- Verify every change preserves a bootable kiosk OS image.
- Validate end-to-end operator flow: boot -> autologin -> kiosk UI -> scan -> print.
- Catch regressions early in CI and before deployment to devices.
- Ensure break-glass access and recovery procedures remain functional.

## 2. Scope

In scope:
- OS image build (`Containerfile`, `bootc/config.toml`).
- CI pipeline (`.github/workflows/image-build.yml`).
- Kiosk runtime services (`gdm`, `kiosk-nginx`, `kiosk-pos-agent`).
- Frontend behavior (`index.html`, `screensaver.mp4`).
- Scanner and receipt printing integration (CoreScanner/raw and CUPS/raw USB backends).

Out of scope:
- Hardware vendor firmware defects.
- External network outages outside kiosk host.

## 3. Environments

Define three test lanes and do not promote artifacts unless all required lanes pass:

- Dev lane (fast): local syntax/lint/smoke checks and container build.
- Pre-release lane (realistic): VM install from ISO, functional/system checks.
- Release lane (production-like): representative kiosk hardware with scanner and printer.

## 4. Quality Gates

Minimum gates for merge/release:

- Source and config integrity checks pass.
- `podman build` completes for the image.
- GitHub Actions workflow succeeds with ISO artifact upload.
- VM install validates kiosk autologin and Chromium kiosk startup.
- POS bridge health, event streaming, and print endpoint behavior pass.
- Zebra/CoreScanner install and service startup verified on target hardware.

## 5. Test Levels and Coverage Matrix

| Level | What to test | Files/Components | Pass criteria |
|---|---|---|---|
| Static validation | Syntax, required placeholders, service references | `Containerfile`, `*.service`, workflow, `index.html` | No parse/syntax errors; build placeholder present |
| Image build smoke | Container image buildability | `Containerfile`, `config-files/*` | Image builds with no failed layer |
| ISO pipeline | OCI push + ISO generation + artifact publishing | `.github/workflows/image-build.yml` | Workflow green, ISO artifact present |
| Boot/install | Installation and first boot behavior | built ISO + target VM/hardware | Installer completes, kiosk boots unattended |
| Runtime services | Service health and restart behavior | `kiosk-nginx`, `kiosk-pos-agent`, `gdm` | Services active and recover after restart/failure |
| App functional | UI interactions and state | `index.html` | Cart, totals, payment UX, idle screensaver behavior correct |
| Integration | Scanner input + print output | POS agent + scanner/printer stack | Scan events received; receipt print succeeds |
| Security/ops | Break-glass and local exposure boundaries | build customization + local bind config | Break-glass login works; agent remains local-bound |

## 6. Pre-Check (Before Any Deep Test)

Run from repo root:

```bash
set -euo pipefail
test -f Containerfile
test -f .github/workflows/image-build.yml
test -f index.html
test -f config-files/kiosk-pos-agent.py
rg -n "__BUILD_VERSION__" index.html
```

Expected:
- Placeholder exists in `index.html` for CI stamping.
- Required files exist.

## 7. Static and Configuration Validation

### 7.1 Shell scripts

```bash
bash -n config-files/kiosk-chromium.sh
bash -n config-files/gnome-kiosk-script
bash -n config-files/kiosk-install-zebra.sh
```

### 7.2 Python POS agent syntax

```bash
python3 -m py_compile config-files/kiosk-pos-agent.py
```

### 7.3 Systemd/quadlet/basic config sanity

```bash
rg -n "ExecStart|WantedBy|After|Wants" config-files/kiosk-pos-agent.service
rg -n "^\[Container\]|^Image=|^Network=|^Volume=" config-files/kiosk-nginx.container
```

### 7.4 Workflow sanity

```bash
rg -n "BREAK_GLASS_PASSWORD|BREAK_GLASS_SSH_PUBLIC_KEY|bootc-image-builder|upload-artifact" .github/workflows/image-build.yml
```

Pass criteria:
- No syntax errors.
- Required service/workflow fields present.

## 8. Local Build Smoke Test

```bash
podman build -t image-mode-shenanigans:qa .
```

Pass criteria:
- Build completes successfully.
- Zebra install step does not hard fail the build.
- Expected files copied into image layers.

Optional spot checks:

```bash
podman run --rm image-mode-shenanigans:qa rpm -qa | rg -i "gdm|gnome-kiosk|chromium|cups"
```

## 9. CI/CD Verification (Required)

On push to `main`, verify workflow `Build, Push, and Build bootc ISO`:

- `build-and-push` job:
  - stamps build label into `index.html`.
  - builds and pushes `latest` and SHA tags to GHCR.
- `build-bootc-iso` job:
  - validates break-glass secrets are present.
  - injects `break-glass` user customization.
  - builds ISO via `bootc-image-builder`.
  - uploads `bootc-iso-<sha>` artifact.

Pass criteria:
- Entire workflow green.
- ISO artifact downloadable.
- No missing-secret failures.

## 10. VM Install and First-Boot Validation

Use latest ISO artifact in a VM:

1. Boot installer and complete install.
2. Reboot installed system.
3. Observe first 2 minutes of startup.

Expected:
- GDM autologin into kiosk session (no manual login).
- Chromium starts in kiosk mode and loads `http://127.0.0.1/`.
- UI appears with no blocking dialogs.

On-host checks:

```bash
systemctl status gdm
systemctl status kiosk-nginx.service
systemctl status kiosk-pos-agent.service
curl -I http://127.0.0.1/
curl -s http://127.0.0.1:8091/healthz
```

Expected:
- All services `active (running)`.
- `/healthz` returns `{"ok":true}`.

## 11. Functional UI Test Checklist

Test manually in kiosk session:

- Add each product button at least once.
- Increase quantity/repeat scans and verify totals.
- Remove/cancel flows reset correctly.
- Select different payment methods and complete payment flow.
- Verify toast/modal behavior for success/error states.
- Verify camera panel:
  - API unavailable message in unsupported case.
  - camera selection and preview when supported/permitted.
- Leave UI idle >=60s and confirm screensaver appears.
- Provide user activity and verify UI returns from screensaver.

Pass criteria:
- No JS crashes or frozen UI.
- Price/total math matches expected values.
- Idle and resume behavior works repeatedly.

## 12. POS Agent API and Event Stream Tests

### 12.1 Health endpoint

```bash
curl -i http://127.0.0.1:8091/healthz
```

Expect HTTP `200` and `{"ok":true}`.

### 12.2 SSE event channel

```bash
curl -N http://127.0.0.1:8091/events
```

Expected:
- Keepalive lines appear periodically.
- `event: scan` messages appear when scanner input is received.

### 12.3 Print endpoint (happy path)

```bash
curl -i -X POST http://127.0.0.1:8091/print \
  -H 'Content-Type: application/json' \
  -d '{
    "timestamp":"2026-03-01T12:00:00Z",
    "payment_method":"Card",
    "items":[{"name":"Apples","qty":2,"unit_price":1.50,"line_total":3.00}],
    "total":3.00
  }'
```

Expect HTTP `200` and `{"printed":true}` when printer backend/device is valid.

### 12.4 Print endpoint (negative)

Set invalid printer device in `/etc/kiosk-pos.conf`, restart service, repeat print call.

Expect HTTP `500` with JSON error field containing device-not-found style failure.

## 13. Scanner and Printer Integration Tests

### 13.1 Zebra/CoreScanner path

```bash
rpm -qa | rg -i zebra
systemctl status cscored.service || systemctl status cscore.service || systemctl status corescanner.service
```

Expected:
- Zebra-related packages installed.
- At least one CoreScanner service active where available.

### 13.2 Raw fallback path

- Stop/unavailable CoreScanner command.
- Confirm `fallback_raw=true` behavior by scanning via configured raw device (`/dev/ttyACM0` default).

Expected:
- Scan events still reach `/events`.

### 13.3 Printer backend variants

Test both supported modes:

- `backend=raw_usb` with `/dev/usb/lp*`.
- `backend=cups` with configured printer name.

Expected:
- Receipt output contains header, line items, total, and paper feed/cut behavior per config.

## 14. Resilience and Recovery Tests

Run while kiosk is active:

```bash
sudo systemctl restart kiosk-nginx.service
sudo systemctl restart kiosk-pos-agent.service
```

Expected:
- UI recovers from local HTTP interruption.
- POS status in UI returns to connected state.

Crash-loop simulation:

- Temporarily misconfigure POS agent, verify restart attempts (`Restart=always`).
- Restore valid config and verify automatic recovery.

Browser recovery:

- Force-close Chromium process.
- Confirm kiosk loop relaunches browser automatically.

## 15. Security and Operational Checks

- Verify POS agent binds to loopback only (`127.0.0.1:8091` by default).
- Confirm nginx serves local static content and no unnecessary open ports.
- Validate break-glass user exists on installed system and is in `wheel`.
- Validate audit trail/log accessibility:
  - kiosk browser log: `/var/home/kiosk/kiosk-session.log` (or `/tmp` fallback).
  - service logs via `journalctl -u kiosk-pos-agent.service`.

## 16. Regression Checklist for Common Change Types

When editing `index.html`:
- Re-test cart math, payment flows, idle screensaver, and camera panel states.

When editing `kiosk-pos-agent.py` or POS config:
- Re-test `/healthz`, `/events`, `/print`, scanner path, and print failures.

When editing `Containerfile` or `config-files/*` service/session files:
- Re-test image build, first-boot autologin, Chromium launch loop, and service status.

When editing workflow files:
- Re-test placeholder stamping, image push tags, ISO build, and artifact upload.

## 17. Release Sign-Off Template

Use this for each candidate release:

- Change set reviewed.
- Static/config checks passed.
- Local image build passed.
- CI workflow green with ISO artifact.
- VM install test passed.
- Hardware scan + print test passed.
- Break-glass login verified.
- Known issues documented with mitigation.
- Final go/no-go decision recorded.

## 18. Suggested Future Improvements

- Add automated smoke tests in CI for API endpoints via containerized runtime.
- Add a minimal JS test harness for pricing/receipt math in `index.html`.
- Add scripted VM boot checks (service health + screenshot diff of kiosk landing page).
- Add log collection bundle script for rapid field triage.
