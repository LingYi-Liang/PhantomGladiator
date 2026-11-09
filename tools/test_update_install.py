"""A whole update the way the app does it (desktop/PhantomGladiator.cs UpdateClient + desktop/AppUpdate.cs), on
this machine: an "installed" folder with version 0.40.11 checks a local fake server, downloads the 0.40.12 zip,
verifies its SHA-256 and installs it in place; the new exe waits for the old one, cleans up and reports. Then going
back: another folder at 0.40.11 picks 0.40.10 from versions.json, then updates forward again. Older versions run
in a separate installation.
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

        files["/latest.json"] = json.dumps(release("0.40.12")).encode("utf-8")
        files["/versions.json"] = json.dumps({"versions": [release("0.40.11"), release("0.40.10"), release("0.40.9")]}).encode("utf-8")

        def setup(name):
            # The installed old version, with a file of the player's own and what versions before 0.37.6 left behind.
            installed, data = work / name, work / (name + "-data")
            (installed / "app" / "python").mkdir(parents=True)
            (installed / "licenses").mkdir()
            shutil.copy2(exe, installed / "PhantomGladiator.exe")
            for dll in WEBVIEW2:
                shutil.copy2(wv / dll, installed / dll)
            (installed / "app" / "version.json").write_text(version_json("0.40.11", base), encoding="utf-8")
            (installed / "app" / "python" / "lib.txt").write_text("A", encoding="utf-8")
            (installed / "licenses" / "old.txt").write_text("A", encoding="utf-8")
            (installed / "my-notes.txt").write_text("mine", encoding="utf-8")
            (data / "updates").mkdir(parents=True)
            (data / "updates" / "updater.exe").write_bytes(b"left by an old update")
            (data / "updates" / "Microsoft.Web.WebView2.Core.dll").write_bytes(b"left by an old update")
            return installed, data

        for case in ("missing", "bad-config", "registration-error", "success"):
            installed, data = setup("components-" + case)
            game = installed / "test-game"
            ue4ss = game / "platform" / "steam" / "ue4ss"
            mods = ue4ss / "Mods"
            mod = mods / "PhantomGladiator"
            live = mod / "Scripts"
            live.mkdir(parents=True)
            assert work.resolve() in live.resolve().parents
            (mods / "shared").mkdir()
            (ue4ss / "UE4SS.dll").write_bytes(b"test loader")
            (ue4ss.parent / "dwmapi.dll").write_bytes(b"test proxy")
            (live / "main.lua").write_text("old scripts", encoding="utf-8")
            (live / "obsolete.lua").write_text("old only", encoding="utf-8")
            runtime = mod / "Runtime"
            runtime.mkdir()
            (runtime / "catalog.tsv").write_text("existing catalog", encoding="utf-8")
            mods_txt = mods / "mods.txt"
            if case == "registration-error":
                mods_txt.mkdir()
            else:
                mods_txt.write_text("OtherMod : 1\n", encoding="utf-8")
            payload = installed / "app" / "payload"
            (payload / "gameconfig").mkdir(parents=True)
            (payload / "seed").mkdir()
            (payload / "seed" / "catalog.tsv").write_text("shipped seed", encoding="utf-8")
            if case != "missing":
                scripts = payload / "mod" / "PhantomGladiator" / "Scripts"
                scripts.mkdir(parents=True)
                (scripts / "main.lua").write_text("new scripts", encoding="utf-8")
                config = 'Config.Other = "bad"' if case == "bad-config" else 'Config.RuntimePath = "old path"'
                (scripts / "config.lua").write_text(config + "\n", encoding="utf-8")
            result = subprocess.run([str(installed / "PhantomGladiator.exe"), "--install-components"],
                                    env=dict(os.environ, PG_DATA_DIR=str(data)), capture_output=True, timeout=30)
            if case == "success":
                assert result.returncode == 0, result.stderr
                assert (live / "main.lua").read_text(encoding="utf-8") == "new scripts"
                assert not (live / "obsolete.lua").exists()
                assert f'Config.RuntimePath = "{runtime.as_posix()}"' in (live / "config.lua").read_text(encoding="utf-8")
                assert mods_txt.read_text(encoding="utf-8").splitlines() == ["OtherMod : 1", "PhantomGladiator : 1"]
            else:
                assert result.returncode != 0, case
                assert (live / "main.lua").is_file(), f"{case}: install removed the old scripts"
                assert (live / "main.lua").read_text(encoding="utf-8") == "old scripts"
                assert (live / "obsolete.lua").is_file()
            assert (runtime / "catalog.tsv").read_text(encoding="utf-8") == "existing catalog"
            assert not list(mod.glob(".pg-install-*")), case
            print(f"PASS components {case}: read back scripts and Runtime")

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
        assert "version=0.40.12" in lines, text
        assert (installed / "app" / "python" / "lib.txt").read_text(encoding="utf-8") == "0.40.12"
        assert "licenses/new.txt" in lines and "licenses/old.txt" not in lines, text
        assert "my-notes.txt" in lines, "a file of the player's own stays"
        assert not any(line.startswith(".pg-app-swap-") for line in lines), "the new exe cleaned its completed backup"
        updates = next(line for line in lines if line.startswith("updates=")).split("=", 1)[1].split(",")
        assert updates == ["PhantomGladiator-0.40.12.zip"], f"the old updater copy and the unpacked files are gone: {updates}"
        print("PASS a whole update: check, download, SHA-256, in-place install, the new exe takes over and cleans up")

        installed, data = setup("rolled-back")
        lines = run_app(installed, data, back="0.40.10")
        text = "\n".join(lines)
        assert "version=0.40.10" in lines, text
        assert (installed / "app" / "python" / "lib.txt").read_text(encoding="utf-8") == "0.40.10"
        assert "my-notes.txt" in lines, "a file of the player's own stays"
        assert not any(line.startswith(".pg-app-swap-") for line in lines), text
        print("PASS going back: the older version is picked from versions.json and installed the same way")
        lines = run_app(installed, data)
        assert "version=0.40.12" in lines, "\n".join(lines)
        assert (installed / "app" / "python" / "lib.txt").read_text(encoding="utf-8") == "0.40.12"
        print("PASS and from the older version the player updates forward again")

        installed, data = setup("legacy-rollback")
        (installed / "my-backup.old").write_text("mine", encoding="utf-8")
        (installed / "notes.old").mkdir()
        (installed / "notes.old" / "note.txt").write_text("mine", encoding="utf-8")
        lines = run_app(installed, data, back="0.40.9")
        directory = next(line.split("=", 1)[1] for line in lines if line.startswith("directory="))
        assert "version=0.40.9" in lines
        assert pathlib.Path(directory).parent.resolve() == (data / "versions").resolve()
        assert json.loads((installed / "app" / "version.json").read_text(encoding="utf-8"))["appVersion"] == "0.40.11"
        assert (installed / "my-backup.old").read_text(encoding="utf-8") == "mine"
        assert (installed / "notes.old" / "note.txt").read_text(encoding="utf-8") == "mine"
        print("PASS legacy rollback: old exe runs in its own directory and the original backups stay")

        installed, data = setup("split")
        lines = run_app(installed, data, line="parts")
        text = "\n".join(lines)
        assert "version=0.40.12" in lines, text
        assert (installed / "app" / "python" / "lib.txt").read_text(encoding="utf-8") == "0.40.12"
        updates = next(line for line in lines if line.startswith("updates=")).split("=", 1)[1].split(",")
        assert updates == ["PhantomGladiator-0.40.12.zip"], f"the parts are joined and gone: {updates}"
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
