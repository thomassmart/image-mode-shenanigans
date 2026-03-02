import configparser
import importlib.util
import tempfile
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).resolve().parents[1] / "config-files" / "kiosk-pos-agent.py"
SPEC = importlib.util.spec_from_file_location("kiosk_pos_agent", MODULE_PATH)
kiosk_pos_agent = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(kiosk_pos_agent)


def make_cfg(values):
    cfg = configparser.ConfigParser()
    for section, section_values in values.items():
        cfg[section] = section_values
    return cfg


class KioskPosAgentTests(unittest.TestCase):
    def test_cfg_get_fallback_when_section_missing(self):
        cfg = configparser.ConfigParser()
        self.assertEqual(kiosk_pos_agent.cfg_get(cfg, "missing", "key", "fallback"), "fallback")

    def test_cfg_getbool_fallback_when_section_missing(self):
        cfg = configparser.ConfigParser()
        self.assertTrue(kiosk_pos_agent.cfg_getbool(cfg, "missing", "key", True))

    def test_first_existing_path_returns_first_hit(self):
        with tempfile.TemporaryDirectory() as tmp:
            p1 = Path(tmp) / "one"
            p2 = Path(tmp) / "two"
            p2.write_text("ok", encoding="utf-8")
            hit = kiosk_pos_agent.first_existing_path([str(p1), str(p2)])
            self.assertEqual(hit, str(p2))

    def test_decode_hex_empty_returns_empty_bytes(self):
        cfg = make_cfg({"printer": {}})
        self.assertEqual(kiosk_pos_agent.decode_hex(cfg, "printer", "init_hex"), b"")

    def test_render_receipt_bytes_contains_core_fields(self):
        cfg = make_cfg(
            {
                "printer": {
                    "profile": "generic",
                    "encoding": "utf-8",
                    "linefeed_hex": "0a",
                    "top_feed_lines": "0",
                    "bottom_feed_lines": "0",
                }
            }
        )
        payload = {
            "timestamp": "2026-03-01T12:00:00Z",
            "payment_method": "Card",
            "items": [{"name": "Apples", "qty": 2, "unit_price": 1.5, "line_total": 3.0}],
            "total": 3.0,
        }
        data = kiosk_pos_agent.render_receipt_bytes(payload, cfg).decode("utf-8")
        self.assertIn("SELF CHECKOUT RECEIPT", data)
        self.assertIn("Payment: Card", data)
        self.assertIn("Apples", data)
        self.assertIn("TOTAL: $3.00", data)

    def test_dn_usb_lp_profile_supplies_init_and_cut_defaults(self):
        cfg = make_cfg(
            {
                "printer": {
                    "profile": "dn_usb_lp",
                    "encoding": "utf-8",
                    "top_feed_lines": "0",
                    "bottom_feed_lines": "0",
                }
            }
        )
        payload = {"timestamp": "", "payment_method": "", "items": [], "total": 0}
        data = kiosk_pos_agent.render_receipt_bytes(payload, cfg)
        self.assertTrue(data.startswith(bytes.fromhex("1b40")))
        self.assertTrue(data.endswith(bytes.fromhex("1d5601")))

    def test_resolve_printer_device_uses_glob_fallback(self):
        with tempfile.TemporaryDirectory() as tmp:
            fake_lp = Path(tmp) / "lp0"
            fake_lp.write_text("", encoding="utf-8")

            cfg = make_cfg(
                {
                    "printer": {
                        "device": str(Path(tmp) / "missing-lp"),
                        "device_glob": str(Path(tmp) / "lp*"),
                    }
                }
            )
            resolved = kiosk_pos_agent.resolve_printer_device(cfg)
            self.assertEqual(resolved, str(fake_lp))


if __name__ == "__main__":
    unittest.main()
