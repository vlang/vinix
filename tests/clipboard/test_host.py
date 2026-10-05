"""Exercise clipboard reads and the actual QEMU loopback HTTP handler."""
import importlib.util
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import unittest
from unittest.mock import patch
from urllib.error import HTTPError
from urllib.request import ProxyHandler, build_opener

urlopen = build_opener(ProxyHandler({})).open

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
import host_clipboard

spec = importlib.util.spec_from_file_location("package_store", ROOT / "tools/qemu-package-store.py")
store = importlib.util.module_from_spec(spec)
spec.loader.exec_module(store)


class HostClipboardTests(unittest.TestCase):
    def test_read_utf8_preserves_tabs_and_newlines(self):
        text = "Привет\t😀\nsecond line\n".encode()
        with patch.object(host_clipboard, "clipboard_command", return_value=["clipboard"]), \
             patch.object(host_clipboard.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, text)):
            self.assertEqual(host_clipboard.read_clipboard(), text)

    def test_read_rejects_invalid_utf8_and_large_or_unavailable_clipboards(self):
        for text in (b"\xff", b"a" * (host_clipboard.MAX_CLIPBOARD_BYTES + 1)):
            with self.subTest(text_length=len(text)), \
                 patch.object(host_clipboard, "clipboard_command", return_value=["clipboard"]), \
                 patch.object(host_clipboard.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, text)):
                with self.assertRaises(host_clipboard.ClipboardError):
                    host_clipboard.read_clipboard()
        with patch.object(host_clipboard, "clipboard_command", return_value=["clipboard"]), \
             patch.object(host_clipboard.subprocess, "run", side_effect=subprocess.TimeoutExpired("clipboard", 2)):
            with self.assertRaises(host_clipboard.ClipboardError):
                host_clipboard.read_clipboard()

    def test_endpoint_reads_only_on_request_and_returns_complete_text(self):
        with tempfile.TemporaryDirectory() as work:
            server = store.OverlayServer(("127.0.0.1", 0), Path(work) / "packages", 1024, None, (), None, True)
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            text = "Привет\t😀\nsecond line".encode()
            with patch.object(store, "read_clipboard", return_value=text) as read:
                thread.start()
                base = f"http://127.0.0.1:{server.server_port}"
                try:
                    with urlopen(base + "/health") as response:
                        self.assertEqual(response.status, 204)
                    read.assert_not_called()
                    with urlopen(base + "/clipboard") as response:
                        self.assertEqual(response.read(), text)
                        self.assertEqual(response.headers["Cache-Control"], "no-store")
                    read.assert_called_once()
                    server.clipboard = False
                    with self.assertRaises(HTTPError) as error:
                        urlopen(base + "/clipboard")
                    self.assertEqual(error.exception.code, 404)
                    self.assertEqual(read.call_count, 1)
                    server.clipboard = True
                    read.side_effect = host_clipboard.ClipboardError("unavailable")
                    with self.assertRaises(HTTPError) as error:
                        urlopen(base + "/clipboard")
                    self.assertEqual(error.exception.code, 503)
                finally:
                    server.shutdown()
                    server.server_close()
                    thread.join()


if __name__ == "__main__":
    unittest.main()
