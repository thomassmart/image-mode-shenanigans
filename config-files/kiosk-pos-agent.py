#!/usr/bin/env python3
import argparse
import configparser
import glob
import json
import os
import queue
import re
import shlex
import shutil
import subprocess
import threading
import time
from datetime import datetime, timezone
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

CONFIG_DEFAULT = "/etc/kiosk-pos.conf"
CONFIG_OVERRIDE_DIR = "/etc/kiosk-pos.conf.d"


def read_config(path: str):
    cfg = configparser.ConfigParser()
    cfg.read(path)

    override_dir = Path(CONFIG_OVERRIDE_DIR)
    if override_dir.is_dir():
        for override in sorted(override_dir.glob("*.conf")):
            cfg.read(override)
    return cfg


def cfg_get(cfg, section, key, fallback=""):
    if not cfg.has_section(section):
        return fallback
    return cfg.get(section, key, fallback=fallback)


def cfg_getbool(cfg, section, key, fallback=False):
    if not cfg.has_section(section):
        return fallback
    return cfg.getboolean(section, key, fallback=fallback)


def first_existing_path(candidates):
    for candidate in candidates:
        if candidate and os.path.exists(candidate):
            return candidate
    return ""


class ScannerBroker:
    def __init__(self):
        self._lock = threading.Lock()
        self._subscribers = []

    def subscribe(self):
        q = queue.Queue(maxsize=64)
        with self._lock:
            self._subscribers.append(q)
        return q

    def unsubscribe(self, q):
        with self._lock:
            if q in self._subscribers:
                self._subscribers.remove(q)

    def publish_scan(self, barcode: str):
        payload = {
            "barcode": barcode,
            "ts": datetime.now(timezone.utc).isoformat(),
        }
        dead = []
        with self._lock:
            for q in self._subscribers:
                try:
                    q.put_nowait(payload)
                except queue.Full:
                    dead.append(q)
            for q in dead:
                self._subscribers.remove(q)


class ScannerWorker(threading.Thread):
    def __init__(self, cfg, broker):
        super().__init__(daemon=True)
        self.cfg = cfg
        self.broker = broker
        self.stop_event = threading.Event()

    def run(self):
        provider = cfg_get(self.cfg, "scanner", "provider", "corescanner").strip().lower()
        fallback_raw = cfg_getbool(self.cfg, "scanner", "fallback_raw", False)

        if provider == "corescanner":
            while not self.stop_event.is_set():
                ok = self._run_corescanner_stream()
                if ok:
                    continue
                if fallback_raw:
                    self._run_raw_stream_once()
                if self.stop_event.wait(2):
                    return
            return

        if provider == "raw":
            while not self.stop_event.is_set():
                self._run_raw_stream_once()
                if self.stop_event.wait(2):
                    return

    def _extract_barcode(self, line: str):
        pattern = cfg_get(self.cfg, "scanner", "barcode_pattern", r"(\\d{4,})")
        m = re.search(pattern, line)
        if m:
            return m.group(1)
        stripped = line.strip()
        if stripped.isdigit() and len(stripped) >= 4:
            return stripped
        return ""

    def _run_corescanner_stream(self):
        cmd = cfg_get(self.cfg, "scanner", "corescanner_command", "").strip()
        if cmd and not os.path.exists(cmd):
            print(f"[scanner] configured CoreScanner command missing: {cmd}", flush=True)
            cmd = ""

        if not cmd:
            path_hit = shutil.which("csclu")
            if path_hit:
                cmd = path_hit

        if not cmd:
            candidates = cfg_get(
                self.cfg,
                "scanner",
                "corescanner_command_candidates",
                "/usr/bin/csclu /usr/local/bin/csclu /opt/zebra/scanner/bin/csclu",
            )
            cmd = first_existing_path(shlex.split(candidates))

        args = shlex.split(cfg_get(self.cfg, "scanner", "corescanner_args", "--wait --xml-events"))

        if not cmd:
            print("[scanner] CoreScanner command missing: tried configured path, PATH lookup, and candidates", flush=True)
            return False

        try:
            proc = subprocess.Popen(
                [cmd] + args,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                bufsize=1,
            )
        except Exception as exc:
            print(f"[scanner] failed to start CoreScanner command: {exc}", flush=True)
            return False

        print(f"[scanner] started CoreScanner stream: {cmd} {' '.join(args)}", flush=True)

        try:
            for line in proc.stdout:
                if self.stop_event.is_set():
                    proc.terminate()
                    return True
                barcode = self._extract_barcode(line)
                if barcode:
                    self.broker.publish_scan(barcode)
        except Exception as exc:
            print(f"[scanner] CoreScanner stream error: {exc}", flush=True)
        finally:
            try:
                proc.terminate()
            except Exception:
                pass

        return False

    def _run_raw_stream_once(self):
        raw_mode = cfg_get(self.cfg, "scanner", "raw_mode", "serial_ascii")
        raw_device = cfg_get(self.cfg, "scanner", "raw_device", "/dev/ttyACM0")
        suffix = cfg_get(self.cfg, "scanner", "raw_suffix", "\\n").encode("utf-8").decode("unicode_escape").encode("utf-8")
        if not suffix:
            suffix = b"\n"

        if not os.path.exists(raw_device):
            print(f"[scanner] raw device missing: {raw_device}", flush=True)
            time.sleep(2)
            return

        print(f"[scanner] reading raw scanner stream mode={raw_mode} device={raw_device}", flush=True)
        buf = bytearray()

        try:
            with open(raw_device, "rb", buffering=0) as f:
                while not self.stop_event.is_set():
                    b = f.read(1)
                    if not b:
                        time.sleep(0.01)
                        continue
                    buf.extend(b)
                    if buf.endswith(suffix):
                        line = bytes(buf[:-len(suffix)] if len(suffix) else buf)
                        buf.clear()
                        text = line.decode("utf-8", errors="ignore").strip()
                        barcode = self._extract_barcode(text)
                        if barcode:
                            self.broker.publish_scan(barcode)
        except Exception as exc:
            print(f"[scanner] raw stream error on {raw_device}: {exc}", flush=True)


class PosRequestHandler(BaseHTTPRequestHandler):
    broker = None
    config = None

    def _send_cors(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET,POST,OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")

    def do_OPTIONS(self):
        self.send_response(HTTPStatus.NO_CONTENT)
        self._send_cors()
        self.end_headers()

    def do_GET(self):
        if self.path == "/healthz":
            self.send_response(HTTPStatus.OK)
            self._send_cors()
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(b'{"ok":true}')
            return

        if self.path == "/events":
            self.send_response(HTTPStatus.OK)
            self._send_cors()
            self.send_header("Content-Type", "text/event-stream")
            self.send_header("Cache-Control", "no-cache")
            self.send_header("Connection", "keep-alive")
            self.end_headers()

            q = self.broker.subscribe()
            try:
                while True:
                    try:
                        event = q.get(timeout=15)
                        payload = json.dumps(event).encode("utf-8")
                        self.wfile.write(b"event: scan\n")
                        self.wfile.write(b"data: ")
                        self.wfile.write(payload)
                        self.wfile.write(b"\n\n")
                        self.wfile.flush()
                    except queue.Empty:
                        self.wfile.write(b": keepalive\n\n")
                        self.wfile.flush()
            except (BrokenPipeError, ConnectionResetError):
                pass
            finally:
                self.broker.unsubscribe(q)
            return

        self.send_response(HTTPStatus.NOT_FOUND)
        self._send_cors()
        self.end_headers()

    def do_POST(self):
        if self.path != "/print":
            self.send_response(HTTPStatus.NOT_FOUND)
            self._send_cors()
            self.end_headers()
            return

        length = int(self.headers.get("Content-Length", "0"))
        data = self.rfile.read(length)

        try:
            payload = json.loads(data.decode("utf-8"))
            write_receipt(payload, self.config)
            body = b'{"printed":true}'
            self.send_response(HTTPStatus.OK)
        except Exception as exc:
            body = json.dumps({"printed": False, "error": str(exc)}).encode("utf-8")
            self.send_response(HTTPStatus.INTERNAL_SERVER_ERROR)

        self._send_cors()
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        print(f"[http] {self.address_string()} - {fmt % args}", flush=True)


def decode_hex(cfg, section, key):
    raw = cfg_get(cfg, section, key, "").strip()
    if not raw:
        return b""
    return bytes.fromhex(raw)


def printer_profile_defaults(cfg):
    profile = cfg_get(cfg, "printer", "profile", "generic").strip().lower()
    if profile == "dn_usb_lp":
        return {
            "init_hex": "1b40",
            "linefeed_hex": "0a",
            "cut_hex": "1d5601",
        }
    return {}


def resolve_printer_device(cfg):
    configured = cfg_get(cfg, "printer", "device", "/dev/usb/lp0").strip()
    if configured and os.path.exists(configured):
        return configured

    pattern = cfg_get(cfg, "printer", "device_glob", "/dev/usb/lp*").strip()
    if pattern:
        matches = sorted(glob.glob(pattern))
        if matches:
            return matches[0]

    return configured


def render_receipt_bytes(payload, cfg):
    encoding = cfg_get(cfg, "printer", "encoding", "utf-8")
    defaults = printer_profile_defaults(cfg)

    linefeed_hex = cfg_get(cfg, "printer", "linefeed_hex", defaults.get("linefeed_hex", ""))
    linefeed = bytes.fromhex(linefeed_hex) if linefeed_hex else b"\n"
    top_feed_lines = int(cfg_get(cfg, "printer", "top_feed_lines", "4"))
    bottom_feed_lines = int(cfg_get(cfg, "printer", "bottom_feed_lines", "8"))

    lines = []
    lines.append("SELF CHECKOUT RECEIPT")
    lines.append("------------------------------")
    lines.append(f"Date: {payload.get('timestamp', '')}")
    lines.append(f"Payment: {payload.get('payment_method', '')}")
    lines.append("")

    for item in payload.get("items", []):
        lines.append(str(item.get("name", "")))
        qty = item.get("qty", 0)
        unit = float(item.get("unit_price", 0))
        line_total = float(item.get("line_total", 0))
        lines.append(f"  {qty} x ${unit:.2f} = ${line_total:.2f}")

    lines.append("")
    lines.append("------------------------------")
    lines.append(f"TOTAL: ${float(payload.get('total', 0)):.2f}")
    lines.append("THANK YOU")

    text = "\n".join(lines)
    body = text.encode(encoding, errors="replace")
    if linefeed != b"\n":
        body = body.replace(b"\n", linefeed)

    init_hex = cfg_get(cfg, "printer", "init_hex", defaults.get("init_hex", ""))
    cut_hex = cfg_get(cfg, "printer", "cut_hex", defaults.get("cut_hex", ""))
    init_bytes = bytes.fromhex(init_hex) if init_hex else b""
    cut_bytes = bytes.fromhex(cut_hex) if cut_hex else b""
    top_pad = linefeed * max(0, top_feed_lines)
    bottom_pad = linefeed * max(0, bottom_feed_lines)
    return init_bytes + top_pad + body + bottom_pad + cut_bytes


def write_receipt(payload, cfg):
    backend = cfg_get(cfg, "printer", "backend", "raw_usb").strip().lower()
    content = render_receipt_bytes(payload, cfg)

    if backend == "raw_usb":
        device = resolve_printer_device(cfg)
        if not device or not os.path.exists(device):
            raise RuntimeError(f"Printer device not found: {device}")
        with open(device, "ab", buffering=0) as f:
            f.write(content)
        return

    if backend == "cups":
        cmd = ["lp"]
        printer = cfg_get(cfg, "printer", "cups_printer", "").strip()
        if printer:
            cmd.extend(["-d", printer])
        subprocess.run(cmd, input=content, check=True)
        return

    raise RuntimeError(f"Unsupported printer backend: {backend}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", default=CONFIG_DEFAULT)
    args = parser.parse_args()

    cfg = read_config(args.config)
    bind = cfg_get(cfg, "agent", "bind", "127.0.0.1")
    port = int(cfg_get(cfg, "agent", "port", "8091"))

    broker = ScannerBroker()
    scanner = ScannerWorker(cfg, broker)
    scanner.start()

    PosRequestHandler.broker = broker
    PosRequestHandler.config = cfg

    server = ThreadingHTTPServer((bind, port), PosRequestHandler)
    print(f"[agent] listening on http://{bind}:{port}", flush=True)

    try:
        server.serve_forever()
    finally:
        scanner.stop_event.set()
        server.server_close()


if __name__ == "__main__":
    main()
