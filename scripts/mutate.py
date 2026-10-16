"""Mutation testing (ADR 0005): plant one small bug at a time and check that the tests notice.

Usage: python3 scripts/mutate.py <package directory> ...   (`make mutate` passes the core and adapters)

Runs on a copy of the packages in build/mutate, so the working tree is never touched. A line ending
in `// mutate:ignore - <reason>` is skipped: use it only for a mutation that cannot change behaviour.
"""

import re
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WORK = ROOT / "build" / "mutate"

# Spaces around operators keep generics, arrows and ranges out of reach.
OPERATORS = [
    ("== to !=", r" == ", " != "),
    ("!= to ==", r" != ", " == "),
    ("< to <=", r" < ", " <= "),
    ("<= to <", r" <= ", " < "),
    ("> to >=", r" > ", " >= "),
    (">= to >", r" >= ", " > "),
    ("&& to ||", r" && ", " || "),
    ("|| to &&", r" \|\| ", " && "),
    ("+ to -", r" \+ ", " - "),
    ("- to +", r" - ", " + "),
    ("true to false", r"\btrue\b", "false"),
    ("false to true", r"\bfalse\b", "true"),
]


def mutants(lines):
    """Yields (line number, description, mutated lines)."""
    for index, line in enumerate(lines):
        code, _, comment = line.partition("//")
        stripped = code.strip()
        if not stripped or "mutate:ignore" in comment:
            continue
        for name, pattern, replacement in OPERATORS:
            for match in re.finditer(pattern, code):
                mutated = line[: match.start()] + replacement + line[match.end():]
                yield index + 1, name, lines[:index] + [mutated] + lines[index + 1:]
        # Remove a statement, if it is self-contained on one line.
        balanced = all(code.count(a) == code.count(b) for a, b in ("()", "{}", "[]"))
        if balanced and not stripped.startswith("return"):
            if re.match(r"^(try |[a-z][A-Za-z.]*\s*(=|\+=|-=|\.|\())", stripped):
                yield index + 1, "remove statement", lines[:index] + [""] + lines[index + 1:]


def passes(command, cwd, timeout=300):
    try:
        return subprocess.run(command, cwd=cwd, capture_output=True, timeout=timeout).returncode == 0
    except subprocess.TimeoutExpired:
        return False


def main(packages):
    WORK.mkdir(parents=True, exist_ok=True)
    # Mirrors the sources, keeping each package's .build so rebuilds stay incremental.
    subprocess.run(["rsync", "-a", "--delete", "--exclude=.build", f"{ROOT}/Packages/", f"{WORK}/Packages/"],
                   check=True)
    counts = {"caught": 0, "survived": 0, "didn't compile": 0}
    survivors = []
    started = time.time()
    for package in packages:
        workdir = WORK / "Packages" / Path(package).name
        # A failing suite would make every mutation look caught.
        if not passes(["swift", "test"], workdir, 900):
            sys.exit(f"{package} must build and pass its tests before mutating")
        for source in sorted((workdir / "Sources" / workdir.name).rglob("*.swift")):
            original = source.read_text()
            for line, name, lines in mutants(original.splitlines(keepends=True)):
                source.write_text("".join(lines))
                if not passes(["swift", "build", "--build-tests"], workdir):
                    outcome = "didn't compile"
                elif passes(["swift", "test", "--skip-build"], workdir):
                    outcome = "survived"
                else:
                    outcome = "caught"
                counts[outcome] += 1
                where = f"{source.relative_to(WORK)}:{line}"
                if outcome == "survived":
                    survivors.append(f"{where}: {name}")
                print(f"{outcome:15} {where} {name}", flush=True)
            source.write_text(original)
    tested = counts["caught"] + counts["survived"]
    broken = counts["didn't compile"]
    print(f"\n{tested} mutations built and tested: {counts['caught']} caught, {counts['survived']} survived, "
          f"{broken} didn't compile ({time.time() - started:.0f} s).")
    print("\n".join(["Survivors, each needing a test, a deletion or a mutate:ignore:"] + survivors)
          if survivors else "No survivors.")


if __name__ == "__main__":
    main(sys.argv[1:])
