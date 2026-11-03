"""A whole update the way the app does it (desktop/PhantomGladiator.cs UpdateClient + desktop/AppUpdate.cs), on
this machine: an "installed" folder with version 0.37.21 checks a local fake server, downloads the 0.37.22 zip,
verifies its SHA-256 and installs it in place; the new exe waits for the old one, cleans up and reports. The test
exe stands in for PhantomGladiator.exe in both versions (tools/test_update_install.cs as the entry point).
Needs a folder with the WebView2 assemblies, by default the newest built dist/PhantomGladiator-* folder:

    python -I tools/test_update_install.py [webview2 folder]
"""
import hashlib, http.server, io, json, os, pathlib, shutil, subprocess, sys, tempfile, threading, time, zipfile

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


def version_json(version, base):
    return json.dumps({"appVersion": version, "modBuild": "test", "verifiedGameBuild": "0", "repo": "test/test",
                       "manifests": [f"local|{base}/latest.json"]})


def main():
    files = {}

    class Handler(http.server.BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass

        def do_HEAD(self):
            self.send_response(200)
            self.end_headers()

        def do_GET(self):
            body = files.get(self.path)
            self.send_response(200 if body is not None else 404)
            self.end_headers()
            if body is not None:
                self.wfile.write(body)

    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    base = f"http://127.0.0.1:{server.server_address[1]}"
    threading.Thread(target=server.serve_forever, daemon=True).start()
    wv = webview2_folder()
    work = pathlib.Path(tempfile.mkdtemp(prefix="pg-install-"))
    try:
        exe = work / "PhantomGladiator.exe"
        subprocess.run([str(CSC), "/nologo", "/target:exe", "/platform:x64", "/utf8output", "/codepage:65001",
                        "/main:PhantomGladiator.UpdateInstallTest", f"/out:{exe}", *[f"/r:{r}" for r in REFS],
                        *[f"/r:{wv / dll}" for dll in WEBVIEW2], str(ROOT / "desktop/PhantomGladiator.cs"),
                        str(ROOT / "desktop/AppUpdate.cs"), str(ROOT / "tools/test_update_install.cs")], check=True)

        # The new version as a release zip: one top folder holding the exe, its DLLs and app\.
        package = io.BytesIO()
        with zipfile.ZipFile(package, "w") as z:
            top = "PhantomGladiator-0.37.22/"
            z.write(exe, top + "PhantomGladiator.exe")
            for dll in WEBVIEW2:
                z.write(wv / dll, top + dll)
            z.writestr(top + "app/version.json", version_json("0.37.22", base))
            z.writestr(top + "app/python/lib.txt", "B")
            z.writestr(top + "licenses/new.txt", "B")
        package = package.getvalue()
        files["/pkg.zip"] = package
        files["/latest.json"] = json.dumps({"version": "0.37.22", "date": "2026-11-02T00:00:00+08:00", "size": len(package),
                                            "sha256": hashlib.sha256(package).hexdigest(), "notes": {"zh": ["test"]},
                                            "downloads": [{"id": "github", "url": base + "/pkg.zip"}]}).encode("utf-8")

        # The installed old version, with a file of the player's own and what versions before 0.37.6 left behind.
        installed, data = work / "installed", work / "data"
        (installed / "app" / "python").mkdir(parents=True)
        (installed / "licenses").mkdir()
        shutil.copy2(exe, installed / "PhantomGladiator.exe")
        for dll in WEBVIEW2:
            shutil.copy2(wv / dll, installed / dll)
        (installed / "app" / "version.json").write_text(version_json("0.37.21", base), encoding="utf-8")
        (installed / "app" / "python" / "lib.txt").write_text("A", encoding="utf-8")
        (installed / "licenses" / "old.txt").write_text("A", encoding="utf-8")
        (installed / "my-notes.txt").write_text("mine", encoding="utf-8")
        (data / "updates").mkdir(parents=True)
        (data / "updates" / "updater.exe").write_bytes(b"left by an old update")
        (data / "updates" / "Microsoft.Web.WebView2.Core.dll").write_bytes(b"left by an old update")

        report = work / "report.txt"
        env = dict(os.environ, PG_DATA_DIR=str(data), PG_TEST_REPORT=str(report))
        run = subprocess.run([str(installed / "PhantomGladiator.exe")], env=env, timeout=120)
        for _ in range(300):
            if report.exists():
                break
            time.sleep(0.1)
        assert report.exists(), f"no report (old exe exit code {run.returncode})"
        time.sleep(0.3)
        lines = report.read_text(encoding="utf-8").splitlines()
        text = "\n".join(lines)
        assert run.returncode == 0 and lines[0] == "ok", text
        assert "version=0.37.22" in lines, text
        assert (installed / "app" / "python" / "lib.txt").read_text(encoding="utf-8") == "B"
        assert "licenses/new.txt" in lines and "licenses/old.txt" not in lines, text
        assert "my-notes.txt" in lines, "a file of the player's own stays"
        assert not any(line.endswith(".old") for line in lines), "nothing set aside is left once the new exe runs"
        updates = next(line for line in lines if line.startswith("updates=")).split("=", 1)[1].split(",")
        assert updates == ["PhantomGladiator-0.37.22.zip"], f"the old updater copy and the unpacked files are gone: {updates}"
        print("PASS a whole update: check, download, SHA-256, in-place install, the new exe takes over and cleans up")
    finally:
        server.shutdown()
        for _ in range(20):
            try:
                shutil.rmtree(work)
                break
            except OSError:
                time.sleep(0.5)
    print("update_install: PASS")


if __name__ == "__main__":
    main()
