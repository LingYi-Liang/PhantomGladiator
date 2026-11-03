"""Lists which files differ between two unpacked release folders. GameConfig (app/payload/gameconfig) must come
out identical unless it was meant to change: the app asks players to reinstall when those files differ.
Python caches written by running a folder (__pycache__) are left out.

usage: python -I tools/release/compare_packages.py <old folder> <new folder>
"""
import hashlib
import pathlib
import sys


def files(root):
    return {p.relative_to(root).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in root.rglob("*") if p.is_file() and "__pycache__" not in p.parts}


def main():
    a, b = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
    fa, fb = files(a), files(b)
    print("identical:", sum(1 for k in fa if fb.get(k) == fa[k]))
    for k in sorted(set(fa) | set(fb)):
        if k not in fb:
            print("removed  ", k)
        elif k not in fa:
            print("added    ", k)
        elif fa[k] != fb[k]:
            print("changed  ", k)
    gameconfig = [k for k in set(fa) | set(fb) if k.startswith("app/payload/gameconfig/") and fa.get(k) != fb.get(k)]
    print("gameconfig:", "identical" if not gameconfig else f"{len(gameconfig)} files differ")


if __name__ == "__main__":
    main()
