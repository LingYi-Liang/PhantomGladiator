"""Updates replace the app's files in place (desktop/AppUpdate.cs), tested for real on Windows: a test exe built
from the same AppSwap code renames itself and a DLL it has loaded while running, copies the new version in,
starts the new exe and exits; the new exe cleans up. A swap that fails halfway puts the old files back.

usage: python -I tools/test_app_update.py
"""
import pathlib, shutil, subprocess, sys, tempfile, time

ROOT = pathlib.Path(__file__).resolve().parents[1]
CSC = pathlib.Path(r"C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe")
SYSTEM_DLL = pathlib.Path(r"C:\Windows\System32\version.dll")  # any small native DLL stands in for WebView2Loader.dll


def write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def version(folder, exe, name, extra):
    folder.mkdir(parents=True)
    shutil.copy2(exe, folder / "PhantomGladiator.exe")
    shutil.copy2(SYSTEM_DLL, folder / "Fake.dll")
    write(folder / "app" / "version.txt", name)
    write(folder / "app" / "python" / "lib.txt", name)
    for rel, text in extra.items():
        write(folder / rel, text)


def run(installed, new, report):
    subprocess.run([str(installed / "PhantomGladiator.exe"), "--swap", str(new), str(report)], check=False)
    for _ in range(300):
        if report.exists():
            time.sleep(0.2)
            return report.read_text(encoding="utf-8")
        time.sleep(0.1)
    raise AssertionError("no report from the test exe")


def main():
    work = pathlib.Path(tempfile.mkdtemp(prefix="pg-update-"))
    try:
        exe = work / "AppUpdateTest.exe"
        subprocess.run([str(CSC), "/nologo", "/target:exe", "/platform:x64", "/utf8output", "/codepage:65001", f"/out:{exe}",
                        str(ROOT / "tools" / "AppUpdateTest.cs"), str(ROOT / "desktop" / "AppUpdate.cs")], check=True)

        # A normal update: the running exe and its loaded DLL are replaced, folders swapped whole, files the new
        # version does not bring are kept, leftovers of an earlier update deleted, and the new exe cleans up.
        installed, new = work / "installed", work / "new"
        version(installed, exe, "A", {"licenses/old.txt": "A", "my-notes.txt": "mine", "stale.old": "left by an earlier update"})
        version(new, exe, "B", {"licenses/new.txt": "B"})
        report = run(installed, new, work / "report-ok.txt")
        lines = report.splitlines()
        assert lines[0] == "ok", report
        assert "version=B" in lines and "app/python/lib.txt" in lines and "licenses/new.txt" in lines, report
        assert "licenses/old.txt" not in lines, "a folder is replaced as a whole"
        assert "my-notes.txt" in lines, "files the new version does not bring are kept"
        assert not any(line.endswith(".old") for line in lines), "nothing set aside is left once the new exe runs"
        assert (installed / "app" / "python" / "lib.txt").read_text(encoding="utf-8") == "B"
        print("PASS update in place: running exe and loaded DLL replaced, old files cleaned up by the new exe")

        # A swap that fails halfway (the last entry is held open, so it cannot be set aside) restores everything.
        installed, new = work / "installed2", work / "new2"
        version(installed, exe, "A", {"licenses/old.txt": "A", "zz_locked.txt": "A"})
        version(new, exe, "B", {"licenses/new.txt": "B", "zz_locked.txt": "B"})
        with open(installed / "zz_locked.txt", "r", encoding="utf-8"):
            report = run(installed, new, work / "report-failed.txt")
        lines = report.splitlines()
        assert lines[0].startswith("failed: "), report
        assert "version=A" in lines and "licenses/old.txt" in lines and "Fake.dll" in lines and "PhantomGladiator.exe" in lines, report
        assert not any(line.endswith(".old") for line in lines) and "licenses/new.txt" not in lines, report
        assert (installed / "zz_locked.txt").read_text(encoding="utf-8") == "A"
        print("PASS failed swap: the old version is restored, nothing new or set aside is left")
    finally:
        for _ in range(20):
            try:
                shutil.rmtree(work)
                break
            except OSError:
                time.sleep(0.5)
    print("app_update: PASS")


if __name__ == "__main__":
    sys.exit(main())
