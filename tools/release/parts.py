"""Publishes a release package as small files that CDNs reachable from mainland China can serve, and lists them in the
manifests the app reads.

    python -I tools/release/parts.py <repo> <version> <zip>

jsDelivr serves files from a repository, not release assets, and only up to 20 MB each, so the parts go into tag
dl-<version>: a commit of its own, unrelated to the project's history and pushed from a temporary repository, so it adds
nothing to the project's branches or to a local checkout. Run it after manifest.py: it adds "parts" to the version's
entry in release/safe/versions.json and, for the latest version, to release/safe/latest.json.

App versions before split downloads ignore "parts". For them the latest version's zip also goes into the tag while it
fits jsDelivr's single-file limit, and its cn1 line in latest.json points there.
"""
import hashlib
import json
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.request

REPO = "LingYi-Liang/PhantomGladiator"
PART_SIZE = 2 * 1024 * 1024
WHOLE_LIMIT = 20 * 1024 * 1024
JSDELIVR = ["fastly", "gcore", "testingcf", "cdn"]
PROXIES = {"ghfast": "https://ghfast.top/", "ghproxy": "https://gh-proxy.com/"}
TRAILER = "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"


def git(cwd, *args, capture=False):
    run = subprocess.run(["git", *args], cwd=cwd, check=True, capture_output=capture, text=capture)
    return run.stdout.strip() if capture else None


def sources(tag):
    listed = [{"id": host, "url": f"https://{host}.jsdelivr.net/gh/{REPO}@{tag}/"} for host in JSDELIVR]
    raw = f"https://raw.githubusercontent.com/{REPO}/{tag}/"
    listed += [{"id": name, "url": prefix + raw} for name, prefix in PROXIES.items()]
    listed.append({"id": "github", "url": raw})
    return listed


def get(url, tries=4):
    for attempt in range(tries):
        try:
            request = urllib.request.Request(url, headers={"User-Agent": "PhantomGladiator"})
            with urllib.request.urlopen(request, timeout=90) as response:
                return response.read()
        except OSError as error:
            if attempt == tries - 1:
                raise error
            time.sleep(5)


def main():
    root, version, archive = pathlib.Path(sys.argv[1]), sys.argv[2], pathlib.Path(sys.argv[3])
    assert re.fullmatch(r"\d+\.\d+\.\d+", version), version
    assert archive.name == f"PhantomGladiator-{version}-win64.zip", archive.name
    data = archive.read_bytes()
    versions_path, latest_path = root / "release/safe/versions.json", root / "release/safe/latest.json"
    versions = json.loads(versions_path.read_text(encoding="utf-8"))
    entry = next(v for v in versions["versions"] if v["version"] == version)
    assert entry["size"] == len(data) and entry["sha256"] == hashlib.sha256(data).hexdigest(), "the zip is not the listed one"
    latest = json.loads(latest_path.read_text(encoding="utf-8"))
    is_latest = latest["version"] == version
    whole = is_latest and len(data) <= WHOLE_LIMIT

    tag = f"dl-{version}"
    files = []
    work = pathlib.Path(tempfile.mkdtemp(prefix="pg-parts-"))
    try:
        git(work, "init", "-q", ".")
        git(work, "config", "core.autocrlf", "false")
        for i in range(0, len(data), PART_SIZE):
            piece = data[i:i + PART_SIZE]
            name = f"{archive.name}.{i // PART_SIZE:03d}"
            (work / name).write_bytes(piece)
            files.append({"name": name, "size": len(piece), "sha256": hashlib.sha256(piece).hexdigest()})
        if whole:
            (work / archive.name).write_bytes(data)
        remote = f"https://github.com/{REPO}.git"
        if git(work, "ls-remote", "--tags", remote, f"refs/tags/{tag}", capture=True):
            print("tag already there:", tag)
        else:
            git(work, "add", "-A")
            name = git(root, "config", "user.name", capture=True)
            email = git(root, "config", "user.email", capture=True)
            git(work, "-c", f"user.name={name}", "-c", f"user.email={email}", "commit", "-q", "-m", f"发布文件分片：v{version}\n\n{TRAILER}")
            git(work, "push", "-q", remote, f"HEAD:refs/tags/{tag}")
            print("pushed", tag, len(files), "parts", "and the whole zip" if whole else "")
    finally:
        shutil.rmtree(work, ignore_errors=True)

    # The first request through each host makes it fetch the tag; players then get the cached copy.
    listed = sources(tag)
    for source in listed:
        started, ok = time.time(), 0
        for file in files:
            try:
                ok += hashlib.sha256(get(source["url"] + file["name"])).hexdigest() == file["sha256"]
            except OSError as error:
                print("  ", source["id"], file["name"], error)
        print(f"{source['id']}: {ok}/{len(files)} parts verified in {time.time() - started:.0f} s")

    parts = {"files": files, "sources": listed}
    entry["parts"] = parts
    versions_path.write_text(json.dumps(versions, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
    if is_latest:
        latest["parts"] = parts
        if whole:
            url = f"https://fastly.jsdelivr.net/gh/{REPO}@{tag}/{archive.name}"
            assert hashlib.sha256(get(url)).hexdigest() == entry["sha256"], "the whole zip did not come back intact"
            next(d for d in latest["downloads"] if d["id"] == "cn1")["url"] = url
            print("cn1 ->", url)
        latest_path.write_text(json.dumps(latest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
    print("listed", version)


if __name__ == "__main__":
    main()
