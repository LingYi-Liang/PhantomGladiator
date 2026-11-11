"""Marks every GitHub release except the given latest one as old: "[旧版]" in front of the title and a pointer to the latest
release at the top of its notes. Downloads stay where they are (the app's rollback uses them). Already marked ones are skipped.

usage: python -I tools/release/mark_old.py <latest tag, e.g. v0.39.1> [--dry-run]
"""
import json
import pathlib
import subprocess
import sys
import tempfile

PREFIX = "[旧版] "
BANNER = (
    "> **这是旧版本。** 最新版请到 [这里]({url}) 下载，已安装的助手也可以直接检查更新。\n"
    "> **This is an old version.** Get the [latest release]({url}) instead.\n\n"
)


def gh(*args):
    return subprocess.run(["gh", *args], check=True, capture_output=True, text=True, encoding="utf-8").stdout


def main():
    latest = sys.argv[1]
    dry = "--dry-run" in sys.argv[2:]
    repo = json.loads(gh("repo", "view", "--json", "url"))["url"]
    url = repo + "/releases/latest"
    releases = json.loads(gh("release", "list", "--limit", "200", "--json", "tagName,name,isPrerelease,isDraft"))
    tags = [r["tagName"] for r in releases]
    assert latest in tags, (latest, tags[:5])
    changed = 0
    for release in releases:
        tag, name = release["tagName"], release["name"]
        if tag == latest or name.startswith(PREFIX) or release.get("isPrerelease") or release.get("isDraft"):
            continue
        body = json.loads(gh("release", "view", tag, "--json", "body"))["body"]
        print(("would mark " if dry else "marking ") + tag)
        changed += 1
        if dry:
            continue
        with tempfile.TemporaryDirectory() as folder:
            notes = pathlib.Path(folder) / "notes.md"
            notes.write_text(BANNER.format(url=url) + body, encoding="utf-8")
            gh("release", "edit", tag, "--title", PREFIX + name, "--notes-file", str(notes), "--latest=false")
    print("marked", changed)


if __name__ == "__main__":
    main()
