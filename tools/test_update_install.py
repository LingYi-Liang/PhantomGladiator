"""A whole update the way the app does it (desktop/PhantomGladiator.cs UpdateClient + desktop/AppUpdate.cs), on
this machine: an "installed" folder with version 0.37.21 checks a local fake server, downloads the 0.37.22 zip,
verifies its SHA-256 and installs it in place; the new exe waits for the old one, cleans up and reports. Then going
back: another folder at 0.37.21 picks 0.37.20 from versions.json the same way, and from there updates forward again.
The test exe stands in for PhantomGladiator.exe in every version (tools/test_update_install.cs as the entry point).
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

        # A version as a release zip: one top folder holding the exe, its DLLs and app\.
        def release(version):
            package = io.BytesIO()
            with zipfile.ZipFile(package, "w") as z:
                top = f"PhantomGladiator-{version}/"
                z.write(exe, top + "PhantomGladiator.exe")
                for dll in WEBVIEW2:
                    z.write(wv / dll, top + dll)
                z.writestr(top + "app/version.json", version_json(version, base))
                z.writestr(top + "app/python/lib.txt", version)
                z.writestr(top + "licenses/new.txt", "B")
            package = package.getvalue()
            files[f"/pkg-{version}.zip"] = package
            return {"version": version, "date": "2026-11-02T00:00:00+08:00", "size": len(package),
                    "sha256": hashlib.sha256(package).hexdigest(), "notes": {"zh": ["test"]},
                    "downloads": [{"id": "github", "url": f"{base}/pkg-{version}.zip"}],
                    "parts": split(version, package)}

        def split(version, package):
            parts = []
            for at in range(0, len(package), 1024 * 1024):
                piece, name = package[at:at + 1024 * 1024], f"{version}.{at // (1024 * 1024):03d}"
                files[f"/parts/{name}"] = piece
                parts.append({"name": name, "size": len(piece), "sha256": hashlib.sha256(piece).hexdigest()})
            return {"files": parts, "sources": [{"id": "local", "url": f"{base}/parts/"}]}

        files["/latest.json"] = json.dumps(release("0.37.22")).encode("utf-8")
        files["/versions.json"] = json.dumps({"versions": [release("0.37.21"), release("0.37.20")]}).encode("utf-8")

        def setup(name):
            # The installed old version, with a file of the player's own and what versions before 0.37.6 left behind.
            installed, data = work / name, work / (name + "-data")
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
            return installed, data

        def run_app(installed, data, back="", line=""):
            report = work / "report.txt"
            report.unlink(missing_ok=True)
            env = dict(os.environ, PG_DATA_DIR=str(data), PG_TEST_REPORT=str(report), PG_TEST_ROLLBACK=back, PG_TEST_LINE=line)
            run = subprocess.run([str(installed / "PhantomGladiator.exe")], env=env, timeout=120)
            for _ in range(300):
                if report.exists():
                    break
                time.sleep(0.1)
            assert report.exists(), f"no report (old exe exit code {run.returncode})"
            time.sleep(0.3)
            lines = report.read_text(encoding="utf-8").splitlines()
            assert run.returncode == 0 and lines[0] == "ok", "\n".join(lines)
            return lines

        installed, data = setup("installed")
        lines = run_app(installed, data)
        text = "\n".join(lines)
        assert "version=0.37.22" in lines, text
        assert (installed / "app" / "python" / "lib.txt").read_text(encoding="utf-8") == "0.37.22"
        assert "licenses/new.txt" in lines and "licenses/old.txt" not in lines, text
        assert "my-notes.txt" in lines, "a file of the player's own stays"
        assert not any(line.endswith(".old") for line in lines), "nothing set aside is left once the new exe runs"
        updates = next(line for line in lines if line.startswith("updates=")).split("=", 1)[1].split(",")
        assert updates == ["PhantomGladiator-0.37.22.zip"], f"the old updater copy and the unpacked files are gone: {updates}"
        print("PASS a whole update: check, download, SHA-256, in-place install, the new exe takes over and cleans up")

        installed, data = setup("rolled-back")
        lines = run_app(installed, data, back="0.37.20")
        text = "\n".join(lines)
        assert "version=0.37.20" in lines, text
        assert (installed / "app" / "python" / "lib.txt").read_text(encoding="utf-8") == "0.37.20"
        assert "my-notes.txt" in lines, "a file of the player's own stays"
        assert not any(line.endswith(".old") for line in lines), text
        print("PASS going back: the older version is picked from versions.json and installed the same way")
        lines = run_app(installed, data)
        assert "version=0.37.22" in lines, "\n".join(lines)
        assert (installed / "app" / "python" / "lib.txt").read_text(encoding="utf-8") == "0.37.22"
        print("PASS and from the older version the player updates forward again")

        installed, data = setup("split")
        lines = run_app(installed, data, line="parts")
        text = "\n".join(lines)
        assert "version=0.37.22" in lines, text
        assert (installed / "app" / "python" / "lib.txt").read_text(encoding="utf-8") == "0.37.22"
        updates = next(line for line in lines if line.startswith("updates=")).split("=", 1)[1].split(",")
        assert updates == ["PhantomGladiator-0.37.22.zip"], f"the parts are joined and gone: {updates}"
        print("PASS a split download joins, passes SHA-256 and installs the same way")
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
