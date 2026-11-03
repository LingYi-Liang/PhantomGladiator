"""Rough Lua block-balance check: python -I lua_balance.py <file.lua>
Strips comments and strings, then counts block openers vs `end`.
"""
import re
import sys

src = open(sys.argv[1], encoding="utf-8").read()
src = re.sub(r"--\[\[.*?\]\]", "", src, flags=re.S)
src = re.sub(r"--[^\n]*", "", src)
src = re.sub(r'"(?:\\.|[^"\\\n])*"', '""', src)
src = re.sub(r"'(?:\\.|[^'\\\n])*'", "''", src)

depth = 0
line_of_min = None
for lineno, line in enumerate(src.split("\n"), 1):
    for tok in re.findall(r"\b(function|if|for|while|repeat|end|until)\b", line):
        if tok in ("function", "if", "for", "while", "repeat"):
            depth += 1
        else:
            depth -= 1
        if depth < 0 and line_of_min is None:
            line_of_min = lineno
print(f"final depth: {depth}" + (f", went negative at line {line_of_min}" if line_of_min else ""))
