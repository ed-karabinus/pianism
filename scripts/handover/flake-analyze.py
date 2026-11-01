#!/usr/bin/env python3 -I
"""Per e2e job log: image version, iOS runtime, per-test-iteration duration, automation-session wait, and failures.

Usage: python3 -I scripts/handover/flake-analyze.py <job log files...>   (gh run view --job <id> --log > file)
Prints one block per job: header line, then one line per test iteration for the first N tests, then counts.
"""
import re
import sys

TEST_START = re.compile(r"Test Case '-\[PianismUITests\.(\w+) (\w+)\]' started(?: \(Iteration (\d) of (\d)\))?")
TEST_END = re.compile(r"Test Case '-\[PianismUITests\.\w+ (\w+)\]' (passed|failed) \(([\d.]+) seconds\)")
T = re.compile(r"t =\s+([\d.]+)s (.*)$")
FATAL_AX = "Failed to get matching snapshots: Error getting main window kAXErrorServerNotFound"
NO_PID = "does not have a process ID"
TIMED_OUT = "Timed out while evaluating UI query"
SUITE_START = re.compile(r"Test Suite 'All tests' started at (\S+ \S+)\.")


def analyze(path, first_n=8):
    image = runtime = xcode = None
    suite_start = None
    tests = []  # dicts
    cur = None
    for raw in open(path, encoding="utf-8", errors="replace"):
        line = raw.rstrip("\n")
        if image is None:
            m = re.search(r"Version: (\d{8}\.\d+(?:\.\d+)?)", line)
            if m and "Runner Image Provisioner" not in line and re.search(r"Version: 2026", line) and ".0" in m.group(1):
                image = m.group(1)
        if runtime is None:
            m = re.search(r"versionAndBuild = ([\d.]+ \([0-9A-Z]+\))", line)
            if m:
                runtime = m.group(1)
        if xcode is None:
            m = re.search(r"\bXcode (27\.\d+|26\.\d+(?:\.\d+)?)\b", line)
            if m:
                xcode = m.group(1)
        if suite_start is None:
            m = SUITE_START.search(line)
            if m:
                suite_start = m.group(1)
        m = TEST_START.search(line)
        if m:
            cur = {"cls": m.group(1), "name": m.group(2), "iter": m.group(3) or "1", "setup": None, "idle": None,
                   "errors": [], "ax": 0, "nopid": 0, "timedout": 0}
            tests.append(cur)
            continue
        if cur is not None:
            m = T.search(line)
            if m:
                t, msg = float(m.group(1)), m.group(2)
                if msg.strip().startswith("Setting up automation session") and cur["setup"] is None:
                    cur["setup"] = t
                elif "Wait for com.edkarabinus.Pianism to idle" in msg and cur["setup"] is not None and cur["idle"] is None:
                    cur["idle"] = t
            if " error: " in line:
                short = line.split(" error: ", 1)[1]
                short = re.sub(r"^-\[PianismUITests\.\w+ \w+\] : ", "", short)
                cur["errors"].append(short[:110])
                if FATAL_AX in line:
                    cur["ax"] += 1
                if NO_PID in line:
                    cur["nopid"] += 1
                if TIMED_OUT in line:
                    cur["timedout"] += 1
            m = TEST_END.search(line)
            if m and m.group(1) == cur["name"]:
                cur["result"] = m.group(2)
                cur["secs"] = float(m.group(3))
                cur = None
    ax = sum(t["ax"] for t in tests)
    nopid = sum(t["nopid"] for t in tests)
    timedout = sum(t["timedout"] for t in tests)
    failed = [t for t in tests if t.get("result") == "failed"]
    name = path.rsplit("/", 1)[-1]
    print(f"### {name}\n    image={image} xcode={xcode} runtime={runtime} suite_start={suite_start} tests={len(tests)} "
          f"failed_iters={len(failed)} fatalAX={ax} noPID={nopid} timedOutQuery={timedout}")
    for i, t in enumerate(tests):
        if i >= first_n and t.get("result") != "failed":
            continue
        wait = "-"
        if t["setup"] is not None and t["idle"] is not None:
            wait = f"{t['idle'] - t['setup']:5.1f}"
        elif t["setup"] is not None:
            wait = "  n/a"
        flag = " <AX" if t["ax"] else (" <noPID" if t["nopid"] else "")
        err = f"  {t['errors'][0]}" if t["errors"] else ""
        print(f"    {i+1:2d}. {t['name'][:44]:44} it{t['iter']} {t.get('result','?'):6} {t.get('secs', 0):6.1f}s  autoWait={wait}{flag}{err}")
    return {"name": name, "image": image, "ax": ax, "nopid": nopid, "failed": len(failed), "tests": tests}


if __name__ == "__main__":
    rows = [analyze(p) for p in sys.argv[1:]]
    print("\n== summary")
    for r in rows:
        waits = [t["idle"] - t["setup"] for t in r["tests"][:6] if t["setup"] is not None and t["idle"] is not None]
        long = sum(1 for w in waits if w >= 59)
        print(f"{r['name'][:60]:60} image={r['image']} fatalAX={r['ax']} noPID={r['nopid']} failedIters={r['failed']} "
              f"60sWaitsInFirst6={long}/{len(waits)}")
