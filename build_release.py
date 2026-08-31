#!/usr/bin/env python3
"""Validate the harness tree and zip agents/, skills/, rules/ into dist/claude-harness-<version>.zip."""
import re, sys, zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent
SKIP = {"__pycache__", ".DS_Store", "Thumbs.db", "README.md"}  # READMEs document the repo, not ~/.claude
NAME_OK = re.compile(r"[a-z0-9-]{1,64}")  # official skill-name charset
VERSION = sys.argv[1] if len(sys.argv) > 1 else "dev"

def validate_skill(name):
    src = ROOT / "skills" / name
    if not (src / "SKILL.md").is_file():
        sys.exit(f"error: skills/{name} has no SKILL.md")
    lines = (src / "SKILL.md").read_text(encoding="utf-8").splitlines()[:8]
    fm = lambda key: next((l.split(":", 1)[1].strip().strip('"\'')
                           for l in lines if l.startswith(key + ":")), "")
    if fm("name") != name:
        sys.exit(f"error: skills/{name}: frontmatter name is {fm('name')!r}, expected {name!r}")
    if not NAME_OK.fullmatch(name) or "claude" in name or "anthropic" in name:
        sys.exit(f"error: skills/{name}: name must be [a-z0-9-]{{1,64}} without 'claude'/'anthropic'")
    if not fm("description"):
        sys.exit(f"error: skills/{name}: frontmatter has no description")
    if not fm("compatibility"):
        sys.exit(f"error: skills/{name}: frontmatter has no compatibility (Claude Code-only declaration)")

def build():
    for d in ("agents", "skills", "rules"):
        if not (ROOT / d).is_dir():
            sys.exit(f"error: missing {d}/")
    for s in sorted(p.name for p in (ROOT / "skills").iterdir() if p.is_dir()):
        validate_skill(s)
    out = ROOT / "dist" / f"claude-harness-{VERSION}.zip"
    out.parent.mkdir(exist_ok=True)
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        for d in ("agents", "skills", "rules"):
            for p in sorted((ROOT / d).rglob("*")):
                if p.is_file() and not SKIP.intersection(p.parts):
                    z.write(p, p.relative_to(ROOT).as_posix())
    print(f"built {out.as_posix()}")

build()
