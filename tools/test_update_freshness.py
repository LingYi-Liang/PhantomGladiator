"""Exercise cache bypass, independent release checks and stable promotion through the real updater."""
import hashlib
import http.server
import json
import os
from pathlib import Path
import runpy
import shutil
import subprocess
import sys
import tempfile
import threading
from urllib.parse import parse_qs, urlsplit

ROOT = Path(__file__).resolve().parent.parent


def main():
    helper = runpy.run_path(str(ROOT / "tools/test_update_check.py"), run_name="fixture")
    pages, requests = {}, []

    class Handler(http.server.BaseHTTPRequestHandler):
        def log_message(self, *_):
            pass

        def do_HEAD(self):
            self.send_response(200)
            self.end_headers()

        def do_GET(self):
            url = urlsplit(self.path)
            requests.append((url.path, parse_qs(url.query), self.headers.get("Cache-Control", "")))
            body = pages.get(url.path)
            if url.path == "/nonce/latest.json":
                body = manifest("0.40.13" if parse_qs(url.query).get("pg_check") else "0.40.11", "nonce")
            if url.path == "/requests":
                body = json.dumps(requests)
            self.send_response(200 if body is not None else 404)
            self.send_header("Content-Type", "application/json")
            self.send_header("Cache-Control", "public,max-age=86400")
            self.end_headers()
            if body is not None:
                self.wfile.write(body.encode("utf-8"))

    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    base = f"http://127.0.0.1:{server.server_address[1]}"

    def manifest(version, label):
        return json.dumps(dict(version=version, date=label, size=1, sha256="0" * 64,
                               notes={"zh": [label]}, downloads=[dict(id="github", url=base + "/download")]))

    release = dict(tag_name="v0.40.13", draft=False, prerelease=False,
                   published_at="2026-11-13T00:00:00Z", assets=[dict(
                       name="PhantomGladiator-0.40.13-win64.zip", size=1,
                       digest="sha256:" + hashlib.sha256(b"x").hexdigest(),
                       browser_download_url=base + "/download")])
    for name in ("stale", "list", "api-only", "current"):
        version = "0.40.13" if name == "current" else "0.40.11"
        pages[f"/{name}/latest.json"] = manifest(version, name)
        listed = "0.40.13" if name == "list" else version
        pages[f"/{name}/versions.json"] = json.dumps({"versions": [json.loads(manifest(listed, "from-list"))]})
    pages["/api/latest"] = json.dumps(release)
    pages["/api/preview"] = json.dumps(dict(release, prerelease=True))
    pages["/api/draft"] = json.dumps(dict(release, draft=True))
    pages["/api/incomplete"] = json.dumps(dict(release, assets=[]))
    threading.Thread(target=server.serve_forever, daemon=True).start()
    try:
        with tempfile.TemporaryDirectory(prefix="pg-fresh-update-") as scratch:
            folder = Path(scratch)
            for dll in helper["WEBVIEW2"]:
                shutil.copy2(helper["webview2_folder"]() / dll, folder / dll)
            exe = folder / "freshness.exe"
            subprocess.run([str(helper["CSC"]), "/nologo", "/target:exe", "/platform:x64", "/utf8output", "/codepage:65001",
                            "/main:PhantomGladiator.UpdateFreshnessTest", f"/out:{exe}",
                            *[f"/r:{ref}" for ref in helper["REFS"]],
                            *[f"/r:{folder / dll}" for dll in helper["WEBVIEW2"]],
                            *[str(ROOT / f"desktop/{name}") for name in ("PhantomGladiator.cs", "AppUpdate.cs", "ManualBeta.cs")],
                            str(ROOT / "tools/test_update_freshness.cs")], check=True)
            result = subprocess.run([str(exe), base], capture_output=True, timeout=60,
                                    env=dict(os.environ, PG_DATA_DIR=str(folder / "data")))
            print(result.stdout.decode("utf-8", errors="replace"), end="")
            print(result.stderr.decode("utf-8", errors="replace"), end="", file=sys.stderr)
            return result.returncode
    finally:
        server.shutdown()
        server.server_close()


if __name__ == "__main__":
    sys.exit(main())
