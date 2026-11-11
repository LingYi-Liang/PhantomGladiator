"""Builds the player package: dist/PhantomGladiator-<version>/ and its zip.

usage: python tools/package/build.py --deps <folder> [--seed <Runtime folder>] [--version 0.30.0] [--channel nexus]

--deps holds the three third-party downloads pinned below (fetched once, by hand, from the listed
URLs). --seed is a Runtime folder whose codex export becomes the slim catalog shipped with the app;
it defaults to the author's game install. Nothing here touches the game or the player's data.

--channel nexus builds the Nexus Mods upload, PhantomGladiator-<version>-nexus: the app is compiled without
its update check and download (Nexus Mods does not allow files that download updates), and the embeddable
Python's standard library is unpacked from its zip (an archive inside the upload is turned away).
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
import subprocess
import sys
import time
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DEPS = {
    "python": ("python-3.11.9-embed-amd64.zip", "009d6bf7e3b2ddca3d784fa09f90fe54336d5b60f0e0f305c37f400bf83cfd3b",
               "https://www.python.org/ftp/python/3.11.9/python-3.11.9-embed-amd64.zip"),
    "webview2": ("microsoft.web.webview2.1.0.4191.47.nupkg", "f492bbf547d0da329553b6727435b677579b1e9f91cc9e4a1ad029366d5f23d0",
                 "https://api.nuget.org/v3-flatcontainer/microsoft.web.webview2/1.0.4191.47/microsoft.web.webview2.1.0.4191.47.nupkg"),
    # UE4SS experimental build 3.0.1-1185 (dff435dd), the one GameConfig is verified with. UE4SS replaced that
    # experimental release with later builds (1195 at the time of writing), so the files are taken unchanged from this
    # app's v0.37.5 package, which unpacked the original zip (SHA-256 67b81fca…0d31) into app/payload/ue4ss.
    "ue4ss": ("PhantomGladiator-0.37.5-win64.zip", "ec6e57bca09ffad7fdce500ab0a8179c7745465a05567781b186ff0387ebfffa",
              "https://github.com/LingYi-Liang/PhantomGladiator/releases/download/v0.37.5/PhantomGladiator-0.37.5-win64.zip"),
}
UE4SS_IN_PACKAGE = "PhantomGladiator-0.37.5/app/payload/ue4ss/"
VERIFIED_GAME_BUILD = "26367565"
REPO = "LingYi-Liang/PhantomGladiator"
NEXUS_PAGE = "https://www.nexusmods.com/phantombladezero/mods/363"
# The legacy feed offers only the one-time migration to 0.40.10.
MANIFESTS = [
    f"cdn|https://cdn.jsdelivr.net/gh/{REPO}@main/release/safe/latest.json",
    f"mirror|https://fastly.jsdelivr.net/gh/{REPO}@main/release/safe/latest.json",
    f"github|https://raw.githubusercontent.com/{REPO}/main/release/safe/latest.json",
]
UI_FILES = ["styles.css", "i18n.js", "i18n-more.js", "units.js", "changelog.js", "ai-params.js", "real-runtime.js", "app.js", "support-wechat.png"]
BACKEND_FILES = ["backend.py", "catalog_labels.py", "catalog_taxonomy.py", "unit_validation.json"]
SEED_FILES = ["catalog.tsv", "codex.tsv", "codex-locations.tsv", "inventory-report.json"]
CSC = Path(r"C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe")
FRAMEWORK_REFS = ["System.dll", "System.Core.dll", "System.Drawing.dll", "System.Windows.Forms.dll", "System.Web.Extensions.dll",
                  "System.IO.Compression.dll", "System.IO.Compression.FileSystem.dll"]


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def dependency(deps: Path, key: str) -> Path:
    name, digest, url = DEPS[key]
    path = deps / name
    if not path.is_file():
        sys.exit(f"missing {name}; download it from {url}")
    if sha256(path) != digest:
        sys.exit(f"{name}: SHA-256 does not match the pinned value")
    return path


def extract(archive: Path, target: Path, members=None, strip="") -> None:
    """Unpacks the archive (only the entries under `members`, if given) into target, dropping the `strip` prefix."""
    with zipfile.ZipFile(archive) as z:
        for info in z.infolist():
            name = info.filename
            if members and not any(name.startswith(m) for m in members):
                continue
            if strip:
                if not name.startswith(strip) or name == strip:
                    continue
                name = name[len(strip):]
            out = (target / name).resolve()
            if not out.is_relative_to(target.resolve()):
                sys.exit(f"{archive.name}: unsafe path {name}")
            if info.is_dir():
                out.mkdir(parents=True, exist_ok=True)
                continue
            out.parent.mkdir(parents=True, exist_ok=True)
            with z.open(info) as src, out.open("wb") as dst:
                shutil.copyfileobj(src, dst)


def make_icon(target: Path) -> None:
    """The seal from the UI header ("斗" on red), rendered by System.Drawing at the usual icon sizes."""
    sizes = [16, 24, 32, 48, 64, 128, 256]
    work = target.parent / "icon-png"
    work.mkdir(exist_ok=True)
    script = rf"""
Add-Type -AssemblyName System.Drawing
foreach ($s in @({','.join(map(str, sizes))})) {{
  $bmp = New-Object System.Drawing.Bitmap $s, $s
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = 'AntiAlias'; $g.TextRenderingHint = 'AntiAliasGridFit'
  $r = [Math]::Max(2, $s * 0.22); $path = New-Object System.Drawing.Drawing2D.GraphicsPath
  $path.AddArc(0, 0, $r * 2, $r * 2, 180, 90); $path.AddArc($s - $r * 2 - 1, 0, $r * 2, $r * 2, 270, 90)
  $path.AddArc($s - $r * 2 - 1, $s - $r * 2 - 1, $r * 2, $r * 2, 0, 90); $path.AddArc(0, $s - $r * 2 - 1, $r * 2, $r * 2, 90, 90); $path.CloseFigure()
  $g.FillPath((New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(181, 55, 42))), $path)
  $font = New-Object System.Drawing.Font 'KaiTi', ($s * 0.62), ([System.Drawing.FontStyle]::Bold), ([System.Drawing.GraphicsUnit]::Pixel)
  $fmt = New-Object System.Drawing.StringFormat; $fmt.Alignment = 'Center'; $fmt.LineAlignment = 'Center'
  $g.DrawString([string][char]0x6597, $font, [System.Drawing.Brushes]::White, (New-Object System.Drawing.RectangleF 0, ($s * 0.04), $s, $s), $fmt)
  $bmp.Save("{work}\$s.png", [System.Drawing.Imaging.ImageFormat]::Png)
  $g.Dispose(); $bmp.Dispose()
}}
"""
    subprocess.run(["powershell", "-NoProfile", "-NonInteractive", "-Command", script], check=True)
    pngs = [(s, (work / f"{s}.png").read_bytes()) for s in sizes]
    header = bytearray(b"\0\0\1\0" + len(pngs).to_bytes(2, "little"))
    offset = 6 + 16 * len(pngs)
    body = bytearray()
    for s, data in pngs:
        header += bytes([s % 256, s % 256, 0, 0]) + (1).to_bytes(2, "little") + (32).to_bytes(2, "little")
        header += len(data).to_bytes(4, "little") + (offset + len(body)).to_bytes(4, "little")
        body += data
    target.write_bytes(bytes(header + body))
    shutil.rmtree(work)


MANIFEST = """<?xml version="1.0" encoding="utf-8"?>
<assembly manifestVersion="1.0" xmlns="urn:schemas-microsoft-com:asm.v1">
  <assemblyIdentity version="{version}.0" name="PhantomGladiator" type="win32"/>
  <trustInfo xmlns="urn:schemas-microsoft-com:asm.v3"><security><requestedPrivileges>
    <requestedExecutionLevel level="asInvoker" uiAccess="false"/>
  </requestedPrivileges></security></trustInfo>
  <compatibility xmlns="urn:schemas-microsoft-com:compatibility.v1"><application>
    <supportedOS Id="{{8e0f7a12-bfb3-4fe8-b9a5-48fd50a15a9a}}"/>
  </application></compatibility>
  <application xmlns="urn:schemas-microsoft-com:asm.v3"><windowsSettings>
    <dpiAware xmlns="http://schemas.microsoft.com/SMI/2005/WindowsSettings">true/pm</dpiAware>
    <dpiAwareness xmlns="http://schemas.microsoft.com/SMI/2016/WindowsSettings">PerMonitorV2</dpiAwareness>
  </windowsSettings></application>
</assembly>
"""
EXE_CONFIG = """<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <startup><supportedRuntime version="v4.0" sku=".NETFramework,Version=v4.8"/></startup>
  <System.Windows.Forms.ApplicationConfigurationSection><add key="DpiAwareness" value="PerMonitorV2"/></System.Windows.Forms.ApplicationConfigurationSection>
</configuration>
"""
README = """斗蛐蛐 · 影之刃零怪物对战助手  v{version}
作者：泠依_01  B站UID：10010098
https://github.com/{repo}

【怎么用】
1. 把整个文件夹解压到任意位置（不要直接在压缩包里双击运行）。
2. 双击 PhantomGladiator.exe。第一次打开会自动找到《影之刃零》并一键装好需要的组件。
3. 启动游戏、进入地图，等助手右上角变绿，就可以选怪、召唤、开战了。

【说明】
- 只支持 Steam 版《影之刃零》build {game_build}，其他版本未经测试。
- 第一次运行时 Windows 可能提示“已保护你的电脑”，点“更多信息 → 仍要运行”。本程序没有购买代码签名证书。
- 需要 Windows 10/11 自带的 Microsoft Edge WebView2 运行库；缺少时程序会给出微软官方下载链接。
- 卸载：在助手里不需要做任何事，直接删除这个文件夹即可；游戏里的组件可在游戏目录 platform\\steam\\ue4ss 中删除。
- 本程序与游戏开发商无关。使用模组的风险由使用者自行承担。

【第三方组件】
UE4SS（MIT 许可，见 app\\payload\\ue4ss\\ue4ss\\LICENSE）
Python {python}（PSF 许可，见 app\\python\\LICENSE.txt）
Microsoft Edge WebView2 SDK（见 licenses\\WebView2-LICENSE.txt）

---------------------------------------------------------------
Phantom Gladiator — NPC battles for Phantom Blade Zero  v{version}
Unzip the whole folder, run PhantomGladiator.exe, and follow the first-run guide.
Steam build {game_build} only. Delete the folder to uninstall.
"""
# The Nexus Mods build checks and downloads nothing, so its readme says where new versions come from.
README_NEXUS = """【更新】
这个版本来自 Nexus Mods，助手不会联网检查或下载更新。新版本请到 {page} 下载，解压后运行新的 PhantomGladiator.exe（设置会保留），再按提示一键安装游戏里的组件。

"""
README_NEXUS_EN = """This Nexus Mods build does not check for or download updates. Get new versions from {page}:
unzip, run the new PhantomGladiator.exe (your settings are kept) and install the game components when the app asks.
"""


def unpack_stdlib(python: Path) -> None:
    """The embeddable Python keeps its standard library (compiled .pyc files) in pythonXY.zip, listed in pythonXY._pth.
    Unpacks it to Lib and lists Lib instead, for the Nexus Mods upload."""
    pth = next(python.glob("python3*._pth"))
    stdlib = python / f"{pth.stem}.zip"
    lines = pth.read_bytes().decode("utf-8").splitlines(keepends=True)
    listed = [i for i, line in enumerate(lines) if line.strip() == stdlib.name]
    if len(listed) != 1 or not stdlib.is_file() or (python / "Lib").exists():
        sys.exit(f"{pth.name}: expected {stdlib.name} listed once, present, and no Lib folder yet")
    extract(stdlib, python / "Lib")
    stdlib.unlink()
    lines[listed[0]] = lines[listed[0]].replace(stdlib.name, "Lib")
    pth.write_bytes("".join(lines).encode("utf-8"))


def mod_build() -> str:
    m = re.search(r'local BUILD = "([^"]+)"', (ROOT / "Mods/PhantomGladiator/Scripts/main.lua").read_text(encoding="utf-8"))
    if not m:
        sys.exit("main.lua: BUILD not found")
    return m.group(1)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--deps", type=Path, required=True)
    parser.add_argument("--seed", type=Path, required=True)
    parser.add_argument("--version", default="0.30.0")
    parser.add_argument("--out", type=Path, default=ROOT / "dist")
    parser.add_argument("--channel", choices=["github", "nexus"], default="github")
    args = parser.parse_args()
    nexus = args.channel == "nexus"

    name = f"PhantomGladiator-{args.version}" + ("-nexus" if nexus else "")
    out = args.out / name
    build = args.out / "build"
    if out.exists():
        shutil.rmtree(out)
    if build.exists():
        shutil.rmtree(build)
    app = out / "app"
    for d in (app, build):
        d.mkdir(parents=True)

    # Third-party pieces, each checked against its pinned hash.
    extract(dependency(args.deps, "python"), app / "python")
    if nexus:
        unpack_stdlib(app / "python")
    extract(dependency(args.deps, "webview2"), build / "webview2", ["lib/net462/", "runtimes/win-x64/native/", "LICENSE"])
    extract(dependency(args.deps, "ue4ss"), app / "payload" / "ue4ss", strip=UE4SS_IN_PACKAGE)

    # Game-specific UE4SS files (signatures and memory layout) and the mod itself.
    shutil.copytree(ROOT / "GameConfig", app / "payload" / "gameconfig")
    scripts = app / "payload" / "mod" / "PhantomGladiator" / "Scripts"
    scripts.mkdir(parents=True)
    for lua in sorted((ROOT / "Mods/PhantomGladiator/Scripts").glob("*.lua")):
        shutil.copy2(lua, scripts / lua.name)
    seed = app / "payload" / "seed"
    seed.mkdir()
    for f in SEED_FILES:
        src = args.seed / f
        if not src.is_file():
            sys.exit(f"seed: {src} missing")
        shutil.copy2(src, seed / f)
    # The inventory says the day it describes, not the moment it was exported.
    report = seed / "inventory-report.json"
    report.write_bytes(re.sub(rb'"created_utc": "(\d{4}-\d\d-\d\d)T[^"]*"', rb'"created_utc": "\1T00:00:00+00:00"', report.read_bytes()))

    # Backend and UI. The packaged page loads the real runtime instead of the prototype's mock.
    (app / "backend").mkdir()
    for f in BACKEND_FILES:
        shutil.copy2(ROOT / "panel" / f, app / "backend" / f)
    ui = app / "ui"
    ui.mkdir()
    for f in UI_FILES:
        shutil.copy2(ROOT / "panel/prototype" / f, ui / f)
    html = (ROOT / "panel/prototype/index.html").read_text(encoding="utf-8")
    html, n = re.subn(r'<script src="mock-runtime\.js"></script>', '<script src="real-runtime.js"></script>', html)
    if n != 1:
        sys.exit("index.html: mock-runtime.js script tag not found")
    # backend.py's CSP allows only same-origin images, so the data: favicon becomes a file.
    html = re.sub(r'<link rel="icon" href="data:[^"]*">', '<link rel="icon" href="favicon.ico">', html)
    (ui / "index.html").write_text(html, encoding="utf-8", newline="\n")

    info = {"appVersion": args.version, "modBuild": mod_build(), "verifiedGameBuild": VERIFIED_GAME_BUILD, "repo": REPO, "manifests": MANIFESTS}
    if nexus:
        info.update(channel="nexus", manifests=[])
    (app / "version.json").write_text(json.dumps(info, ensure_ascii=False, indent=2), encoding="utf-8")

    # Native window, compiled with the .NET Framework's own compiler.
    icon = build / "app.ico"
    make_icon(icon)
    shutil.copy2(icon, ui / "favicon.ico")
    (build / "app.manifest").write_text(MANIFEST.format(version=args.version), encoding="utf-8")
    wv = build / "webview2"
    for dll in ["lib/net462/Microsoft.Web.WebView2.Core.dll", "lib/net462/Microsoft.Web.WebView2.WinForms.dll", "runtimes/win-x64/native/WebView2Loader.dll"]:
        shutil.copy2(wv / dll, out / Path(dll).name)
    refs = [f"/r:{r}" for r in FRAMEWORK_REFS] + [f"/r:{out / 'Microsoft.Web.WebView2.Core.dll'}", f"/r:{out / 'Microsoft.Web.WebView2.WinForms.dll'}"]
    subprocess.run([str(CSC), "/nologo", "/target:winexe", "/platform:x64", "/optimize+", "/utf8output", "/codepage:65001",
                    *(["/define:NEXUS"] if nexus else []),
                    f"/out:{out / 'PhantomGladiator.exe'}", f"/win32icon:{icon}", f"/win32manifest:{build / 'app.manifest'}", *refs,
                    str(ROOT / "desktop/PhantomGladiator.cs"), str(ROOT / "desktop/AppUpdate.cs"), str(ROOT / "desktop/ManualBeta.cs")], check=True)
    (out / "PhantomGladiator.exe.config").write_text(EXE_CONFIG, encoding="utf-8")
    (out / "licenses").mkdir()
    for lic in wv.glob("LICENSE*"):
        shutil.copy2(lic, out / "licenses" / "WebView2-LICENSE.txt")
    shutil.copy2(ROOT / "LICENSE", out / "licenses" / "PhantomGladiator-LICENSE.txt")
    readme = README.format(version=args.version, repo=REPO, game_build=VERIFIED_GAME_BUILD, python="3.11.9")
    if nexus:
        readme = readme.replace("【第三方组件】", README_NEXUS.format(page=NEXUS_PAGE) + "【第三方组件】", 1) + README_NEXUS_EN.format(page=NEXUS_PAGE)
    (out / "使用说明.txt").write_text(readme.replace("\n", "\r\n"), encoding="utf-8-sig")

    # The zip plus the manifest entry a release needs.
    archive = args.out / f"{name}-win64.zip"
    archive.unlink(missing_ok=True)
    # Every entry carries the package's build time, not when each source file was last edited.
    built = time.localtime()[:6]
    with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for path in sorted(out.rglob("*")):
            if path.is_file():
                entry = zipfile.ZipInfo.from_file(path, Path(name) / path.relative_to(out))
                entry.date_time = built
                entry.compress_type = zipfile.ZIP_DEFLATED
                z.writestr(entry, path.read_bytes(), compresslevel=9)
    digest = sha256(archive)
    (args.out / f"{name}-win64.zip.sha256").write_text(f"{digest}  {archive.name}\n", encoding="utf-8")
    if not nexus:  # the update feed only lists the GitHub release
        url = f"https://github.com/{REPO}/releases/download/v{args.version}/{archive.name}"
        latest = {"version": args.version, "date": "", "size": archive.stat().st_size, "sha256": digest,
                  "notes": {"zh": [], "en": []},
                  "downloads": [{"id": "cn1", "url": "https://ghfast.top/" + url}, {"id": "cn2", "url": "https://gh-proxy.com/" + url}, {"id": "github", "url": url}]}
        (args.out / "latest.json").write_text(json.dumps(latest, ensure_ascii=False, indent=2), encoding="utf-8")
    shutil.rmtree(build)
    print(f"{archive} ({archive.stat().st_size / 1048576:.1f} MB)\nsha256 {digest}")


if __name__ == "__main__":
    main()
