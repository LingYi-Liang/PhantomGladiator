"""Writes release/safe/latest.json for a new version and adds it to release/safe/versions.json.
The legacy feed is maintained separately for the one-time migration to 0.40.10. Notes and date are the first entry of
panel/prototype/changelog.js (the app's release history, written by changelog.py), so the update dialog and the
history say the same thing. Downloads point at the GitHub release asset, directly and through the two mirrors
reachable from mainland China.

A release found to be bad comes off versions.json by hand, so nobody goes back to it.

usage: python -I tools/release/manifest.py <repo> <version> <zip sha256> <zip size in bytes>
"""
import json
import pathlib
import re
import sys

REPO = "LingYi-Liang/PhantomGladiator"
MIRRORS = {"cn1": "https://ghfast.top/", "cn2": "https://gh-proxy.com/", "github": ""}


def main():
    root, version, sha, size = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3].lower(), int(sys.argv[4])
    assert re.fullmatch(r"\d+\.\d+\.\d+", version) and tuple(map(int, version.split("."))) >= (0, 40, 10), version
    assert re.fullmatch(r"[0-9a-f]{64}", sha), "the SHA-256 must be 64 hex digits"
    release = root / "release"
    safe = release / "safe"
    path = safe / "latest.json"
    listed = safe / "versions.json"
    old_text = (path if path.is_file() else release / path.name).read_text(encoding="utf-8")
    old = json.loads(old_text)
    assert old["version"] != version, f"latest.json already describes {version}"
    js = (root / "panel/prototype/changelog.js").read_text(encoding="utf-8")
    history = json.loads(re.search(r"window\.PG_CHANGELOG = (\[.*\]);", js, re.S).group(1))
    entry = history[0]
    assert entry["version"] == version, f"changelog.js starts with {entry['version']}, not {version}"
    assert set(entry["notes"]) == set(old["notes"]), (set(entry["notes"]), set(old["notes"]))
    assert [d["id"] for d in old["downloads"]] == list(MIRRORS), [d["id"] for d in old["downloads"]]
    asset = f"https://github.com/{REPO}/releases/download/v{version}/PhantomGladiator-{version}-win64.zip"
    new = {"version": version, "modBuild": "v" + version, "date": entry["date"], "size": size, "sha256": sha, "notes": entry["notes"],
           "downloads": [{"id": k, "url": prefix + asset} for k, prefix in MIRRORS.items()]}
    versions = json.loads((listed if listed.is_file() else release / listed.name).read_text(encoding="utf-8"))
    assert all(v["version"] != version for v in versions["versions"]), f"versions.json already lists {version}"
    versions["versions"].insert(0, {k: new[k] for k in ("version", "modBuild", "date", "size", "sha256", "downloads", "notes")})
    safe.mkdir(exist_ok=True)
    text = json.dumps(new, ensure_ascii=False, indent=2) + ("\n" if old_text.endswith("\n") else "")
    path.write_text(text, encoding="utf-8", newline="\n")
    listed.write_text(json.dumps(versions, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
    print("written", version, entry["date"])


if __name__ == "__main__":
    main()
