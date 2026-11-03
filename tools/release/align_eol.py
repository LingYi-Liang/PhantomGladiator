"""Gives each source file that goes into the package the line endings its copy had in the previous release
package, so files whose content did not change come out byte-identical (the app compares the GameConfig files
byte by byte and asks players to reinstall when they differ). Files the previous package did not have get LF.
Only the working tree is touched; run it before tools/package/build.py.

usage: python -I tools/release/align_eol.py <repo> <previous package folder, e.g. dist/PhantomGladiator-0.37.5>
"""
import pathlib
import sys

BACKEND = ["backend.py", "catalog_labels.py", "catalog_taxonomy.py", "unit_validation.json"]
UI = ["styles.css", "i18n.js", "i18n-more.js", "units.js", "changelog.js", "real-runtime.js", "app.js"]


def pairs(root, old):
    app = old / "app"
    for p in sorted((root / "GameConfig").rglob("*")):
        if p.is_file():
            yield p, app / "payload" / "gameconfig" / p.relative_to(root / "GameConfig")
    for p in sorted((root / "Mods/PhantomGladiator/Scripts").glob("*.lua")):
        yield p, app / "payload/mod/PhantomGladiator/Scripts" / p.name
    for f in BACKEND:
        yield root / "panel" / f, app / "backend" / f
    for f in UI:
        yield root / "panel/prototype" / f, app / "ui" / f
    yield root / "LICENSE", old / "licenses/PhantomGladiator-LICENSE.txt"
    for name in ["PhantomGladiator.cs", "AppUpdate.cs"]:  # what build.py compiles; not shipped as text
        yield root / "desktop" / name, None


def main():
    root, old = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
    if not (old / "app").is_dir():
        sys.exit(f"{old}: not an unpacked package folder")
    counts = {"rewritten": 0, "identical": 0, "content-changed": 0, "new": 0}
    for src, before in pairs(root, old):
        data = src.read_bytes()
        text = data.replace(b"\r\n", b"\n")
        if before is not None and before.is_file():
            previous = before.read_bytes()
            crlf = b"\r\n" in previous
            want = text.replace(b"\n", b"\r\n") if crlf else text
            kind = "content-changed" if want != previous else ("rewritten" if data != want else "identical")
        else:
            crlf, want, kind = False, text, "new"
        if data != want:
            src.write_bytes(want)
        counts[kind] += 1
        if kind != "identical":
            print(f"{kind:15} {src.relative_to(root)} {'CRLF' if crlf else 'LF'}")
    print(" ".join(f"{k}={v}" for k, v in counts.items()))


if __name__ == "__main__":
    main()
