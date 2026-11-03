"""Writes panel/prototype/changelog.js: every released version's notes (six languages, newest first), taken from
the release/latest.json each release published (git history), plus the version being released now.

usage: python -I tools/release/changelog.py <repo> <new version> <new date, ISO 8601 with offset> <notes.json>
notes.json: {"zh": [...], "en": [...], "ja": [...], "fr": [...], "de": [...], "es": [...]}
"""
import json
import pathlib
import subprocess
import sys

LANGS = ["zh", "en", "ja", "fr", "de", "es"]


def main():
    root, version, date, notes_path = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3], sys.argv[4]

    def git(*args):
        return subprocess.run(["git", "-C", str(root), *args], check=True, capture_output=True).stdout

    entries = {}
    for commit in git("log", "--format=%H", "--", "release/latest.json").decode().split():
        manifest = json.loads(git("show", f"{commit}:release/latest.json").decode("utf-8"))
        if manifest["version"] in entries:
            continue  # the newest manifest of a version wins (git log lists newest first)
        assert sorted(manifest["notes"]) == sorted(LANGS), (manifest["version"], sorted(manifest["notes"]))
        entries[manifest["version"]] = {"version": manifest["version"], "date": manifest["date"],
                                        "notes": {k: manifest["notes"][k] for k in LANGS}}

    new = json.loads(pathlib.Path(notes_path).read_text(encoding="utf-8"))
    assert sorted(new) == sorted(LANGS), sorted(new)
    entries[version] = {"version": version, "date": date, "notes": {k: new[k] for k in LANGS}}

    def key(v):
        return tuple(int(p) for p in v.split("."))

    ordered = sorted(entries.values(), key=lambda e: key(e["version"]), reverse=True)
    body = ",\n".join("  " + json.dumps(e, ensure_ascii=False) for e in ordered)
    text = ("// Release history for the update dialog: what each released version changed, in the app's six languages,\n"
            "// newest first. Each entry is the notes release/latest.json published for that version; a release adds its own.\n"
            "window.PG_CHANGELOG = [\n" + body + "\n];\n")
    (root / "panel/prototype/changelog.js").write_text(text, encoding="utf-8", newline="\n")
    print("changelog:", ", ".join(e["version"] for e in ordered))


if __name__ == "__main__":
    main()
