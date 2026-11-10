"""The Nexus Mods build of the app (desktop/PhantomGladiator.cs compiled with /define:NEXUS) has no update check,
download or install.

Compiles tools/test_nexus_build.cs with the app source twice, with and without NEXUS, and runs it against a local
fake update server: the Nexus build refuses every update call and the server sees no request; the GitHub build does
reach the server, so the test would notice a connection. Then compiles the app itself both ways and looks for strings
only the update code holds. Needs a folder with the WebView2 assemblies, by default the newest built
dist/PhantomGladiator-* folder:

    python -I tools/test_nexus_build.py [webview2 folder]
"""
import http.server, json, os, pathlib, shutil, subprocess, sys, tempfile, threading

ROOT = pathlib.Path(__file__).resolve().parent.parent
CSC = pathlib.Path(r"C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe")
REFS = ["System.dll", "System.Core.dll", "System.Drawing.dll", "System.Windows.Forms.dll", "System.Web.Extensions.dll",
        "System.IO.Compression.dll", "System.IO.Compression.FileSystem.dll"]
WEBVIEW2 = ["Microsoft.Web.WebView2.Core.dll", "Microsoft.Web.WebView2.WinForms.dll"]
APP = [str(ROOT / "desktop/PhantomGladiator.cs"), str(ROOT / "desktop/AppUpdate.cs"), str(ROOT / "desktop/ManualBeta.cs")]
# Literals only the update check, download, verify and install code holds (UTF-16 in the exe's string heap).
UPDATE_ONLY = ["versions.json", "所有下载节点都失败了。", "下载的文件校验不通过，已删除。请换一条线路重试。", "更新包的版本与所选版本不一致。"]


def webview2_folder():
    if len(sys.argv) > 1:
        return pathlib.Path(sys.argv[1])
    built = [p for p in (ROOT / "dist").glob("PhantomGladiator-*") if (p / WEBVIEW2[0]).is_file()]
    if not built:
        sys.exit("no built dist/PhantomGladiator-* folder with the WebView2 assemblies; pass one")
    return max(built, key=lambda p: p.stat().st_mtime)


def compile_exe(out, target, nexus, *extra):
    args = [str(CSC), "/nologo", f"/target:{target}", "/platform:x64", "/optimize+", "/utf8output", "/codepage:65001",
            f"/out:{out}", *[f"/r:{r}" for r in REFS], *[f"/r:{out.parent / dll}" for dll in WEBVIEW2], *APP, *extra]
    if nexus:
        args.insert(2, "/define:NEXUS")
    subprocess.run(args, check=True)


def main():
    hits = []
    manifest = json.dumps({"version": "0.40.9", "date": "d", "size": 1, "sha256": "0" * 64,
                           "downloads": [{"id": "github", "url": "http://127.0.0.1:1/never"}]}).encode("utf-8")

    class Handler(http.server.BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass

        def do_HEAD(self):
            hits.append("HEAD " + self.path)
            self.send_response(200)
            self.end_headers()

        def do_GET(self):
            hits.append("GET " + self.path)
            self.send_response(200)
            self.send_header("Content-Length", str(len(manifest)))
            self.end_headers()
            self.wfile.write(manifest)

    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    base = f"http://127.0.0.1:{server.server_address[1]}"
    threading.Thread(target=server.serve_forever, daemon=True).start()

    failures = 0

    def expect(ok, what):
        nonlocal failures
        print(("PASS " if ok else "FAIL ") + what)
        failures += 0 if ok else 1

    wv = webview2_folder()
    with tempfile.TemporaryDirectory() as tmp:
        tmp = pathlib.Path(tmp)
        for dll in WEBVIEW2:
            shutil.copy2(wv / dll, tmp / dll)
        for channel in ("nexus", "github"):
            exe = tmp / f"nexus_test_{channel}.exe"
            compile_exe(exe, "exe", channel == "nexus", "/main:PhantomGladiator.NexusBuildTest", str(ROOT / "tools/test_nexus_build.cs"))
            hits.clear()
            run = subprocess.run([str(exe), base], capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=120,
                                 env=dict(os.environ, PG_DATA_DIR=str(tmp / f"data-{channel}")))
            print(f"--- {channel} build:")
            print(run.stdout, end="")
            if run.stderr:
                print(run.stderr, end="", file=sys.stderr)
            expect(run.returncode == 0, f"{channel} build: the harness passes")
            if channel == "nexus":
                expect(not hits, f"nexus build: the update server got no request ({len(hits)})")
            else:
                expect(any(h.startswith("GET /") for h in hits), f"github build: the update server was asked ({len(hits)} requests)")

        # The shipped app itself, compiled both ways.
        held = {}
        for channel in ("nexus", "github"):
            exe = tmp / f"app_{channel}.exe"
            compile_exe(exe, "winexe", channel == "nexus")
            data = exe.read_bytes()
            held[channel] = [s for s in UPDATE_ONLY if s.encode("utf-16-le") in data]
        expect(held["github"] == UPDATE_ONLY, f"github app holds the update code ({len(held['github'])}/{len(UPDATE_ONLY)} strings)")
        expect(not held["nexus"], f"nexus app holds none of the update code's strings {held['nexus']}")
    server.shutdown()
    print("nexus_build: " + ("PASS" if failures == 0 else f"{failures} FAILED"))
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
