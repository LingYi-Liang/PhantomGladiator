"""The app's update check and rollback pick (desktop/PhantomGladiator.cs UpdateClient.Check, SelectVersion) against a
local fake server.

Compiles the app source with tools/test_update_check.cs as the entry point using the .NET Framework's csc,
serves manifests from 127.0.0.1 and runs it. Needs a folder with the WebView2 assemblies, by default the
newest built dist/PhantomGladiator-* folder:

    python -I tools/test_update_check.py [webview2 folder]
"""
import collections, hashlib, http.server, json, os, pathlib, shutil, subprocess, sys, tempfile, threading, time
from urllib.parse import urlsplit

ROOT = pathlib.Path(__file__).resolve().parent.parent
CSC = pathlib.Path(r"C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe")
REFS = ["System.dll", "System.Core.dll", "System.Drawing.dll", "System.Windows.Forms.dll", "System.Web.Extensions.dll",
        "System.IO.Compression.dll", "System.IO.Compression.FileSystem.dll"]
WEBVIEW2 = ["Microsoft.Web.WebView2.Core.dll", "Microsoft.Web.WebView2.WinForms.dll"]


def webview2_folder():
    if len(sys.argv) > 1:
        return pathlib.Path(sys.argv[1])
    built = [p for p in (ROOT / "dist").glob("PhantomGladiator-*") if (p / WEBVIEW2[0]).is_file()]
    if not built:
        sys.exit("no built dist/PhantomGladiator-* folder with the WebView2 assemblies; pass one")
    return max(built, key=lambda p: p.stat().st_mtime)


def main():
    pages = {}

    class Handler(http.server.BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass

        def do_HEAD(self):  # the download lines' latency probe
            self.send_response(200)
            self.end_headers()

        def do_GET(self):
            self.path = urlsplit(self.path).path
            if self.path == "/hits":
                data = json.dumps(sorted(hits)).encode("utf-8")
                self.send_response(200)
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)
                return
            if self.path == "/whole":
                self.send_response(200)
                self.send_header("Content-Length", str(len(whole)))
                self.end_headers()
                self.wfile.write(whole)
                return
            if self.path.startswith("/src/"):
                _, _, kind, file = self.path.split("/")
                hits[f"{kind}/{file}"] += 1
                body = blobs.get(file)
                try:
                    if kind == "missing" or body is None:
                        self.send_response(404)
                        self.end_headers()
                    elif kind == "corrupt":
                        self.send_response(200)
                        self.send_header("Content-Length", str(len(body)))
                        self.end_headers()
                        self.wfile.write(b"x" * len(body))
                    elif kind == "slow":
                        self.send_response(200)
                        self.send_header("Content-Length", str(len(body)))
                        self.end_headers()
                        for at in range(0, len(body), 2048):
                            self.wfile.write(body[at:at + 2048])
                            time.sleep(0.25)
                    else:
                        self.send_response(200)
                        self.send_header("Content-Length", str(len(body)))
                        self.end_headers()
                        self.wfile.write(body)
                except OSError:
                    pass  # the app dropped a slow source
                return
            name = self.path.strip("/").removesuffix(".json")
            if name.startswith("slow"):
                time.sleep(8)  # past the app's 6 s timeout
            body = pages.get(name)
            try:
                if body is None:
                    self.send_response(404)
                    self.end_headers()
                    return
                data = body.encode("utf-8")
                self.send_response(200)
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)
            except OSError:
                pass  # the client gave up on a slow page

    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    base = f"http://127.0.0.1:{server.server_address[1]}"

    def manifest(version, date, downloads=True):
        m = {"version": version, "date": date, "size": 1, "sha256": "0" * 64, "notes": {"zh": [date]}}
        if downloads:
            m["downloads"] = [{"id": "github", "url": base + "/dl"}]
        return json.dumps(m)

    pages.update(old=manifest("0.36.0", "old"), new=manifest("0.37.1", "first"), new2=manifest("0.37.1", "second"),
                 slow=manifest("0.38.0", "slow"), slow2=manifest("0.38.0", "slow2"),
                 partial=manifest("0.39.0", "partial", downloads=False), bad="{not json")

    def listed(date, *versions, downloads=True):
        return json.dumps({"versions": [json.loads(manifest(v, date, downloads=downloads)) for v in versions]})

    pages.update({"stale/versions": listed("stale", "0.37.1"), "full/versions": listed("full", "0.38.0", "0.37.1", "0.37.0"),
                  "broken/versions": listed("broken", "0.37.1", downloads=False), "nojson/versions": "{not json",
                  "notlisted/versions": json.dumps({"other": []})})

    # A package in five parts, and manifests whose parts come from different kinds of source.
    hits = collections.Counter()
    blobs = {f"part.{i:03d}": bytes([65 + i]) * 200000 for i in range(5)}
    whole = b"".join(blobs[k] for k in sorted(blobs))

    def split(version, kinds, size=None, names=None):
        files = [{"name": (names or {}).get(k, k), "size": len(v), "sha256": hashlib.sha256(v).hexdigest()} for k, v in sorted(blobs.items())]
        return json.dumps({"version": version, "date": "d", "size": size or len(whole), "sha256": hashlib.sha256(whole).hexdigest(),
                           "downloads": [{"id": "github", "url": base + "/whole"}],
                           "parts": {"files": files, "sources": [{"id": k, "url": f"{base}/src/{k}/"} for k in kinds]}})

    pages.update({"split-mixed": split("0.37.2", ["missing", "corrupt", "slow", "good"]),
                  "split-dead": split("0.37.4", ["missing", "corrupt"]),
                  "split-resume": split("0.37.3", ["resume"]),
                  "split-slow": split("0.37.5", ["slow"]),
                  "split-wrongsize": split("0.37.6", ["good"], size=1),
                  "split-badname": split("0.37.7", ["good"], names={"part.000": "../part.000"})})
    threading.Thread(target=server.serve_forever, daemon=True).start()

    wv = webview2_folder()
    with tempfile.TemporaryDirectory() as tmp:
        tmp = pathlib.Path(tmp)
        for dll in WEBVIEW2:
            shutil.copy2(wv / dll, tmp / dll)
        exe = tmp / "update_check.exe"
        subprocess.run([str(CSC), "/nologo", "/target:exe", "/platform:x64", "/utf8output", "/codepage:65001",
                        "/main:PhantomGladiator.UpdateCheckTest", f"/out:{exe}", *[f"/r:{r}" for r in REFS],
                        *[f"/r:{tmp / dll}" for dll in WEBVIEW2],
                        str(ROOT / "desktop/PhantomGladiator.cs"), str(ROOT / "desktop/AppUpdate.cs"), str(ROOT / "desktop/ManualBeta.cs"),
                        str(ROOT / "tools/test_update_check.cs")], check=True)
        # A crash prints in the console's code page, not UTF-8.
        run = subprocess.run([str(exe), base], capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=240,
                             env=dict(os.environ, PG_DATA_DIR=str(tmp / "data")))
    server.shutdown()
    print(run.stdout, end="")
    if run.stderr:
        print(run.stderr, end="", file=sys.stderr)
    sys.exit(run.returncode)


if __name__ == "__main__":
    main()
