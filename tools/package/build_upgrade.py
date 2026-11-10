"""Build a one-time upgrade executable from a published GitHub ZIP.

Usage: python tools/package/build_upgrade.py <published zip> [--out <folder>]
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import subprocess
import sys
from tempfile import TemporaryDirectory
from zipfile import ZipFile

from build import CSC, MANIFEST, MANIFESTS, ROOT, make_icon, sha256


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("package", type=Path)
    parser.add_argument("--out", type=Path, default=ROOT / "dist")
    args = parser.parse_args()
    package = args.package.resolve(strict=True)
    match = re.fullmatch(r"PhantomGladiator-(\d+\.\d+\.\d+)-win64\.zip", package.name)
    if not match:
        sys.exit("Pass the GitHub release ZIP.")
    version = match[1]
    digest = sha256(package)
    releases = json.loads((ROOT / "release/safe/versions.json").read_text(encoding="utf-8"))
    published = next((row for row in releases["versions"] if row["version"] == version), None)
    if not published or published["sha256"] != digest or published["size"] != package.stat().st_size:
        sys.exit("The ZIP does not match the safe release manifest.")
    with ZipFile(package) as archive:
        info = json.loads(archive.read(f"PhantomGladiator-{version}/app/version.json"))
        if info["appVersion"] != version or info.get("channel", "github") != "github" or info.get("manifests") != MANIFESTS:
            sys.exit("The ZIP is not the matching GitHub build.")

    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    exe = out / f"PhantomGladiator-Upgrade-{version}.exe"
    sidecar = exe.with_suffix(".exe.sha256")
    if exe.exists() or sidecar.exists():
        sys.exit("The output already exists. Use a new output folder.")
    with TemporaryDirectory(prefix="pg-upgrade-", dir=out) as scratch:
        work = Path(scratch)
        icon = work / "app.ico"
        make_icon(icon)
        manifest = work / "app.manifest"
        manifest.write_text(MANIFEST.format(version=version), encoding="utf-8")
        stamp = work / "upgrade.txt"
        stamp.write_text(f"{version}\n{digest}\n", encoding="utf-8")
        built = work / exe.name
        subprocess.run([
            str(CSC), "/nologo", "/target:winexe", "/platform:x64", "/optimize+", "/utf8output", "/codepage:65001",
            "/r:System.dll", "/r:System.Core.dll", "/r:System.Drawing.dll", "/r:System.Windows.Forms.dll",
            "/r:System.IO.Compression.dll", "/r:System.IO.Compression.FileSystem.dll", "/r:System.Web.Extensions.dll",
            "/r:Microsoft.CSharp.dll",
            f"/out:{built}", f"/win32icon:{icon}", f"/win32manifest:{manifest}",
            f"/resource:{package},release.zip", f"/resource:{stamp},upgrade.txt",
            str(ROOT / "desktop/Upgrade.cs"),
        ], check=True)
        built.rename(exe)
    built_digest = sha256(exe)
    with sidecar.open("x", encoding="utf-8", newline="\n") as checksum:
        checksum.write(f"{built_digest}  {exe.name}\n")
    print(f"{exe.name}: {exe.stat().st_size} bytes, SHA-256 {built_digest}")


if __name__ == "__main__":
    main()
