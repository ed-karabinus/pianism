#!/usr/bin/env python3
"""plant-swift.py <worktree> <package dir> <test filter> <source file>  (JSON [[name, old, new], ...] on stdin)
Runs the filtered tests once clean, then once per planted bug, restoring the file each time."""
import json, subprocess, sys, time, os
wt, pkg, flt, src = sys.argv[1:5]
plants = json.load(sys.stdin)
path = os.path.join(wt, src)
orig = open(path).read()
def run():
    t = time.time()
    p = subprocess.run(["swift", "test", "--package-path", os.path.join(wt, pkg), "--filter", flt],
                       capture_output=True, text=True)
    out = p.stdout + p.stderr
    fails = [l for l in out.splitlines() if "✘" in l or "error:" in l][:2]
    return p.returncode, int(time.time() - t), fails
try:
    rc, s, fails = run()
    print(f"control: {'PASSED' if rc == 0 else 'FAILED'} ({s} s)")
    if rc != 0:
        print("\n".join("    " + f[:170] for f in fails)); sys.exit(1)
    for name, old, new in plants:
        n = orig.count(old)
        if n != 1:
            print(f"{name}: NOT PLANTED ({n} matches)"); continue
        open(path, "w").write(orig.replace(old, new))
        rc, s, fails = run()
        print(f"{name}: {'CAUGHT' if rc != 0 else 'MISSED'} ({s} s)")
        for f in fails: print("    " + f[:170])
        open(path, "w").write(orig)
finally:
    open(path, "w").write(orig)
