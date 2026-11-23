#!/usr/bin/env python3
"""Synchronize marked helper copies in the app's standalone JavaScript tools."""
import argparse
import re
import sys
from pathlib import Path

DIRECTORY = Path(__file__).resolve().parents[1] / "Sources/ToolchordCore/Scripts"
BLOCK = re.compile(
    r"^(// @shared ([\w.-]+/[\w-]+)\n)(.*?)(^// @endshared$)", re.MULTILINE | re.DOTALL
)


def synchronize(check):
    programs = {}
    owners = {}
    for path in sorted(DIRECTORY.glob("*/*.js")):
        tool_id = path.stem.partition("-")[2]
        source = path.read_text(encoding="utf-8")
        blocks = list(BLOCK.finditer(source))
        for marker in ("// @shared", "// @endshared"):
            if len(re.findall("^" + marker, source, re.MULTILINE)) != len(blocks):
                raise ValueError(f"{path.name}: malformed or nested {marker} marker")
        programs[path] = source
        seen = set()
        for block in blocks:
            key = block[2]
            if key in seen:
                raise ValueError(f"{path.name}: duplicate helper {key}")
            seen.add(key)
            if key.split("/")[0] == tool_id:
                if key in owners:
                    raise ValueError(f"Multiple owners for {key}")
                owners[key] = block[3]

    def replace(block):
        key = block[2]
        if key not in owners:
            raise ValueError(f"Missing owner for {key}")
        return block[1] + owners[key] + block[4]

    updates = {}
    for path, source in programs.items():
        updated = BLOCK.sub(replace, source)
        if source != updated:
            updates[path] = updated
    for path, updated in updates.items():
        print(path.relative_to(DIRECTORY))
        if not check:
            path.write_text(updated, encoding="utf-8")
    return 1 if check and updates else 0


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Report stale helpers without changing files")
    try:
        sys.exit(synchronize(parser.parse_args().check))
    except (OSError, ValueError) as error:
        sys.exit(str(error))
