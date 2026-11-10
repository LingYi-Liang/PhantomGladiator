"""Exercise both manifest writers without publishing a release or a download tag."""
import hashlib
import json
import runpy
import sys
import tempfile
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]


def main():
    with tempfile.TemporaryDirectory(prefix="pg-release-feed-") as scratch:
        repo = Path(scratch).resolve()
        release = repo / "release"
        release.mkdir()
        frozen = {name: (ROOT / "release" / name).read_bytes() for name in ("latest.json", "versions.json")}
        for name, content in frozen.items():
            (release / name).write_bytes(content)
        safe = release / "safe"
        safe.mkdir()
        for name in frozen:
            (safe / name).write_bytes((ROOT / "release" / "safe" / name).read_bytes())
        previous = json.loads((safe / "latest.json").read_bytes())
        previous_versions = json.loads((safe / "versions.json").read_bytes())["versions"]
        major, minor, patch_number = previous["version"].split(".")
        version = f"{major}.{minor}.{int(patch_number) + 1}"

        changelog = repo / "panel" / "prototype" / "changelog.js"
        changelog.parent.mkdir(parents=True)
        entry = {"version": version, "date": previous["date"], "notes": previous["notes"]}
        changelog.write_text("window.PG_CHANGELOG = " + json.dumps([entry]) + ";", encoding="utf-8")
        archive = repo / f"PhantomGladiator-{version}-win64.zip"
        payload = b"isolated release fixture"
        archive.write_bytes(payload)

        manifest = ROOT / "tools" / "release" / "manifest.py"
        with patch.object(sys, "argv", [str(manifest), str(repo), entry["version"], hashlib.sha256(payload).hexdigest(), str(len(payload))]):
            runpy.run_path(str(manifest), run_name="__main__")

        parts = ROOT / "tools" / "release" / "parts.py"
        write_parts = runpy.run_path(str(parts), run_name="parts_fixture")["main"]
        tag = repo / "tag-fixture"
        tag.mkdir()

        def fixture_git(cwd, command, *args, capture=False):
            assert cwd == tag and command in ("init", "config", "ls-remote"), (cwd, command)
            return "existing tag" if command == "ls-remote" else None

        write_parts.__globals__.update(
            git=fixture_git,
            get=lambda url: payload,
            tempfile=SimpleNamespace(mkdtemp=lambda **kwargs: str(tag)),
            shutil=SimpleNamespace(rmtree=lambda path, **kwargs: None),
        )
        with patch.object(sys, "argv", [str(parts), str(repo), entry["version"], str(archive)]):
            write_parts()

        for name, content in frozen.items():
            assert (release / name).read_bytes() == content, name
        latest = json.loads((release / "safe" / "latest.json").read_text(encoding="utf-8"))
        versions = json.loads((release / "safe" / "versions.json").read_text(encoding="utf-8"))["versions"]
        assert latest["version"] == version and latest["parts"] == versions[0]["parts"]
        assert versions[0]["version"] == version and versions[1:] == previous_versions
        manifests = runpy.run_path(str(ROOT / "tools" / "package" / "build.py"), run_name="build_fixture")["MANIFESTS"]
        assert len(manifests) == 3 and all(entry.endswith("/release/safe/latest.json") for entry in manifests)
        print("release_feed: PASS (both writers keep the legacy feed byte-identical)")


if __name__ == "__main__":
    main()
