"""Mutation testing (ADR 0005): plant one small bug at a time and check that the tests notice.

Usage: python3 scripts/mutate.py [package directory ...]   (default: the core and the adapters)

Runs on a copy of the packages in build/mutate, so the working tree is never touched. A line ending
in `// mutate:ignore - <reason>` is skipped: use it only for a mutation that cannot change behaviour.
"""

import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WORK = ROOT / "build" / "mutate"
DEFAULT_PACKAGES = ["Packages/PianismCore", "Packages/PianismPersistence"]

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
SKIPPED_STARTS = ("return", "let ", "var ", "case", "default", "}", "guard", "if ", "func", "public", "private", "init")


def mutants(lines):
    """Yields (line number, description, mutated lines)."""
    for index, line in enumerate(lines):
        code, _, comment = line.partition("//")
        stripped = code.strip()
        if not stripped or stripped.startswith(("import", "#", "@")) or "mutate:ignore" in comment:
            continue
        for name, pattern, replacement in OPERATORS:
            for match in re.finditer(pattern, code):
                mutated = line[: match.start()] + replacement + line[match.end():]
                yield index + 1, name, lines[:index] + [mutated] + lines[index + 1:]
        balanced = all(code.count(a) == code.count(b) for a, b in ("()", "{}", "[]"))
        if balanced and not stripped.startswith(SKIPPED_STARTS):
            if re.match(r"^(try |self\.|[a-z][A-Za-z.]*\s*(=|\+=|-=|\.|\())", stripped):
                yield index + 1, "remove statement", lines[:index] + [""] + lines[index + 1:]


def run(command, cwd, timeout=300):
    try:
        return subprocess.run(command, cwd=cwd, capture_output=True, timeout=timeout).returncode
    except subprocess.TimeoutExpired:
        return "timeout"


def copy_packages():
    """Copies every package's sources into WORK, keeping earlier build products for speed."""
    for package in (ROOT / "Packages").iterdir():
        if not (package / "Package.swift").exists():
            continue
        target = WORK / "Packages" / package.name
        for item in ("Sources", "Tests"):
            shutil.rmtree(target / item, ignore_errors=True)
            if (package / item).exists():
                shutil.copytree(package / item, target / item)
        shutil.copy2(package / "Package.swift", target / "Package.swift")


def main(packages):
    copy_packages()
    counts = {"caught": 0, "survived": 0, "didn't compile": 0}
    survivors = []
    started = time.time()
    for package in packages:
        workdir = WORK / package
        if run(["swift", "build", "--build-tests"], workdir, 900) != 0:
            sys.exit(f"{package} doesn't build before mutating")
        for source in sorted((workdir / "Sources").rglob("*.swift")):
            if "TestSupport" in source.parts[-2]:
                continue
            original = source.read_text()
            try:
                for line, name, lines in mutants(original.splitlines(keepends=True)):
                    source.write_text("".join(lines))
                    if run(["swift", "build", "--build-tests"], workdir) != 0:
                        outcome = "didn't compile"
                    else:
                        outcome = "caught" if run(["swift", "test"], workdir) != 0 else "survived"
                    counts[outcome] += 1
                    where = f"{source.relative_to(WORK)}:{line}"
                    if outcome == "survived":
                        survivors.append(f"{where}: {name}")
                    print(f"{outcome:15} {where} {name}", flush=True)
            finally:
                source.write_text(original)
    tested = counts["caught"] + counts["survived"]
    broken = counts["didn't compile"]
    print(f"\n{tested} mutations built and tested: {counts['caught']} caught, {counts['survived']} survived, "
          f"{broken} didn't compile ({time.time() - started:.0f} s).")
    print("\n".join(["Survivors, each needing a test, a deletion or a mutate:ignore:"] + survivors)
          if survivors else "No survivors.")


if __name__ == "__main__":
    main(sys.argv[1:] or DEFAULT_PACKAGES)
