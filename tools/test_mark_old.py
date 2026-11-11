"""A stable release must leave manual-preview and draft releases untouched."""
import json
from pathlib import Path
import runpy
import sys
from unittest.mock import patch

module = runpy.run_path(str(Path(__file__).parent / "release/mark_old.py"))
edits = []


def fake_gh(*args):
    if args[:2] == ("repo", "view"):
        return json.dumps({"url": "https://github.com/example/project"})
    if args[:2] == ("release", "list"):
        assert "isPrerelease" in args[-1] and "isDraft" in args[-1]
        return json.dumps([
            {"tagName": "v2", "name": "Current", "isPrerelease": False, "isDraft": False},
            {"tagName": "v1", "name": "Previous", "isPrerelease": False, "isDraft": False},
            {"tagName": "beta-preview", "name": "Preview", "isPrerelease": True, "isDraft": False},
            {"tagName": "pending", "name": "Draft", "isPrerelease": False, "isDraft": True},
            {"tagName": "v0", "name": "[旧版] Earlier", "isPrerelease": False, "isDraft": False},
        ])
    if args[:3] == ("release", "view", "v1"):
        return json.dumps({"body": "Existing notes"})
    if args[:2] == ("release", "edit"):
        edits.append(args[2])
        notes = Path(args[args.index("--notes-file") + 1]).read_text(encoding="utf-8")
        assert notes.endswith("Existing notes") and "releases/latest" in notes
        return ""
    raise AssertionError(args)


module["main"].__globals__["gh"] = fake_gh
with patch.object(sys, "argv", ["mark_old.py", "v2"]):
    module["main"]()
assert edits == ["v1"], edits
print("mark_old: PASS (current, preview, draft and already marked releases preserved)")
