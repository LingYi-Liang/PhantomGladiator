"""Writes release/latest.json for a new version in the layout of the current one. Notes and date are the first
entry of panel/prototype/changelog.js (the app's release history, written by changelog.py), so the update dialog
and the history say the same thing. Downloads point at the GitHub release asset, directly and through the two
mirrors reachable from mainland China.

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
    assert re.fullmatch(r"[0-9a-f]{64}", sha), "the SHA-256 must be 64 hex digits"
    path = root / "release/latest.json"
    old_text = path.read_text(encoding="utf-8")
    old = json.loads(old_text)
    assert old["version"] != version, f"latest.json already describes {version}"
    js = (root / "panel/prototype/changelog.js").read_text(encoding="utf-8")
    history = json.loads(re.search(r"window\.PG_CHANGELOG = (\[.*\]);", js, re.S).group(1))
    entry = history[0]
    assert entry["version"] == version, f"changelog.js starts with {entry['version']}, not {version}"
    assert set(entry["notes"]) == set(old["notes"]), (set(entry["notes"]), set(old["notes"]))
    assert [d["id"] for d in old["downloads"]] == list(MIRRORS), [d["id"] for d in old["downloads"]]
    asset = f"https://github.com/{REPO}/releases/download/v{version}/PhantomGladiator-{version}-win64.zip"
    new = {"version": version, "date": entry["date"], "size": size, "sha256": sha, "notes": entry["notes"],
           "downloads": [{"id": k, "url": prefix + asset} for k, prefix in MIRRORS.items()]}
    text = json.dumps(new, ensure_ascii=False, indent=2) + ("\n" if old_text.endswith("\n") else "")
    path.write_text(text, encoding="utf-8", newline="\n")
    print("written", version, entry["date"])


if __name__ == "__main__":
    main()
