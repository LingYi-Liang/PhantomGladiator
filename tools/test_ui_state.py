"""Exercise the native window's copy of the page preferences in an isolated data folder."""
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
    with tempfile.TemporaryDirectory(prefix="pg-ui-state-test-") as name:
        work = Path(name)
        assert work.resolve().is_relative_to(Path(tempfile.gettempdir()).resolve())
        for dll in helper["WEBVIEW2"]:
            shutil.copy2(webview / dll, work / dll)
        exe = work / "UiStateTests.exe"
        subprocess.run([str(helper["CSC"]), "/nologo", "/target:exe", "/platform:x64", "/utf8output", "/codepage:65001",
                        "/main:PhantomGladiator.UiStateTests", f"/out:{exe}",
                        *[f"/r:{ref}" for ref in helper["REFS"]],
                        *[f"/r:{work / dll}" for dll in helper["WEBVIEW2"]],
                        *[str(ROOT / "desktop" / file) for file in ("PhantomGladiator.cs", "AppUpdate.cs", "ManualBeta.cs")],
                        str(ROOT / "tools/test_ui_state.cs")], check=True)
        data = work / "data"
        data.mkdir()
        subprocess.run([str(exe)], check=True, env=dict(os.environ, PG_DATA_DIR=str(data)))


if __name__ == "__main__":
    main()
