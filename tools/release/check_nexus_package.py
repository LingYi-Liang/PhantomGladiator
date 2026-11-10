"""Checks the Nexus Mods upload built by tools/package/build.py --channel nexus before it goes to the Files page.

    python -I tools/release/check_nexus_package.py dist/PhantomGladiator-X-nexus-win64.zip

Nexus Mods turns away an upload with an archive inside it and does not allow files that download updates. Checks that
no file inside is an archive (by its first bytes, whatever its name), that the Python standard library is unpacked and
listed in python311._pth, that version.json names the nexus channel with no update sources, that the exe holds none of
the update code's strings, that the readme points to the mod page, and that the packaged backend starts on the
bundled Python and serves the page, as the app starts it.
"""
import json, os, pathlib, socket, subprocess, sys, tempfile, time, urllib.request, zipfile

MAGIC = {b"PK\x03\x04": "zip", b"PK\x05\x06": "empty zip", b"7z\xbc\xaf\x27\x1c": "7z", b"Rar!\x1a\x07": "rar",
         b"\x1f\x8b": "gzip", b"BZh": "bzip2", b"\xfd7zXZ\x00": "xz", b"MSCF": "cab"}
# Literals only the update check, download, verify and install code holds (tools/test_nexus_build.py).
UPDATE_ONLY = ["versions.json", "所有下载节点都失败了。", "下载的文件校验不通过，已删除。请换一条线路重试。", "更新包的版本与所选版本不一致。"]
NEXUS_PAGE = "https://www.nexusmods.com/phantombladezero/mods/363"

failures = 0


def expect(ok, what):
    global failures
    print(("PASS " if ok else "FAIL ") + what)
    failures += 0 if ok else 1


def free_port():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def main():
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    archive = pathlib.Path(sys.argv[1])
    with zipfile.ZipFile(archive) as z:
        files = [i for i in z.infolist() if not i.is_dir()]
        tops = {i.filename.split("/")[0] for i in files}
        expect(len(tops) == 1 and next(iter(tops)).endswith("-nexus"), f"one top folder named *-nexus: {sorted(tops)}")
        top = next(iter(tops))
        inner = []
        for i in files:
            with z.open(i) as f:
                head = f.read(8)
            kind = next((k for m, k in MAGIC.items() if head.startswith(m)), None)
            if kind:
                inner.append(f"{i.filename} ({kind})")
        expect(not inner, f"no archive inside the upload ({len(files)} files): {inner}")
        names = {i.filename for i in files}
        info = json.loads(z.read(f"{top}/app/version.json"))
        expect(info.get("channel") == "nexus" and info.get("manifests") == [], f"version.json: channel {info.get('channel')}, update sources {info.get('manifests')}")
        pth = [line.strip() for line in z.read(f"{top}/app/python/python311._pth").decode("utf-8").splitlines()
               if line.strip() and not line.lstrip().startswith("#")]
        expect("Lib" in pth and not any(p.endswith(".zip") for p in pth), f"python311._pth lists {pth}")
        expect(f"{top}/app/python/Lib/encodings/__init__.pyc" in names, "the standard library is unpacked in app/python/Lib")
        exe = z.read(f"{top}/PhantomGladiator.exe")
        held = [s for s in UPDATE_ONLY if s.encode("utf-16-le") in exe]
        expect(not held and "updatesOff".encode("utf-16-le") in exe, f"the exe is the nexus build without update code {held}")
        readme = z.read(f"{top}/使用说明.txt").decode("utf-8-sig")
        expect(readme.count(NEXUS_PAGE) == 2, "the readme points to the mod page (Chinese and English)")

        with tempfile.TemporaryDirectory() as tmp:
            tmp = pathlib.Path(tmp)
            z.extractall(tmp)
            app = tmp / top / "app"
            run = subprocess.run([str(app / "python/python.exe"), "-I", "-X", "utf8", "-c",
                                  "import sys, encodings, sqlite3, ssl, json, http.server, zipfile; print(sys.version.split()[0], encodings.__file__)"],
                                 capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=60)
            expect(run.returncode == 0 and "Lib" in run.stdout, f"bundled Python imports its library from Lib: {run.stdout.strip() or run.stderr.strip()}")
            # The backend as the app starts it (desktop/PhantomGladiator.cs Backend.Start), on an empty Runtime folder.
            runtime = tmp / "Runtime"
            runtime.mkdir()
            port = free_port()
            backend = subprocess.Popen([str(app / "python/python.exe"), "-I", "-X", "utf8", str(app / "backend/backend.py"),
                                        "--runtime-dir", str(runtime), "--port", str(port), "--static-dir", str(app / "ui")],
                                       cwd=app / "backend", stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                       env=dict(os.environ, PYTHONIOENCODING="utf-8"))
            page = None
            try:
                for _ in range(100):
                    if backend.poll() is not None:
                        break
                    try:
                        with urllib.request.urlopen(f"http://127.0.0.1:{port}/", timeout=1) as r:
                            page = r.read().decode("utf-8", "replace")
                        break
                    except OSError:
                        time.sleep(0.2)
            finally:
                backend.kill()
                out = backend.communicate(timeout=10)[0].decode("utf-8", "replace")
            expect(page is not None and "real-runtime.js" in page, "the packaged backend starts and serves the app page"
                   + ("" if page else f": {out.strip()[-800:]}"))
    print(f"{archive.name}: " + ("OK" if failures == 0 else f"{failures} FAILED"))
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
