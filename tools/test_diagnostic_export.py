"""Exercise the real report archive creator using isolated files, never the user's Desktop."""
import os
from pathlib import Path
import runpy
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    helper = runpy.run_path(str(ROOT / "tools/test_update_check.py"), run_name="compile_fixture")
    webview = helper["webview2_folder"]()
    with tempfile.TemporaryDirectory(prefix="pg-report-test-") as name:
        work = Path(name)
        assert work.resolve().is_relative_to(Path(tempfile.gettempdir()).resolve())
        for dll in helper["WEBVIEW2"]:
            shutil.copy2(webview / dll, work / dll)
        exe = work / "DiagnosticExportTests.exe"
        subprocess.run([str(helper["CSC"]), "/nologo", "/target:exe", "/platform:x64", "/utf8output", "/codepage:65001",
                        "/main:PhantomGladiator.DiagnosticExportTests", f"/out:{exe}",
                        *[f"/r:{ref}" for ref in helper["REFS"]],
                        *[f"/r:{work / dll}" for dll in helper["WEBVIEW2"]],
                        *[str(ROOT / "desktop" / file) for file in ("PhantomGladiator.cs", "AppUpdate.cs", "ManualBeta.cs")],
                        str(ROOT / "tools/test_diagnostic_export.cs")], check=True)
        reports = work / "reports"
        reports.mkdir()
        subprocess.run([str(exe), str(reports)], check=True, env=dict(os.environ, PG_DATA_DIR=str(work / "data")))


if __name__ == "__main__":
    main()
