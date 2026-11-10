"""Exercise manual preview authorization and isolated package installation without starting the app."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from io import BytesIO
from pathlib import Path
import hashlib
import os
import runpy
import shutil
import subprocess
import tempfile
import threading
from zipfile import ZipFile


ROOT = Path(__file__).resolve().parents[1]


def main():
    helper = runpy.run_path(str(ROOT / "tools/test_update_check.py"), run_name="compile_fixture")
    webview2 = helper["webview2_folder"]()
    stream = BytesIO()
    with ZipFile(stream, "w") as archive:
        archive.writestr("PhantomGladiator-0.40.11/PhantomGladiator.exe", "preview fixture")
        archive.writestr("PhantomGladiator-0.40.11/app/version.json",
                         '{"appVersion":"0.40.11","modBuild":"fixture-beta"}')
    payload = stream.getvalue()

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *_):
            pass

        def do_GET(self):
            if self.path != "/beta.zip":
                self.send_error(404)
                return
            self.send_response(200)
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)

    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    try:
        with tempfile.TemporaryDirectory(prefix="pg-manual-beta-") as scratch:
            folder = Path(scratch)
            for name in helper["WEBVIEW2"]:
                shutil.copyfile(webview2 / name, folder / name)
            (folder / "stable-sentinel.txt").write_text("keep", encoding="utf-8")
            exe = folder / "ManualBetaTest.exe"
            subprocess.run([
                str(helper["CSC"]), "/nologo", "/target:exe", "/platform:x64", "/utf8output", "/codepage:65001",
                "/main:PhantomGladiator.ManualBetaTest", f"/out:{exe}",
                *[f"/r:{r}" for r in helper["REFS"]],
                *[f"/r:{folder / dll}" for dll in helper["WEBVIEW2"]],
                *[str(ROOT / f"desktop/{name}") for name in ("PhantomGladiator.cs", "AppUpdate.cs", "ManualBeta.cs")],
                str(ROOT / "tools/test_manual_beta.cs"),
            ], check=True)
            subprocess.run([
                str(exe), f"http://127.0.0.1:{server.server_address[1]}",
                hashlib.sha256(payload).hexdigest(), str(len(payload)),
            ], check=True, env=dict(os.environ, PG_DATA_DIR=str(folder / "data")), timeout=30)
    finally:
        server.shutdown()
        server.server_close()


if __name__ == "__main__":
    main()
