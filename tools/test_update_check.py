"""The app's update check (desktop/PhantomGladiator.cs UpdateClient.Check) against a local fake server.

Compiles the app source with tools/test_update_check.cs as the entry point using the .NET Framework's csc,
serves manifests from 127.0.0.1 and runs it. Needs a folder with the WebView2 assemblies, by default the
newest built dist/PhantomGladiator-* folder:

    python -I tools/test_update_check.py [webview2 folder]
"""
import http.server, json, pathlib, shutil, subprocess, sys, tempfile, threading, time

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
                        str(ROOT / "desktop/PhantomGladiator.cs"), str(ROOT / "desktop/AppUpdate.cs"),
                        str(ROOT / "tools/test_update_check.cs")], check=True)
        # A crash prints in the console's code page, not UTF-8.
        run = subprocess.run([str(exe), base], capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=120)
    server.shutdown()
    print(run.stdout, end="")
    if run.stderr:
        print(run.stderr, end="", file=sys.stderr)
    sys.exit(run.returncode)


if __name__ == "__main__":
    main()
